#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$script_dir/lib.sh"

payload=$(cat)
tool_name=$(echo "$payload" | jq -r '.tool_name // .tool // ""')

if ! is_write_tool "$tool_name"; then
  exit 0
fi

session_id=$(session_id_from_payload "$payload")
cwd=$(cwd_from_payload "$payload")
raw_path=$(write_path_from_payload "$payload")

if [[ -z "$raw_path" ]]; then
  exit 0
fi

abs_path=$(resolve_against_cwd "$raw_path" "$cwd") || abs_path=""

if is_harness_state "${abs_path:-$raw_path}"; then
  exit 0
fi

if [[ -n "$abs_path" ]]; then
  in_project=0
  path_in_project "$abs_path" "$cwd" || in_project=$?
  if [[ "$in_project" -eq 1 ]]; then
    exit 0
  fi
  rel_path=$(project_relative "$abs_path" "$cwd")
else
  # Relative path with no cwd: it cannot be placed, so keep gating rather than
  # failing open.
  rel_path="$raw_path"
fi

if ! is_agent_file_path "$rel_path"; then
  exit 0
fi

if skill_read_for_session "dual-platform-agents" "$session_id" "$cwd"; then
  exit 0
fi

deny_skill_gates "editing repo agent instructions at $rel_path requires wiring both Cursor and Claude paths." "dual-platform-agents"
