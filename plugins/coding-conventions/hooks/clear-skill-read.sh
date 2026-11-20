#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$script_dir/lib.sh"

payload=$(cat)
clear_skills_read "$(session_id_from_payload "$payload")" "$(cwd_from_payload "$payload")"
exit 0
