#!/usr/bin/env bash
# question-answer-file.sh — The one parser for the question-answer file
# (question-answer 2.0, see shared/question-protocol.md). Sourced, never run:
# write-question-answer.sh and read-question-answer.sh both load a file
# through qa_load, so the writer can never accept a shape the reader refuses,
# or the other way round.
#
# The shape, exactly — every value one line, double-quoted, no double quote
# inside:
#
#   answers:
#     - stage: "<stage id>"
#       question_id: "<lowercase id>"
#       question: "<text>"
#       answer: "<text>"
#
# qa_load <path>
#   Fills QA_STAGE, QA_QID, QA_QUESTION and QA_ANSWER, one index per entry, in
#   file order. An absent file loads as zero entries. Returns 1 and prints
#   "invalid: <reason>" on stderr for anything else that is not the shape
#   above, including two entries under one (stage, question_id) key — no rule
#   says which of them wins, so neither may be handed out.

QA_STAGE_ID_RE='^[a-z][a-z0-9-]*$'
QA_QUESTION_ID_RE='^[a-z][a-z0-9-]*$'
QA_QUESTION_ID_MAX=40

qa_load() {
  local path="$1"
  QA_STAGE=(); QA_QID=(); QA_QUESTION=(); QA_ANSWER=()
  [[ -f "$path" ]] || return 0

  local lines=() line
  while IFS= read -r line || [[ -n "$line" ]]; do
    lines+=("$line")
  done < "$path"
  # Trailing blank lines carry nothing and are not a shape violation.
  while (( ${#lines[@]} > 0 )) && [[ -z "${lines[${#lines[@]}-1]//[[:space:]]/}" ]]; do
    unset 'lines[${#lines[@]}-1]'
  done

  if [[ "${lines[0]:-}" != "answers:" ]]; then
    echo "invalid: $path does not start with an 'answers:' list — not a question-answer 2.0 file" >&2
    return 1
  fi

  local n=${#lines[@]} i=1 entry=0 stage qid question answer key seen=" "
  while (( i < n )); do
    entry=$((entry + 1))
    if [[ ! "${lines[i]}" =~ ^\ \ -\ stage:\ \"([^\"]*)\"$ ]]; then
      echo "invalid: $path entry $entry: expected '  - stage: \"<stage id>\"', got '${lines[i]}'" >&2
      return 1
    fi
    stage="${BASH_REMATCH[1]}"
    if [[ ! "${lines[i+1]:-}" =~ ^\ \ \ \ question_id:\ \"([^\"]*)\"$ ]]; then
      echo "invalid: $path entry $entry: missing or malformed question_id field" >&2
      return 1
    fi
    qid="${BASH_REMATCH[1]}"
    if [[ ! "${lines[i+2]:-}" =~ ^\ \ \ \ question:\ \"([^\"]*)\"$ ]]; then
      echo "invalid: $path entry $entry: missing or malformed question field" >&2
      return 1
    fi
    question="${BASH_REMATCH[1]}"
    if [[ ! "${lines[i+3]:-}" =~ ^\ \ \ \ answer:\ \"([^\"]*)\"$ ]]; then
      echo "invalid: $path entry $entry: missing or malformed answer field" >&2
      return 1
    fi
    answer="${BASH_REMATCH[1]}"

    if [[ ! "$stage" =~ $QA_STAGE_ID_RE ]]; then
      echo "invalid: $path entry $entry: stage '$stage' is not a stage id" >&2
      return 1
    fi
    if [[ ! "$qid" =~ $QA_QUESTION_ID_RE ]] || (( ${#qid} > QA_QUESTION_ID_MAX )); then
      echo "invalid: $path entry $entry: question_id '$qid' is not a lowercase id" >&2
      return 1
    fi
    if [[ -z "$question" || -z "$answer" ]]; then
      echo "invalid: $path entry $entry: question and answer must both be non-empty" >&2
      return 1
    fi
    key="$stage/$qid"
    if [[ "$seen" == *" $key "* ]]; then
      echo "invalid: $path holds two entries under $key" >&2
      return 1
    fi
    seen="$seen$key "

    QA_STAGE+=("$stage"); QA_QID+=("$qid"); QA_QUESTION+=("$question"); QA_ANSWER+=("$answer")
    i=$((i + 4))
  done
  return 0
}
