#!/usr/bin/env bash
# resolve-terminal-state.sh — Deterministic formatter for the three terminal
# states (see shared/terminal-states.md, core contract §10). No model
# involved, and no side effects: like run-stage.sh and handle-question.sh,
# this script only decides and prints what the spec requires — it never
# deletes run-state.json (finalize-run-state.sh's job) and never touches the
# orchestration marker (the route driver's job). The caller has already
# reduced a run to one of the three states or rejected everything else;
# this script's own rejection of a fourth label is what keeps that
# invariant enforceable rather than just documented.
#
# Usage:
#   resolve-terminal-state.sh delivered <progress-file> <published-location>
#   resolve-terminal-state.sh blocked   <missing> <recorded-at>
#   resolve-terminal-state.sh failed    <stage-id> <summary>
#
# Exit codes:
#   0 — prints the terminal state's required output on stdout
#   2 — usage error: no state given, an unrecognized state (including
#       "warn" — a run never ends on warn), wrong argument count for the
#       given state, or (delivered) a progress file that does not exist

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRINT_STATUS_TABLE="$SCRIPT_DIR/print-status-table.sh"

usage() {
  cat >&2 <<'EOF'
usage: resolve-terminal-state.sh delivered <progress-file> <published-location>
       resolve-terminal-state.sh blocked   <missing> <recorded-at>
       resolve-terminal-state.sh failed    <stage-id> <summary>
EOF
  exit 2
}

STATE="${1:-}"
[[ -z "$STATE" ]] && usage

case "$STATE" in
  delivered)
    [[ $# -eq 3 ]] || usage
    PROGRESS_FILE="$2"
    PUBLISHED="$3"
    if [[ ! -f "$PROGRESS_FILE" ]]; then
      echo "invalid: file not found: $PROGRESS_FILE" >&2
      exit 2
    fi
    echo "terminal: delivered"
    "$PRINT_STATUS_TABLE" "$PROGRESS_FILE" || exit 2
    echo "published: $PUBLISHED"
    ;;
  blocked)
    [[ $# -eq 3 ]] || usage
    MISSING="$2"
    RECORDED="$3"
    echo "terminal: blocked"
    echo "missing: $MISSING"
    echo "recorded: $RECORDED"
    ;;
  failed)
    [[ $# -eq 3 ]] || usage
    STAGE_ID="$2"
    SUMMARY="$3"
    echo "terminal: failed"
    echo "stage: $STAGE_ID"
    echo "summary: $SUMMARY"
    ;;
  warn)
    echo "invalid: 'warn' is never a terminal state — a stage returning warn continues the run (core contract §10)" >&2
    exit 2
    ;;
  *)
    echo "invalid: '$STATE' is not a terminal state — must be one of delivered, blocked, failed" >&2
    exit 2
    ;;
esac

exit 0
