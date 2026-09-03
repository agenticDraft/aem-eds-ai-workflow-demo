#!/usr/bin/env bash
# write-run-state.sh — Mechanical (re)write of run-state.json (see
# shared/run-state.md). No judgment involved: the caller already knows the
# route, the stage that just finished, and the counters — this script only
# places them in the fixed shape and rewrites the file in full, which is
# also what refreshes its mtime for the 2-hour staleness rule. There is no
# separate "touch" step, and no code path that updates only some fields.
#
# Usage:
#   write-run-state.sh <state-file> <route-id> <rule> <last-stage> <total> <mode> <questions-used> <start-time>
#
# Exit codes:
#   0 — success; "written: <path>" on stdout
#   1 — contract violation: total or questions_used is not a non-negative
#       integer, mode is not interactive|autonomous, or a string field
#       contains a double quote (would corrupt the quoted-string shape)
#   2 — usage error: wrong argument count

set -uo pipefail

if [[ $# -ne 8 ]]; then
  echo "usage: write-run-state.sh <state-file> <route-id> <rule> <last-stage> <total> <mode> <questions-used> <start-time>" >&2
  exit 2
fi

STATE_FILE="$1"
ROUTE_ID="$2"
RULE="$3"
LAST_STAGE="$4"
TOTAL="$5"
MODE="$6"
QUESTIONS_USED="$7"
START_TIME="$8"

fail() {
  echo "invalid: $1" >&2
  exit 1
}

for pair in "route_id:$ROUTE_ID" "rule:$RULE" "last_stage:$LAST_STAGE" "start_time:$START_TIME"; do
  key="${pair%%:*}"
  value="${pair#*:}"
  [[ "$value" == *'"'* ]] && fail "$key value contains a double quote, which would corrupt the quoted-string shape"
done

[[ "$TOTAL" =~ ^[0-9]+$ ]] || fail "total '$TOTAL' is not a non-negative integer"
[[ "$QUESTIONS_USED" =~ ^[0-9]+$ ]] || fail "questions_used '$QUESTIONS_USED' is not a non-negative integer"
case "$MODE" in
  interactive|autonomous) ;;
  *) fail "mode '$MODE' must be one of interactive, autonomous" ;;
esac

mkdir -p "$(dirname "$STATE_FILE")"

cat > "$STATE_FILE" <<EOF
{
  "route_id": "$ROUTE_ID",
  "rule": "$RULE",
  "last_stage": "$LAST_STAGE",
  "total": $TOTAL,
  "mode": "$MODE",
  "questions_used": $QUESTIONS_USED,
  "start_time": "$START_TIME"
}
EOF

echo "written: $STATE_FILE"
exit 0
