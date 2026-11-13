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
the remote when a workspace opens and after each sync; **Check Again** asks on demand.

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

Beady never syncs by itself. bd advises against automatic pushes when several writers share a
git-hosted remote, and agents working in worktrees are writers too. Agents sync with `bd sync`.

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

- **Database**: how many beads, and where bd keeps them.
- **Checkouts on this Mac**: git worktrees of one repository all use the one database, so a
  bead changed in one is changed in all.
- **Sharing**: the same word and sentence as the toolbar.
- **Backup**: whether one is set up; see [Backing up]({{< relref "workspaces.md#backing-up" >}}).
- **Commits**: whether bd's git hooks are installed. They are what can put beads into commits,
  and sharing doesn't need them.
- **bd**: its version. Everyone sharing a database should run the same one; bd refuses to mix
  them.

## What Beady won't do

It never migrates a database, forces a push, removes a remote, installs git hooks or makes a
git commit. When bd refuses something, Beady shows bd's message as it is.
