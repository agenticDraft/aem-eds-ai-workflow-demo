#!/usr/bin/env bash
# Tests for read-question-answer.sh. Run with:
#   bash plugins/agentic-core/shared/lib/read-question-answer.test.sh
#
# No framework — mirrors the harness in write-question-answer.test.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$SCRIPT_DIR/read-question-answer.sh"
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

TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/read-question-answer-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== read-question-answer.sh tests ==="

QA="$TMPDIR_TEST/question-answer.yaml"
bash "$WRITER" "$QA" prototype target-component "Which existing component, or what name for a new one, should this change target?" "the new table component" >/dev/null
bash "$WRITER" "$QA" prototype asset-name "icon.svg is taken by a different file; which name should the new one get?" "Renamed the files" >/dev/null

echo "[G523] two answers for one stage are both read back, each by its own key"
OUT=$(bash "$READER" "$QA" prototype target-component 2>/dev/null); ST=$?
assert_exit "first key exits 0" 0 $ST "$OUT"
assert_equals "first answer, alone and unquoted" "the new table component" "$OUT"
OUT=$(bash "$READER" "$QA" prototype asset-name 2>/dev/null); ST=$?
assert_exit "second key exits 0" 0 $ST "$OUT"
assert_equals "second answer, alone and unquoted" "Renamed the files" "$OUT"

echo "[upsert] re-answering one key changes only what that key reads back"
bash "$WRITER" "$QA" prototype asset-name "icon.svg is taken by a different file; which name should the new one get?" "icon-alt.svg" >/dev/null
assert_equals "re-answered key reads the new answer" "icon-alt.svg" "$(bash "$READER" "$QA" prototype asset-name 2>/dev/null)"
assert_equals "the other key is unchanged" "the new table component" "$(bash "$READER" "$QA" prototype target-component 2>/dev/null)"

echo "[default] an answer written under default is read back under default"
bash "$WRITER" "$QA" verify-design default "Keep going?" "yes" >/dev/null
OUT=$(bash "$READER" "$QA" verify-design default 2>/dev/null); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_equals "prints the answer" "yes" "$OUT"

echo "[no such key] the stage's own id with a question_id it never asked under gets nothing"
OUT=$(bash "$READER" "$QA" prototype default 2>/dev/null); ST=$?
assert_exit "exits 3" 3 $ST "$OUT"
assert_equals "prints nothing on stdout" "" "$OUT"

echo "[not the owner] another stage's key is invisible, even with a matching question_id"
OUT=$(bash "$READER" "$QA" verify-design target-component 2>/dev/null); ST=$?
assert_exit "exits 3" 3 $ST "$OUT"
assert_equals "prints nothing on stdout" "" "$OUT"

echo "[not the owner] a stage id that merely starts like the owner's is still not the owner"
OUT=$(bash "$READER" "$QA" proto target-component 2>/dev/null); ST=$?
assert_exit "exits 3" 3 $ST "$OUT"

echo "[absent] no file means no answer, not an error"
OUT=$(bash "$READER" "$TMPDIR_TEST/none.yaml" prototype target-component 2>/dev/null); ST=$?
assert_exit "exits 3" 3 $ST "$OUT"
assert_equals "prints nothing on stdout" "" "$OUT"

echo "[malformed] a 1.1 file has no provable key"
cat > "$TMPDIR_TEST/legacy.yaml" <<'YAML'
stage: "prototype"
question: "Which component?"
answer: "the new table component"
YAML
OUT=$(bash "$READER" "$TMPDIR_TEST/legacy.yaml" prototype default 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "reason names the missing answers list" "answers" "$OUT"

echo "[malformed] an entry with no answer field"
cat > "$TMPDIR_TEST/no-answer.yaml" <<'YAML'
answers:
  - stage: "prototype"
    question_id: "target-component"
    question: "Which component?"
YAML
OUT=$(bash "$READER" "$TMPDIR_TEST/no-answer.yaml" prototype target-component 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "reason names the missing answer field" "answer" "$OUT"

echo "[malformed] two entries under one key — no rule says which wins, so neither is handed out"
cat > "$TMPDIR_TEST/dup.yaml" <<'YAML'
answers:
  - stage: "prototype"
    question_id: "target-component"
    question: "Which component?"
    answer: "table"
  - stage: "prototype"
    question_id: "target-component"
    question: "Which component?"
    answer: "columns"
YAML
OUT=$(bash "$READER" "$TMPDIR_TEST/dup.yaml" prototype target-component 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "reason names the duplicate key" "prototype/target-component" "$OUT"

echo "[usage] wrong argument count"
OUT=$(bash "$READER" "$QA" 2>&1); ST=$?
assert_exit "one argument -> usage error (exit 2)" 2 $ST "$OUT"
echo "[usage] the old two-argument form is refused, not misread"
OUT=$(bash "$READER" "$QA" prototype 2>&1); ST=$?
assert_exit "two arguments -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
