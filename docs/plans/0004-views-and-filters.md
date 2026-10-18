# 0004 · Views are saved filters with a layout; lifecycle is just a filter

Status: accepted, proposal A · Owner request, 2026-10-18, decided 2026-10-18 (bdv-jlx) — "the Board is only useful on All; separate
*views* from *types*, which are filters on top; make Board, List and Tree primary; let me save
and share views across Beady instances." No code changes yet; this is the UI system to agree on
first. Three sidebar proposals are at the end, with a recommendation.

## 1. The workflow beads assumes

From the bd docs (core-concepts, README, `bd quickstart`, `bd ready --help`) and bd 1.3.1 itself:

- **One loop.** Create a bead → place it in the dependency graph → `bd ready` shows the frontier
  → `bd update --claim` (atomic: assignee + `in_progress`) → `bd close` → closing releases
  blockers, which makes new beads ready. The docs are explicit that *the graph, not a human
  dispatcher, decides what is workable next*, and that agents "ask for the frontier and claim
  atomically" rather than scanning the tracker.
- **Four lifecycle categories, seven built-in statuses.** `active` (open), `wip` (in_progress,
  blocked, hooked), `frozen` (deferred, pinned), `done` (closed). Custom statuses map onto the
  same four categories. Beady already models this (`StatusCatalog`).
- **Ready and blocked are computed, not stored.** Ready = active ∧ no open `blocks` upstream ∧
  not deferred into the future ∧ not held by a gate. Only `blocks` edges matter; `parent-child`,
  `related`, `discovered-from` don't affect readiness (except that a blocked parent blocks its
  children). bd's stored `blocked` status is a different, weaker thing; Beady follows the computed
  meaning, which is right.
- **Hierarchy is parent-child on any bead**, not an epic feature (plan 0002 already took this on).
  Hierarchical ids (`bd-a3f8.1.1`) are the visible form.
- **Labels, priority 0–4, type, assignee** are the attributes bd offers for slicing; `bd query`
  has a small boolean language over them (`status=open AND priority<=1 AND updated>7d`) with
  `--sort`. That is bd's own notion of a "view": a query string. There is no saved-view concept
  anywhere in bd.
- **The human's role is unwritten.** The docs describe the agent loop in detail and say nothing
  about how a person reviews progress beyond `bd list` filters, `bd status`/`bd stats` counts,
  `bd blocked`, `bd stale` and the dependency graph. That gap is what Beady exists to fill.

So the questions a supervising human asks, and the bd command each one shadows, are the real
spec for Beady's views:

| Question | bd today | What the answer looks like |
| --- | --- | --- |
| What can start right now? | `bd ready` | Active, unblocked, not deferred · list · by priority |
| What's being worked, and by whom? | `bd list --status in_progress` | wip · grouped by assignee (or status) |
| What's stuck, and on what? | `bd blocked` | blocked · list with a Blocked-by column |
| What moved recently? | `bd stale` (inverted), events journal | updated within 24h · by recency |
| How is *this* body of work going? | `bd dep tree`, `bd epic status` | under one bead · tree · with progress |
| What landed this week? | `bd list --status closed` | done, closed within 7d · by close date |
| The whole picture, one glance | `bd status`, `bd stats` | **everything · board · lifecycle columns** |

Every row is the same shape: **a filter over all beads, shown a particular way.** Nothing in the
left column is a *kind* of bead; "Ready" is not a type, it's a predicate.

## 2. Beady today, and why the Board feels wrong

Today a sidebar entry is a `ViewSource`: a lifecycle `Scope` (Open, Ready, In Flight, Blocked,
Deferred, Closed, All), a focused bead, or a label (Starred). Each source remembers its own
`ViewState` — filter rules, layout, grouping, ordering — in UserDefaults. Layout (List / Board /
Tree) is a per-view display choice chosen in the header. Board columns come from the grouping;
"no grouping" means lifecycle columns.

Three things are conflated in the sidebar:

1. **A lifecycle slice** (which is a filter: Open ≡ `lifecycle is active`; Ready ≡ `active ∧ not
   blocked ∧ not deferred`; In Flight ≡ `lifecycle is wip`; Blocked ≡ `blocked is yes`; …).
2. **A label filter** (Starred ≡ `labels includes starred`).
3. **A focus** (≡ `parent is X`, which already exists as a filter rule).

And the layout — the thing that most changes what you *see* — is invisible from the sidebar.

The Board is only good on All because a board needs columns that *split* the data, and six of the
seven sidebar entries pre-narrow to one lifecycle category. On Open with lifecycle columns you get
one column; grouped by status you get one column too (open is the only active status). The Board
isn't bad; it's being handed data with nothing to split.

