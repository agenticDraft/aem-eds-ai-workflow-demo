#!/usr/bin/env bash
# write-question-answer.sh — Mechanical upsert of one answer into the
# question-answer file (question-answer 2.0, see shared/question-protocol.md).
# No judgment involved: the caller already has the asking stage's id, the
# question_id and question text (from the envelope, through
# handle-question.sh) and the answer (from the human) — this script only
# places them. The file lives under the same stage-readable bucket as
# fact-record.yaml; the stage an entry names is re-invoked with it, and is the
# only stage that reads it (read-question-answer.sh).
#
# Upsert (D527): an entry already keyed (stage, question_id) is replaced in
# place; any other key is appended. Every other entry is kept exactly as it
# was — a plain overwrite erased an earlier answer on a live run (G523).
#
# Usage:
#   write-question-answer.sh <path> <stage id> <question id> <question> <answer>
#
# Exit codes:
#   0 — success; "written: <path>" on stdout
#   1 — contract violation: stage is not a stage id, question id is not a
#       lowercase id, question or answer is empty, contains a double quote or
#       spans lines, or the existing file is not a well-formed 2.0 file;
#       nothing is written
#   2 — usage error: wrong argument count

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=question-answer-file.sh
. "$SCRIPT_DIR/question-answer-file.sh"

if [[ $# -ne 5 ]]; then
  echo "usage: write-question-answer.sh <path> <stage id> <question id> <question> <answer>" >&2
  exit 2
fi

OUT_FILE="$1"
STAGE="$2"
QUESTION_ID="$3"
QUESTION="$4"
ANSWER="$5"

fail() {
  echo "invalid: $1" >&2
  exit 1
}

[[ -n "$STAGE" ]] || fail "stage is empty"
[[ "$STAGE" =~ $QA_STAGE_ID_RE ]] || fail "stage '$STAGE' is not a stage id (lowercase letters, digits and hyphens)"
[[ "$QUESTION_ID" =~ $QA_QUESTION_ID_RE ]] && (( ${#QUESTION_ID} <= QA_QUESTION_ID_MAX )) \
  || fail "question_id '$QUESTION_ID' is not a lowercase id (letters, digits and hyphens, starting with a letter, at most $QA_QUESTION_ID_MAX characters)"
[[ -n "$QUESTION" ]] || fail "question is empty"
[[ -n "$ANSWER" ]] || fail "answer is empty"
[[ "$QUESTION" == *'"'* ]] && fail "question contains a double quote, which would corrupt the quoted-string shape"
[[ "$ANSWER" == *'"'* ]] && fail "answer contains a double quote, which would corrupt the quoted-string shape"
[[ "$QUESTION" == *$'\n'* || "$QUESTION" == *$'\r'* ]] && fail "question spans more than one line"
[[ "$ANSWER" == *$'\n'* || "$ANSWER" == *$'\r'* ]] && fail "answer spans more than one line"

qa_load "$OUT_FILE" || exit 1

replaced=0
for ((k = 0; k < ${#QA_STAGE[@]}; k++)); do
  if [[ "${QA_STAGE[k]}" == "$STAGE" && "${QA_QID[k]}" == "$QUESTION_ID" ]]; then
    QA_QUESTION[k]="$QUESTION"
    QA_ANSWER[k]="$ANSWER"
    replaced=1
  fi
done
if (( ! replaced )); then
  QA_STAGE+=("$STAGE"); QA_QID+=("$QUESTION_ID"); QA_QUESTION+=("$QUESTION"); QA_ANSWER+=("$ANSWER")
fi

mkdir -p "$(dirname "$OUT_FILE")"

# Written beside the target and moved over it, so a reader never sees half a
# file and a failed write leaves the previous answers intact.
TMP_FILE="$(mktemp "$(dirname "$OUT_FILE")/.question-answer.XXXXXX")" || fail "cannot create a temporary file beside $OUT_FILE"
{
  echo "answers:"
  for ((k = 0; k < ${#QA_STAGE[@]}; k++)); do
    echo "  - stage: \"${QA_STAGE[k]}\""
    echo "    question_id: \"${QA_QID[k]}\""
    echo "    question: \"${QA_QUESTION[k]}\""
    echo "    answer: \"${QA_ANSWER[k]}\""
  done
} > "$TMP_FILE"
mv "$TMP_FILE" "$OUT_FILE"

echo "written: $OUT_FILE"
exit 0
