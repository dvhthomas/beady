#!/usr/bin/env bash
# The arithmetic behind automatic releases, kept out of the workflow YAML so it
# can be tested (scripts/test-next-version.sh) and run by hand.
#
#     scripts/next-version.sh size <label>...         # one PR's labels -> patch|minor|major|none
#     scripts/next-version.sh largest <size>...       # the biggest of several sizes
#     scripts/next-version.sh bump <version> <size>   # 0.1.1 minor -> 0.2.0
#     scripts/next-version.sh [-C <repo>] current     # highest v* tag reachable from HEAD, without the v
#
# A pull request says how big a release it is with one release:* label.
# No label means patch, so forgetting is safe; two release:* labels, or one
# that isn't patch, minor, major or none, is an error and fails the Release
# size check on the PR. The Version workflow (.github/workflows/version.yml)
# chains these: current -> size for each merged PR -> largest -> bump.
set -euo pipefail

die() { echo "next-version: $*" >&2; exit 1; }

rank() {
  case "$1" in
    none) echo 0 ;; patch) echo 1 ;; minor) echo 2 ;; major) echo 3 ;;
    *) return 1 ;;
  esac
}

size() {
  local label found=()
  for label in "$@"; do
    case "$label" in release:*) found+=("${label#release:}") ;; esac
  done
  case "${#found[@]}" in
    0) echo patch ;;
    1) rank "${found[0]}" >/dev/null ||
         die "unknown release size 'release:${found[0]}'; use release:patch, release:minor, release:major or release:none"
       echo "${found[0]}" ;;
    *) die "more than one release size on this pull request: ${found[*]/#/release:}; keep exactly one" ;;
  esac
}

largest() {
  [ $# -gt 0 ] || die "largest needs at least one size"
  local best=none s r
  for s in "$@"; do
    r=$(rank "$s") || die "unknown size '$s'"
    if [ "$r" -gt "$(rank "$best")" ]; then best=$s; fi
  done
  echo "$best"
}

bump() {
  [ $# -eq 2 ] || die "usage: next-version.sh bump <version> <size>"
  local version="$1" size="$2" major minor patch
  [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || die "'$version' is not a MAJOR.MINOR.PATCH version"
  major=$((10#${BASH_REMATCH[1]})); minor=$((10#${BASH_REMATCH[2]})); patch=$((10#${BASH_REMATCH[3]}))
  case "$size" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
    none)  echo "$version" ;;
    *) die "unknown size '$size'" ;;
  esac
}

current() {
  local tag
  tag=$(git -C "$REPO" tag --list 'v[0-9]*' --merged HEAD --sort=-v:refname | head -n 1)
  [ -n "$tag" ] || die "no v* tag is reachable from HEAD in $REPO"
  echo "${tag#v}"
}

REPO="."
if [ "${1:-}" = "-C" ]; then REPO="${2:?-C needs a directory}"; shift 2; fi
cmd="${1:-}"; shift || true
case "$cmd" in
  size|largest|bump|current) "$cmd" "$@" ;;
  *) die "usage: next-version.sh size <label>... | largest <size>... | bump <version> <size> | [-C <repo>] current" ;;
esac
