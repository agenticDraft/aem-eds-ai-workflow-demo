#!/usr/bin/env bash
# write-question-answer.sh — Mechanical write of one question-answer file
# (see shared/question-protocol.md). No judgment involved: the caller
# already has the asking stage's id and the question text (from the
# envelope) and the answer (from the human) — this script only places them
# in the fixed shape. The file lives under the same stage-readable bucket as
# fact-record.yaml; the stage it names is re-invoked with it, and is the only
# stage that acts on it (read-question-answer.sh).
#
# Usage:
#   write-question-answer.sh <path> <stage id> <question> <answer>
#
# Exit codes:
#   0 — success; "written: <path>" on stdout
#   1 — contract violation: stage is empty or not a stage id, or question or
#       answer is empty or contains a double quote (would corrupt the
#       quoted-string shape); nothing is written
#   2 — usage error: wrong argument count

set -uo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: write-question-answer.sh <path> <stage id> <question> <answer>" >&2
  exit 2
fi

OUT_FILE="$1"
STAGE="$2"
QUESTION="$3"
ANSWER="$4"

fail() {
  echo "invalid: $1" >&2
  exit 1
}

[[ -n "$STAGE" ]] || fail "stage is empty"
[[ "$STAGE" =~ ^[a-z][a-z0-9-]*$ ]] || fail "stage '$STAGE' is not a stage id (lowercase letters, digits and hyphens)"
[[ -n "$QUESTION" ]] || fail "question is empty"
[[ -n "$ANSWER" ]] || fail "answer is empty"
[[ "$QUESTION" == *'"'* ]] && fail "question contains a double quote, which would corrupt the quoted-string shape"
[[ "$ANSWER" == *'"'* ]] && fail "answer contains a double quote, which would corrupt the quoted-string shape"

mkdir -p "$(dirname "$OUT_FILE")"

cat > "$OUT_FILE" <<YAML
stage: "$STAGE"
question: "$QUESTION"
answer: "$ANSWER"
YAML

echo "written: $OUT_FILE"
exit 0
