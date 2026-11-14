# 0006 · Sharing beads

Status: implemented · Owner request, 2026-11-13: "the whole multiuser configuration of beads/dolt
[is] brittle and confusing, especially across multiple local agent sessions in worktrees, and
especially in a shared repo where some people might remember how to use beads and some may not,
across different versions. […] Design a very clear and clean approach in the beady app to visually
manage the setup for this. […] never touch beads (or dolt) directly — always and only ever use the
CLI." Approved direction: a status word in the toolbar, a Share Beads sheet, and a Workspace Setup
checklist behind them. Bead bdv-few.

## What bd says sharing is

Read from the upstream docs at gastownhall/beads `526c1c8` (2026-11-13): core-concepts/sync-concepts,
getting-started/sync-setup, reference/git-integration, reference/worktrees,
reference/protected-branches, reference/configuration, recovery/sync-failures,
getting-started/upgrading.

- The Dolt database is the source of truth. Machines share it through a **Dolt remote**;
  `.beads/issues.jsonl` is an export and never the sync channel.
- For a git-hosted project the remote is normally the same `origin` as the code. The data lives
  under `refs/dolt/data`, outside every branch, so branch protection and pull requests are
  untouched. Any Dolt remote works as well: DoltHub, S3, GCS, Azure, a file path.
- `bd init` wires `origin` as the Dolt remote when the repository has one, and records it as
  `sync.remote` in the tracked `.beads/config.yaml`. Older databases, and ones made where there
  was no origin yet, have no remote; the documented repair is `bd dolt remote add origin <url>`
  then `bd dolt push`, then committing the config change with git.
- A fresh clone gets its database with `bd bootstrap`.
- Day to day it is `bd dolt pull` and `bd dolt push`; `bd sync` (bd 1.2.1 and later) is both, with
  a conflict check and bounded retries.
- All worktrees of a repository use the one `.beads` of the main checkout. Embedded Dolt, the
  default, serves one writer at a time.
- Automatic pushing is opt-in in bd (`dolt.auto-push`), "because concurrent pushes to
  git-protocol Dolt remotes can corrupt or strand remote history when multiple writers race".
- `dolt.local-only` keeps a database off the network on purpose.
- Clones that share a remote upgrade bd together: one migrates and publishes, the others take the
  migrated database. bd itself refuses anything else.

## What was checked against bd 1.3.4

In throwaway repositories with a local bare `origin`, embedded Dolt, Dolt 2.7.2 on the PATH and
then off it. None of this is in the docs in so many words; each line changed the design.

