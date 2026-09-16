# 0002 · Epics stop being a special case

Status: implemented · Owner request, 2026-09-15 — "the Epics area on the left panel has unclear
purpose. If it's removed, what would need to be added to the main panel? This should be
consistent, not 'special' for Epics."

## What the Epics section does today

The sidebar's second section lists every unfinished bead whose *type* is `epic`, with a
`done/total` bar. It provides four things, each of which is really a general idea wearing an
epic-shaped costume:

1. **Discovery** — which containers exist and which are unfinished.
2. **Progress** — how much of a container is done.
3. **Scoping** — clicking one points the whole main panel at everything under it.
4. **Re-parenting** — a bead dragged onto one becomes its child.

Nothing here is true only of epics. bd's parent/child graph is the same relation whatever the
types are: a task can have children, and a feature can contain a spike. The sidebar quietly
claims otherwise, which is why the section reads as arbitrary.

## What replaces it in the main panel

Each capability becomes something that works for **any** bead:

| Today (epics only) | Replacement (every bead) |
| --- | --- |
| Discovery: sidebar list | Filter chip `Type is any of epic` — one click in the Filter menu — and ⌘P, which finds any bead by id or title |
| Progress: bar per epic | A **Progress column** in the list (`3/14`), shown for any bead that has children, plus the count in a group header when grouping by Parent |
| Scoping: click an epic | **Focus** on any row (context menu, ⌥⌘F… no — context menu + the details panel), with a clear way back |
| Re-parenting: drop onto the sidebar | Drop onto any row in Tree layout, or the "Move To" menu in the details panel (both already exist) |

The sidebar goes back to being navigation only — the lifecycle views — which is what Linear's
sidebar is.

## Focus, stated plainly

`ViewSource.epic(id)` already exists and already means "everything under this bead, at any depth,
in any status". Only its *name* is epic-flavoured. This plan keeps the mechanism and:

- renames the user-facing action to **Focus** ("Focus on this bead's work"), available from any
  row's context menu and from the details panel, not only for `type == epic`;
- shows the focused bead in the filter bar as a chip-like breadcrumb with a ✕ that returns to the
  previous lifecycle view, so focus is visible and reversible (today you can get stuck in an epic
  view with no obvious exit);
- keeps per-view filters, so a focused view remembers its own filters exactly like a lifecycle view.

## Work plan

1. Failing tests first, in `BeadsPresentationTests`:
   - focusing works for a bead of any type, and `unfocus()` returns to the view you came from;
   - the breadcrumb describes the focused bead;
   - `ListColumn.progress` exists, is hidden by default, and renders `done/total` only for beads
     with children;
   - grouping by parent puts progress in the group header.
2. Implement in `BeadsPresentation`: `focus(on:)` / `unfocus()` / `focusBreadcrumb`, progress in
   `IssueGroupModel`, the new column.
3. UI: drop the sidebar's Epics section; add the breadcrumb to the filter bar; add "Focus" to the
   row context menu and the details panel; add the Progress column to the table and the Display
   menu; keep `Type is any of epic` one click away in the Filter menu.
4. Re-render the offscreen snapshots and relaunch.

## Landed

All of the above, 2026-09-15: the sidebar is lifecycle views only; `focus(on:)`/`unfocus()` work
for any bead with the breadcrumb in the header; `ListColumn.progress` and parent group headers show
`done/total`; the Parent filter now offers any unfinished bead with children; **Move To** offers
`parentChoices`, which is the same rule. 207 tests green.

## What is deliberately not done

- No "Epics" smart view in the sidebar. That would re-create the special case under a new name.
- No change to bd itself: parent/child stays the only relation, and nothing here writes.
