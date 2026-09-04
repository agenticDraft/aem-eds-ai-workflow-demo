#!/usr/bin/env bash
# finalize-run-state.sh — Deletes run-state.json on a successful terminal
# state (see shared/run-state.md). No model involved, and idempotent: a
# caller finalizing a run that never wrote state, or finalizing twice, is
# not an error.
#
# Usage:
#   finalize-run-state.sh <state-file>
#
# Exit codes:
#   0 — "status: deleted" or "status: not-found"
#   2 — usage error (missing argument)

set -uo pipefail

STATE_FILE="${1:-}"

if [[ -z "$STATE_FILE" ]]; then
  echo "usage: finalize-run-state.sh <state-file>" >&2
  exit 2
fi

if [[ -f "$STATE_FILE" ]]; then
  rm -f "$STATE_FILE"
  echo "status: deleted"
else
  echo "status: not-found"
fi
exit 0
