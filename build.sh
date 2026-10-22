#!/bin/bash
# Builds keypsake.app and installs it to /Applications.
#   ./build.sh          release build + install + launch
#   ./build.sh --no-run build + install only
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/keypsake.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Keypsake "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/Fonts "$APP/Contents/Resources/"

# A stable identity keeps the Accessibility permission across rebuilds; ad-hoc signing would reset it every time.
KC="$HOME/Library/Keychains/keypsake-dev.keychain-db"
if [[ -f "$KC" && -f .signing-password ]]; then
  security unlock-keychain -p "$(cat .signing-password)" "$KC"
  ID=$(security find-identity -p codesigning "$KC" | awk '/keypsake-local/ {print $2; exit}')
  codesign --force --keychain "$KC" --sign "$ID" "$APP"
else
  echo "warning: run scripts/setup-signing.sh once; signing ad-hoc for now (Accessibility resets each build)"
  codesign --force --sign - "$APP"
fi

pkill -x Keypsake 2>/dev/null && sleep 0.5 || true
rm -rf /Applications/keypsake.app
cp -R "$APP" /Applications/
echo "installed /Applications/keypsake.app"
[[ "${1:-}" == "--no-run" ]] || open /Applications/keypsake.app
