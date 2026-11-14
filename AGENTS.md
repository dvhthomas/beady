# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd prime` for full workflow context.

> **Architecture in one line:** Issues live in a local Dolt database
> (`.beads/dolt/`); cross-machine sync uses `bd dolt push/pull` (a
> git-compatible protocol), stored under `refs/dolt/data` on your git
> remote — separate from `refs/heads/*` where your code lives.
> `.beads/issues.jsonl` is a passive export, not the wire protocol.
>
> See [SYNC_CONCEPTS.md](https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md)
> for the one-screen overview and anti-patterns (don't treat JSONL as the
> source of truth; don't `bd import` during normal operation; don't
> reach for third-party Dolt hosting before trying the default).

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work atomically
bd close <id>         # Complete work
bd dolt push          # Push beads data to remote
```

## Non-Interactive Shell Commands

**ALWAYS use non-interactive flags** with file operations to avoid hanging on confirmation prompts.

Shell commands like `cp`, `mv`, and `rm` may be aliased to include `-i` (interactive) mode on some systems, causing the agent to hang indefinitely waiting for y/n input.

**Use these forms instead:**
```bash
# Force overwrite without prompting
cp -f source dest           # NOT: cp source dest
mv -f source dest           # NOT: mv source dest
rm -f file                  # NOT: rm file

