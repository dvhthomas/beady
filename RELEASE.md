# Releasing Beady

Every merge to master is a release, and nobody bumps a number. The Version workflow
([.github/workflows/version.yml](.github/workflows/version.yml)) works out the next version from
the pull requests that merged, writes it to `VERSION`, tags `v<version>`, and starts the Release
workflow ([.github/workflows/release.yml](.github/workflows/release.yml)), which tests, builds the
app, attaches `Beady-<version>.zip` to a GitHub Release, and rewrites the Homebrew cask in
[dvhthomas/homebrew-beady](https://github.com/dvhthomas/homebrew-beady). Homebrew only upgrades
when the cask's `version` string changes, so every tag reaches `brew upgrade` users.

## The one decision: how big is the change?

Say it with a label on the pull request. At most one; none is fine.

| Label | When | From 0.1.1 |
|---|---|---|
| *no label*, or `release:patch` | A bug fix or a minor tweak. The default, so forgetting is safe. | 0.1.2 |
| `release:minor` | Something more significant: a new feature, a visible change in behaviour. | 0.2.0 |
| `release:major` | Rare. It breaks how people use Beady or the files it writes. | 1.0.0 |
| `release:none` | Rare. Nothing worth shipping on its own, like a README typo. Merged alone it releases nothing; merged alongside a patch, the patch wins. | 0.1.1 |

```bash
gh pr create --label release:minor ...      # when opening
gh pr edit <number> --add-label release:minor   # afterwards
```

The Release size check ([.github/workflows/release-size.yml](.github/workflows/release-size.yml))
fails a pull request that carries two `release:*` labels, or one it doesn't know, or that edits
`VERSION`. The label is the whole decision; the number is derived.

## What happens on merge

1. **Version** runs on the push to master. It takes the highest `v*` tag reachable from master
   (`scripts/next-version.sh current`), finds the pull requests merged since that tag, reads each
   one's size from its labels (`size`), keeps the largest (`largest`) and bumps (`bump`). Several
   pull requests merged between releases ship together at the largest of their sizes. A commit
   pushed to master without a pull request counts as a patch.

2. It writes `VERSION`, commits `Version X.Y.Z`, tags that commit `vX.Y.Z`, pushes commit and tag
   together, and starts **Release** on the tag. The bump commit is the tagged commit, so a run
   that starts from it finds master already released and stops; that is what keeps the workflow
   from chasing its own tail. Runs started by merges close together queue, and each works from the
   tip of master as it is then, so the second sees the first's tag and does nothing.

3. **Release** checks that `VERSION` matches the tag, runs `scripts/test.sh`, then
   `scripts/release.sh` (a release-configuration `scripts/bundle.sh` plus `ditto` into the zip,
   which keeps the ad-hoc signature intact), publishes the GitHub Release with the quarantine notes
   and the list of merged pull requests in its body, and finally runs `scripts/publish-cask.sh`,
   which clones the tap, renders `Casks/beady.rb` through `scripts/cask.sh` with the zip's sha256,
   and pushes. The cask push uses a write deploy key on the tap, stored as the
   `HOMEBREW_TAP_DEPLOY_KEY` repository secret, because `GITHUB_TOKEN` cannot push to another
   repository.

Watch it:

```bash
gh run list --repo dvhthomas/beady --limit 3
gh run watch --repo dvhthomas/beady --exit-status
```

## Where the version lives

- **Tags are the source of truth.** `v<version>` on master, made by the Version workflow.
- `VERSION` is what the app reports: `scripts/bundle.sh` stamps it into the bundle as
  `CFBundleShortVersionString` (`CFBundleVersion` is the commit count). Only the Version workflow
  writes it. Release fails when `v$(cat VERSION)` is not the tag, so the cask and the app can't
  disagree.
- `scripts/next-version.sh` is the arithmetic, and `scripts/test-next-version.sh` tests it. Try it:

  ```bash
  scripts/next-version.sh current                 # 0.1.1
  scripts/next-version.sh size release:minor bug  # minor
  scripts/next-version.sh bump 0.1.1 minor        # 0.2.0
  ```

## Check what landed

```bash
gh release view "v$(cat VERSION)" --repo dvhthomas/beady
curl -fsSL https://raw.githubusercontent.com/dvhthomas/homebrew-beady/main/Casks/beady.rb | head -3
brew update && brew upgrade --cask beady
defaults read /Applications/Beady.app/Contents/Info.plist CFBundleShortVersionString
```

The Open Anyway approval from the first install carries across upgrades, so the new build opens
without another trip to System Settings.

## Making it stick

The checks only bind if master requires them. As of this writing master is unprotected, so a red
Release size check can still be merged by clicking. Protecting master (require the `Release size`
check, require a pull request) also blocks the Version workflow's own push, because `GITHUB_TOKEN`
can't bypass branch protection. To protect master, give the workflow a way past: a fine-grained
personal access token or a GitHub App with bypass, stored as a secret and used for the push and
tag. Pushes made with such a token *do* start workflows, so the loop guard above is what matters
then, and the explicit `gh workflow run release.yml` would need to go, since the tag push would
start Release by itself.

## Signing for real, and iCloud sync

The releases are ad-hoc signed, and that is enough for everything but one setting: **Sync my
views between Macs with iCloud** (Settings › Views) uses iCloud's Key-Value Store, which macOS
only grants to an app signed with a Developer ID and carrying the entitlement in
`Resources/Beady.entitlements`. An ad-hoc build runs without it and says so under the toggle.
To build one that has it:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" TEAM_ID=TEAMID scripts/bundle.sh
```

`scripts/bundle.sh` fills the team id into the entitlements and signs with them. The Release
workflow doesn't do this: it has no certificate.

## When something goes wrong

**The Release size check is red.** The pull request has two `release:*` labels, or one that isn't
`patch`, `minor`, `major` or `none`, or it changes `VERSION`. Fix the labels or drop the `VERSION`
change; the check re-runs on every label change and push.

**Version failed: "VERSION says X but the latest tag is vY".** Someone edited `VERSION` by hand
and it got through. Put it back to Y on master (or, if X really was released by hand, tag `vX` on
the commit that shipped it) and re-run the failed run.

**Version failed: "more than one release size".** A pull request merged with conflicting labels.
Labels can be changed after merge: fix them, then re-run the failed run with
`gh run rerun <id> --repo dvhthomas/beady`. It reads the labels afresh.

**Version pushed the tag but Release didn't run, or failed.** Start it again on the tag:

```bash
gh workflow run release.yml --repo dvhthomas/beady --ref "v$(cat VERSION)"
```

If the build itself failed, fix master; the fix is its own release (a patch), with a new tag. Only
move a tag when the release on it never built, and then with `git tag -f` and `git push --force
origin v<version>`; `softprops/action-gh-release` updates the existing release rather than making
a second one.

**The cask step was skipped.** Without the deploy key secret the workflow still makes the GitHub
Release and only skips the cask. Publish it by hand from the release zip:

```bash
gh release download "v$(cat VERSION)" --repo dvhthomas/beady --pattern '*.zip' --dir build
scripts/publish-cask.sh "build/Beady-$(cat VERSION).zip"
```

That pushes over HTTPS with your own GitHub credentials.

**You want to re-run.** Re-run the failed run from the Actions tab or with
`gh run rerun <id> --repo dvhthomas/beady`. `scripts/publish-cask.sh` is idempotent: it pushes
nothing when the cask already matches.

**Releasing by hand**, if Actions is unavailable. This is the old process; keep `VERSION` and the
tag in step, and tag master, not a branch (v0.1.0 was tagged on a PR branch before another PR had
merged, and shipped without Reset Configuration even though master had it).

```bash
git switch master && git pull --ff-only
next=$(scripts/next-version.sh bump "$(scripts/next-version.sh current)" patch)
echo "$next" > VERSION && git commit -am "Version $next"
git tag -a "v$next" -m "Beady $next" && git push --atomic origin master "v$next"
```

**Intel Macs.** The zip and the cask are arm64 only (`depends_on arch: :arm64`). There is no
Intel release; the README points Intel users at `scripts/bundle.sh`.
