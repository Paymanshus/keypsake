#!/bin/bash
# Builds a universal (Apple Silicon + Intel) keypsake.app and packages build/keypsake-<version>.dmg.
# Signed with the local keypsake-local identity (see setup-signing.sh). Not notarized: first launch needs
# System Settings → Privacy & Security → Open Anyway. Same identity every release keeps users' Accessibility grant.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

for arch in arm64 x86_64; do swift build -c release --triple "$arch-apple-macosx14.0"; done

OUT=build/release
APP=$OUT/keypsake.app
rm -rf "$OUT" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create .build/arm64-apple-macosx/release/Keypsake .build/x86_64-apple-macosx/release/Keypsake -output "$APP/Contents/MacOS/Keypsake"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/Fonts "$APP/Contents/Resources/"
cp LICENSE NOTICE "$APP/Contents/Resources/"

KC="$HOME/Library/Keychains/keypsake-dev.keychain-db"
security unlock-keychain -p "$(cat .signing-password)" "$KC"
ID=$(security find-identity -p codesigning "$KC" | awk '/keypsake-local/ {print $2; exit}')
codesign --force --keychain "$KC" --sign "$ID" "$APP"
codesign --verify --strict "$APP"

STAGE=$OUT/dmg
mkdir -p "$STAGE" && cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
DMG=build/keypsake-$VERSION.dmg
rm -f "$DMG"
hdiutil create -volname "keypsake $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
shasum -a 256 "$DMG"
