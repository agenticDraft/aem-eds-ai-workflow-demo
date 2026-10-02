#!/usr/bin/env bash
# check-terminal-state.sh — the verdict of an unattended whole-route run (G121).
#
# A route ends only through resolve-terminal-state.sh (terminal-states.md),
# and the runner records that output in a file. This script turns the file
# into the run's verdict. The session's last message is never consulted: a
# session can stop after any stage and still end with text that looks like a
# result.
#
# Usage:
#   check-terminal-state.sh <terminal-state-file>
#
# Output (stdout): the recorded terminal state, then "verdict: pass|fail".
#
# Exit codes:
#   0 — terminal: delivered
#   1 — terminal: blocked or failed; no file (the route ended without a
#       terminal state); or a file that does not open with a terminal state
#   2 — usage error

set -uo pipefail

FILE="${1:-}"
if [[ -z "$FILE" ]]; then
  echo "usage: check-terminal-state.sh <terminal-state-file>" >&2
  exit 2
fi

if [[ ! -f "$FILE" ]]; then
  echo "verdict: fail"
  echo "route ended without a terminal state: the driver never ran resolve-terminal-state.sh, so the run stopped before any of delivered, blocked or failed"
  exit 1
fi

FIRST="$(head -n 1 "$FILE")"
case "$FIRST" in
  "terminal: delivered")
    cat "$FILE"
    echo "verdict: pass"
    exit 0
    ;;
  "terminal: blocked"|"terminal: failed")
    cat "$FILE"
    echo "verdict: fail"
    exit 1
    ;;
  *)
    echo "verdict: fail"
    echo "invalid: $FILE does not open with a terminal state (got: ${FIRST:-empty})"
    exit 1
    ;;
esac