Plan 0001 chose "sidebar is navigation only" and that lesson stands: a checkbox wall in a selectable
List was fragile and leaked filters between views. Nothing below puts facets back in the sidebar.

## 3. The model

```
   all beads  ──►  Filter (rules ∧ search)  ──►  Presentation (layout, grouping, order, columns)
                   ────────────────── a View = name + filter + presentation ──────────────────
```

**A View is a saved filter with a saved presentation.** That is the whole system. Everything the
sidebar shows today becomes a View over *all beads*:

| Today's source | Becomes | Filter |
| --- | --- | --- |
| Open | built-in view | `lifecycle · is · active` |
| Ready | built-in view **Frontier** | `ready · is · yes` |
| In Flight | built-in view | `lifecycle · is · wip` |
| Blocked | built-in view **Stuck** | `blocked · is · yes` |
| Deferred | built-in view | `lifecycle · is · frozen` |
| Closed | built-in view | `lifecycle · is · done` |
| All | built-in view **Everything** | (none) |
| Starred | built-in view | `labels · includes · starred` |
| Focus on a bead | a temporary `parent · is · X` chip on the current view | existing rule |

`ViewSource` goes away as a user-facing idea. Two filter fields are added so the table above is
expressible: **Lifecycle** (values active / wip / frozen / done; replaces `Scope.includes`) and
**Ready** (single-choice yes, computed exactly as `Scope.ready` is now). The existing rule that
status options are limited to the view's categories becomes derived: *limit status options to the
categories the view's Lifecycle rule allows*; with no Lifecycle rule, all of them.

### Rules the model needs to state plainly

- **Built-in views are locked; you duplicate them, you don't edit them** (owner, 2026-10-18:
  "shouldn't be possible to adjust the definition of baked-in default views, maybe just duplicate
  them"). A built-in's defining rules are shown as locked chips: a lock glyph, no ✕, no operator
  menu, and **Clear** leaves them alone. Its name and icon can't be changed either. What you *can*
  do on a built-in is temporary: add rules on top, flip the layout, grouping, ordering or columns.
  Those show the modified dot and the Save control offers only **Save as new view…** and
  **Reset**. **Duplicate** in a built-in's context menu makes a user view with the same filter and
  presentation, unlocked, under MY VIEWS, which is the one way to get "Frontier, but only P0/P1"
  as a permanent thing. The presentation flip on a built-in is still remembered per view across
  launches, as today, so Frontier stays a priority-sorted list and Pipeline stays a board.
- **User views own everything.** Filter and presentation are both saved; changing either shows the
  modified dot with **Save**, **Save as new view**, **Reset**.
- **Layout is part of a view, and flipping it is cheap.** ⌘1/2/3 and the header switcher keep
  working on any view. A built-in remembers the flip; a user view marks itself modified. So "Board
  of everything" and "List of everything" are either one view you flip, or two saved views —
  the user's call, not the app's.
- **Focus is a chip, not a view.** Focusing on a bead pushes `parent · is · X` onto the current
  view with the breadcrumb look it has now; ✕ pops it. Saving while focused bakes the chip in, which
  is how you get "Offline maps, as a tree" as a permanent view.
- **Filters stay AND-only, one rule per field.** Views are how you express OR: two views, not a
  query builder. If a real OR case appears, it's a new field, not a new operator (see "closed
  within" below).
- **A board on a view whose grouping yields one column tells you so**, and offers the groupings
  that would split it (status, priority, assignee, parent). It should never silently show a
  one-column board again.

### Vocabulary gaps the model exposes

- **`closed · within · 7d` should mean "hide done beads older than 7d"**, not "show only beads
  closed in the last 7d". On the Closed view (all done) the two readings are identical; on
  Everything the second reading throws away every open bead, which is why nobody can build the
  board they want today ("everything live, plus what landed this week"). The "show only what
  landed" reading is still one chip away: `lifecycle is done ∧ closed within 7d`. One semantics
  change, no new operator.
- **Lifecycle** and **Ready** fields, as above. Ready is single-choice (yes); "not ready" is
  not a question anyone asks.
