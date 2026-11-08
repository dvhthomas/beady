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

9. **Feedback must survive the confirmation sheet.** Beady stages changes and confirms them in
   a sheet, so the acknowledgement can't ride on the gesture (the drop is long over). Tie it to
   the model's applied-change record, which fires after confirm → write → reload.

## Checklist for a new interaction

- [ ] Does the user see *where* the change landed? (move and/or glow at the destination)
- [ ] Does a refused action communicate refusal instantly? (no staged work before refusing)
- [ ] Is the animation keyed to derived data, so undo/refresh animate the same way?
- [ ] Is any "what just happened" state in BeadsPresentation with a test?
- [ ] Is it consumed once, with a sequence so repeats still fire?
- [ ] Does Reduce Motion drop the travel but keep a non-motion confirmation?
- [ ] Are the durations from the vocabulary above?
