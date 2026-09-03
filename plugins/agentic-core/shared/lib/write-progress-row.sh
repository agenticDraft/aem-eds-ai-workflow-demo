#!/usr/bin/env bash
# write-progress-row.sh — Upserts one stage's row in progress.md (see
# shared/run-state.md). No model involved: given a stage id and its status,
# replaces that stage's row in place if it already has one, or appends a
# new row at the end — every other row's status and order is left
# untouched. The file this script writes is print-status-table.sh's input
# verbatim (see shared/progress-output.md): same "<stage-id>: <status>"
# shape, same five-value status vocabulary.
#
# Usage:
#   write-progress-row.sh <progress-file> <stage-id> <status>
#
# status is one of done | skipped | failed | running | pending.
#
# Exit codes:
#   0 — success; "written: <path>" (file created) or "updated: <path>"
#       (file already existed) on stdout
#   2 — usage error (wrong argument count, stage id outside
#       [A-Za-z0-9_-]+, status outside the five literals)

set -uo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: write-progress-row.sh <progress-file> <stage-id> <status>" >&2
  exit 2
fi

PROGRESS_FILE="$1"
STAGE_ID="$2"
STATUS="$3"

if [[ ! "$STAGE_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "invalid: stage id '$STAGE_ID' must match [A-Za-z0-9_-]+" >&2
  exit 2
fi

case "$STATUS" in
  done|skipped|failed|running|pending) ;;
  *)
    echo "invalid: status '$STATUS' must be one of done, skipped, failed, running, pending" >&2
    exit 2
    ;;
esac

mkdir -p "$(dirname "$PROGRESS_FILE")"

if [[ ! -f "$PROGRESS_FILE" ]]; then
  echo "${STAGE_ID}: ${STATUS}" > "$PROGRESS_FILE"
  echo "written: $PROGRESS_FILE"
  exit 0
fi

LINES=()
found=0
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^([A-Za-z0-9_-]+):\ (.+)$ ]] && [[ "${BASH_REMATCH[1]}" == "$STAGE_ID" ]]; then
    LINES+=("${STAGE_ID}: ${STATUS}")
    found=1
  else
    LINES+=("$line")
  fi
done < "$PROGRESS_FILE"

if (( found == 0 )); then
  LINES+=("${STAGE_ID}: ${STATUS}")
fi

printf '%s\n' "${LINES[@]}" > "$PROGRESS_FILE"
echo "updated: $PROGRESS_FILE"
exit 0
