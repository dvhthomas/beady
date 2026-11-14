#!/usr/bin/env bash
# Builds the small made-up beads database the website's screenshots are taken from: a mapping
# app with three epics, work in every lifecycle, a few blockers, a pin and two stars.
#
#     scripts/demo-workspace.sh /path/to/new/folder
#
# It is made through the real `bd`, one command per bead, rather than imported from a file:
# the views in the screenshots (Recent, Landed, "closed within 7 days") are relative to now,
# so the dates have to be fresh, and bd's own commands survive bd's storage changing shape.
# Children take their ids from their parent in creation order (map-1.1, map-1.2, …), so the
# order below is what keeps the ids — and the screenshots — the same from run to run.
set -euo pipefail

DIR="${1:?usage: demo-workspace.sh <new folder>}"
command -v bd >/dev/null || { echo "demo-workspace: bd is not on PATH (brew install beads)" >&2; exit 1; }
if [[ -e "$DIR" ]] && [[ -n "$(ls -A "$DIR" 2>/dev/null)" ]]; then
  echo "demo-workspace: $DIR exists and is not empty; give a new folder" >&2
  exit 1
fi

mkdir -p "$DIR"
cd "$DIR"
git init -q .
# bd init commits .beads to the repository, and a CI runner has no git identity of its own.
git config user.name "Beady Demo"
git config user.email "ann@atlas.example"
# bd warns on stderr that the new database has no Dolt remote; true, and beside the point here.
bd init --non-interactive --skip-agents --skip-hooks --prefix=map >/dev/null 2>"$DIR/.bd-init.log" \
  || { cat "$DIR/.bd-init.log" >&2; exit 1; }
rm -f "$DIR/.bd-init.log"

# new <actor> <title> [bd create flags…]: creates a bead and prints nothing.
new() {
  local actor="$1" title="$2"
  shift 2
  bd create "$title" --actor "$actor" --silent "$@" >/dev/null
}
# start <actor> <id>: that actor picks the bead up.
start() { bd update "$2" --actor "$1" --status in_progress --assignee "$1" -q; }
# finish <actor> <id> <reason>
finish() { bd close "$2" --actor "$1" --reason "$3" -q; }

# --- Offline maps -------------------------------------------------------------------------
new Ann "Offline maps" --id map-1 -t epic -p 1 -l offline \
  -d "Download a region and keep using the map with no signal: tiles, search and routing."
new Ann "Tile cache eviction" --parent map-1 -t task -p 1 \
  -d "The cache grows without bound. Evict least-recently-drawn tiles past the size the user picked."
new Bo "Download queue stalls after sleep" --parent map-1 -t bug -p 0 -l pinned \
  -d "After the lid closes mid-download the queue never resumes; the user has to restart."
new Ann "Region picker on the globe" --parent map-1 -t feature -p 2 --deps blocked-by:map-1.1 \
  -d "Drag out a region on the globe and see what it will cost in megabytes before downloading."
new Ann "Stale tile detection" --parent map-1 -t task -p 2 -l starred \
  -d "Mark tiles older than the server's and refresh them quietly on Wi-Fi."
new Bo "Resume partial downloads" --parent map-1 -t feature -p 2 --deps blocked-by:map-1.2 \
  -d "Keep the byte ranges already fetched, so a dropped connection costs seconds rather than the region."
new Ann "Storage budget setting" --parent map-1 -t task -p 3 \
  -d "A slider in Settings for how much disk offline maps may use."

# --- Print layouts ------------------------------------------------------------------------
new Bo "Print layouts" --id map-2 -t epic -p 2 -l print \
  -d "Compose a map with a legend, scale bar and callouts, and export it for print."
new Bo "Callout leader lines" --parent map-2 -t feature -p 2 \
  -d "A callout keeps a line to the place it describes when it's dragged away from it."
