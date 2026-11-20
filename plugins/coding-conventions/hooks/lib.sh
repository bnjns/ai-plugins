#!/usr/bin/env bash
# Shared hook helpers. This file is byte-identical across plugins that ship hooks —
# edit plugins/coding-conventions/hooks/lib.sh and copy it. Per-plugin gate
# definitions live in gates.sh.

# --- payload accessors -------------------------------------------------------

session_id_from_payload() {
  local payload="$1"
  echo "$payload" | jq -r '
    .conversation_id //
    .conversationId //
    .session_id //
    .sessionId //
    .transcript_path //
    .transcriptPath //
    ""
  '
}

cwd_from_payload() {
  local payload="$1"
  echo "$payload" | jq -r '.cwd // .workspace_root // .workspaceRoot // ""'
}

read_path_from_payload() {
  local payload="$1"
  echo "$payload" | jq -r '
    .tool_input.path //
    .tool_input.target_file //
    .tool_input.file_path //
    .tool_input.filePath //
    ""
  '
}

write_path_from_payload() {
  local payload="$1"
  echo "$payload" | jq -r '
    .tool_input.file_path //
    .tool_input.path //
    .tool_input.target_file //
    .tool_input.filePath //
    .tool_input.notebook_path //
    ""
  '
}

# The Skill tool reports the skill name rather than a path. The exact field is
# undocumented, so take the first usable string among the plausible names.
skill_name_from_payload() {
  local payload="$1"
  echo "$payload" | jq -r '
    [ .tool_input.skill,
      .tool_input.skill_name,
      .tool_input.skillName,
      .tool_input.name,
      .tool_input.command,
      .tool_input.path ]
    | map(select(type == "string" and length > 0))
    | .[0] // ""
  '
}

is_write_tool() {
  local tool_name="$1"
  [[ "$tool_name" =~ ^(Write|Edit|MultiEdit|NotebookEdit)$ ]]
}

# --- path handling -----------------------------------------------------------

# Lexical only — the target of a write does not exist yet, so realpath is unusable.
normalize_path() {
  local p="$1" out="" seg rest
  while [[ "$p" == *//* ]]; do p="${p//\/\//\/}"; done
  rest="${p#/}"
  while [[ -n "$rest" ]]; do
    seg="${rest%%/*}"
    if [[ "$rest" == */* ]]; then rest="${rest#*/}"; else rest=""; fi
    case "$seg" in
      ''|'.') ;;
      '..') out="${out%/*}" ;;
      *) out="$out/$seg" ;;
    esac
  done
  printf '%s' "${out:-/}"
}

