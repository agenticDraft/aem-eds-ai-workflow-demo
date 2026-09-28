#!/usr/bin/env bash
# Tests for check-fix-budget-readers.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-fix-budget-readers.test.sh
#
# No framework — assert_exit/assert_contains follow the same pattern as
# check-fix-budget.test.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-fix-budget-readers.sh"
FIX="$SCRIPT_DIR/../fixtures/fix-budget-readers"

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

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected output not to contain: $needle"
    echo "    got: $haystack"
  fi
}

echo "=== check-fix-budget-readers.sh tests ==="

echo "[pass] a declared stage whose skill invokes the script in a fenced block"
OUT=$(bash "$CHECK" "$FIX/read" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "says valid" "valid:" "$OUT"
assert_contains "counts the one declared stage" "1 declared" "$OUT"

echo "[fail] a declared stage whose skill never names the script"
OUT=$(bash "$CHECK" "$FIX/unread" 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "names the stage" "'serve'" "$OUT"
assert_contains "says why" "never invokes check-fix-budget.sh" "$OUT"

echo "[pass] an undeclared stage that asks the script is allowed"
OUT=$(bash "$CHECK" "$FIX/undeclared-asks" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "counts no declared stage" "0 declared" "$OUT"

echo "[fail] a declared stage whose skill file is missing"
OUT=$(bash "$CHECK" "$FIX/missing-skill" 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "names the stage" "'lint'" "$OUT"
assert_contains "says the file is missing" "not found" "$OUT"

echo "[fail] naming the script in prose or inline code is not an invocation"
OUT=$(bash "$CHECK" "$FIX/prose-only" 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "names the stage" "'verify-design'" "$OUT"

echo "[fail] every unread stage is named, and only those"
OUT=$(bash "$CHECK" "$FIX/mixed" 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "names serve" "'serve'" "$OUT"
assert_contains "names verify-design" "'verify-design'" "$OUT"
assert_not_contains "does not name lint, which reads it" "'lint'" "$OUT"
assert_not_contains "does not name plan, which declares none" "'plan'" "$OUT"

echo "[scope] only the stages list is read — an artifact sharing a stage's id is not a stage"
OUT=$(bash "$CHECK" "$FIX/mixed" 2>&1)
assert_not_contains "the artifact entry 'lint-report' is not reported" "lint-report" "$OUT"

echo "[usage] wrong argument count, missing directory or manifest"
OUT=$(bash "$CHECK" 2>&1); ST=$?
assert_exit "no argument exits 2" 2 $ST "$OUT"
OUT=$(bash "$CHECK" "$FIX/read" extra 2>&1); ST=$?
assert_exit "two arguments exits 2" 2 $ST "$OUT"
OUT=$(bash "$CHECK" "$FIX/nope" 2>&1); ST=$?
assert_exit "missing pack root exits 2" 2 $ST "$OUT"
OUT=$(bash "$CHECK" "$FIX" 2>&1); ST=$?
assert_exit "a directory with no pack.yaml exits 2" 2 $ST "$OUT"

echo ""
echo "passed: $PASS, failed: $FAIL"
(( FAIL == 0 ))
