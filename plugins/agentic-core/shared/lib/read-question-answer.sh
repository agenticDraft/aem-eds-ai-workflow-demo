#!/usr/bin/env bash
# read-question-answer.sh — Returns one recorded answer, by key, only to the
# stage that asked for it (question-answer 2.0, see
# shared/question-protocol.md). No judgment involved: the answer is the one
# entry whose (stage, question_id) equals the caller's own stage id and the
# question_id it asked under — an exact comparison, never a scan of the
# answers' free text (D527). The file stays on disk after the asking stage is
# re-invoked and holds other stages' answers too; they are invisible here.
#
# Usage:
#   read-question-answer.sh <path> <stage id> <question id>
#
# Exit codes:
#   0 — an entry is keyed (<stage id>, <question id>); its answer, unquoted,
#       on stdout
#   3 — no answer under that key: the file is absent, or holds no such entry;
#       nothing on stdout
#   1 — malformed file ("invalid: <reason>" on stderr) — the whole file is
#       checked, so an answer is never handed out of a file whose other
#       entries cannot be trusted
#   2 — usage error: wrong argument count

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=question-answer-file.sh
. "$SCRIPT_DIR/question-answer-file.sh"

if [[ $# -ne 3 ]]; then
  echo "usage: read-question-answer.sh <path> <stage id> <question id>" >&2
  exit 2
fi

QA_FILE="$1"
STAGE_ID="$2"
QUESTION_ID="$3"

[[ -f "$QA_FILE" ]] || exit 3
qa_load "$QA_FILE" || exit 1

for ((k = 0; k < ${#QA_STAGE[@]}; k++)); do
  if [[ "${QA_STAGE[k]}" == "$STAGE_ID" && "${QA_QID[k]}" == "$QUESTION_ID" ]]; then
    echo "${QA_ANSWER[k]}"
    exit 0
  fi
done
exit 3
