#!/usr/bin/env bash
# write-convention-record.sh — Mechanical writer for a convention record (see
# shared/convention-record.md). No judgment involved: the caller has already
# interviewed and confirmed the answers with a human; this script only
# places them in the fixed shape.
#
# Unlike write-detected-config.sh (which owns only two sections of a larger
# file it shares with other writers), a convention record has exactly six
# keys and nothing else lives in the file — so a re-run overwrites the whole
# file rather than splicing a block into place.
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

mkdir -p "$(dirname "$OUT_PATH")"
cat <<EOF > "$OUT_PATH"
version: 1
pack_name: "$PACK_NAME"
unit_of_work_location: "$UNIT_OF_WORK_LOCATION"
definition_of_done: "$DEFINITION_OF_DONE"
stage_conventions: "$STAGE_CONVENTIONS"
verification_gate: "$VERIFICATION_GATE"
EOF

if [[ "$EXISTED" -eq 1 ]]; then
  echo "updated: $OUT_PATH"
else
  echo "written: $OUT_PATH"
fi
exit 0
