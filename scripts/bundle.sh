#!/usr/bin/env bash
# Builds the SwiftPM executable and wraps it in build/Beady.app.
# The bundle is assembled beside the old one and swapped in with mv, so a
# running copy of the app is never overwritten in place.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-debug}"
SCRATCH="$ROOT/.build-app"
APP="$ROOT/build/Beady.app"
STAGING="$ROOT/build/Beady.app.staging"

swift build --package-path "$ROOT" -c "$CONFIG" --scratch-path "$SCRATCH" --product Beady
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --scratch-path "$SCRATCH" --show-bin-path)"

rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"
cp "$BIN_DIR/Beady" "$STAGING/Contents/MacOS/Beady"
cp "$ROOT/Resources/AppIcon.icns" "$STAGING/Contents/Resources/AppIcon.icns"

# A build number the OS can order: how many commits are behind this build.
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 0)"
VERSION="$(cat "$ROOT/VERSION")"
cat > "$STAGING/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Beady</string>
  <key>CFBundleDisplayName</key><string>Beady</string>
  <key>CFBundleIdentifier</key><string>me.bitsby.beady</string>
  <key>CFBundleExecutable</key><string>Beady</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$STAGING" >/dev/null 2>&1 || true

rm -rf "$APP"
mv "$STAGING" "$APP"
echo "Built $APP"
