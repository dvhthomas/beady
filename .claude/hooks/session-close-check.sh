#!/usr/bin/env bash
# Stop hook: at most once per session, when a turn ends on a claude/* branch
# with uncommitted source changes or unpushed commits, remind the agent of the
# close-out pipeline (the ship skill). Silent otherwise.
set -euo pipefail

input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')
[ "$active" = "true" ] && exit 0

marker="${TMPDIR:-/tmp}/beady-close-check-$sid"
[ -e "$marker" ] && exit 0

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
case "$branch" in claude/*) ;; *) exit 0 ;; esac

dirty=$(git status --porcelain -- Sources Tests Package.swift 2>/dev/null || true)
unpushed=0
if upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null); then
  unpushed=$(git rev-list --count "$upstream..HEAD" 2>/dev/null || echo 0)
elif git rev-parse --verify --quiet master >/dev/null; then
  unpushed=$(git rev-list --count master..HEAD 2>/dev/null || echo 0)
fi

if [ -n "$dirty" ] || [ "$unpushed" -gt 0 ]; then
  touch "$marker"
  echo "Close-out check (fires once per session): $branch has $unpushed unpushed commit(s) and uncommitted source changes: [${dirty:-none}]. If the task is DONE, run the ship skill (tests, user guide in docs/website, bd close, commit, push, unlabeled PR). If work is still in progress, just continue — no action needed." >&2
  exit 2
fi
exit 0
