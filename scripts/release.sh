#!/usr/bin/env bash
# Builds a release-configuration app and zips it for a GitHub Release.
#
#     scripts/release.sh            # build/BeadsViewer-<version>.zip
#     VERSION=0.2.0 scripts/release.sh
#
# The zip is made with ditto, which preserves the bundle's structure and the
# ad-hoc signature; `zip` alone can mangle both.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(cat "$ROOT/VERSION")}"

CONFIG=release "$ROOT/scripts/bundle.sh"

ZIP="$ROOT/build/BeadsViewer-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$ROOT/build/BeadsViewer.app" "$ZIP"
echo "Wrote $ZIP"
echo
echo "The app is ad-hoc signed, not notarised, so a downloaded copy is quarantined."
echo "Release notes should tell people to either:"
echo "  • open it once, then allow it in System Settings > Privacy & Security > Open Anyway; or"
echo "  • run: xattr -dr com.apple.quarantine /Applications/BeadsViewer.app"
