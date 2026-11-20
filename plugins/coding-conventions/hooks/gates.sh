#!/usr/bin/env bash
# Per-plugin gate definitions. Sourced by lib.sh.

GATED_SKILLS=(
  coding-conventions
  typescript-conventions
)

is_typescript_path() {
  [[ "$1" =~ \.(ts|tsx|mts|cts)$ ]]
}
