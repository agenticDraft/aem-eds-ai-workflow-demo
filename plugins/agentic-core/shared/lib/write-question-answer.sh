#!/usr/bin/env bash
# write-question-answer.sh — Mechanical write of one question-answer file
# (see shared/question-protocol.md). No judgment involved: the caller
# already has the question text (from the envelope) and the answer (from
# the human or from an already-run stage) — this script only places them in
# the fixed shape. This is how an answer given at one stage boundary
# reaches the next stage's input: the file lives under the same stage-
# readable bucket as fact-record.yaml and route.yaml.
#
# Usage:
#   write-question-answer.sh <path> <question> <answer>
#
# Exit codes:
#   0 — success; "written: <path>" on stdout
#   1 — contract violation: question or answer is empty, or contains a
#       double quote (would corrupt the quoted-string shape)
#   2 — usage error: wrong argument count

set -uo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: write-question-answer.sh <path> <question> <answer>" >&2
  exit 2
fi

OUT_FILE="$1"
QUESTION="$2"
ANSWER="$3"

fail() {
  echo "invalid: $1" >&2
  exit 1
}

[[ -n "$QUESTION" ]] || fail "question is empty"
[[ -n "$ANSWER" ]] || fail "answer is empty"
[[ "$QUESTION" == *'"'* ]] && fail "question contains a double quote, which would corrupt the quoted-string shape"
[[ "$ANSWER" == *'"'* ]] && fail "answer contains a double quote, which would corrupt the quoted-string shape"

mkdir -p "$(dirname "$OUT_FILE")"

cat > "$OUT_FILE" <<EOF
question: "$QUESTION"
answer: "$ANSWER"
EOF

echo "written: $OUT_FILE"
exit 0
