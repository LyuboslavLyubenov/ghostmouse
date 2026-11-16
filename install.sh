#!/bin/bash
# Build, sign and install GhostMouse for the current user.
set -euo pipefail
cd "$(dirname "$0")"

if ! xcode-select -p >/dev/null 2>&1; then
    echo "Xcode Command Line Tools are required: xcode-select --install" >&2
    exit 1
fi

./package.sh

TARGET="$HOME/Applications"
mkdir -p "$TARGET"
rm -rf "$TARGET/GhostMouse.app"
cp -R "dist/GhostMouse.app" "$TARGET/"

BIN="$TARGET/GhostMouse.app/Contents/MacOS/ghostmouse"
echo
echo "installed: $TARGET/GhostMouse.app"
echo
echo "Grant permissions, then verify:"
echo "  1. System Settings > Privacy & Security > Accessibility     : add GhostMouse.app"
echo "  2. System Settings > Privacy & Security > Screen Recording  : add GhostMouse.app"
echo "  3. $BIN request-permissions"
echo "  4. $BIN selftest    (both flags must be true)"
echo
echo "MCP command: $BIN"
