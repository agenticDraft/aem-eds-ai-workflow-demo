#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/capture-envelope.sh .ai/run-context/envelope-<stage id>.txt
#
# capture-envelope.sh <envelope-file>
#
# Deterministic. Reduces a captured stage envelope to the block the contract
# describes, in place, before the validator judges it. Two reductions only,
# both of which are transcription artifacts rather than statements a stage
# made:
#
#   1. Anything above the envelope's own heading is dropped. The heading is
#      the last one in the file, so a heading quoted inside a stage's own
#      prose never wins over the block that terminates its output.
#   2. Blank lines between that heading and the line after it are removed,
#      and ONLY when that line is a `verdict:` line.
#
# The second condition is the whole restraint. A blank line before a
# `verdict:` line carries no meaning any reader could have intended, so
# removing it changes nothing a stage said. Any other first line — a bulleted
# list, a summary, a fenced block — is a stage saying something the contract
# does not allow, and it is left exactly as found for the validator to reject.
# Repairing that would be answering for the stage.
#
# Every reduction is reported on stdout. A normalization nobody can see is
# indistinguishable from an envelope that was already correct, and the run's
# own record is where that difference has to survive.
#
# Exit codes: 0 — a `## Result` block is present and the file now holds it
# alone; 1 — no such heading, so there is no envelope to capture; 2 — usage.

set -uo pipefail

usage() {
  echo "usage: capture-envelope.sh <envelope-file>" >&2
  if [ "$#" -gt 0 ]; then echo "$1" >&2; fi
  exit 2
}

[ "$#" -eq 1 ] || usage "expected exactly 1 argument"
FILE="$1"
[ -f "$FILE" ] && [ -r "$FILE" ] || usage "'$FILE' is not a readable file"

LINES=()
while IFS= read -r line || [ -n "$line" ]; do
  LINES+=("$line")
done < "$FILE"

TOTAL=${#LINES[@]}

HEAD_IDX=-1
i=0
while [ "$i" -lt "$TOTAL" ]; do
  if [[ "${LINES[$i]}" =~ ^##[[:space:]]+Result[[:space:]]*$ ]]; then
    HEAD_IDX=$i
  fi
  i=$((i + 1))
done

if [ "$HEAD_IDX" -lt 0 ]; then
  echo "invalid: no '## Result' heading found in '$FILE'" >&2
  exit 1
fi

# The first line after the heading that carries anything at all.
NEXT_IDX=$((HEAD_IDX + 1))
while [ "$NEXT_IDX" -lt "$TOTAL" ] && [ -z "${LINES[$NEXT_IDX]// /}" ]; do
  NEXT_IDX=$((NEXT_IDX + 1))
done

DROPPED_ABOVE=$HEAD_IDX
BLANKS=0
NEXT_IS_VERDICT=0
if [ "$NEXT_IDX" -lt "$TOTAL" ] && [[ "${LINES[$NEXT_IDX]}" =~ ^verdict: ]]; then
  NEXT_IS_VERDICT=1
  BLANKS=$((NEXT_IDX - HEAD_IDX - 1))
fi

REPORT=()
OUT=()
OUT+=("${LINES[$HEAD_IDX]}")

if [ "$NEXT_IS_VERDICT" -eq 1 ]; then
  i=$NEXT_IDX
else
  i=$((HEAD_IDX + 1))
fi
while [ "$i" -lt "$TOTAL" ]; do
  OUT+=("${LINES[$i]}")
  i=$((i + 1))
done

if [ "$DROPPED_ABOVE" -gt 0 ]; then
  REPORT+=("normalized: dropped $DROPPED_ABOVE line(s) above the envelope's own heading")
fi
if [ "$BLANKS" -gt 0 ]; then
  REPORT+=("normalized: removed $BLANKS blank line(s) between '## Result' and 'verdict:'")
fi

if [ "${#REPORT[@]}" -gt 0 ]; then
  : > "$FILE"
  for line in "${OUT[@]}"; do printf '%s\n' "$line" >> "$FILE"; done
  printf '%s\n' "${REPORT[@]}"
  echo "captured: ${#OUT[@]} line(s) from '## Result' onward"
elif [ "$NEXT_IS_VERDICT" -eq 0 ]; then
  echo "captured: the line after '## Result' is not a 'verdict:' line; left unchanged for the validator to judge"
else
  echo "captured: unchanged (${#OUT[@]} lines)"
fi

exit 0
