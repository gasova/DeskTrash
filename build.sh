#!/bin/bash
# Builds DeskTrash.app next to this script. Requires the Xcode command line tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="DeskTrash.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O main.swift -o "$APP/Contents/MacOS/DeskTrash"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DeskTrash</string>
    <key>CFBundleDisplayName</key><string>DeskTrash</string>
    <key>CFBundleIdentifier</key><string>local.desktrash</string>
    <key>CFBundleExecutable</key><string>DeskTrash</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSUIElement</key><true/>
    <key>LSMultipleInstancesProhibited</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>DeskTrash asks Finder to move items to the Trash, open it and empty it.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