new Bo "Legend auto-layout" --parent map-2 -t task -p 3 --deps blocked-by:map-2.1 \
  -d "Legend entries wrap into columns that fit the frame, rather than running off the page."
new Ann "Freeform furniture positioning" --parent map-2 -t feature -p 1 \
  -d "Scale bar, north arrow and legend go wherever they're dropped, with snapping to the margins."
new Bo "PDF export at 300 dpi" --parent map-2 -t task -p 2 \
  -d "Vector where possible; raster layers resampled to 300 dpi."

# --- Renderer performance -----------------------------------------------------------------
new Ann "Renderer performance" --id map-3 -t epic -p 1 -l renderer \
  -d "Sixty frames a second while panning a city at street level, on the oldest Mac we support."
new Ann "Globe midpoint seam" --parent map-3 -t bug -p 1 \
  -d "A one-pixel seam along the antimeridian at zoom levels 2 to 4."
new Ann "Split the layout pass" --parent map-3 -t task -p 1 \
  -d "Label layout runs on the render thread; move it off."
new Ann "Label collision cache" --parent map-3 -t task -p 2 \
  -d "Reuse last frame's collision boxes when the camera has barely moved."
new claude "Profile the tessellator" --parent map-3 -t task -p 2 \
  -d "Find where polygon tessellation spends its time on dense city blocks."

# --- On their own -------------------------------------------------------------------------
new Bo "Agent tiles for the dashboard" --id map-4 -t feature -p 2 -l agent-tiles,starred \
  -d "A tile per running agent on the team dashboard: what it holds, and what it's waiting for."
new Ann "Crash rotating during a route preview" --id map-5 -t bug -p 1 -l renderer \
  -d "Rotating the device while the route preview animates dereferences a freed camera."
new Bo "Upgrade the geocoder client" --id map-6 -t chore -p 3 \
  -d "Two major versions behind; the new one batches reverse lookups."
new Ann "Vector or raster hillshade" --id map-7 -t decision -p 2 -l renderer \
  -d "Vector hillshade is sharper and themeable; raster is a tenth of the work. Decide before map-3 lands."
new Bo "Search by coordinates" --id map-8 -t feature -p 3 \
  -d "Paste 51.5072, -0.1276 into search and go there."
new Ann "Dark basemap" --id map-9 -t feature -p 3 \
  -d "A basemap drawn for dark mode, rather than the light one inverted."
new claude "Measure tool snaps to roads" --id map-10 -t feature -p 2 \
  -d "Hold Option while measuring and the line follows the road network."

# --- What waits on what -------------------------------------------------------------------
# blocks <blocker> <waiting>. Besides the --deps above, these make chains more than one hop
# long, so the dependency graph has a bead with work on both sides of it.
blocks() { bd dep add "$2" "$1" >/dev/null; }
blocks map-3.2 map-3.1   # the seam can't be fixed until layout is off the render thread
blocks map-1.5 map-1.3   # the region picker shows resumable progress
blocks map-1.1 map-1.6   # the budget is what eviction enforces
blocks map-2.2 map-2.3   # furniture snaps to the legend's frame

# --- Where the work stands ----------------------------------------------------------------
start Ann map-1.1
start Ann map-1.2
start Bo map-2.1
start Ann map-3.2
start claude map-10

start Bo map-2.4
finish Bo map-2.4 "Exports match the proof at 300 dpi; vector text survives."
start Ann map-3.3
finish Ann map-3.3 "Cache hit rate 94% while panning; layout time down a third."
start claude map-3.4
finish claude map-3.4 "Profile attached: 60% of the time is in ear clipping. Filed map-3.2 from it."

bd defer map-8 --actor Bo --reason "After offline maps ships." >/dev/null
bd defer map-9 --actor Ann --reason "Waiting on the design refresh." >/dev/null

echo "demo-workspace: $(bd --readonly list --all --limit 0 --json | grep -c '"id"') beads in $DIR"
