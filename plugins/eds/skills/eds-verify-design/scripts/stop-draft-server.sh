#!/usr/bin/env bash
# stop-draft-server.sh — Stops this stage's own draft server, if this run
# started one. No model involved.
#
# Safe to call unconditionally on every exit path: start-draft-server.sh
# writes the pid file only when it actually launched a process itself, never
# when it found one already answering, so calling this when nothing was
# started here is a no-op rather than something the caller must check for
# first.
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
