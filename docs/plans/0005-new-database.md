# 0005 · Create a beads database from Beady

Status: implemented · Owner request, 2026-10-21: "beady should support the ability to create a new
beads db in a folder with a git repo with some sensible default settings. whether 'opening' a
workspace (folder) that already has a beads db or trying to open and then offering to create a new
db because one was not found. test first." Bead bdv-g3q.

## What was wrong without it

⌘O accepted only a folder that already held an initialised `.beads`. Anything else was "has no
initialised .beads folder", and the way to a new database was the terminal.

## What changes

1. **One decision for a chosen folder** (`WorkspaceOpening.decide`, pure, in BeadsPresentation).
   The app gathers two facts about the folder (`BeadsWorkspace.inspect`): whether `.beads` is
   there and initialised, and whether `.git` is inside the folder, as a directory or a worktree's
   file. A database is opened wherever it is. A git repository without one gets an offer. A plain
   folder is refused with the reason: `bd init` runs `git init` itself in a folder without one,
   and opening a folder shouldn't start a repository.
2. **An offer, with the command.** An alert: "Create a beads database in *folder*?", the ids to
   expect, the exact command line, what bd commits, and Create Database or Cancel. Cancel writes
   nothing and remembers nothing. Yes runs `bd init` and then opens the folder like any other
   workspace, so the change journal decision (plan 0003) happens there as usual.
3. **The defaults** (`NewDatabasePlan`): the prefix from the folder's name, lowercased, letters
   and digits with runs of anything else folded to one hyphen, starting with a letter (bd's
   database name must) and at most 16 characters cut back to a whole word; `beads` when nothing
   usable is left. `--skip-agents --skip-hooks`: the database and nothing else, since AGENTS.md,
   CLAUDE.md, Cursor and Codex files and git hooks in someone's repository are their call, and
   `bd setup` / `bd hooks install` add them later. `--non-interactive`: no terminal for wizards.
   Storage is left at bd's default, embedded Dolt.
4. **`BDCommand.initDatabase(prefix:)`**, a write like the others, with one difference found by
   the integration test: `bd -C <folder> init` refuses a folder with no beads project, so init runs
   with the folder as its working directory. `CommandRunning` gained a `directory` parameter for
   it, and the preview reads `cd <folder> && bd init …` so that what is shown is what runs.

## What was checked against bd 1.3.1

- `bd init` in a git repository commits `.beads/` and a `.gitignore` entry ("bd init: initialize
  beads issue tracking") and leaves an otherwise dirty working tree alone. The offer says so.
- Without `--skip-agents` it writes AGENTS.md, CLAUDE.md, `.claude/`, `.codex/`, `.cursor/` and
  `.agents/`; without `--skip-hooks`, `.beads/hooks/`. With both and `--quiet` it prints nothing.
- A folder name with a space or a leading digit is refused as a prefix, which is why the prefix is
  derived rather than left to bd's default of the folder name.
- An existing empty `.beads` folder is fine; init fills it.

## Not done

- No field to change the prefix before creating; the derived one is shown in the alert. If it
  turns out to be wanted, the plan already carries the prefix separately from the path.
