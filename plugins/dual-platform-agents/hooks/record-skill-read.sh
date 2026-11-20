#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$script_dir/lib.sh"

payload=$(cat)
tool_name=$(echo "$payload" | jq -r '.tool_name // .tool // ""')

case "$tool_name" in
  Read|ReadTool)
    kind=read
    candidate=$(read_path_from_payload "$payload")
    ;;
  Skill|SkillTool)
    kind=skill
    candidate=$(skill_name_from_payload "$payload")
    ;;
  *) exit 0 ;;
esac

if [[ -z "$candidate" ]]; then
  exit 0
fi

session_id=$(session_id_from_payload "$payload")
cwd=$(cwd_from_payload "$payload")

for skill in "${GATED_SKILLS[@]}"; do
  mark_if_skill "$kind" "$candidate" "$session_id" "$cwd" "$skill"
done

exit 0
