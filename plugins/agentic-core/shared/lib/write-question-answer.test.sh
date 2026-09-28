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

assert_equals() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected: '$expected'"
    echo "    got:      '$actual'"
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

OUT_FILE="$TMPDIR_TEST/question-answer.yaml"
TARGET_Q="Which existing component, or what name for a new one, should this change target?"
NAME_Q="icon.svg is taken by a different file; which name should the new one get?"

echo "[create] fresh file holds one keyed entry"
OUT=$(bash "$WRITER" "$OUT_FILE" prototype target-component "$TARGET_Q" "table" 2>&1); ST=$?
assert_exit "create succeeds (exit 0)" 0 $ST "$OUT"
assert_contains "reports the path written" "$OUT_FILE" "$OUT"
EXPECTED="answers:
  - stage: \"prototype\"
    question_id: \"target-component\"
    question: \"$TARGET_Q\"
    answer: \"table\""
assert_equals "file is exactly the 2.0 shape" "$EXPECTED" "$(cat "$OUT_FILE")"

echo "[create] parent directory does not exist yet — script creates it"
NESTED="$TMPDIR_TEST/nested/dir/question-answer.yaml"
OUT=$(bash "$WRITER" "$NESTED" prototype default "Q?" "A" 2>&1); ST=$?
assert_exit "create under a missing parent directory succeeds (exit 0)" 0 $ST "$OUT"
[[ -f "$NESTED" ]] && { PASS=$((PASS + 1)); echo "  ok: file exists under the newly created parent directory"; } \
  || { FAIL=$((FAIL + 1)); echo "  FAIL: file was not created"; }

echo "[G523] a second question from the same stage keeps the first answer"
OUT=$(bash "$WRITER" "$OUT_FILE" prototype asset-name "$NAME_Q" "icon-2.svg" 2>&1); ST=$?
assert_exit "second write succeeds (exit 0)" 0 $ST "$OUT"
EXPECTED="answers:
  - stage: \"prototype\"
    question_id: \"target-component\"
    question: \"$TARGET_Q\"
    answer: \"table\"
  - stage: \"prototype\"
    question_id: \"asset-name\"
    question: \"$NAME_Q\"
    answer: \"icon-2.svg\""
assert_equals "both entries present, first unchanged, new one appended" "$EXPECTED" "$(cat "$OUT_FILE")"

echo "[upsert] another stage's answer is appended, not a replacement"
OUT=$(bash "$WRITER" "$OUT_FILE" verify-design default "Second question?" "Second answer" 2>&1); ST=$?
assert_exit "third write succeeds (exit 0)" 0 $ST "$OUT"
assert_equals "three entries" "3" "$(grep -c '^  - stage: ' "$OUT_FILE")"

echo "[upsert] the same key asked again replaces only its own entry, in place"
OUT=$(bash "$WRITER" "$OUT_FILE" prototype target-component "$TARGET_Q" "a new block named data-table" 2>&1); ST=$?
assert_exit "re-answer succeeds (exit 0)" 0 $ST "$OUT"
assert_equals "still three entries" "3" "$(grep -c '^  - stage: ' "$OUT_FILE")"
assert_equals "the replaced entry stays first" '  - stage: "prototype"' "$(sed -n 2p "$OUT_FILE")"
assert_equals "its answer is the new one" '    answer: "a new block named data-table"' "$(sed -n 5p "$OUT_FILE")"
assert_contains "the other stage-local answer survives" 'answer: "icon-2.svg"' "$(cat "$OUT_FILE")"
assert_contains "the other stage's answer survives" 'answer: "Second answer"' "$(cat "$OUT_FILE")"
if [[ "$(cat "$OUT_FILE")" == *'answer: "table"'* ]]; then
  FAIL=$((FAIL + 1)); echo "  FAIL: the replaced answer is still on file"
else
  PASS=$((PASS + 1)); echo "  ok: the replaced answer is gone"
fi

echo "[upsert] same question_id under another stage is a different key"
bash "$WRITER" "$OUT_FILE" verify-design target-component "Q?" "other" >/dev/null 2>&1
assert_equals "four entries" "4" "$(grep -c '^  - stage: ' "$OUT_FILE")"

echo "[reject] empty question"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/bad-q.yaml" prototype default "" "an answer" 2>&1); ST=$?
assert_exit "empty question rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names question" "question" "$OUT"

echo "[reject] empty answer"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/bad-a.yaml" prototype default "a question" "" 2>&1); ST=$?
assert_exit "empty answer rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names answer" "answer" "$OUT"

echo "[reject] a value containing a double quote"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/bad-quote.yaml" prototype default 'a "quoted" question' "an answer" 2>&1); ST=$?
assert_exit "quote-containing value rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] a value spanning two lines"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/bad-nl.yaml" prototype default "a question" $'line one\nline two' 2>&1); ST=$?
assert_exit "multi-line value rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the line break" "line" "$OUT"

echo "[reject] empty stage"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/bad-s.yaml" "" default "a question" "an answer" 2>&1); ST=$?
assert_exit "empty stage rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names stage" "stage" "$OUT"

echo "[reject] a stage that is not a stage id"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/bad-s2.yaml" "Verify Design" default "a question" "an answer" 2>&1); ST=$?
assert_exit "malformed stage rejected (exit 1)" 1 $ST "$OUT"
[[ -f "$TMPDIR_TEST/bad-s2.yaml" ]] && { FAIL=$((FAIL + 1)); echo "  FAIL: a rejected write still produced a file"; } \
  || { PASS=$((PASS + 1)); echo "  ok: a rejected write produces no file"; }

echo "[reject] a question_id that is not a lowercase id"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/bad-id.yaml" prototype "Target Component" "a question" "an answer" 2>&1); ST=$?
assert_exit "malformed question_id rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names question_id" "question_id" "$OUT"

echo "[reject] an existing 1.1 file is refused, never overwritten"
LEGACY="$TMPDIR_TEST/legacy.yaml"
printf 'stage: "prototype"\nquestion: "Which component?"\nanswer: "table"\n' > "$LEGACY"
BEFORE="$(cat "$LEGACY")"
OUT=$(bash "$WRITER" "$LEGACY" prototype asset-name "a question" "an answer" 2>&1); ST=$?
assert_exit "1.1 file rejected (exit 1)" 1 $ST "$OUT"
assert_equals "the 1.1 file is untouched" "$BEFORE" "$(cat "$LEGACY")"

echo "[usage] wrong argument count"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/x.yaml" only-one-value 2>&1); ST=$?
assert_exit "wrong arg count -> usage error (exit 2)" 2 $ST "$OUT"
echo "[usage] the old four-argument form is refused, not misread"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/x.yaml" prototype "a question" "an answer" 2>&1); ST=$?
assert_exit "four arguments -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
