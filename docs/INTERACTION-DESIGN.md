# Interaction design: motion and feedback

How Beady acknowledges what the user just did. Follow these rules for any interaction that
changes what's on screen — they are what makes the app feel like it *responded* rather than
merely re-rendered. The worked example throughout is the board: dropping a card on a column.

## The rules

1. **Every user-initiated change gets a visible acknowledgement, where the user is looking.**
   A write that lands silently is indistinguishable from one that failed. After a confirmed
   change, the affected row/card/node must do something the eye can catch: travel to its new
   place, glow briefly, or both. Never let data simply disappear from one spot and reappear in
   another.

2. **Motion explains; it never decorates.** Animate only to preserve continuity (this card
   *became* that card over there) or to confirm an outcome (it landed). If an animation carries
   no information, leave it out. Refusals are the flip side: a drop that can't be accepted must
   be refused immediately (return `false` from the drop handler without staging work), so the
   drag image snaps home without a pause — the snap-home *is* the "nothing happened" message.

3. **Animate the data change, not the gesture.** Attach `.animation(_:value:)` keyed to the
   *derived arrangement* (e.g. the board's `[[IssueID]]` of cards per column), not to the drop
   event. Then every path that re-arranges the view animates the same way: a confirmed drop, an
   undo, a background refresh bringing another session's change. The user gets continuity no
   matter who moved the bead.

4. **A thing that moves between containers is the same view.** Use one `Namespace` for the whole
   surface and `.matchedGeometryEffect(id:in:)` on each item, so SwiftUI glides the item from
   its old container to its new one instead of fading it out and in. Identity (`id`) must be the
   domain id (`IssueID`), stable across the re-render, unique on the surface.

5. **Acknowledgements are facts the model owns; drawings the views own.** The model
   (BeadsPresentation, pure, tested) records *what* to acknowledge — see `AppliedChange` /
   `WorkspaceModel.lastAppliedChange`, set only after the write landed and the data reloaded, so
   the acknowledgement plays on the refreshed board. The app layer decides *how it looks* (the
   glow in `IssueLayouts.swift`). This keeps the logic testable and the choreography swappable.

6. **An acknowledgement plays once.** The view hands it back when done
   (`acknowledgeAppliedChange`), so a rebuilt view doesn't replay it. Sequence numbers, not
   booleans, so a repeat change to the same bead still reads as new.

7. **Honour Reduce Motion.** Check `@Environment(\.accessibilityReduceMotion)`. Travel becomes
   instant (`.animation(nil, ...)`); a static highlight that fades stays, because it is the
   confirmation itself, not decoration — crossfades are the accepted substitute for motion.

8. **One vocabulary of timing.** Pick from these; don't invent new curves per view:
   - Layout re-arrangement (items moving): `.snappy(duration: 0.4)`
   - Panes and reveals (inspector, graph focus): `.smooth(duration: 0.25)` – `.easeInOut(0.35)`
   - Acknowledgement glow: appear with the landing, hold ~0.5s, fade `.easeOut(duration: 0.9)`

9. **Confirm on risk, never on everything.** A direct-manipulation gesture (a drag, a toggle) is
   already the decision; a modal that restates it is confirmation theater. Apply immediately when
   nothing needs the user, and show the confirmation sheet only when something does: a reason to
   type (close/reopen), a warning or error from the checks, a conflict found at write time, or a
   failure — a skipped sheet must come back rather than let a write fail silently. Three things
   make the immediate path safe, and all are required: the change validates clean, the step lands
   on the window's undo stack (rule 12), and the acknowledgement (rule 1) shows the write landed.
   `WorkspaceModel.applyDrop` is the worked example.

10. **Feedback must survive the sheet when it does appear.** The acknowledgement can't ride on
    the gesture (the drop is long over by the confirm). Tie it to the model's applied-change
    record, which fires after write → reload, on both the immediate and the confirmed path.

11. **The screen never waits for bd.** A bd write costs the best part of a second across several
    processes; a UI that waits for it reads as broken, and users retry mid-write. Show the
    change on the snapshot the instant the gesture lands (`IssueChange.applied(to:)` +
    `snapshot.replacing`), write in the background one change at a time, then read back only
    the changed bead (`store.currentIssue`), never the full reload — the file watcher covers
    the rest. A failure takes the preview back (the card visibly returns) and says why. Keep
    previews re-applied over mid-write reloads, and keep everything else interactive while one
    write is in flight — only the bead being written is off-limits. `toggleMark` and
    `drainDrops` in WorkspaceModel are the worked examples.

12. **Undo is the system's undo, not a menu of levers.** Every reversible write this session
    makes registers on the window's `UndoManager` (`WorkspaceModel.registerUndo(of:)`), so taking
    a change back works the way it does everywhere on the Mac: ⌘Z walks a stack, ⇧⌘Z walks back
    up it, the Edit menu names each step ("Undo Move bdv-1 to In Progress"), and a focused text
    field keeps its own typing undo. Never scatter per-item Undo buttons through a list — the
    Changes menu is history, not a control panel. Two things keep this honest over a *shared*
    database that cannot be rolled back blind: each invocation is re-validated against that
    moment's data, and a step that can no longer apply raises the confirmation sheet with the
    problems spelled out and Apply disabled, so it explains itself instead of writing or dying
    silently. Registration is optimistic (the manager flips a step to its redo stack before the
    validated write runs), which is the honest trade: the menu may rarely offer a step that, when
    chosen, explains why it can't apply — never one that applies something it didn't name.

13. **Progressive disclosure for mechanics.** The sheet leads with what changes in plain words;
    the exact `bd` commands and safe-write caveats live behind a closed disclosure ("How this
    will be written") for whoever wants them. Never delete the mechanics — agents and the
    curious rely on them — but never make a person read them to click Apply.

## Checklist for a new interaction

- [ ] Does the user see *where* the change landed? (move and/or glow at the destination)
- [ ] Does a refused action communicate refusal instantly? (no staged work before refusing)
- [ ] Does it confirm only on risk? (immediate when clean + Undo; sheet for reasons/problems/failures)
- [ ] Does the screen move before the write? (preview + targeted read-back; revert visibly on failure)
- [ ] Does a reversible write land on the window's undo stack, named for the Edit menu? (never a per-item Undo button)
- [ ] Is the animation keyed to derived data, so undo/refresh animate the same way?
- [ ] Is any "what just happened" state in BeadsPresentation with a test?
- [ ] Is it consumed once, with a sequence so repeats still fire?
- [ ] Does Reduce Motion drop the travel but keep a non-motion confirmation?
- [ ] Are the durations from the vocabulary above?
