#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$script_dir/lib.sh"

payload=$(cat)
command=$(echo "$payload" | jq -r '.tool_input.command // ""')

if ! echo "$command" | grep -qE '\bgh\s+pr\s+(create|edit|ready)\b'; then
  exit 0
fi

if skill_read_for_session "create-pull-request" "$(session_id_from_payload "$payload")"; then
  exit 0
fi

echo "Blocked: read skills/create-pull-request/SKILL.md in the Create Pull Request plugin before running gh pr create, gh pr edit, or gh pr ready. Follow the skill exactly — do not improvise." >&2
exit 2
