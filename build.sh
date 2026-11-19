#!/bin/bash
# Builds TidyGrid.app (Apple silicon + Intel) into ./build.
#   ./build.sh                    build only
#   ./build.sh install            also copy to /Applications here and start it
#   ./build.sh deploy HOST...     also copy to /Applications on each SSH host and start it there
set -euo pipefail
cd "$(dirname "$0")"

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/TidyGrid"

APP=build/TidyGrid.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TidyGrid"
cp Resources/Info.plist "$APP/Contents/Info.plist"
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
esac
