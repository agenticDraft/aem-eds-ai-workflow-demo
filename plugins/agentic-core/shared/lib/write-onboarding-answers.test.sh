#!/usr/bin/env bash
# Tests for write-onboarding-answers.sh. Run with:
#   bash plugins/agentic-core/shared/lib/write-onboarding-answers.test.sh
#
# No framework — exits 0 on success, 1 on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/write-onboarding-answers.sh"
CONVENTION_WRITER="$SCRIPT_DIR/write-convention-record.sh"
VALIDATOR="$SCRIPT_DIR/validate-convention-record.sh"
TMPDIR_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/write-onboarding-answers-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

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

echo "=== write-onboarding-answers.sh tests ==="

RECORD="$TMPDIR_ROOT/project-conventions.yaml"
bash "$CONVENTION_WRITER" "$RECORD" "acme" "components/" "renders with no errors" "none" "lint and test both exit 0" >/dev/null

echo "[write] one question/answer pair, then validates"
OUT=$(bash "$WRITER" "$RECORD" "what should package.json's name say?" "acme-storefront" 2>&1); ST=$?
assert_exit "writer exits 0" 0 $ST "$OUT"
assert_contains "reports updated" "updated: $RECORD" "$OUT"
assert_contains "question present" 'question: "what should package.json'"'"'s name say?"' "$(cat "$RECORD")"
assert_contains "answer present" 'answer: "acme-storefront"' "$(cat "$RECORD")"
assert_contains "original field untouched" 'pack_name: "acme"' "$(cat "$RECORD")"
VALID_OUT=$(bash "$VALIDATOR" "$RECORD" 2>&1); VALID_ST=$?
assert_exit "written file passes the validator" 0 $VALID_ST "$VALID_OUT"

echo "[write] a second run appends rather than replacing"
OUT2=$(bash "$WRITER" "$RECORD" "which token for the near-miss color?" "Dividers/Divider 1" 2>&1); ST2=$?
assert_exit "second run exits 0" 0 $ST2 "$OUT2"
CONTENT="$(cat "$RECORD")"
assert_contains "first answer still present" "acme-storefront" "$CONTENT"
assert_contains "second answer present" "Dividers/Divider 1" "$CONTENT"
VALID_OUT2=$(bash "$VALIDATOR" "$RECORD" 2>&1); VALID_ST2=$?
assert_exit "file with two entries passes the validator" 0 $VALID_ST2 "$VALID_OUT2"

echo "[write] zero pairs leaves onboarding_answers untouched"
BEFORE="$(cat "$RECORD")"
OUT3=$(bash "$WRITER" "$RECORD" 2>&1); ST3=$?
assert_exit "zero-pair run exits 0" 0 $ST3 "$OUT3"
AFTER="$(cat "$RECORD")"
if [[ "$BEFORE" == "$AFTER" ]]; then
  PASS=$((PASS + 1)); echo "  ok: file unchanged by a zero-pair run"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: file unchanged by a zero-pair run"
fi

echo "[write] a fresh record with no prior onboarding_answers still gets []-then-append correctly"
FRESH_RECORD="$TMPDIR_ROOT/fresh.yaml"
bash "$CONVENTION_WRITER" "$FRESH_RECORD" "acme" "components/" "done" "none" "lint" >/dev/null
OUT4=$(bash "$WRITER" "$FRESH_RECORD" "q1" "a1" 2>&1); ST4=$?
assert_exit "first-ever answer on a fresh record exits 0" 0 $ST4 "$OUT4"
VALID_OUT4=$(bash "$VALIDATOR" "$FRESH_RECORD" 2>&1); VALID_ST4=$?
assert_exit "fresh-record result passes the validator" 0 $VALID_ST4 "$VALID_OUT4"

echo "[reject] record does not exist"
OUT5=$(bash "$WRITER" "$TMPDIR_ROOT/does-not-exist.yaml" "q" "a" 2>&1); ST5=$?
assert_exit "missing record rejected (exit 1)" 1 $ST5 "$OUT5"

echo "[reject] odd number of trailing arguments"
OUT6=$(bash "$WRITER" "$RECORD" "q" "a" "orphan" 2>&1); ST6=$?
assert_exit "odd trailing args rejected (exit 1)" 1 $ST6 "$OUT6"

echo "[reject] empty question"
OUT7=$(bash "$WRITER" "$RECORD" "" "answer" 2>&1); ST7=$?
assert_exit "empty question rejected (exit 1)" 1 $ST7 "$OUT7"

echo "[reject] empty answer"
OUT8=$(bash "$WRITER" "$RECORD" "question" "" 2>&1); ST8=$?
assert_exit "empty answer rejected (exit 1)" 1 $ST8 "$OUT8"

echo "[reject] a value containing a double quote"
OUT9=$(bash "$WRITER" "$RECORD" 'question with a "quote"' "answer" 2>&1); ST9=$?
assert_exit "double-quote value rejected (exit 1)" 1 $ST9 "$OUT9"

echo "[usage] no path argument"
OUT10=$(bash "$WRITER" 2>&1); ST10=$?
assert_exit "no path -> usage error (exit 2)" 2 $ST10 "$OUT10"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
