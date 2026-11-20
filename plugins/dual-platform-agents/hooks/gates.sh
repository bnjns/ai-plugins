#!/usr/bin/env bash
# Per-plugin gate definitions. Sourced by lib.sh.

GATED_SKILLS=(
  dual-platform-agents
)

# Matched against the repo-relative path, so a monorepo packages/api/AGENTS.md
# still gates while $HOME/.claude/... never reaches here.
is_agent_file_path() {
  local rel="$1"
  [[ "$rel" =~ (^|/)AGENTS\.md$ ]] && return 0
  [[ "$rel" =~ (^|/)CLAUDE\.md$ ]] && return 0
  [[ "$rel" =~ (^|/)\.agents/ ]] && return 0
  is_claude_wiring_path "$rel"
}
