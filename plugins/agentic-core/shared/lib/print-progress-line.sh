#!/usr/bin/env bash
# print-progress-line.sh — Deterministic formatter for one stage's progress
# line (see shared/progress-output.md). No model involved: given the route's
# current skip state and one stage's outcome, prints the line and never
# caches a total across calls, so a stage marked skipped is reflected
# immediately in every line printed after it.
#
# Usage:
#   print-progress-line.sh <route-file> <current-stage-id> <verdict> <summary>
#
# <route-file>: one stage id per line, in route order. A stage already known
# to be skipped is written as "<stage-id>: skipped"; every other line is a
# bare stage id. Total is the count of lines NOT marked skipped; a stage's
# position is 1 plus the count of non-skipped lines before it.
#
# Exit codes:
#   0 — prints "Stage <n>/<total>: <stage id> — <verdict> · <summary>"
#   2 — usage error (missing argument, route file not found, stage id absent
#       from the route file or marked skipped in it, verdict outside
#       pass|warn|fail|question, summary empty/multi-line/over 200 chars)

set -uo pipefail

ROUTE_FILE="${1:-}"
STAGE_ID="${2:-}"
VERDICT="${3:-}"
SUMMARY="${4:-}"

usage() {
  echo "usage: print-progress-line.sh <route-file> <current-stage-id> <verdict> <summary>" >&2
  exit 2
}

[[ -z "$ROUTE_FILE" || -z "$STAGE_ID" || -z "$VERDICT" ]] && usage
[[ -f "$ROUTE_FILE" ]] || { echo "invalid: file not found: $ROUTE_FILE" >&2; exit 2; }

case "$VERDICT" in
  pass|warn|fail|question) ;;
  *)
    echo "invalid: verdict '$VERDICT' must be one of pass, warn, fail, question" >&2
    exit 2
    ;;
esac

if [[ -z "$SUMMARY" ]]; then
  echo "invalid: summary is empty" >&2
  exit 2
fi
if [[ "$SUMMARY" == *$'\n'* ]]; then
  echo "invalid: summary spans multiple lines" >&2
  exit 2
fi
if (( ${#SUMMARY} > 200 )); then
  echo "invalid: summary exceeds 200 characters" >&2
  exit 2
fi

total=0
position=0
found=0
skipped=0

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" ]] && continue
  if [[ "$line" =~ ^([A-Za-z0-9_-]+):\ skipped$ ]]; then
    id="${BASH_REMATCH[1]}"
    is_skipped=1
  else
    id="$line"
    is_skipped=0
  fi

  if (( is_skipped == 0 )); then
    total=$((total + 1))
  fi

  if [[ "$id" == "$STAGE_ID" ]]; then
    found=1
    skipped=$is_skipped
    if (( is_skipped == 0 )); then
      position=$total
    fi
    # Keep scanning: later lines still count toward the total.
  fi
done < "$ROUTE_FILE"

if (( found == 0 )); then
  echo "invalid: stage '$STAGE_ID' not found in $ROUTE_FILE" >&2
  exit 2
fi
if (( skipped == 1 )); then
  echo "invalid: stage '$STAGE_ID' is marked skipped in $ROUTE_FILE" >&2
  exit 2
fi

echo "Stage ${position}/${total}: ${STAGE_ID} — ${VERDICT} · ${SUMMARY}"
exit 0
