# 0001 · Linear-style navigation, filters and one bd gateway

Status: implemented · Owner request, 2026-09-14. All steps below are done: 184 tests green,
including the lifecycle-switch regression, the gateway architecture test, read-only bd parity on
mapshop, and the scratch write round trip. Verified with offscreen snapshots.

## Intent

The owner opens Beady to see how work is going and, occasionally, to make a careful change.
Today that's harder than it should be:

- **The sidebar is cluttered.** It mixes navigation (lifecycle, epics) with a long wall of filter
  checkboxes and pickers.
- **Filters don't "refresh properly" when moving between lifecycles** (Open → In Flight, say).

The ask is to follow the Linear desktop app's model for navigation, filtering and display, while
respecting that beads are not Linear issues. Work is test-first: pure filtering functions first,
then every read and write of beads/Dolt funnelled through one layer, then the UI.

## Why filters "don't refresh" today

- **Filters are global; the lifecycle is just another AND term.** Ticking Status → `open` while in
  Open, then clicking In Flight, keeps `status is open` *and* adds `category is in flight`. The
  result is always empty.
- **Stale values carry across views.** Priority, label and assignee ticks chosen for one view carry
  into the next, where their counts and meaning differ. Hidden zero-count options stay ticked, so
  results shrink for reasons the user can't see.
- **The sidebar List mixes selection rows with checkbox rows.** Sections appear and disappear as
  counts change (a facet with no options hides). A selectable SwiftUI `List` whose structure changes
  on every click is fragile. Rows and checkmarks can lag, and clicking a checkbox can fight the row
  selection.
- **Epic "subtree" is a filter chip that survives lifecycle clicks,** so a view silently stays
  narrowed to one epic.

## What we take from Linear

| Linear | Beady |
| --- | --- |
| Sidebar is navigation only: views, projects, teams | Sidebar is navigation only: **Views** (Open, Ready, In Flight, Blocked, Deferred, Closed, All) and **Epics** (open epics with progress) |
| Default tabs *All / Active / Backlog* are built-in filtered views | Lifecycle views are built-in views over bd's status categories and dependency state |
| **Filter** button / `F` → pick a property → tick values (menu stays open) | Same. Properties: Status, Priority, Type, Assignee, Labels, Blocked, Parent epic, Updated, Closed |
| Chip = property · operator · values · ✕, with a clickable operator | Same. `is` / `is not` for single-valued fields; `includes all / any / none` for labels; `within` for dates |
| Filters and display options are stored **per view** | Each view (every lifecycle view, every epic) keeps its own filters, layout, grouping and ordering. Switching views restores that view's state |
| **Display** button / `⇧V`: layout, grouping, ordering | Same. Layout List / Board / Tree; grouping None, Lifecycle, Status, Priority, Type, Assignee, Parent; ordering Priority, Updated, Created, Closed, ID |
| List grouped under group headers with counts | Same |
| Board columns = grouping | Same. Dropping a card into a column writes that column's value where that's a safe change: status (and lifecycle), and parent |

### What we deliberately don't copy

- **No teams, cycles, projects or triage.** Beads have one workspace per project folder; epics are
  parent beads and can nest.
- **Blocked and Ready are computed** from `blocks` dependencies (matching `bd ready` / `bd blocked`),
  not stored workflow states.
- **Status options in a filter are limited to the statuses that can appear in the view.** Filtering
  In Flight by `closed` is impossible, not merely empty.
- **Many agents write concurrently.** Views refresh from bd automatically, and all writes keep going
  through the confirmation sheet and `ChangeRunner`.
- **The tree layout stays.** Hierarchy matters more for beads than for Linear issues.
- **Views stay in memory for the session.** No saved custom views yet.

## Filter semantics (pure, in BeadsCore)

