# Beads Viewer

A native macOS app for looking at, and carefully changing, a
[beads](https://github.com/steveyegge/beads) (`bd`) database: what's open, what's in flight, what's
blocked, what got closed, and how work breaks down. Loading always uses `bd --readonly`. Editing is
always available, and every change goes through the checks described under **Editing** before it is
written.

## Install

Requirements: macOS 15 or later, and `bd` on your PATH.

**Build it yourself** (recommended — an app you build is never quarantined). You also need a
Swift 6 toolchain, from Xcode or the Command Line Tools:

```bash
git clone https://github.com/dvhthomas/beads-viewer.git
cd beads-viewer
scripts/bundle.sh && open build/BeadsViewer.app
```

**Or download a release.** Grab the zip from
[Releases](https://github.com/dvhthomas/beads-viewer/releases), unzip it, and move
Beads Viewer to /Applications. The app is ad-hoc signed but not notarised — there's no Apple
Developer ID behind it — so macOS quarantines it the first time. Either open it and then choose
**Open Anyway** in System Settings → Privacy & Security, or clear the flag yourself:

```bash
xattr -dr com.apple.quarantine /Applications/BeadsViewer.app
```

`scripts/release.sh` builds that zip locally; tagging `v*` builds and publishes it from CI.

## Run it

Open a project folder that contains `.beads` (or the `.beads` folder itself) with ⌘O. The last
workspace reopens on launch; `--workspace /path/to/project` overrides it.

While developing, `scripts/dev-watch.sh /path/to/project` rebuilds and relaunches the app whenever
`Sources/` changes (into its own `.build-app` folder, so it doesn't fight `swift test` for the lock).

## What you can see

- **Views** (sidebar, modelled on Linear, navigation only): Open, Ready (open and unblocked),
  In Flight, Blocked, Deferred, Closed and All, with each view's total. Categories come from `bd statuses`, so custom statuses
  land in the right place. Each view keeps its own filters, search, layout, grouping and ordering,
  so switching from Open to In Flight never carries Open's filters along.
- **Filter** (button or `F`, in the view header): pick a property, then tick values. The menu
  stays open, and each value shows how many issues you'd see. Rules appear as chips reading
  `Priority · is any of · P1, P2 · ✕`; click the operator to switch between `is` / `is not` (or
  `includes all / any / none` for labels), and the values to change them. Chips are ANDed, and a
  view's status options only include statuses that view can contain.
- **Display** (button or `⇧V`): layout (List, Board, Tree), grouping (Lifecycle, Status, Priority,
  Type, Assignee, Parent), ordering, and which columns the list shows.
- **Columns**: the list is a real table — drag the header dividers to resize, right-click the
  header (or use Display) to show and hide columns, including Labels and Progress. Your layout is
  saved between launches; **Reset Columns** puts it back.
- **Focus** (any row's context menu, or the details panel): points the whole view at everything
  under that bead, at any depth — for any bead, not just epics. A breadcrumb in the header names
  it, and its ✕ returns you to the view you came from.
- **Layouts**: List (a table with section headers per group), Board (a column per group, lifecycle
  when ungrouped), and Tree (parent/child outline, expanded by default, with completion;
  right-click to expand or collapse all).
- **Search** narrows the current view: every word must appear in the id, title, description,
  notes, labels or close reason.
  - Different facets are ANDed.
  - Within a single-valued facet (type, status, priority, assignee) the picked values are
    alternatives, because an issue has exactly one of each.
  - Labels are multi-valued, so every selected label is required.
  - Every search word must appear somewhere (id, title, description, notes, labels, close reason).
- **Tree context**: when a filter matches a child, its ancestors stay visible (dimmed) so nothing
  appears orphaned.
- **Details inspector**: metadata, parent / blocked-by / blocks / children links, description and
  notes (inline Markdown), close reason.
- **Auto-refresh**: the app watches the `.beads` folder with FSEvents and reloads within a moment
  of any write — yours or an agent's — falling back to a 15-second check. Nothing is opened or
  written to do it. ⌘R reloads on demand.
- **Other sessions**: bd has no lease or lock, so when another actor changed a bead recently
  (from `.beads/interactions.jsonl`) the details panel says who and when, the row is marked, and a
  change to that bead carries a warning on the confirmation sheet. It informs; it never blocks.

## Keyboard

`⌘P` opens the command palette: type a few letters to run any command or jump to a bead by id or
title. `?` lists every shortcut. `/` focuses search, `F` opens the filter menu, `⇧V` the display
options, `⌘N` a new bead, `⌘E` edits the selected one, `⌘I` toggles the details panel, `⌘1/2/3`
switch layout, `⌘O` opens a workspace, `⌘R` refreshes. Everything in the palette is also in the
menu bar.

## Editing

Editing is always on, and the confirmation sheet is the gate. You can:

- edit a bead's title, priority, description and notes (**Edit** in the details panel, or `⌘E`);
- move it under another bead (**Move To** in the details panel — anything that already holds work,
  not only epics — or drag a card or tree row onto another tree row);
- change its lifecycle, status, priority or parent by dragging a card to another board column
  (the board's grouping decides which), or change status with **Status** in the details panel;
- create a bead (**+** in the toolbar, or `⌘N`).

Nothing is written until you confirm a sheet showing the change, any warnings, and the exact bd
commands. Confirming runs `BeadsCore.ChangeRunner`, the only path to a write:

1. **Validate** against the loaded data: one-line, non-blank titles; priorities P0–P4; statuses the
   database knows; known types; parents that exist; no parent loops. Closing needs a reason, and
   epics with unfinished children and pinned beads can't be closed (bd refuses both). Clearing text,
   or closing a non-epic with unfinished children, is allowed but flagged. The checks run again when
   you confirm; if a refresh changed their outcome, you're asked to look again before anything is
   written.
2. **Check the live parent chain** for loops, one `bd show` per ancestor. bd itself doesn't prevent
   them.
3. **Compare with the live bead**, as the last step before writing: re-read it and refuse if any field
   being changed differs from the version you started from. An edit form keeps its starting version
   across auto-refreshes. bd has no atomic check-and-write, so a write by another session in the
   instant between this read and the write can't be stopped beforehand; step 5 catches its effects.
4. **Write through bd**: values as `--flag=value` with the id after `--` (text that looks like a flag
   stays text), closing via `bd close --reason`, leaving closed via `bd reopen`, and creates
   preflighted with bd's `--dry-run`. Descriptions and notes are written exactly as typed.
5. **Verify** by reading the bead back: every intended field, including the close reason, must be
   there. If bd reports an error or times out, the app waits for bd to exit and re-reads. A change
   that landed cleanly is recognised (for a create, by finding the new bead, so retrying won't
   duplicate it). A bead left as it was is a plain failure, safe to retry. Anything in between, such
   as a half-finished reopen or another session writing at the same moment, is reported as uncertain
   along with the bead's actual state.

While a change is being written the sheet can't be dismissed and nothing new can be proposed.

Outcomes are listed under **Changes** in the toolbar.

## Architecture

```
BeadsViewer (app target)      SwiftUI views + AppSession composition root
   │            │
   ▼            ▼
BeadsPresentation   BeadsData     WorkspaceModel (per-view state) │ BDGateway + BDStore
        │               │
        └──────► BeadsCore ◄──────┘  Issue, IssueSnapshot, Scope, IssueFilter,
                                     IssueQuery, IssueTree, IssueBoard  (pure, no I/O)
```

- **BeadsCore** is the domain: the snapshot, lifecycle scopes, Linear-style view filtering
  (`ViewSource`, `FilterRule`, `ViewFilter`, `FilterOptions`, `IssueGrouping`), sorting, tree
  building (cycle-safe), and the change pipeline (`IssueChange`, `ChangeValidator`, `ChangeGuard`,
  `ChangeRunner`). It defines the single `BeadsStore` port.
- **BeadsData** implements that port. Every bd invocation is a typed `BDCommand` run by one
  `BDGateway`, which also owns the change token and workspace detection. Reads always carry
  `--readonly`; the only writes are `update`, `close`, `reopen` and `create`. `BDStore` implements
  `BeadsStore` purely through the gateway, and an architecture test keeps it that way. Underneath:
  locating `bd` (Finder-launched apps get a minimal PATH), non-blocking pipe draining, timeouts and
  cancellation that escalate SIGTERM to SIGKILL (bd traps SIGTERM), and per-record JSON decoding.
- **BeadsPresentation** holds all view state and decisions in a UI-framework-free `@Observable`
  model, so it's unit-tested without SwiftUI.
- **BeadsViewer** is thin SwiftUI plus the composition root.

### Why the bd CLI rather than reading Dolt directly

bd owns its storage: embedded or server Dolt, schema migrations, and derived fields (`parent`,
dependency types, status categories). Reading Dolt tables directly would couple the viewer to
bd's internal schema and need a MySQL-protocol client or the Dolt engine embedded in the app.
One `bd --readonly list --json --all --limit 0 --flat` returns the whole database (about 0.3s for
~70 issues), and all filtering happens in memory, which keeps the UI instant. The loader sits
behind a protocol, so a direct Dolt adapter can replace it later without touching the rest.

### Change detection

Polling every 2s compares a fingerprint of `.beads/last-touched`, `.beads/issues.jsonl` (mtime
and size) and Dolt's `noms` files (**size only**). Even `bd --readonly` bumps the mtime of Dolt's
manifest and journal, so mtimes there would make every reload trigger another. Data older than
five minutes is reloaded regardless, to cover writes the probe can't see (such as a remote Dolt
server).

## Tests

```bash
scripts/test.sh
```

Swift Testing, test-first per layer: domain rules, JSON decoding against realistic bd output, the
CLI loader with a fake runner (asserting it only ever runs `--readonly list` / `statuses`), the
process runner (pipe deadlocks, timeouts), and the presentation model (loading, change-driven
refresh, scope/filter/sort, chips, tree, board).

An opt-in integration test uses the real `bd` against an existing workspace, read-only, and checks
that reading doesn't register as a change:

```bash
BEADS_VIEWER_IT_WORKSPACE=/path/to/project scripts/test.sh
```

A second opt-in test writes through the real bd: it creates epics and a bead, edits it, moves it
between epics, confirms a loop is refused, closes and reopens it, and checks the result. It only
runs against a workspace containing a `.beads-viewer-scratch` marker file, so it can't touch a real
project:

```bash
BEADS_VIEWER_IT_WRITABLE_WORKSPACE=/path/to/scratch-project scripts/test.sh
```

`scripts/test.sh` also passes the Swift Testing macro plugin path when only the Command Line Tools
are installed, since SwiftPM doesn't find it on its own there. For the same reason (no SwiftUI
macro plugin in the Command Line Tools) the views use `State` as a plain stored property rather
than the `@State` macro.

## Not yet

Editing labels, assignees and blocking dependencies; comments and history (`bd comments`,
`bd history`); and dependency graphs beyond parent/child and blockers.

## Developing

`scripts/test.sh` runs the suite (it passes the Swift Testing macro plugin path, which plain
`swift test` misses under Command Line Tools). Two opt-in integration suites run against a real
bd when you point them at one:

```bash
BEADS_VIEWER_IT_WORKSPACE=/path/to/project scripts/test.sh            # read-only
BEADS_VIEWER_IT_WRITABLE_WORKSPACE=/path/to/scratch scripts/test.sh   # writes; needs a
                                                                      # .beads-viewer-scratch marker
```

`BEADS_VIEWER_SNAPSHOT_DIR=/tmp/shots scripts/bundle.sh && … --workspace <project>` renders the
main views to PNGs offscreen, which is how UI changes get checked without a window.

`swift scripts/make-icon.swift` redraws `Resources/AppIcon.icns`.

This app's own work is tracked in beads, in this repo — `bd list` to see it.

## Licence

MIT. See [LICENSE](LICENSE).
