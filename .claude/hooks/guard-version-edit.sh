#!/usr/bin/env bash
# PreToolUse(Edit|Write) hook: VERSION is written by the Version workflow on
# merge, never by hand. The Release size CI check backs this up; failing fast
# here saves the round trip.
set -euo pipefail

fp=$(jq -r '.tool_input.file_path // ""')
case "$fp" in
  VERSION|*/VERSION)
    echo "Blocked: VERSION is derived from the release:* label when a pull request merges; never edit it by hand (see RELEASE.md). If a release went wrong, follow RELEASE.md's 'When something goes wrong'." >&2
    exit 2
    ;;
esac
exit 0