- **Assignee is me.** bd's actor (`$BEADS_ACTOR`, git user.name) is knowable; `assignee · is ·
  me` makes shared views portable between people. Cheap, and worth it the moment a view is
  exported.
- Later, not now: *touched by* (events journal actor), *created within*.

### Words that mean something exact in bd get hover help

Ready, Blocked, Deferred, Pinned, Hooked, In Flight, Frozen, Done are not plain English here:
Ready is *active, no open `blocks` upstream, not deferred into the future, not held by a gate*;
Deferred is *the `deferred` status, frozen on purpose until a date or forever*; Blocked is
*computed from the dependency graph, not the stored `blocked` status*. Someone reading the sidebar
for the first time can't know that, and the names of the built-in views (Frontier, Stuck, Landed)
lean on it.

One pure glossary in BeadsPresentation, `DisplayText.help(for:)`, keyed by the thing being
described (a `FilterField`, a filter value, a `StatusCategory`, a status name, a built-in view),
returns the one-sentence definition, phrased from `bd statuses` and `bd ready --help` so it says
what bd says. The same string is the `.help()` tooltip on a sidebar row, a filter chip, a Filter
menu option, a status badge and a Display grouping label, and the description line in ⌘P. A
completeness test asserts every field, value, category, built-in status and built-in view has an
entry, so a new word can't ship without its definition.

## 4. Pre-baked views

Shipped with Beady, derived from the table in §1. Names say what the view answers, not which bd
status it is; the bd name is in the help text and ⌘P matches both.

| View | Filter | Layout · grouping · order |
| --- | --- | --- |
| **Frontier** (Ready) | ready is yes | List · none · priority; Blocked-by off |
| **In Flight** | lifecycle is wip | List · status · recently updated |
| **Stuck** (Blocked) | blocked is yes | List · none · priority; Blocked-by column on |
| **Pipeline** | closed within 7d (new semantics) | **Board** · lifecycle · priority |
| **Recent** | updated within 24h | List · assignee · recently updated |
| **Landed** | lifecycle is done ∧ closed within 7d | List · none · recently closed |
| **Deferred** | lifecycle is frozen | List · none · priority |
| **Everything** | — | List · lifecycle · recently updated |
| **Starred** | labels includes starred | List · lifecycle · priority (appears when non-empty) |

Open and Closed as separate entries go: Open is Everything minus three columns, Closed is Landed
without the window, and both are one chip away. If the owner wants them back they are two user
views. Pipeline is the Board the owner already uses on All, with the Done column kept to a week so
it stays a working surface rather than an archive.

### Icons

Every view has an icon, and it is never the List / Board / Tree glyph (owner: the layout switcher
in the header already owns those; a sidebar row should say what the view *answers*). The built-ins
ship with theirs; a user view picks from a small set, with a default, when it is saved or later
from **Change Icon…** in its context menu. A duplicate keeps its source's icon until changed.

| Built-in | Symbol | Why |
| --- | --- | --- |
| Frontier | `play.circle` | what can start now |
| In Flight | `circle.lefthalf.filled` | bd's own in-progress glyph |
| Stuck | `hourglass` | waiting on something upstream; quiet, not an alarm |
| Pipeline | `flowchart` | work flowing through stages |
| Recent | `clock` | what moved lately |
| Landed | `checkmark.circle` | done |
| Deferred | `snowflake` | bd's frozen category |
| Everything | `tray.full` | the whole database |
| Starred | `star.fill` | the star mark |

User set, default first: `bookmark`, `tag`, `flag`, `bolt`, `target`, `ladybug`,
`wrench.and.screwdriver`, `person`, `person.2`, `shippingbox`, `calendar`, `folder`, `lightbulb`,
`map`. Fourteen is enough to tell views apart and few enough to pick from a grid without
searching. Both sets live in one pure `ViewIcon` catalogue in BeadsPresentation; a test asserts
the symbols are non-empty, distinct from each other and from the three layout symbols. The
`symbol` field in the `.beadyview` file is the SF Symbol name, so an imported view that names a
symbol outside the set still renders, and the picker shows it as the current choice.

## 5. Saving, storing and sharing views (the mac-app part)

**Format.** One JSON document per view, the `Codable` shapes Beady already has plus a header:

```json
{
  "beadyView": 1,
  "id": "2F1A…",            "name": "Agent tiles",      "symbol": "square.grid.3x3",
  "filter": { "rules": [ { "field": "labels", "op": "includesAny", "values": ["agent-tiles"] } ],
              "searchText": "" },
  "presentation": { "layout": "board", "grouping": "status", "ordering": "priority",
                    "columns": ["priority", "id", "title", "assignee", "updated"] }
}
```

Exported file: `Agent tiles.beadyview`, a registered document type, so double-clicking one in
Finder opens Beady and imports it; dropping one on the sidebar does the same; **Share…** on a view
produces the file through the standard share sheet (AirDrop, Messages, Mail). A `.beadyviews`
bundle is just an array, for "send me your views".

**Where views live.** Two tiers, which the sidebar shows as two sections:

| Tier | Lives at | Syncs via | Who sees it |
| --- | --- | --- | --- |
| **Library** (yours) | `~/Library/Application Support/Beady/views/*.beadyview` | iCloud Key-Value Store, optional (1 MB cap; a view is ~400 bytes) | you, on every Mac signed into the same Apple ID |
| **This workspace** (one database's) | `.beads/beady/views/*.beadyview` next to the database | git, like `.beads/issues.jsonl` | everyone who clones the repo and opens it in Beady |

A view is dragged between the two sections to move it. The Library is the "across Beady app
instances" ask; the this-workspace tier is the natural extension because a view that names labels,
assignees or a parent id only means something in one database, and the repo is already how that
database travels. Both are plain files, so `cp` works when iCloud or git isn't wanted.

**Switching workspaces.** A workspace is what Beady already calls a database folder (one git
checkout, one `.beads`): `AppSession.workspace`, the Open Recent menu, the welcome screen's
Recent list. Today switching means File ▸ Open Recent or the welcome screen. The sidebar gets a
**workspace switcher** at its top: the workspace's display name and bd prefix, a click opens a
menu of the eight recents (name, path, the prefix as a badge) and **Open Other…**. ⌘P gets
`switch workspace <name>` from the same list, and ⌃⌘O cycles. Switching swaps the model in
place, as `AppSession.open` does now; the Library section stays, the this-workspace section and
the counts change. It lands after the views work, not before: the sidebar it sits on is rewritten
in step 4. Several workspaces open at once (one window each, or one window with several) is a
maybe for later, not part of this plan; the switcher is designed so that a second window would
simply be a second `AppSession`. Views carry across because the Library is per user, not per
database; a Library view that names a label or parent id this database doesn't have simply shows
a count of 0, which is honest.

**Migration.** Today's `viewStates` (UserDefaults, keyed by `ViewSource`) map one-to-one onto the
built-ins' remembered presentations; a lifecycle scope's filter rules, if any, become a modified
state on that built-in, and the first launch offers to save them as a user view. Nothing is lost.

**bd parity.** Each view gets **Copy as bd command**: `bd query "status=open AND priority<=1"
--sort priority` where the rules map (lifecycle, status, priority, type, assignee, labels, parent,
updated, closed, title words) and a comment line for what doesn't (ready, blocked are computed —
`bd ready` and `bd blocked` cover them). Same spirit as pinned being a real bd label.

## 6. Three sidebars

Common to all three: the header keeps `Filter`, the chips, the layout switcher and `Display`, and
gains a **Save** control that only appears when the view is modified:

```
[ Filter ]  Lifecycle · is · active ✕   Priority · is any of · P0, P1 ✕   Clear   [▤|▥|⌲]  [Display]  [Save ▾]
                                                                                             Save · Save as new view… · Reset
```

### Proposal A — Views are the sidebar (recommended)

The sidebar lists views and nothing else. Each row carries the view's own icon (see Icons in
§4), its count, and a modified dot when the live state differs from the saved view. Lifecycle
stops being a sidebar concept; it's a chip.

```
┌──────────────────────────┐
│ ▾ mapshop · demo         │  ← workspace switcher: recents, Open Other…
│──────────────────────────│
│ VIEWS                    │
│ ▷ Frontier            3  │
│ ◐ In Flight           5  │
│ ⧗ Stuck               6  │
│ ⇶ Pipeline           18  │  ← the board you actually use
│ ◷ Recent              4  │
│ ✓ Landed              4  │
│ ❄ Deferred            1  │
│ ▣ Everything         18  │
│                          │
│ MY VIEWS               + │
│ ⚑ Agent tiles         7  │
│ ⌖ Offline maps        6  │  ← a saved focus
│ ⚐ P0/P1 bugs •        2  │  ← modified since saved
│                          │
│ THIS WORKSPACE           │
│ ▭ Release board      11  │  ← from .beads/beady/views, via git
│                          │
│ ★ Starred             2  │
└──────────────────────────┘
```

- **Closest to today.** It is the current sidebar with three entries renamed, two dropped, two
  sections and the workspace switcher added. Plan 0001's "navigation only" rule holds.
- **Answers the Board complaint directly:** Pipeline is a built-in board on everything, one click.
- **Layout is one click away, not in the sidebar.** The header switcher changes it and a built-in
  remembers the flip. If "make Board/List/Tree primary" means *the first choice you make*, see C.
- Cost: a long sidebar once a person saves many views. Sections collapse; ⌘P already finds any
  view by name.

### Proposal B — Layout first, lifecycle as shortcuts

Layout becomes a mode at the top of the sidebar, global across views (a view remembers nothing
about layout). Below it, lifecycle rows are *shortcuts* that set the Lifecycle chip on the current
base, not views of their own. Views come last.

```
┌──────────────────────────┐
│ [ List ][ Board ][ Tree ]│  ← global, ⌘1/2/3
│                          │
│ SHOW                     │
│ ● Everything         18  │
│ ○ Frontier            3  │  single-click: sets the chip
│ ○ Active              8  │  ⌘-click: adds to it
│ ○ In Flight           5  │
│ ○ Stuck               6  │
│ ○ Frozen              1  │
│ ○ Done                4  │
│                          │
│ VIEWS                  + │
│   Pipeline               │
│   Agent tiles            │
│ ★ Starred             2  │
└──────────────────────────┘
```

- **Most literal reading of "layout primary, lifecycle is a filter."** You pick how to look, then
  what to look at.
- Problem: a global layout fights the per-view memory that makes Frontier-as-list and
  Pipeline-as-board both work. Clicking Board while on Frontier gives a one-column board, which is
  the exact complaint we started with, now one click more likely.
- Problem: the SHOW rows are the checkbox wall from before plan 0001 wearing radio buttons. Two
  selection models in one List (view rows vs. shortcut rows) was what broke then.
- Keep only if the owner really wants layout to be a mode. I don't recommend it.

### Proposal C — A layout rail, views per layout

Layout is a narrow icon rail on the far left (List, Board, Tree, and Graph, which is already a
window). The sidebar lists the views saved *for that layout*. Same filter can be saved under two
layouts as two views.

```
┌──┬───────────────────────┐
│▤ │ BOARDS                │
│▥●│ Pipeline          18  │
│⌲ │ By owner          18  │
│⟳ │ Agent tiles        7  │
│  │                       │
│  │ MY BOARDS           + │
│  │ Release board     11  │
│  │                       │
│  │ ★ Starred          2  │
└──┴───────────────────────┘
   rail: List · Board · Tree · Graph (● = current)
```

- **Layout is genuinely primary**, and each layout gets views that make sense *for it*: boards
  that split, trees rooted somewhere, lists sorted for scanning. The one-column board can't happen
  because nothing in BOARDS is defined without a splitting grouping.
- Graph joins the family naturally, which it can't in A or B.
- Cost: the mental model splits "what" from "how" in two places (a filter can exist under List and
  under Board as two things to maintain), and ⌘1/2/3 changes *which list of views you see* rather
  than how the current one looks, which is a bigger behaviour change. Also two sidebars' worth of
  horizontal space.
- The right move if, after living with A, the owner finds they always want the same four views in
  each layout.

### Recommendation

**A now, with C's rail held in reserve.** A keeps everything plan 0001 and 0002 got right,
resolves the Board problem by giving the board a proper home (Pipeline), makes layout legible
from the sidebar, and gives saving, library and workspace tiers a place to live. It is also the
smallest implementation: no new sidebar selection model, `ViewState` and `ViewFilter` already
encode almost everything a view file needs, and `ViewSource` collapses into two new filter fields.

## 7. What changes, in order, if A is taken

Working style for every step, from the owner: **tests first, pure functions, good architecture.**
The filter, view, glossary, query-rendering and library-merge logic are all pure and live in
BeadsCore or BeadsPresentation with tests; the app layer only wires them to AppKit and files.

1. **Core:** `FilterField.lifecycle` and `.ready`; `closed within` semantics; status-option
   limiting derived from the Lifecycle rule. Tests first (`ViewFilterTests`).
2. **Core:** `View` (id, name, symbol, filter, presentation, `isBuiltIn`) and the built-in table
   from §4; `ViewSource` removed, focus becomes a parent chip.
3. **Presentation:** `WorkspaceModel.view` replaces `source`; modified state; Save / Save as /
   Reset; migration of `viewStates`; one-column-board detection.
4. **UI:** sidebar sections and icons; header Save control; board "nothing to split" state.
5. **App:** `.beadyview` document type, Library and this-workspace stores, Share, drop-to-import,
   iCloud KVS behind a setting, Copy as bd command.
6. **App:** the workspace switcher at the top of the sidebar, once step 4's sidebar is in.
7. **Presentation + UI:** locked chips for a built-in's defining rules, Duplicate on built-ins;
   the `ViewIcon` catalogue, built-in icons, the user icon picker on save and in the context menu.
8. **Presentation + UI:** the hover-help glossary; independent of the rest and can land now,
   on today's sidebar, chips and badges; step 4 keeps it.
