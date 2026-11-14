#!/usr/bin/env bash
# Prints the Homebrew cask for a release zip, with the zip's sha256 filled in.
#
#     scripts/cask.sh build/Beady-0.1.0.zip > Casks/beady.rb
#     VERSION=0.2.0 scripts/cask.sh build/Beady-0.2.0.zip
#
# The cask downloads the zip that scripts/release.sh built and the Release
# workflow attached to the GitHub Release for tag v<version>, so the version
# here must be the one in that tag (it defaults to the VERSION file).
# scripts/publish-cask.sh pushes the result to the tap repo.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIP="${1:?usage: scripts/cask.sh <release zip>}"
VERSION="${VERSION:-$(cat "$ROOT/VERSION")}"
SHA256="$(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)"

cat <<CASK
cask "beady" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/dvhthomas/beady/releases/download/v#{version}/Beady-#{version}.zip"
  name "Beady"
  desc "Window onto a beads (bd) issue database"
  homepage "https://github.com/dvhthomas/beady"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  # Beady is a window onto bd and does nothing without it, so bd comes with it.
  depends_on formula: "beads"
  depends_on macos: :sequoia

  # Beady has no Developer ID behind it, so every release carries a new ad-hoc signature that
  # macOS has never seen, and a quarantined copy is refused at each upgrade, not just the
  # first install. Clear the flag on the staged copy, before the app is moved into place:
  # once it is in Applications, macOS App Management can deny the change. A failure here
  # must not fail the install; the caveats say what to type instead.
  preflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{staged_path}}/Beady.app"],
        writable_paths: ["Beady.app"],
        must_succeed:   false
  end

  app "Beady.app"

  zap trash: [
    "~/Library/Application Support/Beady",
    "~/Library/Preferences/me.bitsby.beady.plist",
    "~/Library/Saved Application State/me.bitsby.beady.savedState",
  ]

  caveats do
    <<~EOS
      Beady is ad-hoc signed but not notarised (there is no Apple Developer ID
      behind it), and macOS refuses to open a quarantined copy of such an app.
      This cask clears the quarantine flag itself on every install and upgrade,
      so Beady should simply open. If macOS refuses it anyway, clear the flag
      by hand; each release is a new signature, so that means after each upgrade:

        xattr -dr com.apple.quarantine "#{appdir}/Beady.app"

      Beady drives bd. Homebrew installed it alongside (the beads formula) and
      keeps it up to date with: brew upgrade beads
    EOS
  end
end
CASK
