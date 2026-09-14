#!/usr/bin/env bash
# write-onboarding-answers.sh — Appends onboarding-interview answers to an
# existing convention record's onboarding_answers key (see
# shared/convention-record.md). No judgment involved: the caller has already
# interviewed and confirmed the answers with a human; this script only
# rewrites the record in the fixed shape.
#
# Unlike write-convention-record.sh (which owns the setup interview's own
# six fields and always resets onboarding_answers to whatever the file
# already had), this script owns exactly the opposite: it reads the six
# existing fields back verbatim and appends new entries to
# onboarding_answers — an existing record's other six fields must already
# be there, since this operation only ever runs after setup has generated
# one.
#
# Usage:
#   write-onboarding-answers.sh <path> [<question> <answer> ...]
#
# Zero question/answer pairs is valid (an onboarding run that asked
# nothing) and leaves the file's onboarding_answers key exactly as it was.
#
# Exit codes:
#   0 — success; "updated: <path>" on stdout
#   1 — contract violation: the record does not exist or does not already
#       conform, an odd number of trailing arguments, or a question/answer
#       that is empty or contains a double quote
#   2 — usage error: no path argument

set -uo pipefail

OUT_PATH="${1:-}"
if [[ -z "$OUT_PATH" ]]; then
  echo "usage: write-onboarding-answers.sh <path> [<question> <answer> ...]" >&2
  exit 2
fi
shift

fail() {
  echo "invalid: $1" >&2
  exit 1
}

if [[ ! -f "$OUT_PATH" ]]; then
  fail "no convention record at $OUT_PATH — run setup first"
fi

if (( $# % 2 != 0 )); then
  fail "question/answer arguments must come in pairs, got $# trailing arguments"
fi

# Read the six existing fields back verbatim, in the same fixed order
# validate-convention-record.sh requires. A record this script is handed
# must already conform — this is not the tool that repairs one.
read_field() {
  local key="$1" line
  line="$(grep -m1 "^${key}: " "$OUT_PATH" || true)"
  if [[ ! "$line" =~ ^${key}:\ \"(.*)\"$ ]]; then
    fail "existing record is missing a conformant '${key}: \"<value>\"' line"
  fi
  printf '%s' "${BASH_REMATCH[1]}"
}

VERSION_LINE="$(grep -m1 '^version: ' "$OUT_PATH" || true)"
[[ "$VERSION_LINE" =~ ^version:\ ([0-9]+)$ ]] || fail "existing record is missing a conformant 'version: <int>' line"
VERSION="${BASH_REMATCH[1]}"

PACK_NAME="$(read_field pack_name)"
UNIT_OF_WORK_LOCATION="$(read_field unit_of_work_location)"
DEFINITION_OF_DONE="$(read_field definition_of_done)"
STAGE_CONVENTIONS="$(read_field stage_conventions)"
VERIFICATION_GATE="$(read_field verification_gate)"

# Existing onboarding_answers entries, carried forward verbatim as raw
# lines — new entries are appended after them, never replacing them.
EXISTING_ENTRIES=""
if grep -q '^onboarding_answers:$' "$OUT_PATH"; then
  EXISTING_ENTRIES="$(sed -n '/^onboarding_answers:$/,$p' "$OUT_PATH" | tail -n +2)"
fi

NEW_ENTRIES=""
while (( $# > 0 )); do
  Q="$1"; A="$2"; shift 2
  [[ -z "$Q" ]] && fail "question is empty"
  [[ -z "$A" ]] && fail "answer is empty"
  [[ "$Q" == *'"'* ]] && fail "question contains a double quote, which would corrupt the quoted-string shape"
  [[ "$A" == *'"'* ]] && fail "answer contains a double quote, which would corrupt the quoted-string shape"
  NEW_ENTRIES="${NEW_ENTRIES}  - question: \"${Q}\"
    answer: \"${A}\"
"
done

ALL_ENTRIES="${EXISTING_ENTRIES}"
if [[ -n "$NEW_ENTRIES" ]]; then
  if [[ -n "$ALL_ENTRIES" ]]; then
    ALL_ENTRIES="${ALL_ENTRIES}"$'\n'"${NEW_ENTRIES}"
  else
    ALL_ENTRIES="${NEW_ENTRIES}"
  fi
fi

if [[ -z "$ALL_ENTRIES" ]]; then
  ONBOARDING_BLOCK="onboarding_answers: []"
else
  # Trim exactly one trailing newline left by the loop above.
  ONBOARDING_BLOCK="onboarding_answers:
${ALL_ENTRIES%$'\n'}"
fi

cat <<EOF > "$OUT_PATH"
version: $VERSION
pack_name: "$PACK_NAME"
unit_of_work_location: "$UNIT_OF_WORK_LOCATION"
definition_of_done: "$DEFINITION_OF_DONE"
stage_conventions: "$STAGE_CONVENTIONS"
verification_gate: "$VERIFICATION_GATE"
$ONBOARDING_BLOCK
EOF

echo "updated: $OUT_PATH"
exit 0
