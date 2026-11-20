#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Hermetic marker state — otherwise leftover acks from a previous run can make a
# later run pass spuriously.
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/hook-tests.XXXXXX")"
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT

run_pr() {
  ./guard-gh-pr.sh <<<"$1"
}

run_record() {
  ./record-skill-read.sh <<<"$1"
}

run_clear() {
  ./clear-skill-read.sh <<<"$1"
}

session='test-session'
pr_cmd='{"conversation_id":"'"$session"'","tool_input":{"command":"gh pr create --draft"}}'
read_pr='{"conversation_id":"'"$session"'","tool_name":"Read","tool_input":{"path":"/cache/create-pull-request/skills/create-pull-request/SKILL.md"}}'

echo 'block gh pr create without skill read'
if run_pr "$pr_cmd"; then
  echo 'expected block'
  exit 1
fi

echo 'record create-pull-request read'
run_record "$read_pr"

echo 'allow gh pr create after skill read'
run_pr "$pr_cmd"

echo 'allow read-only gh pr without create-pull-request skill'
run_pr '{"conversation_id":"other-session","tool_input":{"command":"gh pr view 123"}}'

echo 'clear on session end'
run_clear '{"conversation_id":"'"$session"'"}'

echo 'block gh pr again after session end'
if run_pr "$pr_cmd"; then
  echo 'expected block'
  exit 1
fi

echo 'ok'
