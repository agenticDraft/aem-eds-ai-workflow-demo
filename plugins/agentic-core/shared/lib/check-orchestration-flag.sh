#!/usr/bin/env bash
# check-orchestration-flag.sh — Deterministic presence/staleness check for
# the orchestration marker (see shared/orchestration-flag.md). No model
# involved, and no fields to read: the marker's own mtime is the entire
# signal, the same 2-hour window shared/run-state.md defines for
# run-state.json. This script does not decide what a caller does with the
# result — deciding to resume, to suppress a human-facing summary, or
# anything else is the caller's job.
#
# Usage:
#   check-orchestration-flag.sh <flag-path>
#
# Exit codes:
#   0 — "status: none" (no file), "status: fresh" (mtime under 2 hours), or
#       "status: stale-deleted" after removing the file (mtime 2 hours or
#       older)
#   2 — usage error (missing argument)

set -uo pipefail

FLAG="${1:-}"

if [[ -z "$FLAG" ]]; then
  echo "usage: check-orchestration-flag.sh <flag-path>" >&2
  exit 2
fi

if [[ ! -f "$FLAG" ]]; then
  echo "status: none"
  exit 0
fi

STALE_AFTER_SECONDS=7200

MTIME="$(date -r "$FLAG" +%s 2>/dev/null)"
if [[ -z "$MTIME" ]]; then
  echo "status: none"
  exit 0
fi

AGE=$(( $(date +%s) - MTIME ))

if (( AGE >= STALE_AFTER_SECONDS )); then
  rm -f "$FLAG"
  echo "status: stale-deleted"
  exit 0
fi

echo "status: fresh"
exit 0
