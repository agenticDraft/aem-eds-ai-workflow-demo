#!/usr/bin/env bash
# check-run-state.sh — Deterministic resume/staleness check for run-state.json
# (see shared/run-state.md). No model involved: reads the file's own mtime,
# not any field inside it, to decide whether a previous run is resumable.
# Asking the human "resume or start fresh?" is not this script's job — that
# belongs to whichever skill drives a full route; this script only reports
# the age and, when resumable, the fields needed to phrase that question.
#
# Usage:
#   check-run-state.sh <state-file>
#
# Exit codes:
#   0 — "status: none" (no file), "status: resume" followed by the seven
#       fields (mtime under 2 hours), or "status: stale-deleted" after
#       removing the file (mtime 2 hours or older)
#   1 — contract violation: file exists but is not a state file this script
#       recognizes; "invalid: <reason>" on stderr
#   2 — usage error (missing argument)

set -uo pipefail

STATE_FILE="${1:-}"

if [[ -z "$STATE_FILE" ]]; then
  echo "usage: check-run-state.sh <state-file>" >&2
  exit 2
fi

if [[ ! -f "$STATE_FILE" ]]; then
  echo "status: none"
  exit 0
fi

STALE_AFTER_SECONDS=7200

MTIME="$(stat -f %m "$STATE_FILE" 2>/dev/null || stat -c %Y "$STATE_FILE" 2>/dev/null)"
if [[ -z "$MTIME" ]]; then
  echo "invalid: could not read mtime of $STATE_FILE" >&2
  exit 1
fi

AGE=$(( $(date +%s) - MTIME ))

if (( AGE >= STALE_AFTER_SECONDS )); then
  rm -f "$STATE_FILE"
  echo "status: stale-deleted"
  exit 0
fi

field() {
  local key="$1" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*\"${key}\":\ (.*)$ ]]; then
      local value="${BASH_REMATCH[1]}"
      value="${value%,}"
      value="${value#\"}"
      value="${value%\"}"
      echo "$value"
      return 0
    fi
  done < "$STATE_FILE"
  return 1
}

ROUTE_ID="$(field route_id)" || true
RULE="$(field rule)" || true
LAST_STAGE="$(field last_stage)" || true
TOTAL="$(field total)" || true
MODE="$(field mode)" || true
QUESTIONS_USED="$(field questions_used)" || true
START_TIME="$(field start_time)" || true

for pair in "route_id:$ROUTE_ID" "last_stage:$LAST_STAGE" "total:$TOTAL"; do
  key="${pair%%:*}"
  value="${pair#*:}"
  [[ -z "$value" ]] && { echo "invalid: malformed state file — missing '$key' in $STATE_FILE" >&2; exit 1; }
done

echo "status: resume"
echo "route_id: $ROUTE_ID"
echo "rule: $RULE"
echo "last_stage: $LAST_STAGE"
echo "total: $TOTAL"
echo "mode: $MODE"
echo "questions_used: $QUESTIONS_USED"
echo "start_time: $START_TIME"
exit 0
