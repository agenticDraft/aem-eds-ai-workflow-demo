#!/usr/bin/env bash
# start-serve.sh — Starts the project's configured serve command as a
# detached background process and reports the process id that stops it
# again. No model involved.
#
# Detached is the point. This stage runs in its own isolated subagent, but
# every later stage that needs a rendered page runs in a different one, so a
# server tied to the lifetime of the process that started it would be gone
# before the first consumer asked for a page. The command is started with
# its own output redirected to a log file and its parentage released, so it
# outlives the caller.
#
# **Nothing ever stops it.** The stage vocabulary has no teardown stage, so
# the process this script starts survives the whole run and every run after
# it, until a human ends it. That is exactly why the process id is reported
# and recorded rather than discarded: it is the only handle anyone gets.
#
# The command is run as written, the same way every other consumer of the
# project's configured commands runs them. It is a project-owned value, and
# a command string that has been rewritten is no longer the command the
# project declared.
#
# A command that exits immediately — a serve command that is not installed,
# or a port already taken by something that is not answering — is caught
# here rather than thirty seconds later at the end of a readiness poll, so
# the failure names itself instead of arriving as a silent absence.
#
# Usage:
#   start-serve.sh <serve-command> <log-path> <pid-path>
#
# Output on success: one line,
#   started: pid=<pid> log=<log-path>
#
# Exit codes:
#   0 — the command was started and was still running a moment later
#   1 — the command could not be started, or exited immediately; the reason
#       and the first lines of its log are on stderr
#   2 — usage error (a missing or empty argument)

set -uo pipefail

COMMAND="${1:-}"
LOG_PATH="${2:-}"
PID_PATH="${3:-}"

if [[ -z "$COMMAND" || -z "$LOG_PATH" || -z "$PID_PATH" ]]; then
  echo "usage: start-serve.sh <serve-command> <log-path> <pid-path>" >&2
  exit 2
fi

mkdir -p "$(dirname "$LOG_PATH")" "$(dirname "$PID_PATH")" 2>/dev/null

if ! : >"$LOG_PATH" 2>/dev/null; then
  echo "start-failed: cannot write the log at $LOG_PATH" >&2
  exit 1
fi

nohup sh -c "$COMMAND" >"$LOG_PATH" 2>&1 &
PID=$!

# A command that is going to fail on startup does so well inside a second.
sleep 1

if ! kill -0 "$PID" 2>/dev/null; then
  echo "start-failed: the serve command exited immediately; its first lines were:" >&2
  head -20 "$LOG_PATH" >&2 2>/dev/null
  exit 1
fi

echo "$PID" >"$PID_PATH"
echo "started: pid=$PID log=$LOG_PATH"
exit 0
