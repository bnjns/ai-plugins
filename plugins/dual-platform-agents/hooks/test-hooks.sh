#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Hermetic marker state — otherwise leftover acks from a previous run can make a
# later run pass spuriously.
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/hook-tests.XXXXXX")"
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT

run_agent() {
  ./guard-agent-files.sh <<<"$1"
}

run_record() {
  ./record-skill-read.sh <<<"$1"
}

run_clear() {
  ./clear-skill-read.sh <<<"$1"
}

session='test-session'
repo='/repo'
other_write='{"conversation_id":"'"$session"'","cwd":"'"$repo"'","tool_name":"Edit","tool_input":{"file_path":"README.md"}}'
agents_write='{"conversation_id":"'"$session"'","cwd":"'"$repo"'","tool_name":"Write","tool_input":{"file_path":"AGENTS.md"}}'
read_agents='{"conversation_id":"'"$session"'","tool_name":"Read","tool_input":{"path":"/cache/dual-platform-agents/skills/dual-platform-agents/SKILL.md"}}'

echo 'block AGENTS.md write without dual-platform skill read'
if run_agent "$agents_write"; then
  echo 'expected block'
  exit 1
fi

echo 'allow unrelated write for agent-files guard without skill read'
run_agent "$other_write"

echo 'record dual-platform-agents read'
run_record "$read_agents"

echo 'allow AGENTS.md write after dual-platform skill read'
run_agent "$agents_write"

echo 'clear on session end'
run_clear '{"conversation_id":"'"$session"'"}'

echo 'block AGENTS.md again after session end'
if run_agent "$agents_write"; then
  echo 'expected block'
  exit 1
fi

transcript='/tmp/claude/transcripts/session.jsonl'
transcript_write='{"transcript_path":"'"$transcript"'","cwd":"'"$repo"'","tool_name":"Write","tool_input":{"file_path":"AGENTS.md"}}'
transcript_read='{"transcript_path":"'"$transcript"'","tool_name":"Read","tool_input":{"path":"/cache/dual-platform-agents/skills/dual-platform-agents/SKILL.md"}}'

echo 'record skill read keyed by transcript path'
run_record "$transcript_read"
run_agent "$transcript_write"
run_clear '{"transcript_path":"'"$transcript"'"}'

anon_write='{"cwd":"'"$repo"'","tool_name":"Write","tool_input":{"file_path":"AGENTS.md"}}'
anon_read='{"cwd":"'"$repo"'","tool_name":"Read","tool_input":{"path":"/cache/dual-platform-agents/skills/dual-platform-agents/SKILL.md"}}'

echo 'block writes without session identity until the skill is read'
if run_agent "$anon_write"; then
  echo 'expected block'
  exit 1
fi

# Previously these payloads could never satisfy a gate: mark_skill_read silently
# wrote nothing without a session id while skill_read_for_session returned false,
# so the block was unrecoverable. The key now falls back to the cwd.
echo 'allow writes without session identity after the skill is read (cwd fallback)'
run_record "$anon_read"
run_agent "$anon_write"
run_clear '{"cwd":"'"$repo"'"}'

echo 'block writes without session identity again after session end'
if run_agent "$anon_write"; then
  echo 'expected block'
  exit 1
fi


# --- path scoping -----------------------------------------------------------
# The gate applies to project files. Agent-owned state (plans, memory, session
# scratch) and paths outside the project must never be gated, regardless of
# file type and regardless of whether any skill has been read.

scoped='scope-session'
write_at() {
  echo '{"conversation_id":"'"$scoped"'","cwd":"'"$1"'","tool_name":"Write","tool_input":{"file_path":"'"$2"'"}}'
}

allow_agent() {
  if ! run_agent "$(write_at "$1" "$2")"; then
    echo "expected guard-agent-files allow: $2"
    exit 1
  fi
}

echo 'allow plan files under the user-level .claude tree'
allow_agent "$repo" "$HOME/.claude/plans/some-plan.md"

echo 'allow plan files under a repo-local .claude tree'
allow_agent "$repo" "$repo/.claude/plans/some-plan.md"

echo 'allow memory files'
allow_agent "$repo" "$HOME/.claude/projects/-repo/memory/notes.md"

echo 'allow other in-repo harness state'
allow_agent "$repo" "$repo/.claude/todos/list.json"
allow_agent "$repo" "$repo/.claude/statsig/cache"
allow_agent "$repo" "$repo/.claude/.cc-writes/pending"
allow_agent "$repo" "$repo/.claude/settings.local.json"

# Default-exempt under .claude/: a state directory the harness adds later must
# not start blocking writes without a change here.
echo 'allow an unknown .claude subdirectory'
allow_agent "$repo" "$repo/.claude/output-styles/concise.md"

echo 'allow scratch writes under TMPDIR'
allow_agent "$repo" "$TMPDIR/scratchpad/AGENTS.md"

echo 'allow writes outside the project'
allow_agent "$repo" '/other/project/AGENTS.md'

echo 'block repo agent wiring files'
for scoped_path in "$repo/AGENTS.md" "$repo/CLAUDE.md" "$repo/packages/api/AGENTS.md" \
                   "$repo/.agents/skills/x/SKILL.md" "$repo/.claude/skills/x/SKILL.md" \
                   "$repo/.claude/agents/x.md"; do
  if run_agent "$(write_at "$repo" "$scoped_path")"; then
    echo "expected block: $scoped_path"
    exit 1
  fi
done

echo 'the agent-file gate ignores a near-miss basename'
if ! run_agent "$(write_at "$repo" "$repo/docs/CLAUDE-notes.md")"; then
  echo 'expected guard-agent-files allow: docs/CLAUDE-notes.md'
  exit 1
fi

# --- Skill tool satisfies a gate --------------------------------------------

skill_payload() {
  echo '{"conversation_id":"'"$1"'","cwd":"'"$repo"'","tool_name":"Skill","tool_input":{"'"$2"'":"'"$3"'"}}'
}

echo 'Skill tool satisfies the dual-platform gate'
run_record "$(skill_payload 'skill-agents' 'skill' 'dual-platform-agents:dual-platform-agents')"
if ! run_agent '{"conversation_id":"skill-agents","cwd":"'"$repo"'","tool_name":"Write","tool_input":{"file_path":"'"$repo"'/AGENTS.md"}}'; then
  echo 'expected allow after dual-platform-agents Skill'
  exit 1
fi

# --- fail-closed behaviour --------------------------------------------------
# A path the guard cannot place must keep gating.

echo 'block a relative agent file when cwd is absent'
if run_agent '{"conversation_id":"unresolved","tool_name":"Write","tool_input":{"file_path":"AGENTS.md"}}'; then
  echo 'expected block'
  exit 1
fi

echo 'ok'