- **A view** = source (a lifecycle scope, or everything under an epic) ∧ rules ∧ search words.
- **Rules:** at most one per field, kept in the order added, and ANDed together.
- **Operators by field:**

  | Field | Default | Other operators | Matches |
  | --- | --- | --- | --- |
  | Status, Priority, Type, Assignee | `is any of` | `is none of` | Assignee includes Unassigned |
  | Labels | `includes all of` | `includes any of`, `includes none of` | |
  | Blocked | `is` | `is not` | Uses dependency state |
  | Parent epic | `is any of` | `is none of` | Anywhere under the epic, at any depth |
  | Updated, Closed | `within` | | One window at a time: 24h / 7d / 30d / 90d |

- **Ticking and unticking:** ticking a value adds the rule with its default operator. Unticking the
  last value removes the rule. Single-choice fields (Blocked, dates) replace their value.
- **Option counts** are computed within the view, under every rule *except the field's own*, so
  adding a second value is always informed. Status options are limited to the view's categories.
  Priority, Status, Blocked and date options are always listed. Long lists (Type, Assignee, Labels,
  Parent) hide zero-count values unless ticked.
- **Grouping is a pure function** with a stable order:
  - lifecycle order for Lifecycle and Status;
  - numeric for Priority;
  - alphabetical for Type, with Unassigned and No parent last.
  - Board columns can be forced to exist (so there's always a column to drop into).

## One gateway for bd and Dolt

Every operation that touches beads data goes through one layer in BeadsData:

- `BDGateway` owns the workspace, the bd executable and the process runner.
- **Commands.** Every bd invocation is a typed `BDCommand`. Read commands always run with
  `--readonly`; the only mutating commands are `update`, `close`, `reopen` and `create`. Arguments
  are built in one place: `--flag=value`, with the id after `--`.
- **Direct file reads.** Reads of Dolt and `.beads` files (the change token) are gateway methods.
- **Port.** `BDStore` implements BeadsCore's single `BeadsStore` port (load snapshot, live read,
  find created, apply, preview, change token) purely through the gateway.
- **Model.** `WorkspaceModel` receives one `BeadsStore`, so there are no separate loader, writer and
  fingerprint closures.
- **Fitness test.** An architecture test scans `Sources/` so that only the gateway builds bd
  arguments and only `CommandRunner.swift` spawns processes.

## Work plan

1. **Plan** (this document).
2. **Failing tests, then implementation, for pure filtering** in BeadsCore: `FilterRule` and
   `ViewFilter` (operators, ticking, AND, search), `ViewSource` (lifecycle / epic, allowed
   categories), `FilterOptions` (counts excluding own rule, category-limited statuses, hiding
   rules) and `IssueGrouping`.
3. **Failing tests, then the gateway:**
   - `BDCommand` arguments and read-only classification;
   - `BDStore` over a fake runner;
   - the architecture fitness test;
   - migrate the loader, writer and change probe into it;
   - `WorkspaceModel` takes one `BeadsStore`.
4. **Failing tests, then presentation:**
   - per-view state, including the lifecycle-switch regression;
   - chips with operator menus;
   - option labels and counts;
   - grouped list sections;
   - board columns and drop targets per grouping;
   - sidebar items with unfiltered counts.
5. **UI:**
   - sidebar = Views + Epics only;
   - header filter bar (Filter menu, chips, Clear) and a Display popover;
   - grouped list;
   - board by grouping;
   - tree;
   - keyboard shortcuts `F` and `⇧V`.
6. **Verify:** unit tests, bd integration (read-only on mapshop, writes on the marked scratch db),
   offscreen snapshots of each layout, relaunch the app.

## Later

Saved custom views, persisting view state across launches, `My beads` (needs an actor identity),
and advanced AND/OR filter groups.

## References

- [Linear Docs: Filters](https://linear.app/docs/filters)
- [Linear Docs: Display options](https://linear.app/docs/display-options)
- [Linear Docs: Custom views](https://linear.app/docs/custom-views)
- [Linear Docs: My issues](https://linear.app/docs/my-issues)
