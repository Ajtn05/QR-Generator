#!/bin/bash
# Builds "QR Generator.app" into ./build — no Xcode project required.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/QR Generator.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# The icon is checked in; regenerate with --icon after editing Tools/MakeIcon.swift.
if [ "${1:-}" = "--icon" ] || [ ! -f Resources/AppIcon.icns ]; then
  ICONTOOL="$(mktemp -d)/makeicon"
  swiftc -O -parse-as-library -o "$ICONTOOL" Tools/MakeIcon.swift
  "$ICONTOOL" Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

swiftc -O -parse-as-library \
  -target arm64-apple-macos13.0 \
  -o "$APP/Contents/MacOS/QRGenerator" \
  Sources/*.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>QR Generator</string>
  <key>CFBundleDisplayName</key><string>QR Generator</string>
  <key>CFBundleExecutable</key><string>QRGenerator</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>local.qrgenerator</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
touch "$APP"   # nudge Finder to pick up the icon
echo "Built: $APP"
