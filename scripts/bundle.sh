#!/usr/bin/env bash
# Builds the SwiftPM executable and wraps it in build/Beady.app.
# The bundle is assembled beside the old one and swapped in with mv, so a
# running copy of the app is never overwritten in place.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=swift-flags.sh
source "$ROOT/scripts/swift-flags.sh"
CONFIG="${CONFIG:-debug}"
SCRATCH="$ROOT/.build-app"
APP="$ROOT/build/Beady.app"
STAGING="$ROOT/build/Beady.app.staging"

swift build --package-path "$ROOT" -c "$CONFIG" --scratch-path "$SCRATCH" --product Beady "${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}"
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --scratch-path "$SCRATCH" --show-bin-path "${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}")"

rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"
cp "$BIN_DIR/Beady" "$STAGING/Contents/MacOS/Beady"
cp "$ROOT/Resources/AppIcon.icns" "$STAGING/Contents/Resources/AppIcon.icns"

# Translations. SwiftPM compiles each module's Localizable.xcstrings into a resource bundle
# (Beady_<Module>.bundle); the library modules look theirs up through Bundle.module, so those
# bundles ride along whole. The app target's own strings are looked up in Bundle.main, the way
# an Xcode-built app does it, so its .lproj folders go straight into Contents/Resources — which
# is also what tells macOS the app is localised, so System Settings offers it a language.
for bundle in "$BIN_DIR"/Beady_*.bundle; do
  [[ -d "$bundle" ]] || continue
  if [[ "$(basename "$bundle")" == "Beady_Beady.bundle" ]]; then
    for lproj in "$bundle"/Contents/Resources/*.lproj; do
      [[ -d "$lproj" ]] && cp -R "$lproj" "$STAGING/Contents/Resources/"
    done
  else
    cp -R "$bundle" "$STAGING/Contents/Resources/"
  fi
done
# The development language has no .lproj of its own (its strings are the keys); an empty one
# declares it, so English stays on the list of languages the app offers.
mkdir -p "$STAGING/Contents/Resources/en.lproj"

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
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>Beady</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>me.bitsby.beady.view</string>
      <key>UTTypeDescription</key><string>Beady View</string>
      <key>UTTypeConformsTo</key><array><string>public.json</string></array>
      <key>UTTypeTagSpecification</key>
      <dict><key>public.filename-extension</key><array><string>beadyview</string></array></dict>
    </dict>
    <dict>
      <key>UTTypeIdentifier</key><string>me.bitsby.beady.views</string>
      <key>UTTypeDescription</key><string>Beady Views</string>
      <key>UTTypeConformsTo</key><array><string>public.json</string></array>
      <key>UTTypeTagSpecification</key>
      <dict><key>public.filename-extension</key><array><string>beadyviews</string></array></dict>
    </dict>
  </array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Beady View</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>LSItemContentTypes</key><array><string>me.bitsby.beady.view</string></array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>Beady Views</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>LSItemContentTypes</key><array><string>me.bitsby.beady.views</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST
# Signing. Ad hoc by default, which is what the releases get. With CODESIGN_IDENTITY (a
# Developer ID Application certificate) and TEAM_ID set, the app is signed for real with
# Resources/Beady.entitlements, which carries the iCloud Key-Value Store entitlement that
# syncing the view Library needs; the Settings toggle stays off without it.
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  : "${TEAM_ID:?set TEAM_ID to the Apple Developer team id the identity belongs to}"
  ENTITLEMENTS="$ROOT/build/Beady.entitlements"
  sed "s/TEAM_ID/$TEAM_ID/" "$ROOT/Resources/Beady.entitlements" > "$ENTITLEMENTS"
  codesign --force --sign "$CODESIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$STAGING"
else
  codesign --force --sign - "$STAGING" >/dev/null 2>&1 || true
fi

rm -rf "$APP"
mv "$STAGING" "$APP"
echo "Built $APP"
