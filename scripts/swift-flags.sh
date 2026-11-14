#!/usr/bin/env bash
# Sourced by the other scripts: the flags every swift build / swift test here needs.
#
# The String Catalogs (Localizable.xcstrings) are compiled into .lproj folders only by SwiftPM's
# Swift Build backend. The older build system copies the catalog file into the bundle untouched,
# which Foundation can't read: the app comes up in English with no plural forms, and the tests
# that check a plural fail. Swift 6.4 uses Swift Build by default; Swift 6.1 to 6.3 have it
# behind --build-system swiftbuild; older toolchains have neither, and get no flag (and no
# translations).
SWIFT_FLAGS=()
if swift build --help 2>/dev/null | grep -q -- '--build-system'; then
  SWIFT_FLAGS=(--build-system swiftbuild)
fi
