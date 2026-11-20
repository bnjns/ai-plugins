#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Hermetic marker state — otherwise leftover acks from a previous run can make a
# later run pass spuriously.
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/hook-tests.XXXXXX")"
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT

run_write() {
  ./guard-write.sh <<<"$1"
}

run_record() {
  ./record-skill-read.sh <<<"$1"
}

run_clear() {
  ./clear-skill-read.sh <<<"$1"
}

session='test-session'
repo='/repo'
ts_write='{"conversation_id":"'"$session"'","cwd":"'"$repo"'","tool_name":"Write","tool_input":{"file_path":"src/example.ts"}}'
other_write='{"conversation_id":"'"$session"'","cwd":"'"$repo"'","tool_name":"Edit","tool_input":{"file_path":"README.md"}}'
read_coding='{"conversation_id":"'"$session"'","tool_name":"Read","tool_input":{"path":"/cache/coding-conventions/skills/coding-conventions/SKILL.md"}}'
read_ts='{"conversation_id":"'"$session"'","tool_name":"Read","tool_input":{"path":"/cache/coding-conventions/skills/typescript-conventions/SKILL.md"}}'

echo 'block TS write without any skill read'
if run_write "$ts_write"; then
  echo 'expected block'
  exit 1
fi

echo 'block non-TS write without coding skill read'
if run_write "$other_write"; then
  echo 'expected block'
  exit 1
fi

echo 'record coding-conventions read'
run_record "$read_coding"

echo 'allow non-TS write after coding skill read'
run_write "$other_write"

echo 'block TS write with only coding skill read'
if run_write "$ts_write"; then
  echo 'expected block'
  exit 1
fi

echo 'record typescript-conventions read'
run_record "$read_ts"

echo 'allow TS write after both skills read'
run_write "$ts_write"

echo 'clear on session end'
run_clear '{"conversation_id":"'"$session"'"}'

echo 'block write again after session end'
if run_write "$other_write"; then
  echo 'expected block'
  exit 1
fi


# --- path scoping -----------------------------------------------------------
# The gates apply to project files. Agent-owned state (plans, memory, session
# scratch) and paths outside the project must never be gated, regardless of
# file type and regardless of whether any skill has been read.

scoped='scope-session'
write_at() {
  echo '{"conversation_id":"'"$scoped"'","cwd":"'"$1"'","tool_name":"Write","tool_input":{"file_path":"'"$2"'"}}'
}

allow_write() {
  if ! run_write "$(write_at "$1" "$2")"; then
    echo "expected guard-write allow: $2"
    exit 1
  fi
}

echo 'allow plan files under the user-level .claude tree'
allow_write "$repo" "$HOME/.claude/plans/some-plan.md"

echo 'allow plan files under a repo-local .claude tree'
allow_write "$repo" "$repo/.claude/plans/some-plan.md"

echo 'allow memory files'
allow_write "$repo" "$HOME/.claude/projects/-repo/memory/notes.md"

echo 'allow other in-repo harness state'
allow_write "$repo" "$repo/.claude/todos/list.json"
allow_write "$repo" "$repo/.claude/statsig/cache"
allow_write "$repo" "$repo/.claude/.cc-writes/pending"
allow_write "$repo" "$repo/.claude/settings.local.json"

# Default-exempt under .claude/: a state directory the harness adds later must
# not start blocking writes without a change here.
echo 'allow an unknown .claude subdirectory'
allow_write "$repo" "$repo/.claude/output-styles/concise.md"

echo 'allow scratch writes under TMPDIR even for code files'
allow_write "$repo" "$TMPDIR/scratchpad/scratch.ts"

echo 'allow writes outside the project'
allow_write "$repo" '/other/project/src/app.ts'

echo 'allow code writes when cwd is itself under TMPDIR'
allow_write "$TMPDIR/repo" "$TMPDIR/repo/src/app.ts"

echo 'block project code writes (all file types are gated)'
for scoped_path in "$repo/src/app.ts" "$repo/src/app.py" "$repo/main.go" "$repo/README.md" "$repo/package.json"; do
  if run_write "$(write_at "$repo" "$scoped_path")"; then
    echo "expected block: $scoped_path"
    exit 1
  fi
done

echo 'block project code writes given a relative path plus cwd'
if run_write "$(write_at "$repo" 'src/app.py')"; then
  echo 'expected block'
  exit 1
fi

# A missing cwd must not disable the gate — path_in_project reports "unknown",
# not "outside".
echo 'block absolute project code writes when cwd is absent'
if run_write '{"conversation_id":"'"$scoped"'","tool_name":"Write","tool_input":{"file_path":"/repo/src/app.ts"}}'; then
  echo 'expected block'
  exit 1
fi

# --- Skill tool satisfies a gate --------------------------------------------
# The exact payload field is undocumented, so every plausible field and name
# form must record. This is what stops the agent having to Read SKILL.md after
# already loading the skill natively.

