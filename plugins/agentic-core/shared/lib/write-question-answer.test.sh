#!/usr/bin/env bash
# Tests for write-question-answer.sh. Run with:
#   bash plugins/agentic-core/shared/lib/write-question-answer.test.sh
#
# No framework — mirrors the harness in write-run-state.test.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/write-question-answer.sh"

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3" output="$4"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected exit=$expected, got exit=$actual"
    [[ -n "$output" ]] && echo "    output: $output"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected output to contain: $needle"
    echo "    got: $haystack"
  fi
}

TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/write-question-answer-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== write-question-answer.sh tests ==="

echo "[create] fresh file gets all three fields"
OUT_FILE="$TMPDIR_TEST/question-answer.yaml"
OUT=$(bash "$WRITER" "$OUT_FILE" prototype "Which pack should own the tracker role?" "Use the linear pack" 2>&1); ST=$?
assert_exit "create succeeds (exit 0)" 0 $ST "$OUT"
assert_contains "reports the path written" "$OUT_FILE" "$OUT"
CONTENT="$(cat "$OUT_FILE")"
assert_contains "file names the stage that asked" 'stage: "prototype"' "$CONTENT"
assert_contains "file carries the question" 'question: "Which pack should own the tracker role?"' "$CONTENT"
assert_contains "file carries the answer" 'answer: "Use the linear pack"' "$CONTENT"

echo "[create] parent directory does not exist yet — script creates it"
NESTED="$TMPDIR_TEST/nested/dir/question-answer.yaml"
OUT=$(bash "$WRITER" "$NESTED" prototype "Q?" "A" 2>&1); ST=$?
assert_exit "create under a missing parent directory succeeds (exit 0)" 0 $ST "$OUT"
[[ -f "$NESTED" ]] && { PASS=$((PASS + 1)); echo "  ok: file exists under the newly created parent directory"; } \
  || { FAIL=$((FAIL + 1)); echo "  FAIL: file was not created"; }

echo "[the answer reaches the stage that asked] a stub reader gets the same text back"
READ_BACK="$(grep '^answer: ' "$OUT_FILE" | sed 's/^answer: "\(.*\)"$/\1/')"
if [[ "$READ_BACK" == "Use the linear pack" ]]; then
  PASS=$((PASS + 1))
  echo "  ok: the answer written at one stage boundary is exactly what a reader gets"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: read-back answer was '$READ_BACK'"
fi

echo "[refresh] rewriting an existing file replaces its content"
OUT=$(bash "$WRITER" "$OUT_FILE" verify-design "Second question?" "Second answer" 2>&1); ST=$?
assert_exit "rewrite succeeds (exit 0)" 0 $ST "$OUT"
CONTENT="$(cat "$OUT_FILE")"
assert_contains "file names the new asking stage" 'stage: "verify-design"' "$CONTENT"
assert_contains "file carries the new question" 'question: "Second question?"' "$CONTENT"
assert_contains "file carries the new answer" 'answer: "Second answer"' "$CONTENT"
if [[ "$CONTENT" == *"linear pack"* ]]; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: old answer text was not replaced"
else
  PASS=$((PASS + 1))
  echo "  ok: old answer text was replaced"
fi

echo "[reject] empty question"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/bad-q.yaml" prototype "" "an answer" 2>&1); ST=$?
assert_exit "empty question rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names question" "question" "$OUT"

echo "[reject] empty answer"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/bad-a.yaml" prototype "a question" "" 2>&1); ST=$?
assert_exit "empty answer rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names answer" "answer" "$OUT"

echo "[reject] a value containing a double quote"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/bad-quote.yaml" prototype 'a "quoted" question' "an answer" 2>&1); ST=$?
assert_exit "quote-containing value rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] empty stage"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/bad-s.yaml" "" "a question" "an answer" 2>&1); ST=$?
assert_exit "empty stage rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names stage" "stage" "$OUT"

echo "[reject] a stage that is not a stage id"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/bad-s2.yaml" "Verify Design" "a question" "an answer" 2>&1); ST=$?
assert_exit "malformed stage rejected (exit 1)" 1 $ST "$OUT"
[[ -f "$TMPDIR_TEST/bad-s2.yaml" ]] && { FAIL=$((FAIL + 1)); echo "  FAIL: a rejected write still produced a file"; } \
  || { PASS=$((PASS + 1)); echo "  ok: a rejected write produces no file"; }

echo "[usage] wrong argument count"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/x.yaml" only-one-value 2>&1); ST=$?
assert_exit "wrong arg count -> usage error (exit 2)" 2 $ST "$OUT"
echo "[usage] the old three-argument form is refused, not misread"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/x.yaml" "a question" "an answer" 2>&1); ST=$?
assert_exit "three arguments -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
