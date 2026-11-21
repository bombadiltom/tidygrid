#!/bin/bash
# Builds TidyGrid.app (Apple silicon + Intel) into ./build.
#   ./build.sh                    build only
#   ./build.sh install            also copy to /Applications here and start it
#   ./build.sh deploy HOST...     also copy to /Applications on each SSH host and start it there
#   ./build.sh release            also notarize it, publish it as a GitHub release of this repo
#                                 and update the cask in the Homebrew tap
#                                 (version from Resources/Info.plist; re-running replaces the zip)
#
# Signing: "Developer ID Application" when available, else "Apple Development", else ad hoc.
# Using the same certificate for every build keeps the Accessibility permission across rebuilds
# and between Homebrew installs and local builds. Override with SIGN_IDENTITY=...
#
# Releases need the Developer ID certificate and a notarytool keychain profile
# (NOTARY_PROFILE, default "BombadilTom": the credentials are team-wide), created with
#   xcrun notarytool store-credentials <profile> --apple-id <apple-id> --team-id K6QN2C7Q55
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-BombadilTom}"
TAP="${TAP:-bombadiltom/tap}"

if [[ "$MODE" == "release" ]]; then
  # Fail before building: a release must match a commit that is on GitHub.
  [[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes before releasing."; exit 1; }
  git fetch -q origin
  git merge-base --is-ancestor HEAD origin/main || { echo "Push HEAD to origin/main before releasing."; exit 1; }
fi

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/TidyGrid"

APP=build/TidyGrid.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TidyGrid"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# The build number is the commit count, so every build from a new commit is distinguishable.
plutil -replace CFBundleVersion -string "$(git rev-list --count HEAD 2>/dev/null || echo 1)" "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  IDENTITY="$SIGN_IDENTITY"
elif grep -q "Developer ID Application" <<<"$IDENTITIES"; then
  IDENTITY="Developer ID Application"
elif grep -q "Apple Development" <<<"$IDENTITIES"; then
  IDENTITY="Apple Development"
else
  IDENTITY="-"
fi

if [[ "$MODE" == "release" ]]; then
  [[ "$IDENTITY" == Developer\ ID* ]] || { echo "Releases need a 'Developer ID Application' certificate."; exit 1; }
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
elif [[ "$IDENTITY" == "-" ]]; then
  echo "No signing certificate found, signing ad hoc (Accessibility must be granted again after each build)."
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
fi
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/TidyGrid"), signed: $IDENTITY)"

case "$MODE" in
  install)
    pkill -x TidyGrid || true
    rm -rf /Applications/TidyGrid.app
    cp -R "$APP" /Applications/
    open /Applications/TidyGrid.app
    echo "Installed /Applications/TidyGrid.app"
    ;;
  deploy)
    shift
    [[ $# -gt 0 ]] || { echo "usage: ./build.sh deploy HOST..."; exit 1; }
    for host in "$@"; do
      echo "Deploying to $host"
      ssh "$host" 'pkill -x TidyGrid || true; mkdir -p /tmp/tidygrid-deploy && rm -rf /tmp/tidygrid-deploy/TidyGrid.app'
      rsync -a "$APP" "$host:/tmp/tidygrid-deploy/"
      ssh "$host" 'rm -rf /Applications/TidyGrid.app && mv /tmp/tidygrid-deploy/TidyGrid.app /Applications/ && open /Applications/TidyGrid.app'
      echo "Installed /Applications/TidyGrid.app on $host"
    done
    ;;
  release)
    VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
    TAG="v$VERSION"
    ZIP="build/TidyGrid-$VERSION.zip"
    rm -f build/TidyGrid*.zip

    echo "Notarizing (usually a few minutes)"
    ditto -c -k --keepParent "$APP" "$ZIP"
    SUBMISSION="$(xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
    SUBMISSION_ID="$(plutil -extract id raw - <<<"$SUBMISSION")"
    STATUS="$(plutil -extract status raw - <<<"$SUBMISSION")"
    echo "Submission $SUBMISSION_ID: $STATUS"
    if [[ "$STATUS" != "Accepted" ]]; then
      xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2
      exit 1
    fi
    xcrun stapler staple "$APP"
    spctl --assess --type execute "$APP"
    # Re-zip so the download carries the stapled ticket.
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    SHA256="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"

    # Publish with the account that owns the repo, whichever gh account is active.
    REPO="$(git remote get-url origin | sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##')"
    OWNER="${REPO%%/*}"
    if TOKEN="$(gh auth token --user "$OWNER" 2>/dev/null)"; then export GH_TOKEN="$TOKEN"; fi

    if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
      gh release upload "$TAG" "$ZIP" -R "$REPO" --clobber
      echo "Replaced $(basename "$ZIP") in release $TAG of $REPO"
    else
      gh release create "$TAG" "$ZIP" -R "$REPO" --target "$(git rev-parse HEAD)" \
        --title "TidyGrid $VERSION" \
        --notes "Install with Homebrew:

\`\`\`bash
brew tap $TAP
brew trust --cask $TAP/tidygrid
brew install --cask $TAP/tidygrid
\`\`\`

Or download TidyGrid-$VERSION.zip below and move the app to Applications.
Then allow TidyGrid under System Settings → Privacy & Security → Accessibility."
      echo "Published release $TAG of $REPO"
    fi

    # Point the cask at the new zip. Clone the tap inside build/ rather than using Homebrew's copy:
    # git then commits with the identity configured for this repo's location (e.g. an includeIf).
    TAP_DIR=build/tap
    rm -rf "$TAP_DIR"
    git clone -q "git@github.com:bombadiltom/homebrew-tap.git" "$TAP_DIR"
    CASK="$TAP_DIR/Casks/tidygrid.rb"
    sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA256\"/" "$CASK"
    if [[ -n "$(git -C "$TAP_DIR" status --porcelain -- Casks/tidygrid.rb)" ]]; then
      git -C "$TAP_DIR" commit -q -m "tidygrid $VERSION" -- Casks/tidygrid.rb
      git -C "$TAP_DIR" push -q
      echo "Updated and pushed the cask in $TAP to $VERSION"
    else
      echo "The cask in $TAP is already at $VERSION"
    fi
    ;;
esac
