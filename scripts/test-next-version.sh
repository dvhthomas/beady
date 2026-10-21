#!/usr/bin/env bash
# Tests for scripts/next-version.sh. Run: scripts/test-next-version.sh
# Plain bash on purpose: the script under test is what CI runs, so the tests
# should need nothing CI doesn't have.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NV="$ROOT/scripts/next-version.sh"
failed=0

# expect_out <description> <expected stdout> <args...>
expect_out() {
  local desc="$1" want="$2"; shift 2
  local got
  if got=$("$NV" "$@" 2>&1) && [ "$got" = "$want" ]; then
    echo "ok   $desc"
  else
    echo "FAIL $desc"; echo "     next-version.sh $*"; echo "     want: $want"; echo "     got:  $got"
    failed=1
  fi
}

# expect_fail <description> <text the error must mention> <args...>
expect_fail() {
  local desc="$1" mention="$2"; shift 2
  local got
  if got=$("$NV" "$@" 2>&1); then
    echo "FAIL $desc (succeeded with: $got)"; failed=1
  elif [[ "$got" != *"$mention"* ]]; then
    echo "FAIL $desc"; echo "     error should mention: $mention"; echo "     got: $got"; failed=1
  else
    echo "ok   $desc"
  fi
}

echo "# size: one pull request's labels"
expect_out  "no labels is a patch"                       patch size
expect_out  "ordinary labels alone are a patch"          patch size bug documentation
expect_out  "release:patch"                              patch size release:patch
expect_out  "release:minor"                              minor size release:minor
expect_out  "release:major"                              major size release:major
expect_out  "release:none"                               none  size release:none
expect_out  "release label among other labels"           minor size bug release:minor "good first issue"
expect_fail "two release labels is ambiguous"            "release:patch release:minor" size release:patch release:minor
expect_fail "an unknown release size is refused"         "release:huge" size release:huge
expect_fail "size needs a subcommand it knows"           usage sizes

echo "# largest: across several pull requests"
expect_out  "a single size"                              patch largest patch
expect_out  "minor beats patch"                          minor largest patch minor
expect_out  "major beats everything"                     major largest minor major patch
expect_out  "patch beats none"                           patch largest none patch
expect_out  "all none stays none"                        none  largest none none
expect_fail "largest needs at least one size"            "at least one" largest
expect_fail "largest refuses an unknown size"            "huge" largest patch huge

echo "# bump: arithmetic"
expect_out  "patch bumps the last number"                0.1.2  bump 0.1.1 patch
expect_out  "minor bumps the middle and resets patch"    0.2.0  bump 0.1.1 minor
expect_out  "major bumps the first and resets the rest"  1.0.0  bump 0.1.1 major
expect_out  "none leaves the version alone"              0.1.1  bump 0.1.1 none
expect_out  "numbers, not digits: 9 goes to 10"          0.1.10 bump 0.1.9 patch
expect_out  "minor past 9"                               0.10.0 bump 0.9.3 minor
expect_fail "a leading v is not part of the version"     "v0.1.1" bump v0.1.1 patch
expect_fail "two numbers are not a version"              "0.1" bump 0.1 patch
expect_fail "a pre-release suffix is not supported"      "0.1.1-rc1" bump 0.1.1-rc1 patch
expect_fail "bump refuses an unknown size"               "huge" bump 0.1.1 huge

echo "# current: the highest v* tag reachable from HEAD"
repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT
g() { git -C "$repo" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false "$@" >/dev/null 2>&1; }
g init -q -b main
g commit --allow-empty -m one
expect_fail "no tags at all"                             "no v" -C "$repo" current
g tag v0.1.0
expect_out  "one tag"                                    0.1.0 -C "$repo" current
g commit --allow-empty -m two
g tag v0.1.9
g commit --allow-empty -m three
g tag -a v0.1.10 -m "annotated"
expect_out  "sorted as numbers, annotated or not"        0.1.10 -C "$repo" current
g tag not-a-version
g tag version-2.0.0
expect_out  "tags without the v prefix are ignored"      0.1.10 -C "$repo" current
g switch -q -c side
g commit --allow-empty -m side
g tag v9.9.9
g switch -q main
expect_out  "a tag on another branch doesn't count"      0.1.10 -C "$repo" current
g commit --allow-empty -m four
expect_out  "commits after the tag still see it"         0.1.10 -C "$repo" current

echo
if [ "$failed" -eq 0 ]; then echo "All next-version tests passed."; else echo "Some next-version tests FAILED."; exit 1; fi
