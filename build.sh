#!/bin/bash
# Builds TidyGrid.app into ./build. Pass "install" to copy it to /Applications and start it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/TidyGrid"

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
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x TidyGrid || true
  rm -rf /Applications/TidyGrid.app
  cp -R "$APP" /Applications/
  open /Applications/TidyGrid.app
  echo "Installed /Applications/TidyGrid.app"
fi
