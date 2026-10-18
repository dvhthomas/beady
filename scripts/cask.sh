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
  depends_on macos: :sequoia

  app "Beady.app"

  zap trash: [
    "~/Library/Application Support/Beady",
    "~/Library/Preferences/me.bitsby.beady.plist",
    "~/Library/Saved Application State/me.bitsby.beady.savedState",
  ]

  caveats do
    <<~EOS
      Beady is ad-hoc signed but not notarised (there is no Apple Developer ID
      behind it), so macOS quarantines the download. The first launch is refused;
      System Settings > Privacy & Security then offers "Open Anyway", and that
      approval is kept across upgrades. To clear the flag yourself instead:

        xattr -dr com.apple.quarantine "#{appdir}/Beady.app"

      Beady drives bd, which it looks for on PATH and in Homebrew's bin:

        brew install beads
    EOS
  end
end
CASK
