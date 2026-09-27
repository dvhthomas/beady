# 0003 · bd's events journal says who changed what

Status: implemented · Owner request, 2026-09-27, following
[issue #19](https://github.com/dvhthomas/beady/issues/19): use the journal bd 1.3.0 adds; detect
bd's version when a workspace opens; turn the journal on only as the user's choice; keep its
retention to what Beady needs; keep FSEvents as the fallback when the journal is off or bd is too
old.

## What was wrong without it

Beady's live-work warnings ("agent-7 touched this 4 seconds ago") read `.beads/interactions.jsonl`.
In bd 1.3.0 that file is an optional sidecar behind `audit.enabled`, which
[defaults to false](https://github.com/gastownhall/beads/blob/v1.3.0/internal/config/config.go#L245),
and a fresh `bd init` doesn't create it. On a new 1.3.0 workspace the warnings were silently empty.

The [events journal](https://beads.gascity.com/reference/events-journal) records every write made
through bd in the same transaction as the write, in order, with the actor. That is exactly what the
warnings need.

## What changes

1. **Version check on open.** `bd version --json` once per workspace. Below 1.3.0 (or no answer),
   nothing else is asked and everything works as before.
2. **An offer, never an assumption.** With 1.3.0 and the journal off, a "Who's working?" button
   appears in the toolbar. It opens an alert that says what the journal is for, that it is a
   workspace setting every bd command (agents' included) will follow, and shows the exact command.
   **Not Now** is remembered per workspace; ⌘P → "Turn On bd's Change Journal…" is there for a
   change of mind.
3. **Small retention.** bd keeps 7 days or the newest 100,000 records, whichever is more. Beady
   reads the journal for activity in the last ten minutes, so turning it on from Beady sets
   `events-journal-retain-days: 1` and `events-journal-retain-rows: 1000`, in one
   `bd config set-many`. Only values still at bd's defaults are replaced: a retention someone chose
   is left alone.
4. **Following it.** With the journal on, each reload reads `bd --readonly events tail --since
   <checkpoint> --json`, folds the records into activity (newest first, the last day kept), and
   moves the checkpoint on. A checkpoint bd has pruned past
   ([exit 1 with `events_journal_truncated`](https://github.com/gastownhall/beads/blob/v1.3.0/cmd/bd/events.go))
   resumes from the oldest record left. If the journal can't be read, the interaction log answers,
   as before.

## What stays the same, and why

**FSEvents is still what wakes the app, in both modes.** `bd events tail --follow` would push
changes, but it keeps a bd process and its store open for as long as the window is. A bd command
holds the workspace's shared gate
[for the lifetime of its store](https://github.com/gastownhall/beads/blob/v1.3.0/internal/workspacegate/gate.go),
and maintenance operations (migration, restore, repair) need that gate exclusively, so a follower
would block them for as long as Beady is open. Polling `bd events tail` instead would start a bd
process every few seconds. FSEvents costs nothing and opens nothing. The journal is read after the
wake-up, to say who made the change. A journal read doesn't change the change token (checked with bd
1.3.0), so it can't set off another wake-up.

**The whole database is still reloaded on a change**, rather than applying each record's issue
payload. The payload is not the same shape as `bd list --json`: labels are omitted when empty, so a
bead whose last label was removed looks the same as one whose labels weren't sent, and dependencies
are attached only for dependency writes
([`snapshotter`](https://github.com/gastownhall/beads/blob/v1.3.0/internal/storage/uow/notifying.go)).
Applying it would drift from bd. `bd dolt pull` isn't journaled either, so a full reload is needed
after syncs anyway.

**History attribution** still matches by field. Journal records say what kind of write it was, not
which field changed, so only creation ("created") is attributed from the journal.

## Not done

- `bd serve`'s HTTP feed: it needs a Dolt server today and refuses the default embedded mode
  ([issue #19](https://github.com/dvhthomas/beady/issues/19)).
- The checkpoint isn't persisted between launches. Each open reads what the journal retains, which
  the one-day retention keeps small.
