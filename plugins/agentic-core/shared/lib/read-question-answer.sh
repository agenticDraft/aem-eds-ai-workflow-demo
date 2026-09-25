#!/usr/bin/env bash
# read-question-answer.sh — Returns a recorded answer only to the stage that
# asked for it (see shared/question-protocol.md). No judgment involved:
# ownership is an exact comparison of the file's `stage` field against the
# caller's own stage id. The file stays on disk after the asking stage is
# re-invoked, so every other stage must be able to tell it is not theirs.
#
# Usage:
#   read-question-answer.sh <path> <stage id>
#
# Exit codes:
#   0 — the file exists and names <stage id>; the answer, unquoted, on stdout
#   3 — no answer for this stage: the file is absent, or names another stage;
#       nothing on stdout
#   1 — malformed file: no `stage` or no `answer` field ("invalid: <reason>"
#       on stderr) — an answer with no provable owner is never handed out
#   2 — usage error: wrong argument count

set -uo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: read-question-answer.sh <path> <stage id>" >&2
  exit 2
fi

QA_FILE="$1"
STAGE_ID="$2"

[[ -f "$QA_FILE" ]] || exit 3

field() {
  grep -m1 "^$1: \"" "$QA_FILE" | sed "s/^$1: \"\(.*\)\"\$/\1/"
}

OWNER="$(field stage)"
ANSWER="$(field answer)"

if [[ -z "$OWNER" ]]; then
  echo "invalid: $QA_FILE has no stage field, so no stage can prove the answer is its own" >&2
  exit 1
fi
if [[ -z "$ANSWER" ]]; then
  echo "invalid: $QA_FILE has no answer field" >&2
  exit 1
fi

[[ "$OWNER" == "$STAGE_ID" ]] || exit 3

echo "$ANSWER"
exit 0
