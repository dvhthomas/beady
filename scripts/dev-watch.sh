#!/usr/bin/env bash
# Dev loop: rebuild and relaunch the app whenever Sources/ or Package.swift change.
#   scripts/dev-watch.sh [/path/to/project-with-.beads]
# Relaunches after the first one open in the background so they don't steal focus.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="${1:-}"
APP="$ROOT/build/BeadsViewer.app"
LOG="$ROOT/build/dev-watch-build.log"
mkdir -p "$ROOT/build"

fingerprint() {
  find "$ROOT/Sources" "$ROOT/Package.swift" -type f -exec stat -f '%m %z %N' {} + 2>/dev/null | sort | shasum | cut -d' ' -f1
}

launch() {
  local args=()
  [[ -n "$WORKSPACE" ]] && args=(--args --workspace "$WORKSPACE")
  if pgrep -x BeadsViewer >/dev/null; then
    pkill -x BeadsViewer
    while pgrep -x BeadsViewer >/dev/null; do sleep 0.2; done
    open -g "$APP" ${args[@]+"${args[@]}"}
  else
    open "$APP" ${args[@]+"${args[@]}"}
  fi
}

built=""
while true; do
  current="$(fingerprint)"
  if [[ "$current" != "$built" ]]; then
    # Debounce: wait until the tree has been quiet for a few seconds.
    sleep 3
    [[ "$(fingerprint)" != "$current" ]] && continue
    built="$current"
    echo "[dev-watch] $(date +%T) building…"
    if "$ROOT/scripts/bundle.sh" >"$LOG" 2>&1; then
      launch
      echo "[dev-watch] $(date +%T) relaunched"
    else
      echo "[dev-watch] $(date +%T) build failed; previous app left running"
      grep -E "error:" "$LOG" | head -5
    fi
  fi
  sleep 2
done
