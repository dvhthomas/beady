---
title: Blockers and the dependency graph
linkTitle: Blockers and the graph
weight: 40
description: How Beady shows what a bead is waiting on, and how to read the dependency graph.
---

## What "blocked" means

In bd, a bead is blocked when something it depends on hasn't finished. That's ordinary: it
means something upstream has to land first. So Beady marks it quietly rather than raising an
alarm.

- A **waiting mark** on the row or card. Click it to see what the bead is waiting on.
- A **Blocked by** column that names the blocker. It's on by default in the Stuck view.
- In the details pane, the path to unblocking, grouped into what you can **start now** and
  what comes **then**.

{{< shot name="stuck" crop="520" alt="The Stuck view listing the blocked beads, each with a waiting mark and a Blocked by column reading Waiting on followed by the blocker's id." caption="Stuck: every blocked bead, with what it's waiting on." >}}

{{< shot name="waiting" alt="A popover explaining that a bead is waiting on another bead, which is named and linked." caption="The popover behind a waiting mark." >}}

## The dependency graph

Press {{< k "⌘G" >}} to open every blocking dependency in the database as one graph, in its
own window. It reads left to right, the way `bd graph` does: what can start now is on the
left, and what waits on it is further right.

{{< shot name="graph" alt="The dependency graph focused on one bead. Arrows run from blockers on the left to waiting beads on the right; the focused bead's chain is highlighted and the others are faded." caption="Focused on one bead: what it's waiting on is bold, what's waiting on it is tinted, and the rest fades." >}}

- **Click a bead** to follow it. The view recentres on it.
- Selecting a bead in the main window moves the graph too, and **Show in Main Window** goes
  the other way.
- **This view only** limits the graph to the beads in the current view.
- Finished beads are drawn struck through. Untick **Finished work** to hide them.
- {{< k "⌘+" >}} and {{< k "⌘−" >}} zoom.

You can also pin a small graph under the details pane, where it follows your selection.
