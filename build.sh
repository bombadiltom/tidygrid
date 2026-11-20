#!/bin/bash
# Builds TidyGrid.app (Apple silicon + Intel) into ./build.
#   ./build.sh                    build only
#   ./build.sh install            also copy to /Applications here and start it
#   ./build.sh deploy HOST...     also copy to /Applications on each SSH host and start it there
#   ./build.sh release            also zip it and publish it as a GitHub release of this repo
#                                 (version from Resources/Info.plist; re-running replaces the zip)
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${1:-}" == "release" ]]; then
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

# A stable signing identity keeps the Accessibility permission across rebuilds.
IDENTITY="${SIGN_IDENTITY:-Apple Development}"
if ! codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP" 2>/dev/null; then
  echo "No '$IDENTITY' certificate found, signing ad hoc (Accessibility must be granted again after each build)."
  codesign --force --sign - "$APP"
fi
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/TidyGrid"))"

case "${1:-}" in
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
    ZIP=build/TidyGrid.zip
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"

    # Publish with the account that owns the repo, whichever gh account is active.
    REPO="$(git remote get-url origin | sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##')"
    OWNER="${REPO%%/*}"
    if TOKEN="$(gh auth token --user "$OWNER" 2>/dev/null)"; then export GH_TOKEN="$TOKEN"; fi

    if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
      gh release upload "$TAG" "$ZIP" -R "$REPO" --clobber
      echo "Replaced TidyGrid.zip in release $TAG of $REPO"
    else
      gh release create "$TAG" "$ZIP" -R "$REPO" --target "$(git rev-parse HEAD)" \
        --title "TidyGrid $VERSION" \
        --notes "Install or update on a Mac with gh access to this repo:

\`\`\`bash
gh release download -R $REPO -p TidyGrid.zip -D /tmp --clobber && { pkill -x TidyGrid; rm -rf /Applications/TidyGrid.app; ditto -x -k /tmp/TidyGrid.zip /Applications && open /Applications/TidyGrid.app; }
\`\`\`

Then allow TidyGrid under System Settings → Privacy & Security → Accessibility."
      echo "Published release $TAG of $REPO"
    fi
    ;;
esac
