---
title: Lists, boards and trees
linkTitle: Lists, boards and trees
weight: 30
description: The three layouts, grouping and ordering, the details pane, and pins and stars.
---

Every view can be shown three ways. Press {{< k "⌘1" >}}, {{< k "⌘2" >}} or {{< k "⌘3" >}},
or use the three buttons at the top of the view. Each view remembers the layout you left it
in.

## List

A table with a section header for each group.

{{< shot name="in-flight" crop="600" alt="The In Flight view as a table grouped by status, with ID, Status, Type, Title and Priority columns." caption="In Flight, grouped by status. The pinned P0 bug leads its group." >}}

- Drag the dividers in the header to resize columns.
- Right-click the header to show or hide columns, including Labels, Progress and Blocked by.
- **Reset Columns** puts the layout back.

## Board

A column for each group. Ungrouped, the columns are bd's lifecycle: open, in flight,
deferred and done.

{{< shot name="board" alt="The Pipeline board with Open, In Flight and Deferred columns of cards." caption="Pipeline: everything live plus a week of done." >}}

Drag a card to another column to change it. The grouping decides what a drop means: on a
board grouped by lifecycle or status it changes the status, by priority the priority, and by
parent it moves the bead under that parent. (Boards grouped by type or assignee don't take
drops.) You still confirm the change before anything is written.

If a grouping would put everything in one column, the board says *Nothing to split* and
offers the groupings that would spread the beads out.

Turn on **Nest sub-tasks** in Display to fold children into their parent's card.

{{< shot name="board-nested" alt="The Pipeline board with sub-tasks nested inside their parent epic's card, one epic expanded to show its children." caption="Sub-tasks folded into their parents, with one epic opened." >}}

## Tree

The parent and child outline, expanded by default, with a progress bar on each parent.
Right-click to expand or collapse everything.

{{< shot name="tree" crop="600" alt="The tree layout focused on the Offline maps epic with its six children beneath it." caption="Focused on one epic. The focus is the chip at the top left; its ✕ lets go." >}}

When a filter matches a child but not its parent, the ancestors stay visible, dimmed, so
nothing looks orphaned.

### Focus

**Focus** narrows the current view to one bead and everything under it, at any depth. It's
in any row's right-click menu and in the details pane. It works for any bead with children,
not only epics. Save while focused and you have "this epic, as a tree" as a view of its own.

## Display options

Press {{< k "⇧V" >}} or click **Display** to choose:

- **Layout**: List, Board or Tree.
- **Grouping**: Lifecycle, Status, Priority, Type, Assignee or Parent.
- **Ordering**.
- **Columns** for the list.

## The details pane

Select a bead and its details appear on the right: status, priority, type, assignee, labels
and dates, then links to its parent, what blocks it, what it blocks and its children, then
the description, notes and close reason.

{{< shot name="details" alt="The details pane for one bead, with back and forward arrows at the top, its status, priority and dates, links to its parent, the bead blocking it and the bead it blocks, its description, and a small dependency graph pinned underneath." caption="Details, with the dependency graph pinned beneath." >}}

- Click a linked bead to go to it. The arrows at the top go back and forward.
- **History** shows each change bd recorded, such as "status · open → in_progress", and who
  made it.
- {{< k "⌘I" >}} docks the pane so it stays open. If it's hidden, clicking a bead floats the
  details over the beads; {{< k "Esc" >}}, a click elsewhere or the pane's ✕ sends them away.

## Pins and stars

- **Pin** a bead with {{< k "⇧⌘P" >}} and it leads every list, tree and board column.
- **Star** one with {{< k "⇧⌘S" >}} and it collects in the Starred view.

Both are ordinary bd labels (`pinned` and `starred`), so `bd list --label pinned` sees
exactly what Beady sees. The mark appears at once and is written behind it. If the write
fails, the mark goes back and the Changes menu says why.

> bd also has a built-in *status* called pinned. That's a different thing. The label is
> Beady's "show me this first".
