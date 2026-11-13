---
title: Install and first launch
linkTitle: Install
weight: 10
description: Homebrew or a download, what to do if macOS refuses to open it, and opening your first database.
---

## What you need

- **macOS 15 or later.**
- **Apple silicon** for the Homebrew cask and the release downloads. On an Intel Mac,
  [build it yourself](#build-it-yourself).
- **`bd` on your PATH.** Beady does all its reading and writing through the `bd` command.
  Homebrew installs it for you with Beady. Any other way in, get it with
  `brew install beads`.

## Homebrew

```bash
brew install --cask dvhthomas/beady/beady
```

That's all. The cask installs `bd` alongside and clears macOS's quarantine flag, so Beady
simply opens.

- `brew upgrade` picks up new releases.
- `brew uninstall --zap beady` removes the app along with its saved views and settings.

### If macOS refuses to open it

Beady is ad-hoc signed but not notarised (there's no Apple Developer ID behind it), and macOS
won't open a quarantined copy of such an app. The cask clears the flag on every install and
upgrade, but it needs a current Homebrew to do so. Run `brew update`, then reinstall. Or
clear the flag yourself:

```bash
xattr -dr com.apple.quarantine /Applications/Beady.app
```

Every release is a new signature, so an earlier **Open Anyway** doesn't carry over to the
next one. If you're clearing the flag by hand, you'll do it after each upgrade.

## Or download a release

Take the zip from [Releases](https://github.com/dvhthomas/beady/releases/latest), unzip it,
and move Beady to your Applications folder. You'll also need `bd` (`brew install beads`).

A downloaded copy is quarantined, so macOS refuses it the first time. Either:

- open Beady, then go to **System Settings → Privacy & Security** and choose **Open Anyway**;
  or
- run `xattr -dr com.apple.quarantine /Applications/Beady.app`.

## Open a database

Press {{< k "⌘O" >}} and choose a project folder that contains `.beads`, or the `.beads`
folder itself. Beady reopens the last workspace each time it launches.

{{< shot name="ready-dark" crop="640" light="ready-light" alt="Beady's main window with the Ready view selected in the sidebar, the ready beads listed, and the details of the first on the right." caption="A database open on the Ready view: what can start now." >}}

### Starting a new database

If you choose a folder that holds a git repository but no `.beads`, Beady offers to create a
database there. It shows the exact `bd init` line it will run, and Cancel writes nothing.
The defaults are the fewest that make a workspace Beady can open:

- **A prefix from the folder's name**, lowercased and tidied: `Tile Engine` becomes
  `tile-engine`, so beads are named `tile-engine-a3f2`.
- **The database and nothing else.** No AGENTS.md, CLAUDE.md or git hooks appear in the
  repository. `bd setup` and `bd hooks install` add them later if you want them.

bd itself commits `.beads/` and a `.gitignore` entry to the repository as part of `bd init`.

A plain folder with no git repository is refused, because `bd init` would run `git init`
there, which is more than opening a folder should do. Run `git init` first.

## Build it yourself

An app you build is never quarantined, and this is the route on an Intel Mac. You need a
Swift 6.1 or later toolchain, from Xcode or the Command Line Tools.

```bash
git clone https://github.com/dvhthomas/beady.git
cd beady
scripts/bundle.sh && open build/Beady.app
```

## Starting over

**Reset Configuration…**, in Settings or from {{< k "⌘P" >}}, removes everything Beady keeps
on this Mac: remembered workspaces, each view's filters and layout, theme, text size and
column widths. Your saved views are removed only if you tick the box, and Beady offers to
export them first. Nothing inside a workspace is touched.
