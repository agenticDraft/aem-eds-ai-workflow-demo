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
bash "$WRITER" "$QA" prototype "Which existing component, or what name for a new one, should this change target?" "the new table component" >/dev/null

echo "[owner] the stage that asked gets its answer back, verbatim"
OUT=$(bash "$READER" "$QA" prototype 2>/dev/null); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_equals "prints the answer alone, unquoted" "the new table component" "$OUT"

echo "[not the owner] any other stage gets nothing"
OUT=$(bash "$READER" "$QA" verify-design 2>/dev/null); ST=$?
assert_exit "exits 3" 3 $ST "$OUT"
assert_equals "prints nothing on stdout" "" "$OUT"

echo "[not the owner] a stage id that merely starts like the owner's is still not the owner"
OUT=$(bash "$READER" "$QA" proto 2>/dev/null); ST=$?
assert_exit "exits 3" 3 $ST "$OUT"

echo "[absent] no file means no answer, not an error"
OUT=$(bash "$READER" "$TMPDIR_TEST/none.yaml" prototype 2>/dev/null); ST=$?
assert_exit "exits 3" 3 $ST "$OUT"
assert_equals "prints nothing on stdout" "" "$OUT"

echo "[malformed] a file with no stage field has no provable owner"
cat > "$TMPDIR_TEST/legacy.yaml" <<'YAML'
question: "Which component?"
answer: "the new table component"
YAML
OUT=$(bash "$READER" "$TMPDIR_TEST/legacy.yaml" prototype 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "reason names the missing stage field" "stage" "$OUT"

echo "[malformed] a file with no answer field"
cat > "$TMPDIR_TEST/no-answer.yaml" <<'YAML'
stage: "prototype"
question: "Which component?"
YAML
OUT=$(bash "$READER" "$TMPDIR_TEST/no-answer.yaml" prototype 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "reason names the missing answer field" "answer" "$OUT"

echo "[usage] wrong argument count"
OUT=$(bash "$READER" "$QA" 2>&1); ST=$?
assert_exit "one argument -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
