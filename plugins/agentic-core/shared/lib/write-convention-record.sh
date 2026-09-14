#!/usr/bin/env bash
# write-convention-record.sh — Mechanical writer for a convention record (see
# shared/convention-record.md). No judgment involved: the caller has already
# interviewed and confirmed the answers with a human; this script only
# places them in the fixed shape.
#
# Unlike write-detected-config.sh (which owns only two sections of a larger
# file it shares with other writers), a convention record has exactly seven
# keys and nothing else lives in the file — so a re-run overwrites the whole
# file rather than splicing a block into place. The one exception is
# onboarding_answers: a re-run here preserves whatever that key already
# holds (verbatim, carried over from the existing file) rather than
# resetting it to [] — this script owns the setup interview's own six
# fields, never the onboarding interview's history, and setup's own
# keep/re-detect/edit re-run must not silently discard an onboarding run
# that happened since the pack was generated. write-onboarding-answers.sh is
# the separate writer that appends real answers to that key.
#
# Usage:
#   write-convention-record.sh <path> <pack_name> <unit_of_work_location> \
#     <definition_of_done> <stage_conventions> <verification_gate>
#
# Exit codes:
#   0 — success; "written: <path>" or "updated: <path>" on stdout
#   1 — contract violation: an empty value, or a value containing a double
#       quote (would corrupt the quoted-string shape)
#   2 — usage error: wrong argument count

set -uo pipefail

if [[ $# -ne 6 ]]; then
  echo "usage: write-convention-record.sh <path> <pack_name> <unit_of_work_location> <definition_of_done> <stage_conventions> <verification_gate>" >&2
  exit 2
fi

OUT_PATH="$1"
PACK_NAME="$2"
UNIT_OF_WORK_LOCATION="$3"
DEFINITION_OF_DONE="$4"
STAGE_CONVENTIONS="$5"
VERIFICATION_GATE="$6"

fail() {
  echo "invalid: $1" >&2
  exit 1
}

for pair in "pack_name:$PACK_NAME" "unit_of_work_location:$UNIT_OF_WORK_LOCATION" "definition_of_done:$DEFINITION_OF_DONE" "stage_conventions:$STAGE_CONVENTIONS" "verification_gate:$VERIFICATION_GATE"; do
  key="${pair%%:*}"
  value="${pair#*:}"
  [[ -z "$value" ]] && fail "$key is empty"
  [[ "$value" == *'"'* ]] && fail "$key contains a double quote, which would corrupt the quoted-string shape"
done

EXISTED=0
[[ -f "$OUT_PATH" ]] && EXISTED=1

ONBOARDING_BLOCK="onboarding_answers: []"
if [[ "$EXISTED" -eq 1 ]] && grep -q '^onboarding_answers:' "$OUT_PATH"; then
  ONBOARDING_BLOCK="$(sed -n '/^onboarding_answers:/,$p' "$OUT_PATH")"
fi

mkdir -p "$(dirname "$OUT_PATH")"
cat <<EOF > "$OUT_PATH"
version: 1
pack_name: "$PACK_NAME"
unit_of_work_location: "$UNIT_OF_WORK_LOCATION"
definition_of_done: "$DEFINITION_OF_DONE"
stage_conventions: "$STAGE_CONVENTIONS"
verification_gate: "$VERIFICATION_GATE"
$ONBOARDING_BLOCK
EOF

if [[ "$EXISTED" -eq 1 ]]; then
  echo "updated: $OUT_PATH"
else
  echo "written: $OUT_PATH"
fi
exit 0
