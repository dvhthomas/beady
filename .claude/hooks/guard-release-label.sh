#!/usr/bin/env bash
# PreToolUse(Bash) hook: release:minor and release:major are human decisions.
# An agent may recommend them in a PR body, never apply them. See RELEASE.md.
set -euo pipefail

cmd=$(jq -r '.tool_input.command // ""')
if printf '%s' "$cmd" | grep -qE '(^|[ ;&|(])gh[[:space:]]' \
   && printf '%s' "$cmd" | grep -qE 'release:(minor|major)'; then
  echo "Blocked: release:minor and release:major are human decisions. Leave the pull request unlabeled (that means patch, the norm), state the size you recommend and why in the PR body, and ask the user to apply it themselves with: gh pr edit <n> --add-label release:minor" >&2
  exit 2
fi
exit 0
