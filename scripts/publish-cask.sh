#!/usr/bin/env bash
# Writes the cask for a release zip into the Homebrew tap and pushes it, so
# `brew install --cask dvhthomas/beady/beady` picks up the new version.
#
#     scripts/publish-cask.sh build/Beady-0.1.0.zip
#     VERSION=0.2.0 scripts/publish-cask.sh build/Beady-0.2.0.zip <tap git url>
#
# The tap defaults to https://github.com/dvhthomas/homebrew-beady.git; the Release
# workflow passes its SSH URL and pushes with a deploy key. An empty tap (no commits yet) is
# started from scratch, so the repo only has to exist. Nothing is pushed when
# the cask is already up to date.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIP="${1:?usage: scripts/publish-cask.sh <release zip> [tap git url]}"
ZIP="$(cd "$(dirname "$ZIP")" && pwd)/$(basename "$ZIP")" # absolute: we cd into the clone below
TAP_URL="${2:-https://github.com/dvhthomas/homebrew-beady.git}"
VERSION="${VERSION:-$(cat "$ROOT/VERSION")}"
export VERSION

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
TAP="$WORK/tap"

git clone --quiet "$TAP_URL" "$TAP"
cd "$TAP" # an empty tap clones onto an unborn branch, and the first commit creates it

mkdir -p Casks
"$ROOT/scripts/cask.sh" "$ZIP" > Casks/beady.rb
git add Casks/beady.rb
if git diff --cached --quiet; then
  echo "Cask for Beady $VERSION already published; nothing to do."
  exit 0
fi

git -c user.name="${GIT_AUTHOR_NAME:-beady-release}" \
    -c user.email="${GIT_AUTHOR_EMAIL:-beady-release@users.noreply.github.com}" \
    commit --quiet -m "beady $VERSION"
git push --quiet origin HEAD
echo "Published cask for Beady $VERSION to $TAP_URL"
