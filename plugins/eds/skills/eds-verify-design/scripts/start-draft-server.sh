#!/usr/bin/env bash
# start-draft-server.sh — Deterministic, self-owned lifecycle for this
# stage's own draft-rendering server. No model involved.
#
# eds-serve's own server never mounts drafts/ (only --html-folder does that,
# and the project's configured serve command does not pass it), so nothing
# eds-serve started can ever render drafts/<item_id>.plain.html. This stage
# does not share that server: it starts its own, on the next port after the
# configured preview's, mounted at /drafts. stop-draft-server.sh (this same
# skill's own scripts/) stops it again before this stage returns.
#
# Polls before starting, for the same reason eds-serve's own start-serve.sh
# does: a previous run of this same stage that crashed before its own
# teardown ran can leave one still answering.
#
# Usage:
#   start-draft-server.sh <preview-url> <log-path> <pid-path>
#
# Output on success: one line,
#   ready: origin=<url> port=<n> started=yes|no pid=<pid|none> log=<path|none>
#
# Exit codes:
#   0 — something is answering at the draft origin, started by this run or already there
#   1 — the command could not be started, or the poll ladder was exhausted; reason on stderr
#   2 — usage error (a missing or empty argument)

set -uo pipefail

PREVIEW_URL="${1:-}"
LOG_PATH="${2:-}"
PID_PATH="${3:-}"

if [[ -z "$PREVIEW_URL" || -z "$LOG_PATH" || -z "$PID_PATH" ]]; then
  echo "usage: start-draft-server.sh <preview-url> <log-path> <pid-path>" >&2
  exit 2
fi

PORT=$(printf '%s' "$PREVIEW_URL" | sed -n 's#^[a-zA-Z]*://[^:/]*:\([0-9][0-9]*\).*#\1#p')
if [[ -z "$PORT" ]]; then
  PORT=3000
fi
DRAFT_PORT=$((PORT + 1))
ORIGIN="http://localhost:${DRAFT_PORT}"

poll() {
  local url="$1"
  local n=0
  local status
  for DELAY in 0 2 4 8 16; do
    if [[ "$DELAY" -gt 0 ]]; then
      sleep "$DELAY"
    fi
    n=$(( n + 1 ))
    status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$url" 2>/dev/null)
    if [[ -n "$status" && "$status" != "000" ]]; then
      return 0
    fi
  done
  return 1
}

if poll "$ORIGIN"; then
  echo "ready: origin=$ORIGIN port=$DRAFT_PORT started=no pid=none log=none"
  exit 0
fi

mkdir -p "$(dirname "$LOG_PATH")" "$(dirname "$PID_PATH")" 2>/dev/null

if ! : >"$LOG_PATH" 2>/dev/null; then
  echo "start-failed: cannot write the log at $LOG_PATH" >&2
  exit 1
fi

nohup sh -c "npx --no-install aem up --no-open --forward-browser-logs --html-folder drafts --port ${DRAFT_PORT}" >"$LOG_PATH" 2>&1 &
PID=$!

# A command that is going to fail on startup does so well inside a second.
sleep 1

if ! kill -0 "$PID" 2>/dev/null; then
  echo "start-failed: the draft server exited immediately; its first lines were:" >&2
  head -20 "$LOG_PATH" >&2 2>/dev/null
  exit 1
fi

echo "$PID" >"$PID_PATH"

if poll "$ORIGIN"; then
  echo "ready: origin=$ORIGIN port=$DRAFT_PORT started=yes pid=$PID log=$LOG_PATH"
  exit 0
fi

echo "no-answer: nothing answered at $ORIGIN before the poll ladder was exhausted; pid=$PID log=$LOG_PATH" >&2
exit 1
