---
title: Sharing beads between Macs and people
linkTitle: Sharing beads
weight: 90
description: Seeing whether a database is shared, sharing it through your repository, getting the beads on a fresh clone, and syncing.
---

A beads database lives in your project's `.beads` folder, on your Mac. bd can share it through
a **remote**, usually the same git repository as your code, so that another Mac or a teammate
works on the same beads. Beady shows whether that is set up and whether it is up to date, and
does each step with the `bd` command that bd's own documentation gives for it.

## The word in the toolbar

The toolbar says where the open database lives besides this Mac:

| It says | What it means |
|---|---|
| **Only on this Mac** | Nothing is shared. Another Mac or a teammate can't see these beads. |
| **Kept on this Mac** | bd is set to keep this database off the network (`dolt.local-only`). |
| **Not sent yet** | A remote is set up and nothing has been sent to it. |
| **2 to send · 1 to receive** | Changes are waiting in one or both directions. |
| **In sync** | Everything here is on the remote, and everything there is here. |
| **Can't reach origin** | bd couldn't contact the remote: the network, or signing in to it. |
| **Needs a decision** | The last sync found a conflict it won't settle by itself. |
| **Two different backlogs** | The beads here and on the remote were started separately. |
{.table-scroll}

Click it for the sentence behind the word and the one thing to do about it. Beady asks bd about
the remote when a workspace opens and after each sync; **Check Again** asks on demand. While bd
is working the word is **Syncing…** and its symbol turns.

## Sharing a database

Choose **Share Beads…** from the toolbar word, the Beads menu or {{< k "⌘P" >}}. The sheet asks
who works on these beads, and before anything runs it shows:

- **who will be able to read them**: anyone who can read the remote can read every bead and its
  history, so sharing to a public repository makes the beads public;
- **what appears on the remote**: bd keeps the beads under `refs/dolt/data`, outside every
  branch, and adds one small branch named `__dolt_remote_info__`. Commits, branches and pull
  requests are untouched;
- **what changes in the repository**: bd records the remote as `sync.remote` in
  `.beads/config.yaml`. Commit that file with git so other clones find the beads;
- **the commands**, under *How this will be done*: `bd dolt remote add` and `bd dolt push`.

The remote is your repository's own git origin unless you type another. Any Dolt remote works:
DoltHub, S3, GCS, Azure or a folder.

Choosing **Only me, on this Mac** shares nothing and offers a backup instead.

## Getting the beads on another Mac

Clone the repository and open the folder in Beady. A fresh clone has bd's configuration and no
database, so Beady asks bd what it would do and offers it: **Get Beads** when the beads are on
the remote. That runs `bd bootstrap` in the folder, which is all a teammate needs to do.

If bd finds no beads anywhere, the offer is to start an empty database, with a warning: if the
beads already exist on another Mac, share them from there first, or the two will be separate
backlogs that bd can't merge.

## Syncing

**Sync Now** runs one `bd sync`: it receives what's new, then sends what's yours. Two people
editing the same field of the same bead don't conflict; the later edit wins.

### Stopping a sync

While a sync runs, its button reads **Stop**; **Stop Syncing** is also in the Beads menu and
{{< k "⌘P" >}}. Stop asks bd to stop the way Ctrl-C does in a terminal, and waits for it: bd
finishes what it is writing and exits, usually within a second. Whatever bd had already received
or sent stays, and the next sync picks up the rest. Nothing needs repairing afterwards.

A first share and the settling of a conflict can't be stopped part-way.

### Syncing automatically

The popover's **Sync** choice sets how often this workspace syncs by itself while its window is
open: **When I ask** (the default), every minute, every 5 minutes or every 15 minutes. Each
automatic sync is the same one `bd sync`; this is the timer bd's guide describes, run by Beady
instead of cron. The choice is this Mac's alone: it changes nothing in bd's configuration or the
repository, so teammates and agents aren't affected.

What an automatic sync does with bd's answer:

| bd says | Beady |
|---|---|
| Synced, or nothing to do | Nothing. New beads appear. |
| An error, such as no network | Shows it once it has happened three times running, and keeps trying. |
| A conflict | Shows **Needs a decision** and stops until you settle it. |
| Another writer was in the way | Nothing. The next one retries. |
| Edits bd can't publish | Shows bd's message and stops until a **Sync Now** succeeds. |
{.table-scroll}

Stopping a sync pauses automatic syncing until you press **Sync Now** or choose again.

A shorter interval means fresher beads and fewer conflicts; bd's guide calls a minute
comfortable. For a remote hosted in a git repository bd adds a caution, which is why this is off
until you choose it:

> concurrent pushes to git-protocol Dolt remotes can corrupt or strand remote history when
> multiple writers race

That is written about bd's own `dolt.auto-push` setting, which pushes after every change. `bd
sync` is built for the race: it only replaces what it last saw on the remote, and tries again
when someone else got there first. Beady never turns `dolt.auto-push` on.

### When a sync needs a decision

Some changes can't both be kept, such as a bead deleted on one side and edited on the other. bd
stops before changing anything: nothing is sent and nothing here is lost. The toolbar says
**Needs a decision** and offers bd's two ways through, each asked twice because it discards the
other side's version of the beads in conflict:

- **Keep This Mac's**
- **Take the Remote's**

bd doesn't say which beads are in conflict, so the choice applies to all of them; everything
else merges as usual.

## Workspace Setup

**Workspace Setup…**, in the Beads menu and {{< k "⌘P" >}}, lists what bd reports about the
open workspace, a row a fact:

- **Database**: how many beads, and the folder bd keeps them in. bd's default storage needs no
  server; one program writes at a time.
- **Worktrees on this Mac**: every working copy of the repository (git worktrees, such as the
  ones agents work in) uses the one database, so a bead changed in one is changed in all. Up to
  four are named by branch; more than that are counted.
- **Sharing**: the same word and sentence as the toolbar.
- **Backup**: whether one is set up; see [Backing up]({{< relref "workspaces.md#backing-up" >}}).
- **Git commits**: whether beads end up in your git commits. They do only when bd's optional
  git hooks are installed and bd is set to export `.beads/issues.jsonl`; sharing needs neither.
- **bd**: its version. Everyone sharing a database should run the same one; bd refuses to mix
  them.

The list scrolls when it is taller than the screen; **Done** and **Check Again** stay put.

## What Beady won't do

It never migrates a database, forces a push, removes a remote, installs git hooks, makes a
git commit, changes bd's configuration to sync, or settles a conflict by itself. When bd refuses something, Beady shows bd's message as it is.