skill_payload() {
  echo '{"conversation_id":"'"$1"'","cwd":"'"$repo"'","tool_name":"Skill","tool_input":{"'"$2"'":"'"$3"'"}}'
}

echo 'Skill tool records the read for every plausible field and name form'
skill_case=0
for skill_field in skill skill_name skillName name command; do
  for skill_form in 'coding-conventions' '/coding-conventions' \
                    'coding-conventions:coding-conventions' \
                    '/cache/coding-conventions/skills/coding-conventions/SKILL.md'; do
    skill_case=$((skill_case + 1))
    skill_session="skill-form-$skill_case"
    run_record "$(skill_payload "$skill_session" "$skill_field" "$skill_form")"
    if ! run_write '{"conversation_id":"'"$skill_session"'","cwd":"'"$repo"'","tool_name":"Write","tool_input":{"file_path":"'"$repo"'/src/app.js"}}'; then
      echo "expected allow after Skill: field=$skill_field form=$skill_form"
      exit 1
    fi
  done
done

echo 'Skill tool does not record a near-miss skill name'
run_record "$(skill_payload 'skill-negative' 'skill' 'coding-conventions-extra')"
run_record "$(skill_payload 'skill-negative' 'skill' 'other:coding-conventions-extra')"
if run_write '{"conversation_id":"skill-negative","cwd":"'"$repo"'","tool_name":"Write","tool_input":{"file_path":"'"$repo"'/src/app.js"}}'; then
  echo 'expected block for near-miss skill name'
  exit 1
fi

echo 'a TypeScript write reports both missing skills in one block'
ts_block_msg=$(run_write '{"conversation_id":"one-shot","cwd":"'"$repo"'","tool_name":"Write","tool_input":{"file_path":"'"$repo"'/src/app.ts"}}' 2>&1 || true)
case "$ts_block_msg" in
  *coding-conventions*typescript-conventions*) ;;
  *)
    echo 'expected one block naming both skills'
    exit 1
    ;;
esac

echo 'the block message names an absolute SKILL.md path'
case "$ts_block_msg" in
  */skills/coding-conventions/SKILL.md*) ;;
  *)
    echo 'expected an absolute SKILL.md path in the block message'
    exit 1
    ;;
esac


# --- fail-closed behaviour --------------------------------------------------
# A path the guard cannot place must keep gating. Previously an unresolvable
# relative path exited zero, so `src/app.ts` with no cwd bypassed the gate.

echo 'block a relative code write when cwd is absent'
if run_write '{"conversation_id":"unresolved","tool_name":"Write","tool_input":{"file_path":"src/app.ts"}}'; then
  echo 'expected block'
  exit 1
fi

echo 'still allow a relative harness path when cwd is absent'
run_write '{"conversation_id":"unresolved","tool_name":"Write","tool_input":{"file_path":".claude/plans/p.md"}}'

echo 'allow a payload with no path at all'
run_write '{"conversation_id":"unresolved","cwd":"/repo","tool_name":"Write","tool_input":{}}'

# --- Read matching ----------------------------------------------------------
# Only the skill's own SKILL.md may satisfy a gate. A bare trailing name would
# let an unrelated file stand in for the skill.

echo 'an unrelated Read path ending in a skill name does not satisfy the gate'
run_record '{"conversation_id":"bare-read","cwd":"/repo","tool_name":"Read","tool_input":{"path":"/notes/coding-conventions"}}'
if run_write '{"conversation_id":"bare-read","cwd":"/repo","tool_name":"Write","tool_input":{"file_path":"/repo/src/app.js"}}'; then
  echo 'expected block'
  exit 1
fi

echo 'a Read of the real SKILL.md still satisfies the gate'
run_record '{"conversation_id":"real-read","cwd":"/repo","tool_name":"Read","tool_input":{"path":"/cache/coding-conventions/skills/coding-conventions/SKILL.md"}}'
run_write '{"conversation_id":"real-read","cwd":"/repo","tool_name":"Write","tool_input":{"file_path":"/repo/src/app.js"}}'

# --- identity-less ack window -----------------------------------------------
# A cwd-derived key cannot separate two conversations in the same project, so
# the ack must expire quickly rather than lasting the full 12h.

echo 'an identity-less ack works while fresh'
run_record '{"cwd":"/repo","tool_name":"Skill","tool_input":{"skill":"coding-conventions"}}'
run_write '{"cwd":"/repo","tool_name":"Write","tool_input":{"file_path":"/repo/src/anon.js"}}'

echo 'an identity-less ack expires well before the 12h identified window'
find "$TMPDIR" -name 'skill-read-coding-conventions-*' -exec touch -t 202501010000 {} \; 2>/dev/null
if run_write '{"cwd":"/repo","tool_name":"Write","tool_input":{"file_path":"/repo/src/anon.js"}}'; then
  echo 'expected block once the short window elapsed'
  exit 1
fi

echo 'ok'
