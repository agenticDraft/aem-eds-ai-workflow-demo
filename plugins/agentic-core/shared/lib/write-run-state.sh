#!/usr/bin/env bash
# write-run-state.sh — Mechanical (re)write of run-state.json (see
# shared/run-state.md). No judgment involved: the caller already knows the
# stage that just finished and the counters — this script only places them in
# the fixed shape and rewrites the file in full, which is also what refreshes
# its mtime for the 2-hour staleness rule. There is no separate "touch" step,
# and no code path that updates only some fields.
#
# The skipped stages are read from the stage-conditions file rather than
# passed inline, so the record of which stages were skipped, and why, is
# always the evaluator's own output rather than a caller's restatement of it.
#
# Usage:
#   write-run-state.sh <state-file> <route-id> <rule> <last-stage> <total> <mode> <questions-used> <start-time> <conditions-file>
#
# <conditions-file> is evaluate-stage-conditions.sh's output. Its "skipped:"
# lines become the state file's "skipped" array; a file with none yields an
# empty array, which is written rather than omitted.
#
# Exit codes:
#   0 — success; "written: <path>" on stdout
#   1 — contract violation: total or questions_used is not a non-negative
#       integer, mode is not interactive|autonomous, or a string field
#       contains a double quote (would corrupt the quoted-string shape)
#   2 — usage error: wrong argument count, or conditions file not found

set -uo pipefail

if [[ $# -ne 9 ]]; then
  echo "usage: write-run-state.sh <state-file> <route-id> <rule> <last-stage> <total> <mode> <questions-used> <start-time> <conditions-file>" >&2
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
CONDITIONS_FILE="$9"

fail() {
  echo "invalid: $1" >&2
  exit 1
}

if [[ ! -f "$CONDITIONS_FILE" ]]; then
  echo "invalid: conditions file not found: $CONDITIONS_FILE" >&2
  exit 2
fi

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

# Each skipped line is "skipped: <stage id> — <condition>". The separator is
# the same one the evaluator prints, so nothing reformats it on the way in.
SKIPPED_JSON=""
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^skipped:\ ([^[:space:]]+)\ —\ (.+)$ ]] || continue
  stage="${BASH_REMATCH[1]}"
  condition="${BASH_REMATCH[2]}"
  [[ "$stage$condition" == *'"'* ]] \
    && fail "a skipped stage's record contains a double quote, which would corrupt the quoted-string shape"
  [[ -n "$SKIPPED_JSON" ]] && SKIPPED_JSON+=","
  SKIPPED_JSON+="
    { \"stage\": \"$stage\", \"condition\": \"$condition\" }"
done < "$CONDITIONS_FILE"

if [[ -n "$SKIPPED_JSON" ]]; then
  SKIPPED_BLOCK="[$SKIPPED_JSON
  ]"
else
  SKIPPED_BLOCK="[]"
fi

mkdir -p "$(dirname "$STATE_FILE")"

cat > "$STATE_FILE" <<EOF
{
  "route_id": "$ROUTE_ID",
  "rule": "$RULE",
  "last_stage": "$LAST_STAGE",
  "total": $TOTAL,
  "mode": "$MODE",
  "questions_used": $QUESTIONS_USED,
  "start_time": "$START_TIME",
  "skipped": $SKIPPED_BLOCK
}
EOF

echo "written: $STATE_FILE"
exit 0