# macOS aliases /tmp and /var onto /private, so compare on one spelling.
strip_private() {
  local p="$1"
  case "$p" in
    /private/tmp|/private/var|/private/tmp/*|/private/var/*) printf '%s' "${p#/private}" ;;
    *) printf '%s' "$p" ;;
  esac
}

resolve_against_cwd() {
  local p="$1" cwd="$2"
  [[ -n "$p" ]] || return 1
  if [[ "$p" != /* ]]; then
    [[ -n "$cwd" && "$cwd" == /* ]] || return 1
    p="${cwd%/}/$p"
  fi
  normalize_path "$p"
}

# The only .claude/.cursor paths that are project content. Transcribed from
# dual-platform-agents/SKILL.md — everything else under those trees is agent
# state (plans, projects, todos, session scratch) and must never be gated.
is_claude_wiring_path() {
  local p="$1"
  [[ "$p" =~ (^|/)\.claude/(skills|agents|commands|hooks|rules)(/|$) ]] && return 0
  [[ "$p" =~ (^|/)\.cursor/rules(/|$) ]] && return 0
  return 1
}

# Agent-owned state, wherever it lives. Checked before any containment test so it
# still holds when cwd is itself a temp dir, or a plan file sits inside the repo.
is_harness_state() {
  local abs home tmp
  abs="$(strip_private "$1")"
  home="${HOME:-}"
  if [[ -n "$home" ]]; then
    [[ "$abs" == "$home"/.claude/* || "$abs" == "$home"/.cursor/* ]] && return 0
  fi
  [[ "$abs" == /tmp/* || "$abs" == /var/folders/* ]] && return 0
  if [[ -n "${TMPDIR:-}" ]]; then
    tmp="$(strip_private "${TMPDIR%/}")"
    [[ -n "$tmp" && "$abs" == "$tmp"/* ]] && return 0
  fi
  if [[ "$abs" =~ (^|/)\.(claude|cursor)/ ]]; then
    is_claude_wiring_path "$abs" || return 0
  fi
  return 1
}

# 0 inside, 1 outside, 2 undeterminable. Callers must keep gating on 2 — treating
# a missing cwd as "outside" would let a client disable every gate.
path_in_project() {
  local abs="$1" cwd="$2" a b
  [[ -n "$cwd" && "$cwd" == /* ]] || return 2
  a="$(strip_private "$abs")"
  b="$(strip_private "$(normalize_path "${cwd%/}")")"
  [[ "$a" == "$b" || "$a" == "$b"/* ]]
}

project_relative() {
  local abs="$1" cwd="$2" a b
  a="$(strip_private "$abs")"
  if [[ -n "$cwd" && "$cwd" == /* ]]; then
    b="$(strip_private "$(normalize_path "${cwd%/}")")"
    if [[ "$a" == "$b"/* ]]; then
      printf '%s' "${a#"$b"/}"
      return 0
    fi
  fi
  printf '%s' "$a"
}

# --- plugin identity ---------------------------------------------------------

plugin_root() {
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -d "${CLAUDE_PLUGIN_ROOT}/skills" ]]; then
    printf '%s' "${CLAUDE_PLUGIN_ROOT%/}"
  else
    ( cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd )
  fi
}

_plugin_slug_cache=""
plugin_slug() {
  local root name=""
  if [[ -z "$_plugin_slug_cache" ]]; then
    root="$(plugin_root)"
    if [[ -f "$root/.claude-plugin/plugin.json" ]]; then
      name="$(jq -r '.name // ""' "$root/.claude-plugin/plugin.json" 2>/dev/null || true)"
    fi
    [[ -n "$name" ]] || name="$(basename "$root")"
    _plugin_slug_cache="$name"
  fi
  printf '%s' "$_plugin_slug_cache"
}

skill_md_path() {
  printf '%s/skills/%s/SKILL.md' "$(plugin_root)" "$1"
}

# --- skill-read markers ------------------------------------------------------

state_dir() {
  printf '%s/cursor-%s-hook' "${TMPDIR:-/tmp}" "$(plugin_slug)"
}

# Falls back to a cwd-derived key so a payload without a session id can still
# satisfy a gate. Failing closed there made every write permanently blocked.
session_key() {
  local session_id="$1" cwd="${2:-}"
  [[ -n "$session_id" ]] || session_id="cwd:${cwd:-unknown}"
  printf '%s' "$session_id" | cksum | cut -d ' ' -f 1
}

ack_file_for_session() {
  printf '%s/skill-read-%s-%s' "$(state_dir)" "$1" "$(session_key "$2" "${3:-}")"
}

mark_skill_read() {
  local ack_file
  ack_file="$(ack_file_for_session "$1" "$2" "${3:-}")"
  mkdir -p "$(dirname "$ack_file")"
  touch "$ack_file"
}

# A cwd-derived key cannot tell two conversations in the same project apart, so
# an identity-less ack gets a short window: long enough to unblock the session
# that created it, short enough not to leak into a concurrent one.
ack_ttl_minutes() {
  if [[ -n "$1" ]]; then
    printf '720'
  else
    printf '15'
  fi
}

# Expires so a crashed session without SessionEnd cannot leave a marker behind
# indefinitely.
skill_read_for_session() {
  local ack_file ttl
  ack_file="$(ack_file_for_session "$1" "$2" "${3:-}")"
  [[ -f "$ack_file" ]] || return 1
  ttl="$(ack_ttl_minutes "$2")"
  [[ -n "$(find "$ack_file" -mmin -"$ttl" 2>/dev/null)" ]]
}

clear_skills_read() {
  local session_id="$1" cwd="${2:-}" skill
  for skill in "${GATED_SKILLS[@]}"; do
    rm -f "$(ack_file_for_session "$skill" "$session_id" "$cwd")"
  done
}

# Quoting $skill forces a literal match; the anchors reject near-misses.

# A Read only counts when it is the skill's own SKILL.md. Accepting a bare
# trailing name here would let an unrelated file (/notes/coding-conventions)
# satisfy the gate.
skill_read_path_matches() {
  local path="$1" skill="$2"
  [[ "$path" =~ (^|/)"$skill"/SKILL\.md$ ]]
}

# The Skill tool reports a name, not a path: bare, plugin:skill, or slash form.
skill_name_matches() {
  local candidate="$1" skill="$2"
  [[ "$candidate" =~ (^|[/:])"$skill"$ ]] && return 0
  skill_read_path_matches "$candidate" "$skill"
}

# kind is "read" or "skill" — the two sources match on different shapes.
mark_if_skill() {
  local kind="$1" candidate="$2" session_id="$3" cwd="$4" skill="$5"
  case "$kind" in
    read) skill_read_path_matches "$candidate" "$skill" || return 0 ;;
    skill) skill_name_matches "$candidate" "$skill" || return 0 ;;
    *) return 0 ;;
  esac
  mark_skill_read "$skill" "$session_id" "$cwd"
}

# --- blocking ----------------------------------------------------------------

# Reports every unsatisfied gate at once, with a path the agent can act on
# directly. Does not inline the skill body: a denial sets no marker, so the next
# attempt would re-emit it.
deny_skill_gates() {
  local context="$1"; shift
  local slug skill md
  slug="$(plugin_slug)"
  {
    printf 'Blocked: %s\n\n' "$context"
    printf 'Not loaded in this conversation yet: %s\n\n' "$*"
    printf 'Load each one, then retry:\n'
    for skill in "$@"; do
      printf '  Skill tool: %s:%s\n' "$slug" "$skill"
      md="$(skill_md_path "$skill")"
      if [[ -f "$md" ]]; then
        printf '    or Read: %s\n' "$md"
      else
        printf '    or Read: skills/%s/SKILL.md in the %s plugin\n' "$skill" "$slug"
      fi
    done
    printf '\nFollow the skill exactly — do not improvise. Loading it once satisfies this gate for the rest of the session.\n'
  } >&2
  exit 2
}

# shellcheck source=gates.sh
source "$(dirname "${BASH_SOURCE[0]}")/gates.sh"
