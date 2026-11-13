---
title: Views and filters
linkTitle: Views and filters
weight: 20
description: The sidebar's built-in views, filtering with chips, and saving and sharing views of your own.
---

## The sidebar is views

Every entry in the sidebar is a **view**: a saved filter with a saved layout, grouping,
ordering and set of columns. Each shows how many beads it holds. Switching views never
carries filters along, because each view keeps its own.

| View | What it shows |
|---|---|
| **Pipeline** | Everything live plus the last week of finished work, as a board. |
| **Ready** | bd's ready work: active, nothing open blocking it, not deferred to a future date. |
| **In Flight** | Work in progress. |
| **Stuck** | Beads that are blocked, worked out from the dependency graph. |
| **Recent** | Updated in the last 24 hours, grouped by assignee. |
| **Landed** | Finished and closed in the last week. |
| **Deferred** | Beads deliberately put on ice. |
| **Everything** | The whole database. |
| **Starred** | Beads you've starred. It appears once something is starred. |
{.table-scroll}

Which statuses count as live, in progress, frozen or done comes from `bd statuses`, so custom
statuses land in the right view.

Hover over a view, a filter chip, a status or a grouping and the tooltip says what it means
in bd's own words.

## Filtering

Press {{< k "F" >}} or click **Filter**. Pick a property, then tick values. The menu stays
open while you tick, and each value shows how many beads you'd see.

{{< shot name="filter-menu" crop="190" alt="The filter menu open on Priority, listing P0 to P4 with a checkbox and a count beside each." caption="Each value shows the count you'd get." >}}

Each rule becomes a chip in the filter bar that reads like a sentence:
`Priority · is any of · P1, P2`. Click the operator to switch between *is* and *is not* (or
*includes all*, *any* or *none* for labels). Click the values to change them. The ✕ removes
the rule.

{{< shot name="filters" crop="560" alt="The Ready view with three chips in the filter bar: the locked Ready chip, a Priority chip and a Labels chip, and the list narrowed to match." caption="Chips combine with AND. The first chip here is locked because it is what makes this view Ready." >}}

You can filter on Lifecycle, Status, Priority, Type, Assignee, Labels, Blocked, Ready, Parent,
Updated and Closed.

How the rules combine:

- Different properties are **ANDed**.
- Values of a single-valued property (type, status, priority, assignee) are **alternatives**,
  because a bead has exactly one of each.
- Labels are multi-valued, so by default every label you tick is required.

## Search

Press {{< k "/" >}} to search within the current view. Every word you type must appear
somewhere in the bead: its id, title, description, notes, labels or close reason.

## Built-in views and their locks

A built-in view's filter is its definition, so those chips are locked: a lock instead of ✕.
You can still add chips on top. When you do, a dot appears beside the view's name and a
**Save** control offers *Save as new view…* and *Reset*.

{{< shot name="views" crop="600" alt="The sidebar with a saved view called Epics under My Views, and Ready marked with a dot because a Priority chip has been added to it; a Save control sits in the filter bar." caption="Ready with a chip added (the dot), and a saved view of your own, Epics, under My Views." >}}

To change what a built-in means, right-click it and choose **Duplicate**. The copy is yours
to edit.

## Views of your own

The **+** beside My Views saves the current view under a name. Your views remember
everything: filters, search, layout, grouping, ordering and columns.

| To | Do this |
|---|---|
| Save changes to your view | {{< k "⌘S" >}} |
| Save as a new view | {{< k "⌥⌘S" >}} |
| Put a view back as saved | {{< k "⌥⌘R" >}} |
| Rename, change icon, duplicate, export, share or delete | Right-click the view |

## Sharing views

Each of your views is one `.beadyview` file in
`~/Library/Application Support/Beady/views`, so `cp` works and they follow you between
workspaces.

- **Export…** writes a view to a file. **Share…** hands it to AirDrop or Messages.
- To import one, double-click a `.beadyview` file in Finder, drop it on the sidebar, or use
  **Import Views…**.

Beady keeps no files of its own inside your project's repository.
