#!/bin/bash
# Build and assemble a .app bundle so the binary has a stable TCC identity.
# TCC (Accessibility / Screen Recording) grants are tied to the bundle, so
# rebuilds keep their permissions as long as the bundle id and path stay put.
set -euo pipefail

cd "$(dirname "$0")"

APP="dist/GhostMouse.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ghostmouse "$APP/Contents/MacOS/ghostmouse"
mkdir -p "$APP/Contents/Resources/playbooks"
cp playbooks/*.md "$APP/Contents/Resources/playbooks/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>          <string>dev.ghostmouse.app</string>
    <key>CFBundleName</key>                <string>GhostMouse</string>
    <key>CFBundleDisplayName</key>         <string>GhostMouse</string>
    <key>CFBundleExecutable</key>          <string>ghostmouse</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>0.1.0</string>
    <key>CFBundleVersion</key>             <string>1</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>LSUIElement</key>                 <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Drives the target app for computer-use actions.</string>
    <key>NSHighResolutionCapable</key>     <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "built: $APP"
codesign -dv "$APP" 2>&1 | sed -n '1,6p'
