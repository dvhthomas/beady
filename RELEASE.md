# Releasing Beady

A release is a git tag `v<version>` on master. Pushing the tag runs the Release workflow
([.github/workflows/release.yml](.github/workflows/release.yml)), which tests, builds the app,
attaches `Beady-<version>.zip` to a GitHub Release, and rewrites the Homebrew cask in
[dvhthomas/homebrew-beady](https://github.com/dvhthomas/homebrew-beady). Homebrew only upgrades
when the cask's `version` string changes, so nothing reaches `brew upgrade` users until there is a
new tag.

The version lives in two places, and they have to agree:

- `VERSION` is what the app reports. `scripts/bundle.sh` stamps it into the bundle as
  `CFBundleShortVersionString`, and `CFBundleVersion` is the commit count.
- The tag names the zip and the cask. The workflow derives `VERSION` from `GITHUB_REF_NAME`
  for `scripts/release.sh`, `scripts/cask.sh` and `scripts/publish-cask.sh`.

If they differ, the cask says one version and the app says another. The workflow now fails the
build when `v$(cat VERSION)` is not the tag.

## Steps

1. **Check master has everything you mean to ship.** Tag master, not a feature branch.
   v0.1.0 was tagged on a PR branch before another PR had merged, so the Homebrew build
   shipped without Reset Configuration even though master had it.

2. **Bump `VERSION`** on a branch, open a PR, merge it. Patch for fixes, minor for features.

   ```bash
   echo 0.1.1 > VERSION
   git commit -am "Version 0.1.1"
   ```

3. **Tag the merge commit on master and push the tag.**

   ```bash
   git switch master && git pull --ff-only
   git tag "v$(cat VERSION)" && git push origin "v$(cat VERSION)"
   ```

4. **Watch the workflow.**

   ```bash
   gh run watch --repo dvhthomas/beady --exit-status
   ```

   It runs `scripts/test.sh`, then `scripts/release.sh` (a release-configuration
   `scripts/bundle.sh` plus `ditto` into the zip, which keeps the ad-hoc signature intact),
   publishes the GitHub Release with the quarantine notes in its body, and finally runs
   `scripts/publish-cask.sh`, which clones the tap, renders `Casks/beady.rb` through
   `scripts/cask.sh` with the zip's sha256, and pushes. The cask push uses a write deploy key on
   the tap, stored as the `HOMEBREW_TAP_DEPLOY_KEY` repository secret, because `GITHUB_TOKEN`
   cannot push to another repository.

5. **Check what landed.**

   ```bash
   gh release view "v$(cat VERSION)" --repo dvhthomas/beady
   curl -fsSL https://raw.githubusercontent.com/dvhthomas/homebrew-beady/main/Casks/beady.rb | head -3
   brew update && brew upgrade --cask beady
   defaults read /Applications/Beady.app/Contents/Info.plist CFBundleShortVersionString
   ```

   The Open Anyway approval from the first install carries across upgrades, so the new build
   opens without another trip to System Settings.

## When something goes wrong

**The cask step was skipped.** Without the deploy key secret the workflow still makes the GitHub
Release and only skips the cask. Publish it by hand from the release zip:

```bash
gh release download "v$(cat VERSION)" --repo dvhthomas/beady --pattern '*.zip' --dir build
scripts/publish-cask.sh "build/Beady-$(cat VERSION).zip"
```

That pushes over HTTPS with your own GitHub credentials.

**The tag is on the wrong commit, or the build failed.** Fix master, then move the tag and push
it again. The workflow re-runs on the new push, and `softprops/action-gh-release` updates the
existing release rather than making a second one.

```bash
git tag -f "v$(cat VERSION)" && git push --force origin "v$(cat VERSION)"
```

**The build itself is fine but you want to re-run.** Re-run the failed run from the Actions tab
or with `gh run rerun <id> --repo dvhthomas/beady`. `scripts/publish-cask.sh` is idempotent: it
pushes nothing when the cask already matches.

**Intel Macs.** The zip and the cask are arm64 only (`depends_on arch: :arm64`). There is no
Intel release; the README points Intel users at `scripts/bundle.sh`.
