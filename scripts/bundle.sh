#!/bin/sh
# Builds "Keyboard Trainer.app" and puts it in ~/Applications.
set -eu
cd "$(dirname "$0")/.."

swift build -c release
APP="build/Keyboard Trainer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/KeyboardTrainer "$APP/Contents/MacOS/KeyboardTrainer"

# AppIcon.icon is an Icon Composer file. actool turns it into a Liquid Glass
# icon (Assets.car) plus a flat .icns for older macOS.
xcrun actool AppIcon.icon --compile "$APP/Contents/Resources" --app-icon AppIcon \
  --platform macosx --target-device mac --minimum-deployment-target 14.0 \
  --output-partial-info-plist build/icon-partial.plist >/dev/null

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Keyboard Trainer</string>
  <key>CFBundleDisplayName</key><string>Keyboard Trainer</string>
  <key>CFBundleIdentifier</key><string>com.alii.keyboard-trainer</string>
  <key>CFBundleExecutable</key><string>KeyboardTrainer</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"

DEST="$HOME/Applications/Keyboard Trainer.app"
mkdir -p "$HOME/Applications"
pkill -x KeyboardTrainer 2>/dev/null || true
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "Installed to $DEST"