| Observed | Consequence for Beady |
|---|---|
| `bd init` with Beady's flags adds the `origin` remote and `sync.remote`, and publishes nothing. | "Set up, nothing sent yet" is a state of its own, and the commonest one for a database Beady made. |
| `bd sync` against a remote with no Dolt data fails: `no branches found in remote`. | The first publish is `bd dolt push`, never `bd sync`. |
| `bd dolt push` to a git remote with no branch at all (a repository nobody has pushed code to) fails: "initialize the repository with an initial branch/commit first". | bd's message is shown as it is; the remedy is a `git push`, which is the user's. |
| The first push creates `refs/dolt/data` **and a branch, `__dolt_remote_info__`**. | The sheet says so before anything is sent: teammates will see the branch. |
| Whoever can read the remote can read every bead and its history (bd #5068 made adoption a consent decision for this reason). | The sheet says this first, and nothing is ever shared without the sheet. |
| `bd dolt remote add` refuses a URL that matches the git origin unless `--allow-git-origin` is passed, and `bd dolt push --yes` did not adopt the origin by itself. | Beady runs the documented repair, with the flag, and shows it. |
| `remote add` and `remote remove` rewrite `sync.remote` in `.beads/config.yaml` and leave the file modified; bd made no git commit. | The sheet names the file; committing it stays the user's. |
| bd rewrites `https://…` to `git+https://…` and `git@host:path` to `git+ssh://…`. | The origin's URL is passed as git reports it. |
| `bd federation status --json` reports, per remote, whether it can be reached and how many commits this database is ahead and behind (`-1` when unknown). It fetches, so `--readonly` makes it report "unreachable". | The status word can say "2 to send · 1 to receive" without pulling. It runs without `--readonly`. |
| `bd sync --json`: `status` is `ok`, `no-remote`, `disabled` or `conflict` (with the tables); a failure is `{"error": …}`. Exit codes 0, 1, 2, and 3/4 per its help. | One decoder, `SyncOutcome`. |
| Two edits to the same field of the same bead merge silently, last write wins. | Not a conflict; nothing to show. |
| A delete against an edit is a conflict: exit 2, merge aborted, working set restored, `bd conflicts list` empty. `bd dolt pull --strategy ours` or `theirs` settles it (embedded storage only), then `bd sync` publishes. | Conflict offers exactly those two, for every conflicted bead at once, and only on embedded storage. Elsewhere bd's message is shown as it is. |
| A database made separately and pushed to an origin that already has beads: `no common ancestor`, with bd's advice to use `bd bootstrap`. | Shown as "two different backlogs", with no automatic fix: every fix discards one side. |
| `bd -C <folder> bootstrap` on a fresh clone without `sync.remote` plans a **fresh** database; the same command run inside the folder finds the origin's data and clones it. | Bootstrap runs with the folder as its working directory, like init. This is the difference between joining a backlog and forking it. |
| On a fresh clone `.beads/config.yaml` and `metadata.json` are there and the database is not; `bd list` says "no beads database found". | Beady used to open such a folder and fail. It now asks bd for its bootstrap plan and offers it. |
| `bd init` on such a clone also joins rather than forks ("initialized from git remote"). | The existing Create Database path is safe; the wording is bd's plan either way. |
| `bd sync` from a linked worktree syncs the one shared database. | One status per repository, whichever checkout is open. |
| Embedded sync works without a `dolt` binary. | Nothing to install or check. |
| `bd -C <folder> context` looks for the git repository in the working directory, not in `<folder>`. An app's working directory is `/`, so it answered "not a git repository" and the sheet lost the database's place, the storage and bd's version (found in 0.7.0, in a live window; the tests ran inside a repository and never saw it). | `context` runs inside the folder, like bootstrap and `worktree list`. |
| `bd context` refuses a database under `/tmp` ("BEADS_DIR points to unsafe location"). | A lab repository for looking at the sheet has to live elsewhere. |
| `bd doctor` is not available on embedded storage. | Workspace Setup reads `context`, `dolt remote list`, `federation status`, `worktree list` and `hooks list` instead. |

Not reproduced, and so left to bd's own words: exit 3 (push race) and exit 4 (stuck working set)
of `bd sync`, server and shared-server storage, credentials prompts, and a clone on an older bd
meeting a migrated remote. In each, Beady shows what bd printed and does nothing further.

## The design

**One sentence of state.** Where these beads live and whether that is current, derived by a pure
function (`SharingState.derive`) from what bd reports:

| State | From | Says |
|---|---|---|
| kept local | `dolt.local-only` | Kept on this Mac |
| not shared | no remote | Only on this Mac |
| never published | remote, reachable, ahead/behind unknown | Not sent yet |
| unreachable | remote, not reachable | Can't reach *origin* |
| pending | ahead or behind above zero | 2 to send · 1 to receive |
| in sync | both zero | In sync with *origin* |
| conflict | the last sync halted on one | Needs a decision |
| unrelated | the last sync or push said `no common ancestor` | Two different backlogs |

Conflict and unrelated come from the last sync this session, because bd reports nothing afterwards:
the aborted merge leaves no trace.

**A. The status word** takes the place of the backup word in the toolbar and opens a popover: the
state in a sentence, the remote, Sync Now, and the way into the two sheets. Backup moves into the
popover and Workspace Setup; its commands are unchanged.

**B. Share Beads** is the only place a database gains a remote. It asks who works on these beads,
shows the remote (the git origin, editable, any Dolt URL), says who will be able to read them and
what appears on the remote and in the repository, and lists the commands. Nothing runs until Share
Beads is pressed. "Only me, on this Mac" leads to backup and shares nothing.

**Joining.** A folder with `.beads` configuration and no database is asked for bd's bootstrap plan.
A plan to clone is offered as "Get the beads"; any other plan is offered in bd's own words; yes
runs `bd bootstrap --yes` inside the folder.

**D. Workspace Setup** lists what is true of this workspace, one row a fact: database, checkouts,
sharing, backup, git hooks, bd. A row that needs something says what, and has at most one button.
The facts scroll and the buttons don't, so Done is in reach whatever bd reports; checkouts are
named up to four and counted beyond that (a repository worked by agents had 91).

**The popover keeps its shape while bd works.** Its buttons stay where they are, disabled, and
the symbol turns. A popover that dropped its buttons for the length of a real sync and then put
them back came out clipped at the top and bottom.

**No automatic sync.** Beady refreshes the status when a workspace opens and after each sync, and
syncs when asked. bd's own caution about racing pushes is the reason; with several agents writing
through worktrees, an app that pushed by itself would be one more racer. If it is wanted later,
the place for it is bd's `dolt.auto-push`, which is bd's to throttle.

**What Beady never does here:** run `bd migrate`, pass `--force` or `--ignore-schema-skew`, remove
a remote, install or remove git hooks, make a git commit, or read or write Dolt's files.

## Where it lives

- `BeadsCore/Sharing.swift`: `DoltRemote`, `PeerStatus`, `SyncOutcome`, `SharingFacts`,
  `SharingState`, `WorkspaceSetup`, `BootstrapPlan`. Pure.
- `BeadsData`: the commands (`BDCommand`), their decoders (`BDJSON`), and `BDStore`'s
  implementations. `GitOrigin` asks git for the origin's URL, which is the one question here that
  isn't bd's.
- `BeadsPresentation/SharingPresentation.swift`: the words for each state, the share plan and the
  setup rows. `WorkspaceModel` holds the facts and runs the actions. `WorkspaceOpening` decides
  about joining.
- `Beady/Views/SharingViews.swift`: the toolbar item, the popover and the two sheets.

## Tests

Pure rules in `SharingTests` (BeadsCore, BeadsPresentation), the commands and decoders in
`SharingDataTests` against the JSON bd printed, and one opt-in round trip through the real bd in
`BDSharingIntegrationTests`: a bare origin, a clone that shares, a fresh clone that joins, and a
change synced each way. The offscreen snapshots (`BEADY_SNAPSHOT_DIR`) render the status word,
the popover and both sheets.

## Not done

- Per-bead conflict resolution. On embedded storage bd aborts the merge and names only the table,
  so there is nothing to choose between bead by bead.
- Changing or removing a remote, more than one remote, and federation peers: shown, not managed.
- Installing git hooks. They are optional for sharing, and they are what puts beads into commits.
- Teammates' bd versions and last sync: bd has no command that reports them.
