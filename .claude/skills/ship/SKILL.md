---
name: ship
description: End-of-work pipeline for beady — run the quality gates, bring the user guide (docs/website) up to date with the change, close finished beads, commit, push, and open an unlabeled (patch) pull request with Auto-fix watching it. Use when the session's work is done and verified, or the user says "ship it", "wrap up", or "make a PR".
---

# Ship

Ships the current worktree branch as a pull request. **Patch is the norm**: the PR goes up
unlabeled, which the Version workflow reads as a patch. You never apply `release:minor` or
`release:major` — a PreToolUse hook blocks it; those are the human's decision.

## Steps

1. **Gates.** `scripts/test.sh` must pass. If app code changed, also `swift build`. Stop and
   fix on failure — never ship red.

2. **Docs.** Every release republishes the website, so the user guide has to be right at the
   merge. Look at the diff (`git diff master...HEAD --stat`) and ask: would a user notice?
   - **Yes** (a feature, setting, shortcut, menu item, view, default, or wording they see):
     update the matching page in `docs/website/content/guide/`, and `content/_index.md` if the
     landing page describes it. Renamed or removed something? `grep -rn` the old words under
     `docs/website/content` and `README.md`. New UI worth a picture: capture it in
     `SnapshotMode.run` and add it to `SHOTS` in `scripts/screenshots.sh`.
   - **No** (refactor, tests, CI, tooling): nothing to edit; say so in the PR body.
   - If `Sources/Beady/SnapshotMode.swift` or `scripts/screenshots.sh` changed, run
     `scripts/screenshots.sh` — it fails if a snapshot the site uses went missing.
   - If anything under `docs/website` changed, it must build:
     `hugo --source docs/website --destination "$(mktemp -d)"`.
   "The website and user guide" in CLAUDE.md has the full rule.

3. **Beads.** `bd close <id> ...` for finished issues; `bd create` for anything left over.
   Reference the ids in the commit message.

4. **Commit and push.** Commit style here is a plain sentence plus the bead id, e.g.
   `Optimistic drops: the card moves instantly, bd catches up behind (bdv-9ec)`.
   Push the `claude/*` branch. Never push master, never push tags, never force-push.

5. **Release size.** Decide what the change deserves and act accordingly:
   - **Bug fix, tweak, refactor, test, docs or tooling**: ship unlabeled. Put
     "Release size: patch (the default — no label)" in the PR body.
   - **Repo-only change nobody needs shipped** (CI, agent config, README, or a change only to
     the website): `gh pr create --label release:none`. The website is still republished.
   - **New feature or visible behaviour change**: ship as a **draft** (`gh pr create --draft`),
     write "Release size: I recommend `release:minor` because ..." in the PR body, and ask the
     user to label it (`gh pr edit <n> --add-label release:minor`), mark it ready, and merge.
     Same pattern for `major`. Never add those labels yourself; the hook enforces this. The
     draft matters: Merge-when-green skips drafts, so the PR cannot ship as a patch while the
     user reads the recommendation.

6. **PR.** `gh pr create` with a body covering: what changed and why, test evidence, bead
   ids, a **Docs** line (which guide pages changed, or "Docs: no user-visible change"), and
   the release size line. End the body with the standard attribution line.

7. **Bind.** In the Claude desktop app, bind the PR (ccd_pr `get_status`, then `bind_pr` if
   it is not reported) so Auto-fix handles CI failures, merge conflicts and review comments.

8. **Report.** Unlabeled, patch and `release:none` PRs merge themselves once CI and the
   Release size check pass (the Merge-when-green workflow), and the merge releases itself —
   tell the user whether this PR will self-merge or waits on their label, ready-up and merge.
