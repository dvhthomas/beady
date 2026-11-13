---
name: land
description: Verify a merged beady PR actually released — watch the Version and Release workflows, check the GitHub Release, the Homebrew cask and the republished website, tidy beads. Use after a PR merges or when the user asks "did it ship?".
---

# Land

1. `gh run list --repo dvhthomas/beady --limit 5` — find the Version run for the merge.
   Watch long runs in the background: `gh run watch <id> --repo dvhthomas/beady --exit-status`.
2. Confirm the Release run on the new tag is green, then check what shipped:
   ```bash
   gh release view --repo dvhthomas/beady
   curl -fsSL https://raw.githubusercontent.com/dvhthomas/homebrew-beady/main/Casks/beady.rb | head -3
   ```
   The cask `version` must match the new tag. A `release:none`-only merge releases nothing —
   that is success, not a failure.
3. Confirm the website followed. The Website workflow runs after every Version run, release
   or not, and retakes the screenshots from the released app:
   ```bash
   gh run list --repo dvhthomas/beady --workflow pages.yml --limit 3
   curl -fsSL https://dvhthomas.github.io/beady/ | grep -o 'version [0-9.]*' | head -1
   ```
   The version on the site must match the release. A red Screenshots job with a green Deploy
   means the site went out with the screenshots kept in the repository; say so, and file a
   bead to fix the screenshot run. If no Website run started, start one:
   `gh workflow run pages.yml --repo dvhthomas/beady --ref master`.
4. If Version or Release failed, or the cask step was skipped, follow RELEASE.md's
   "When something goes wrong" section rather than improvising.
5. `bd close` anything finished but still open. Run `bd dolt push` only if a Dolt remote is
   configured (`bd doctor` says so); otherwise skip it silently.
6. Report the shipped version with links to the release and the website. Session and worktree cleanup is
   the desktop app's job (auto-archive); don't delete worktrees by hand.
