#!/usr/bin/env bash
# print-status-table.sh — Deterministic formatter for the once-only final
# status table (see shared/progress-output.md). No model involved: renders
# one row per stage from a flat "<stage-id>: <status>" file. Whether this
# script is invoked more than once in a run is a caller discipline, not
# something the script itself can enforce — see the contract doc's
# single-emission rule.
#
# Usage:
#   print-status-table.sh <progress-file>
#
# <progress-file>: one line per stage, "<stage-id>: <status>", in the order
# rows should render. status is one of done | skipped | failed | running |
# pending — the same vocabulary shared/progress-output.md and (once built)
# progress.md use.
#
# Exit codes:
#   0 — prints the table on stdout
#   2 — usage error (missing argument, file not found, malformed line, a
#       status outside the five literals)

set -uo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
  echo "usage: print-status-table.sh <progress-file>" >&2
  exit 2
fi
if [[ ! -f "$FILE" ]]; then
  echo "invalid: file not found: $FILE" >&2
  exit 2
fi

ROWS=()

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" ]] && continue
  if [[ "$line" =~ ^([A-Za-z0-9_-]+):\ (done|skipped|failed|running|pending)$ ]]; then
    ROWS+=("| ${BASH_REMATCH[1]} | ${BASH_REMATCH[2]} |")
  else
    echo "invalid: malformed line '$line' (expected '<stage-id>: done|skipped|failed|running|pending')" >&2
    exit 2
  fi
done < "$FILE"

echo "| Stage | Status |"
echo "| --- | --- |"
if (( ${#ROWS[@]} > 0 )); then
  for row in "${ROWS[@]}"; do
    echo "$row"
  done
fi
exit 0