# For recursive operations
rm -rf directory            # NOT: rm -r directory
cp -rf source dest          # NOT: cp -r source dest
```

**Other commands that may prompt:**
- `scp` - use `-o BatchMode=yes` for non-interactive
- `ssh` - use `-o BatchMode=yes` to fail instead of prompting
- `apt-get` - use `-y` flag
- `brew` - use `HOMEBREW_NO_AUTO_UPDATE=1` env var

## Releases and the version number

Every merge to master is a release: CI works out the next version from the pull request's
labels, writes `VERSION`, tags `vX.Y.Z` and publishes the Homebrew cask. The one decision is how
big the change is, said with at most one label on the pull request:

- no label, or `release:patch`: nearly everything — a bug fix, a tweak, a new feature, a visible
  change in behaviour (0.1.1 → 0.1.2). The default.
- `release:minor`: rare and never needed; the owner's way to mark a milestone early (0.1.1 → 0.2.0).
- `release:major`: rare; it breaks how people use Beady or its files (0.1.1 → 1.0.0).
- `release:none`: nothing in the app changes, such as a change only to the website or the README.

**The patch number does the counting.** It runs 0.1.1, 0.1.2 … 0.1.99, and the patch after 0.1.99
is 0.2.0, by itself: the middle number moves only when a hundred patches have shipped, so a new
feature is a patch like any other and nobody labels a pull request to move it.

Add a label with `gh pr create --label release:none` or `gh pr edit <number> --add-label release:none`.
Never edit `VERSION` by hand; the Release size check fails a pull request that does. Details in
[RELEASE.md](RELEASE.md).

**Agents never apply `release:minor` or `release:major`, and never recommend `release:minor`**:
a feature ships unlabeled, as a patch. Only for a breaking change, open the PR as a **draft**,
recommend `release:major` in the PR body, and ask the user to label it, mark it ready and merge.
Unlabeled and patch PRs merge themselves when CI is green (the Merge-when-green workflow);
minor/major and draft PRs wait for a human.

## Claude session authority (Team-maintainer opt-in)

This repository **opts in to the Team-maintainer profile** for agent sessions working in a git
worktree on a `claude/*` branch. In such a session, without asking first, an agent may:

- claim, create and close beads;
- run quality gates (`scripts/test.sh`, `swift build`);
- commit to the session's `claude/*` branch and push it;
- open a pull request — **unlabeled** (which means patch) or `release:none`.

Still forbidden without an explicit user request: pushing to master, pushing tags,
force-pushing, editing `VERSION`, applying `release:minor` or `release:major`, and merging a
minor/major pull request. **Patch releases are the norm, for features as well as fixes, and
fully automated; the middle number moves by itself after patch 99. Minor and major labels are
a human decision.**

## The website and user guide

The user-facing documentation is the website in `docs/website` (a Hugo site), published at
<https://dvhthomas.github.io/beady/>. The README is deliberately short and points there; do
not grow user documentation back into it. Developer documentation is `docs/DEVELOPING.md`.

**The guide ships with the change.** Every release republishes the site, so whatever is in
`docs/website` at the merge is what users read about that version. A pull request that changes
what a user sees or does updates the guide in the same pull request:

- A new or changed feature, setting, menu item, shortcut, view, filter or default: edit the
  matching page in `docs/website/content/guide/` (and `content/_index.md` if the landing page
  describes it). A new shortcut also goes in the tables in `guide/keyboard.md`.
- Something removed or renamed: remove or rename it in the guide too. Search for the old words:
  `grep -rn "old name" docs/website/content README.md`.
- New UI worth a picture: capture it in `SnapshotMode.run` and add a line to `SHOTS` in
  `scripts/screenshots.sh`. A snapshot the site uses that is renamed or dropped in
  `SnapshotMode.swift` must be renamed or dropped there too, or the script fails.
- No user-visible change (a refactor, tests, CI): say "Docs: no user-visible change" in the
  pull request body, so it is a decision rather than an omission.

Check the site builds before the pull request: `hugo --source docs/website --destination
"$(mktemp -d)"` must finish without errors (`brew install hugo` if it is missing).
`scripts/screenshots.sh` retakes the screenshots locally; you don't have to commit fresh ones,
because the Website workflow (`.github/workflows/pages.yml`) retakes them on every deploy, after
the Version workflow, including for `release:none` merges. A pull request that changes only
the website or other documentation is `release:none`.

## Build & Test

```bash
scripts/test.sh        # the whole suite (Swift Testing); the gate before any PR
swift build            # compile check
scripts/bundle.sh      # build build/Beady.app — test THIS dev build, not /Applications
scripts/dev-watch.sh   # rebuild and relaunch the app on source changes
scripts/screenshots.sh # retake the website's screenshots from the app
hugo server --source docs/website   # preview the website at localhost:1313/beady/
```

CI runs `scripts/test.sh` on every pull request ([.github/workflows/ci.yml](.github/workflows/ci.yml)).

## Architecture Overview

Pure logic (filtering, views, glossary, rendering) lives in `BeadsCore`, `BeadsData` and
`BeadsPresentation`, each with its own test target. The `Beady` app target only wires those
libraries to AppKit, the filesystem and the `bd` CLI. New logic goes in a library target,
tests first.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->

<!-- BEGIN BEADS CODEX SETUP: generated by bd setup codex -->
## Beads Issue Tracker

Use Beads (`bd`) for durable task tracking in repositories that include it. Use the `beads` skill at `.agents/skills/beads/SKILL.md` (project install) or `~/.agents/skills/beads/SKILL.md` (global install) for Beads workflow guidance, then use the `bd` CLI for issue operations.

### Quick Reference

```bash
bd ready                # Find available work
bd show <id>            # View issue details
bd update <id> --claim  # Claim work
bd close <id>           # Complete work
bd prime                # Refresh Beads context
```

### Rules

- Use `bd` for all task tracking; do not create markdown TODO lists.
- Run `bd prime` when Beads context is missing or stale. Codex 0.129.0+ can load Beads context automatically through native hooks; use `/hooks` to inspect or toggle them.
- Keep persistent project memory in Beads via `bd remember`; do not create ad hoc memory files.

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.
<!-- END BEADS CODEX SETUP -->

## Conventions & Patterns

- **Interaction design**: any change that moves or acknowledges something on screen follows
  [docs/INTERACTION-DESIGN.md](docs/INTERACTION-DESIGN.md) — read it before adding or touching
  animations, drag-and-drop, or any visual feedback for a user action.
