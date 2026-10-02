#!/usr/bin/env bash
# start-draft-server.sh — Deterministic start of the draft server. No model
# involved.
#
# eds-serve's own server never mounts drafts/ (only --html-folder does that,
# and the project's configured serve command does not pass it). The draft
# server runs on the next port after the configured preview's, mounted at
# /drafts, and serves every item's draft. It is long-lived: no stage that
# renders a draft stops it. Only clean-drafts.sh, run by eds-serve, stops it,
# by the pid file this script writes.
#
# Checks the checked-out branch's length first (D539, check-branch-length.sh):
# too long → `start-failed: branch name too long (<n> > 23)`, before any poll.
#
# Polls before starting: the server an earlier stage or run started is
# normally still answering, and is reused. The pid file is written only when
# this call launched the process itself.
#
# Usage:
#   start-draft-server.sh <preview-url> <log-path> <pid-path>
#
# Output on success: one line,
#   ready: origin=<url> port=<n> started=yes|no pid=<pid|none> log=<path|none>
#
# Exit codes:
#   0 — something is answering at the draft origin, started by this run or already there
#   1 — the branch name is too long, the command could not be started, or the
#       poll ladder was exhausted; reason on stderr
#   2 — usage error (a missing or empty argument)

set -uo pipefail

PREVIEW_URL="${1:-}"
LOG_PATH="${2:-}"
PID_PATH="${3:-}"

if [[ -z "$PREVIEW_URL" || -z "$LOG_PATH" || -z "$PID_PATH" ]]; then
  echo "usage: start-draft-server.sh <preview-url> <log-path> <pid-path>" >&2
  exit 2
fi

# D539: the dev server refuses a branch over 23 characters, and that refusal
# only reaches its log. Check first, so a too-long branch never polls or
# starts and the caller sees the real cause. No branch (detached HEAD, or not
# a repository) leaves nothing to measure.
BRANCH=$(git branch --show-current 2>/dev/null)
if [[ -n "$BRANCH" ]]; then
  if ! CHECK=$(bash "$(dirname "${BASH_SOURCE[0]}")/check-branch-length.sh" "$BRANCH"); then
    LENGTH=$(printf '%s' "$CHECK" | sed -n 's/.* length=\([0-9]*\) limit=\([0-9]*\)$/\1 > \2/p')
    echo "start-failed: branch name too long ($LENGTH); rename the branch, then start again" >&2
    exit 1
  fi
fi

PORT=$(printf '%s' "$PREVIEW_URL" | sed -n 's#^[a-zA-Z]*://[^:/]*:\([0-9][0-9]*\).*#\1#p')
if [[ -z "$PORT" ]]; then
  PORT=3000
fi
DRAFT_PORT=$((PORT + 1))
ORIGIN="http://localhost:${DRAFT_PORT}"

# A sandboxed caller reaches a local address only through its proxy, and the
# sandbox lists local addresses as never proxied; so with a proxy in the
# environment every address goes through it. With none, nothing changes.
PROXY_ARGS=()
if [[ -n "${HTTP_PROXY:-${http_proxy:-}}" ]]; then
  PROXY_ARGS=(--noproxy '')
fi

poll() {
  local url="$1"
  local n=0
  local status
  for DELAY in 0 2 4 8 16; do
    if [[ "$DELAY" -gt 0 ]]; then
      sleep "$DELAY"
    fi
    n=$(( n + 1 ))
    status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 ${PROXY_ARGS[@]+"${PROXY_ARGS[@]}"} "$url" 2>/dev/null)
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
