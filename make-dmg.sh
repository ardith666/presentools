#!/bin/bash
# Rakit Presentools.dmg — drag ke Applications dengan visual layout, background,
# dan 1-click update script.
set -euo pipefail

cd "$(dirname "$0")"

APP="build/Presentools.app"
TEMP_DMG="build/temp.dmg"
DMG="build/Presentools.dmg"
BG_IMG="build/dmg-background.png"

[ -d "$APP" ] || { echo "error: run ./bundle.sh first"; exit 1; }
[ -f build/Presentools.icns ] || { echo "error: no build/Presentools.icns"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
VOL="Presentools ${VERSION}"

# 1. Pastikan background DMG sudah digenerate
swift tools/makedmgbackground.swift "$BG_IMG"

rm -f "$TEMP_DMG" "$DMG"

# 2. Buat read-write disk image sementara (~30MB)
hdiutil create -size 30m -fs HFS+ -volname "$VOL" -ov "$TEMP_DMG" >/dev/null

# 3. Mount disk image
MOUNT_INFO=$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG")
DEV_NAME=$(echo "$MOUNT_INFO" | head -n 1 | awk '{print $1}')
MOUNT_DIR=$(echo "$MOUNT_INFO" | grep "/Volumes/${VOL}" | sed 's/.*\/Volumes\//\/Volumes\//')

echo "Mounted $DEV_NAME at $MOUNT_DIR"

cleanup() {
  if [ -n "${MOUNT_DIR:-}" ] && [ -d "$MOUNT_DIR" ]; then
    hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
  fi
  rm -f "$TEMP_DMG"
}
trap cleanup EXIT

# 4. Salin .app dan buat symlink /Applications
cp -R "$APP" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"

# 5. Buat 1-click installer script jika user kesulitan men-drag saat app sedang running
cat > "$MOUNT_DIR/Install or Update.command" <<'INSTALLER'
#!/bin/bash
clear
echo "=================================================="
echo "          Presentools Installer & Updater         "
echo "=================================================="
echo ""
echo "Menghentikan Presentools lama jika sedang berjalan..."
pkill -x Presentools 2>/dev/null || true
sleep 1

DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Menyalin Presentools.app ke /Applications..."
rm -rf /Applications/Presentools.app
cp -R "$DIR/Presentools.app" /Applications/
xattr -dr com.apple.quarantine /Applications/Presentools.app 2>/dev/null || true

echo ""
echo "✅ Instalasi / Update berhasil!"
echo "Membuka Presentools..."
open /Applications/Presentools.app
sleep 1
echo "Jendela ini boleh ditutup."
INSTALLER
chmod +x "$MOUNT_DIR/Install or Update.command"

# 6. Salin gambar background
mkdir -p "$MOUNT_DIR/.background"
cp "$BG_IMG" "$MOUNT_DIR/.background/background.png"

# Pastikan permission world-readable dan bersihkan xattr kotor
chmod -R a+rX "$MOUNT_DIR"
xattr -c "$MOUNT_DIR/Applications" 2>/dev/null || true

# 7. Tata layout Finder dengan AppleScript
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "${VOL}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {350, 100, 930, 520}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 104
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "Presentools.app" of container window to {130, 180}
    set position of item "Applications" of container window to {410, 180}
    set position of item "Install or Update.command" of container window to {270, 310}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
APPLESCRIPT

# Sync disk cache
sync || true
sleep 1

# 8. Unmount image
hdiutil detach "$MOUNT_DIR"
MOUNT_DIR=""

# 9. Convert ke compressed read-only DMG (UDZO)
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
rm -f "$TEMP_DMG"

# 10. Verify DMG
hdiutil verify "$DMG" >/dev/null 2>&1 || { echo "error: dmg failed verify"; exit 1; }

echo "built $DMG ($(du -h "$DMG" | cut -f1))"
echo "open: open $DMG"
