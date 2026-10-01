#!/bin/bash
# Rakit Presentools.dmg — drag ke Applications.
#
# Standar macOS: volume berisi .app + symlink /Applications. Menyeret .app ke
# Applications = menyalin app, persis seperti app mana pun di App Store.
#
# `hdiutil create -srcfolder` sudah membuat volume read-only dengan sendirinya,
# jadi tidak perlu AppleScript untuk membuka window Finder atau mengatur layout.
set -euo pipefail

cd "$(dirname "$0")"

APP="build/Presentools.app"
STAGE="build/dmg"

[ -d "$APP" ] || { echo "error: run ./bundle.sh first"; exit 1; }
[ -f build/Presentools.icns ] || { echo "error: no build/Presentools.icns"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/Presentools-${VERSION}.dmg"
VOL="Presentools ${VERSION}"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"

# Symlink, bukan folder asli: volume jadi kecil dan drag tetap ke path yang benar.
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"

# Volume harus bisa dibaca ulang;DMG rusak lebih buruk daripada tidak ada.
hdiutil verify "$DMG" >/dev/null 2>&1 || { echo "error: dmg failed verify"; exit 1; }

echo "built $DMG ($(du -h "$DMG" | cut -f1))"
echo "open: open $DMG"
