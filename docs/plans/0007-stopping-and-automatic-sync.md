# 0007 · Stopping a sync, and syncing automatically

Status: implemented · Owner request, 2026-11-13: "ensure that the sync icon is animated to indicate
something is happening, and also support auto-syncing somehow plus the ability to cancel a sync",
then "that will require careful design based on docs for sync/canceled or interrupted sync." Bead
bdv-3h2. Builds on [0006](0006-sharing.md), and reverses its "no automatic sync" for people who
ask for it; the reasons 0006 gave still decide the default.

## What bd says

Read from the upstream docs and source at gastownhall/beads `8cdfa79` (2026-11-13).

**A sync is meant to be run from a timer.** `bd sync`'s own help calls it "the loop every
multi-machine beads deployment otherwise hand-rolls in shell" and gives exit codes that "a sync
timer can branch on". `docs/multi-agent/bucket-federation.md` §4, *Pick a sync cadence*: "Run it
from a timer on both machines. A 60-second cadence is comfortable at the scale measured below; the
loop is a no-op when nothing changed", with this table:

| Exit | Meaning | What the timer should do |
|---|---|---|
| 0 | Synced, or nothing to do | Nothing |
| 1 | Error (transport, auth, storage) | Alert if it repeats |
| 2 | Merge conflict: halted, nothing pushed | Alert a human; never auto-resolve |
| 3 | Retries exhausted (push race, or another writer's dirty working set) | Nothing; the next tick retries |
| 4 | Dirty working set is stuck, not busy | Alert a human; no later tick will publish |

And three rules for the interval: staleness is the interval; "a longer interval means more
conflicts, not just staler data", because every bd change touches `updated_at`.

**bd's own automatic push is something else.** `dolt.auto-push` pushes after each write command,
never pulls, and is "explicit opt-in because concurrent pushes to git-protocol Dolt remotes can
corrupt or strand remote history when multiple writers race"; the docs call it "safe for
single-writer setups". It is a setting in bd's configuration, so it would apply to every agent
and teammate using the workspace. Beady leaves it alone.

**Ctrl-C is a supported way to stop.** `cmd/bd/main.go`, `setupGracefulShutdown`: bd catches
SIGINT, SIGTERM and SIGHUP, flushes a pending batch commit, cancels the command's context, and
on a second signal exits at once. `runSyncLoop` checks the context between attempts "so ^C or a
timer's deadline is not swallowed by the retry budget".

**A killed command is survivable, and not free.** `docs/recovery/database-corruption.md`: a lock
file left by an interrupted or killed command is "normally already released", because the kernel
drops a dead process's locks. `docs/reference/troubleshooting.md`: a corrupted journal comes from
"an unclean shutdown or an interrupted write". So bd is asked to stop, and is not killed while it
can still answer.

## What was checked against bd 1.3.4

Two clones of one bare origin, with a `git` on the PATH that sleeps a second before every
`fetch`, `push` and `ls-remote`, so a sync lasts about 14 seconds and can be interrupted anywhere
in it. Each trial: the other clone makes a bead and syncs; this clone makes one and syncs; bd is
signalled after a chosen delay; then both sync plainly and are compared.

| Observed | Consequence for Beady |
|---|---|
| 14 syncs interrupted with SIGINT between 0.3 s and 13.3 s, 5 with SIGTERM: bd exited within 1.1 s every time, exit 1, with `{"error": "sync failed: … context canceled"}` (or git's "signal: killed"). | One SIGINT, then wait for bd to exit. The exit is quick enough to wait for. |
| After each: no bd or git process left, `bd conflicts list` says `merging: false`, the next `bd sync` is `ok`, and both clones list the same beads. | A stopped sync needs no repair. The next sync finishes the job. |
| Where it stopped decides what was kept. Before the pull: nothing changed (1 to send, 1 to receive). After the pull: the remote's changes are here and committed (2 to send). After the push to `refs/dolt/data`: everything is there, though bd still exits 1. | The message after a stop says only that: what bd had already received or sent stays. The status is read again and shows what is left. |
| A sync signalled too late finishes normally: exit 0, or exit 2 for a conflict. | The outcome is decoded as usual; "stopped" is said only when bd reports the failure it was asked for. |
| Syncs heading into a delete-against-edit conflict, interrupted before and after the merge: no conflict rows left behind, the next sync reports the same conflict, and `bd dolt pull --strategy theirs` settles it as before. | Stopping is safe on the conflict path too. |
| bd pushes with `git push --force-with-lease=refs/dolt/data:<the commit it fetched>`. | A lost race is a rejected push, which `bd sync` retries (exit 3 when it runs out). |
| bd's git children die with it; Beady signals bd alone. | No process group handling. |

Not reproduced: a real network remote, server and shared-server storage, a sync interrupted during
a schema migration, and bd hanging after SIGINT. For the last there is a backstop (below), and it
has only ever run against a shell script standing in for bd.

## The design

**Stop.** While a sync runs, its button reads Stop, and the Beads menu and ⌘P offer Stop Syncing.
Stop sends bd one SIGINT, the word in the toolbar becomes "Stopping…", and Beady waits for bd to
exit before it reads the status again. bd's answer is decoded as any sync's is; if it is the
failure the stop asked for, the popover says "Sync stopped. Anything bd had already received or
sent stays; the next sync picks up the rest.", drawn as a plain note. Nothing is recorded as an
error.

If bd is still running ten seconds after the SIGINT, it gets a second one, on which bd exits at
once by its own rule; five seconds after that, SIGKILL, so a hung bd can't hold the window. That
is the only path on which a sync is killed, and none of the trials reached it.

Only `bd sync` can be stopped. A first share (`bd dolt push`) and a conflict settlement
(`bd dolt pull --strategy`) run to the end: each was confirmed in a sheet first, and each is the
step that puts a database right.

**Automatic sync** is one `bd sync` on a timer, per workspace, while its window is open: the loop
bd's guide describes, run by the app in place of cron. It is off until chosen, in the popover:
When I ask (the default), every minute, every 5 minutes, every 15 minutes. The choice is this
Mac's, kept in Beady's preferences, and changes nothing in bd's configuration or the repository,
so no teammate or agent inherits it.

A tick follows bd's table:

| bd says | Beady |
|---|---|
| synced (0) | Nothing. The status is read again; new beads appear. |
| error (1) | Nothing the first two times in a row; the third is shown in the popover. The timer keeps going, so a laptop back on the network recovers by itself. |
| conflict (2) | "Needs a decision". No more ticks until it is settled. |
| retries exhausted (3) | Nothing. The next tick retries. |
| stuck (4) | bd's message is shown. No more ticks until a sync asked for by hand succeeds. |
| unrelated histories | "Two different backlogs". No more ticks. |

A tick is skipped while anything else is running, when the workspace can't be written, and in any
state where `bd sync` isn't the right command: nothing shared, kept local, or set up and never
sent, which is Share Beads's to do, with its warnings. Stopping an automatic sync pauses the timer
until a sync is asked for by hand: the person's last word wins.

**The caution.** For a git-hosted remote the popover says, under the choice, that bd advises care
when several writers push to one; the guide quotes bd. `bd sync` is built for that race (compare
and swap on the ref, bounded retries, exit 3) where `dolt.auto-push` is not. The intervals
offered are bd's "comfortable" minute, five minutes (bd's own default spacing for automatic
pushes) and fifteen.

**What Beady still never does here:** set `dolt.auto-push` or any other bd configuration, pass
`--attempts`, `--force` or a strategy to an automatic sync, settle a conflict by itself, sync a
workspace whose window is closed, or adopt a git origin as a remote from a timer.

## Where it lives

- `BeadsCore`: `SyncOutcome.stopped`.
- `BeadsData/CommandRunner.swift`: `StopStyle`. `.interrupt` sends SIGINT on cancellation, waits
  for the exit and returns the process's own result. `BDCommand.stopsGracefully` picks it for
  `sync`.
- `BeadsPresentation/AutoSync.swift`: `SyncCadence` and `AutoSync`, the timer's rules as pure
  functions of the time, the state and the last outcome. `WorkspaceModel` runs them
  (`autoSyncTick`, `stopSync`); `SharingActivity` and `SharingSummary` carry Stop and "Stopping…".
- `Beady`: the popover's button and choice, the menu item, and a loop in `WorkspaceView` that
  asks the model every few seconds whether a tick is due.

## Seen in a live window

The dev build under its own bundle id, on the two-clone lab with the slowed git and the real bd
1.3.4: Sync Now, then Stop four seconds in ("Stopping…", then the note, "1 to send", no bd left
running); and with the cadence saved as every minute, a sync on opening that brought a bead made
in the other clone and sent this one's, and a second about a minute later that brought another.
The cadence menu itself was not operated by hand: background input can't open a pop-up menu, so
the choice was written to the test copy's preferences and read back by the app.

## Tests

`AutoSyncTests` for the timer's rules against bd's table; the model's stop and tick through the
stub store; `ProcessCommandRunnerTests` for interrupt-and-wait against a shell script that traps
INT, one that ignores it, and one that finishes first; the decoders for a cancelled sync's JSON as
bd printed it. The interruption trials are scripts kept out of the repository; their results are
the table above.
