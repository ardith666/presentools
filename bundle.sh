#!/bin/bash
# Rakit Presentools.app dari hasil swift build.
# Info.plist wajib: LSUIElement bikin tray-only, dan identitas bundle yang
# dipacenahi ScreenCaptureKit — tanpa itu SCK melaporkan 0 display.
set -euo pipefail

cd "$(dirname "$0")"
CONFIG="${1:-release}"
APP="build/Presentools.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/presentools"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Presentools"

# Icon is optional: bundle.sh must keep working before tools/makeicon has run.
if [ -f build/Presentools.icns ]; then
  cp build/Presentools.icns "$APP/Contents/Resources/Presentools.icns"
else
  echo "note: no build/Presentools.icns - run tools/makeicon first for an icon"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>          <string>id.my.digitechnesia.presentools</string>
  <key>CFBundleName</key>                <string>Presentools</string>
  <key>CFBundleExecutable</key>          <string>Presentools</string>
  <key>CFBundlePackageType</key>         <string>APPL</string>
  <key>CFBundleShortVersionString</key>  <string>0.5.0</string>
  <key>CFBundleVersion</key>             <string>1</string>
  <key>LSMinimumSystemVersion</key>      <string>15.2</string>
  <key>LSUIElement</key>                 <true/>
  <key>CFBundleIconFile</key>           <string>Presentools</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Presentools needs Screen Recording to magnify what is on your screen. Spotlight and the laser pointer work without it.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign: unsigned bundles get killed by TCC, so the Screen Recording
# grant would never survive a relaunch.
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "warn: ad-hoc codesign failed"

echo "built $APP ($(du -sh "$APP" | cut -f1))"
