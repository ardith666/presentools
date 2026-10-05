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
# Filename has no version on purpose. The website links to
# /releases/latest/download/Presentools.dmg, which only resolves if the asset
# name is version-independent — otherwise every release breaks the download
# button on the landing page. The version still shows on the mounted volume.
DMG="build/Presentools.dmg"
VOL="Presentools ${VERSION}"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"

# cp -R applies the caller's umask to the modes it creates, so a shell running
# with umask 077 (common for a build user) silently downgrades a bundle that is
# already 755 in build/ back to 700 on its way into the DMG. The volume then
# ships a bundle only its build account can read, and Gatekeeper reports that as
# "damaged" instead of "unidentified" — with no way for the user to tell the two
# apart. Normalise here rather than trusting the caller.
chmod -R a+rX "$STAGE"

# Symlink, bukan folder asli: volume jadi kecil dan drag tetap ke path yang benar.
ln -s /Applications "$STAGE/Applications"

# Fail loudly instead of shipping a broken download: an unreadable binary inside
# a read-only volume is invisible at build time and only shows up as a Gatekeeper
# error on someone else's machine.
[ -r "$STAGE/Presentools.app/Contents/MacOS/Presentools" ] \
  || { echo "error: staged binary is not world-readable"; exit 1; }
[ -x "$STAGE/Presentools.app/Contents/MacOS/Presentools" ] \
  || { echo "error: staged binary is not executable"; exit 1; }

hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"

# Volume harus bisa dibaca ulang;DMG rusak lebih buruk daripada tidak ada.
hdiutil verify "$DMG" >/dev/null 2>&1 || { echo "error: dmg failed verify"; exit 1; }

echo "built $DMG ($(du -h "$DMG" | cut -f1))"
echo "open: open $DMG"
