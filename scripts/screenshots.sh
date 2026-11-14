#!/usr/bin/env bash
# Retakes every screenshot on the website (docs/website) from the app as it is now.
#
#     scripts/screenshots.sh              # into docs/website/assets/screenshots
#     scripts/screenshots.sh /some/dir    # somewhere else
#
# No window appears and nothing is clicked: the app has a snapshot mode (SnapshotMode.swift,
# BEADY_SNAPSHOT_DIR) that renders its views offscreen and exits. This script gives it
#   - a fresh demo database, made by scripts/demo-workspace.sh, so the beads are the same
#     every time and nobody's real backlog ends up on a web page; and
#   - a copy of the app under a throwaway bundle identifier, so it starts from factory
#     settings — your theme, column widths and collapsed sidebar sections don't leak into the
#     pictures, and the demo database doesn't land in your recent workspaces;
# then copies the snapshots the site uses to their names there. The Pages workflow runs this
# on every deploy, so the published site always shows the released app; run it by hand to see
# the result locally, or to refresh the copies kept in the repository.
#
# SKIP_BUILD=1 reuses build/Beady.app instead of rebuilding it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/docs/website/assets/screenshots}"
DOMAIN="me.bitsby.beady.screenshots"

# What the site calls each picture, and the snapshot it is. A snapshot that has gone missing
# (renamed in SnapshotMode.swift, say) fails the run rather than leaving a stale picture.
SHOTS=(
  "ready-dark=1-open-list"
  "ready-light=1b-open-list-light"
  "in-flight=2-in-flight-grouped-by-status"
  "stuck=2b-blocked-view"
  "filters=4-open-with-filter-chips"
  "filter-menu=7-filter-menu-priority"
  "views=20-sidebar-views-and-modified-frontier"
  "board=21-pipeline-board"
  "board-nested=25-pipeline-board-nested"
  "tree=6-focused-bead-tree"
  "details=24-detail-with-graph-pane"
  "waiting=14-waiting-detail"
  "graph=18b-graph-after-follow"
  "confirm=8-confirm-move"
  "new-bead=10-new-bead"
  "edit=16-edit-form"
  "palette=9-command-palette"
  "themes=11-themes"
)

WORK="$(mktemp -d "${TMPDIR:-/tmp}/beady-screenshots.XXXXXX")"
cleanup() {
  rm -rf "$WORK"
  defaults delete "$DOMAIN" >/dev/null 2>&1 || true
}
trap cleanup EXIT

[[ -n "${SKIP_BUILD:-}" ]] || "$ROOT/scripts/bundle.sh"
[[ -d "$ROOT/build/Beady.app" ]] || { echo "screenshots: build/Beady.app is missing; run scripts/bundle.sh" >&2; exit 1; }

cp -R "$ROOT/build/Beady.app" "$WORK/Beady.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $DOMAIN" "$WORK/Beady.app/Contents/Info.plist"
codesign --force --sign - "$WORK/Beady.app" >/dev/null 2>&1 || true
defaults delete "$DOMAIN" >/dev/null 2>&1 || true
# English whatever the Mac speaks, so the pictures match the words around them.
defaults write "$DOMAIN" AppleLanguages -array en

# The folder's name is the workspace's name in the sidebar.
"$ROOT/scripts/demo-workspace.sh" "$WORK/atlas"

BEADY_SNAPSHOT_SCALE=2 BEADY_SNAPSHOT_DIR="$WORK/shots" \
  "$WORK/Beady.app/Contents/MacOS/Beady" --workspace "$WORK/atlas" > "$WORK/snapshot.log" 2>&1 \
  || { cat "$WORK/snapshot.log" >&2; echo "screenshots: the app's snapshot mode failed" >&2; exit 1; }

missing=0
for shot in "${SHOTS[@]}"; do
  [[ -s "$WORK/shots/${shot#*=}.png" ]] || { echo "screenshots: no snapshot named ${shot#*=}.png" >&2; missing=1; }
done
[[ "$missing" -eq 0 ]] || { echo "screenshots: nothing copied; see SnapshotMode.run for the names" >&2; exit 1; }

mkdir -p "$OUT"
for shot in "${SHOTS[@]}"; do
  cp "$WORK/shots/${shot#*=}.png" "$OUT/${shot%%=*}.png"
done
echo "screenshots: ${#SHOTS[@]} written to $OUT"
