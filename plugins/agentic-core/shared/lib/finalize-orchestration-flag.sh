#!/usr/bin/env bash
# finalize-orchestration-flag.sh — Removes the orchestration marker
# unconditionally (see shared/orchestration-flag.md). No model involved, and
# idempotent: called at every terminal state alike — delivered, blocked and
# failed — unlike shared/lib/finalize-run-state.sh, which only ever runs on
# delivered. A caller finalizing a run whose marker is already gone, or
# finalizing twice, is not an error.
#
# Usage:
#   finalize-orchestration-flag.sh <flag-path>
#
# Exit codes:
#   0 — "status: deleted" or "status: not-found"
#   2 — usage error (missing argument)

set -uo pipefail

FLAG="${1:-}"

if [[ -z "$FLAG" ]]; then
  echo "usage: finalize-orchestration-flag.sh <flag-path>" >&2
  exit 2
fi

if [[ -f "$FLAG" ]]; then
  rm -f "$FLAG"
  echo "status: deleted"
else
  echo "status: not-found"
fi
exit 0
