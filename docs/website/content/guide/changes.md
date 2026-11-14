---
title: Making changes
linkTitle: Making changes
weight: 50
description: Creating and editing beads, the confirmation sheet, and how Beady stays safe beside agents writing to the same database.
---

bd has no lease or lock, and agents write whenever they like. Beady is built to be one
writer among several, so the rule is simple: **nothing is written until you confirm a sheet
that shows exactly what will happen.**

## Creating a bead

Press {{< k "⌘N" >}}.

{{< shot name="new-bead" crop="340" alt="The top of the New Bead form: a title field, a type menu, priority buttons from P0 to P4, a parent menu and the start of the description." caption="A new bead needs a title; type, priority, parent and description are there if you want them." >}}

## Editing a bead

Select a bead and press {{< k "⌘E" >}}, or click **Edit** in the details pane. You can
change its status, parent, title, type, priority, assignee, labels, what it waits on, its
description and its notes.

{{< shot name="edit" crop="600" alt="The edit form for a bead, with status and parent menus at the top, then title, type, priority, assignee, labels, blocked by, description and notes, and a Review Changes button." caption="Editing. Review Changes… leads to the confirmation sheet." >}}

Quicker routes for common changes:

- The **Status** and **Move To** menus in the details pane.
- Dragging a card between board columns.
- {{< k "⇧⌘P" >}} to pin and {{< k "⇧⌘S" >}} to star.

Closing a bead needs a reason. bd's own rules are respected: no closing a pinned bead, and
no closing an epic that still has open children.

## The confirmation sheet

{{< shot name="confirm" alt="A confirmation sheet titled Move map-1.1 to map-2, describing the change of parent, with a disclosure labelled How this will be written and Cancel and Apply Change buttons." caption="Moving a bead to another epic. Open “How this will be written” for the bd commands." >}}

Every change goes through the same four steps:

1. **Validation** against the loaded data: titles, priorities, known statuses and types,
   parents that exist, no parent loops.
2. **A conflict check** immediately before writing, comparing what you saw with what's in bd
   now.
3. **The exact commands**, shown before you agree to them.
4. **A read-back** afterwards. If anything goes wrong, Beady re-reads the bead to find out
   whether the change landed, failed or is uncertain. It never guesses.

{{< k "⌘Z" >}} takes back a change to a bead. The **Changes** menu in the toolbar is the
history of what Beady has written this session, and whether each write was verified.

## When someone else is working on a bead

If another actor, a person or an agent, changed a bead recently:

- the row is marked,
- the details pane says who and when, and
- a change to that bead carries a warning on the confirmation sheet.

It informs. It never blocks, because a lock bd doesn't offer can't be faked.

### bd's change journal

Knowing who changed what comes from bd's events journal (bd 1.3 and later). When you open a
writable workspace where the journal is off, Beady turns it on. This is a workspace setting,
so from then on every `bd` command there records to it, agents' included.

- The change is listed under **Changes**, with an **Undo** that turns it back off.
- To stop Beady doing this, switch off *Turn on bd's change journal in workspaces that don't
  have it* in Settings ({{< k "⌘," >}}).
- Where bd's own defaults still stand, Beady also shortens the journal's retention from a
  week to a day. A retention someone chose is left alone.
- Read-only workspaces are never written to.

With an older bd, or the journal off, Beady reads bd's interaction log instead.
