#!/usr/bin/env bash
# write-orchestration-flag.sh — Creates or refreshes the orchestration marker
# (see shared/orchestration-flag.md). No model involved, no fields to
# validate: the marker's only content is its own presence and mtime, so this
# script either creates an empty file or touches an existing one. The same
# call serves both the initial write (before the first stage of a run) and
# every per-stage mtime refresh — there is no separate "touch" step.
#
# Usage:
#   write-orchestration-flag.sh <flag-path>
#
# Exit codes:
#   0 — "written: <path>" (file created) or "refreshed: <path>" (already existed)
#   2 — usage error (missing argument)

set -uo pipefail

FLAG="${1:-}"

if [[ -z "$FLAG" ]]; then
  echo "usage: write-orchestration-flag.sh <flag-path>" >&2
  exit 2
fi

if [[ -f "$FLAG" ]]; then
  touch "$FLAG"
  echo "refreshed: $FLAG"
  exit 0
fi

mkdir -p "$(dirname "$FLAG")"
: > "$FLAG"
echo "written: $FLAG"
exit 0
