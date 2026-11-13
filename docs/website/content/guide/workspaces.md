---
title: Workspaces, live updates and backups
linkTitle: Workspaces and backups
weight: 80
description: Switching between databases, how Beady keeps up with other writers, and backing a database up.
---

## Switching workspaces

The top of the sidebar names the open workspace and its bd prefix. Click it for your recent
workspaces, each with its path so two checkouts of one project can be told apart, and
**Open Other…**.

- {{< k "⌃⌘O" >}} cycles through recent workspaces.
- In {{< k "⌘P" >}}, type `switch to` and a name.
- Launched from a terminal, `Beady.app/Contents/MacOS/Beady --workspace /path/to/project`
  opens a specific one.

## Live updates

Beady watches the `.beads` folder and reloads within a moment of any write, yours or an
agent's. You don't need to refresh, though {{< k "⌘R" >}} does it on demand.

Reading never changes anything: Beady reads with `bd --readonly`.

## Backing up

Click the word in the toolbar that says where the beads live
([Sharing beads]({{< relref "sharing.md" >}})). The popover says whether the open database could
be recovered, "backed up 6 min ago" or "not backed up", and **Workspace Setup…** has the button
to back up now, or to choose a folder the first time. So does {{< k "⌘P" >}}: type `back up`.

Underneath it's `bd backup`, which copies the whole database with its history, not only the
beads. (`bd export` writes a file for interchange and is not a backup.)

Pick a folder that something already carries off your Mac: Time Machine, iCloud Drive or a
synced disk.

### Restoring

Restoring replaces a database, so it's deliberately a job for the terminal:

```bash
bd init                         # only if the workspace is empty
bd backup restore /path/to/backup --force
```

## Where Beady keeps things

| What | Where |
|---|---|
| Your saved views | `~/Library/Application Support/Beady/views` |
| Settings, recent workspaces, each view's state | macOS preferences for Beady |
| Your beads | Your project's `.beads` folder, managed by bd |
{.table-scroll}

Beady keeps no files of its own in your repository.
