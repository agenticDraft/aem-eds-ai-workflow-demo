#!/usr/bin/env bash
# stop-draft-server.sh — Stops the draft server by its pid file. No model
# involved. Called only by clean-drafts.sh, once no recorded change is still
# open.
#
# A missing pid file is a no-op: start-draft-server.sh writes it only when it
# launched the process itself, never when it found one already answering.
#
# Usage:
#   stop-draft-server.sh <pid-path>
#
# Output: one line, `stopped: pid=<pid>` or `nothing-to-stop`.
# Exit codes: 0 always — there is nothing a caller need react to here.
#             2 — usage error (missing argument).

set -uo pipefail

PID_PATH="${1:-}"

if [[ -z "$PID_PATH" ]]; then
  echo "usage: stop-draft-server.sh <pid-path>" >&2
  exit 2
fi

if [[ ! -f "$PID_PATH" ]]; then
  echo "nothing-to-stop"
  exit 0
fi

PID=$(cat "$PID_PATH" 2>/dev/null)
rm -f "$PID_PATH"

if [[ -z "$PID" ]] || ! kill -0 "$PID" 2>/dev/null; then
  echo "nothing-to-stop"
  exit 0
fi

kill "$PID" 2>/dev/null
sleep 1
if kill -0 "$PID" 2>/dev/null; then
  kill -9 "$PID" 2>/dev/null
fi

echo "stopped: pid=$PID"
exit 0
