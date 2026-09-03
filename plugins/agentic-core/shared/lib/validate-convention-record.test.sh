#!/usr/bin/env bash
# Tests for validate-convention-record.sh. Run with:
#   bash plugins/agentic-core/shared/lib/validate-convention-record.test.sh
#
# No framework — exits 0 on success, 1 on first failure. assert_exit below
# compares expected vs. actual exit code per case, against fixture inputs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-convention-record.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/convention-record"

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

echo "=== validate-convention-record.sh tests ==="

echo "[accept] a well-formed convention record"
OUT=$(bash "$VALIDATOR" "$FIXDIR/valid.yaml" 2>&1); ST=$?
assert_exit "valid.yaml accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports valid" "valid" "$OUT"

echo "[reject] an empty required field"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/empty-field.yaml" 2>&1); ST=$?
assert_exit "empty-field.yaml rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the empty field" "definition_of_done" "$OUT"

echo "[reject] unknown top-level key"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/unknown-top-level-key.yaml" 2>&1); ST=$?
assert_exit "unknown-top-level-key.yaml rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the bad key" "notes" "$OUT"

echo "[usage] no argument"
OUT=$(bash "$VALIDATOR" 2>&1); ST=$?
assert_exit "no arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] file not found"
OUT=$(bash "$VALIDATOR" "$FIXDIR/does-not-exist.yaml" 2>&1); ST=$?
assert_exit "missing file -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
