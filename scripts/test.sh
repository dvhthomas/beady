#!/usr/bin/env bash
# Runs the test suite. Under Command Line Tools (no Xcode) SwiftPM cannot find the
# Swift Testing macro plugin on its own, so point the compiler at it explicitly.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

EXTRA=()
DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
PLUGINS="$DEV_DIR/usr/lib/swift/host/plugins/testing"
if [[ "$DEV_DIR" == *CommandLineTools* && -d "$PLUGINS" ]]; then
  EXTRA=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
fi

exec swift test --package-path "$ROOT" ${EXTRA[@]+"${EXTRA[@]}"} "$@"
