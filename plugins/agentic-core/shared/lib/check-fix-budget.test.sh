#!/usr/bin/env bash
# Tests for check-fix-budget.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-fix-budget.test.sh
#
# No framework — assert_exit/assert_contains follow the same pattern as
# handle-question.test.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-fix-budget.sh"
FIX="$SCRIPT_DIR/../fixtures/fix-budget"
PACK="$FIX/pack.yaml"
CONFIG="$FIX/config.yaml"

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

echo "=== check-fix-budget.sh tests ==="

echo "[edit] fix_attempts: 2 allows an edit after the first check"
OUT=$(bash "$CHECK" "$PACK" "$CONFIG" verify-design 0 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "decides edit" "decision: edit" "$OUT"
assert_contains "reports the budget it read" "fix_attempts: 2" "$OUT"
assert_contains "names the stage's own value as the source" "source: stage" "$OUT"

echo "[edit] fix_attempts: 2 allows a second edit after one"
OUT=$(bash "$CHECK" "$PACK" "$CONFIG" verify-design 1 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "decides edit" "decision: edit" "$OUT"
assert_contains "reports one edit left after this one" "edits_left_after: 0" "$OUT"

echo "[exhausted] fix_attempts: 2 is spent after two edits"
OUT=$(bash "$CHECK" "$PACK" "$CONFIG" verify-design 2 2>&1); ST=$?
assert_exit "exits 4" 4 $ST "$OUT"
assert_contains "decides exhausted" "decision: exhausted" "$OUT"

echo "[exhausted] a count beyond the budget is still exhausted, not an error"
OUT=$(bash "$CHECK" "$PACK" "$CONFIG" verify-design 5 2>&1); ST=$?
assert_exit "exits 4" 4 $ST "$OUT"

echo "[edit] fix_attempts: 3 allows a third edit"
OUT=$(bash "$CHECK" "$PACK" "$CONFIG" lint 2 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "decides edit" "decision: edit" "$OUT"

echo "[exhausted] fix_attempts: 3 is spent after three edits"
OUT=$(bash "$CHECK" "$PACK" "$CONFIG" lint 3 2>&1); ST=$?
assert_exit "exits 4" 4 $ST "$OUT"

echo "[exhausted] fix_attempts: 1 is spent after one edit"
OUT=$(bash "$CHECK" "$PACK" "$CONFIG" plan 1 2>&1); ST=$?
assert_exit "exits 4" 4 $ST "$OUT"
OUT=$(bash "$CHECK" "$PACK" "$CONFIG" plan 0 2>&1); ST=$?
assert_exit "fix_attempts: 1 allows the one edit" 0 $ST "$OUT"

echo "[default] a stage with no fix_attempts reads limits.fix_attempts_default"
OUT=$(bash "$CHECK" "$PACK" "$CONFIG" implement 3 2>&1); ST=$?
assert_exit "exits 0 below the default of 4" 0 $ST "$OUT"
assert_contains "reports the default" "fix_attempts: 4" "$OUT"
assert_contains "names the default as the source" "source: default" "$OUT"
OUT=$(bash "$CHECK" "$PACK" "$CONFIG" implement 4 2>&1); ST=$?
assert_exit "exits 4 at the default" 4 $ST "$OUT"

echo "[default] a stage's own value wins over the default"
OUT=$(bash "$CHECK" "$PACK" "$CONFIG" plan 1 2>&1); ST=$?
assert_exit "exits 4 at 1 edit though the default is 4" 4 $ST "$OUT"

echo "[reject] a malformed edits-made count is a contract violation"
for bad in -1 x 1.5 "" " 1" 08 01; do
  OUT=$(bash "$CHECK" "$PACK" "$CONFIG" lint "$bad" 2>&1); ST=$?
  assert_exit "edits-made '$bad' exits 1" 1 $ST "$OUT"
  assert_contains "edits-made '$bad' says terminate-contract-violation" "decision: terminate-contract-violation" "$OUT"
done

echo "[reject] a malformed fix_attempts in the pack is a contract violation"
OUT=$(bash "$CHECK" "$PACK" "$CONFIG" verify 0 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "names the field" "fix_attempts" "$OUT"

echo "[exhausted] a default of 0 is valid config and allows no edit"
OUT=$(bash "$CHECK" "$PACK" "$FIX/config-zero-default.yaml" implement 0 2>&1); ST=$?
assert_exit "exits 4" 4 $ST "$OUT"
assert_contains "decides exhausted" "decision: exhausted" "$OUT"

echo "[reject] a malformed default is a contract violation"
OUT=$(bash "$CHECK" "$PACK" "$FIX/config-bad-default.yaml" implement 0 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "names the field" "fix_attempts_default" "$OUT"

echo "[reject] no stage value and no default is a contract violation"
OUT=$(bash "$CHECK" "$PACK" "$FIX/config-no-default.yaml" implement 0 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"

echo "[ok] no default needed when the stage carries its own value"
OUT=$(bash "$CHECK" "$PACK" "$FIX/config-no-default.yaml" lint 0 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"

echo "[reject] a stage id the pack does not declare is a contract violation"
OUT=$(bash "$CHECK" "$PACK" "$CONFIG" prototype 0 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "names the stage" "prototype" "$OUT"

echo "[reject] the id is matched whole, not as a prefix"
OUT=$(bash "$CHECK" "$PACK" "$CONFIG" verify-desig 0 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"

echo "[scope] only the stages list is read — an artifact sharing a stage's id is not a stage"
OUT=$(bash "$CHECK" "$PACK" "$CONFIG" plan 0 2>&1); ST=$?
assert_exit "plan still reads its own fix_attempts: 1" 0 $ST "$OUT"
assert_contains "reports 1, not a contract violation" "fix_attempts: 1" "$OUT"
OUT=$(bash "$CHECK" "$PACK" "$CONFIG" prototype 0 2>&1); ST=$?
assert_exit "an id that is only an artifact is not a declared stage" 1 $ST "$OUT"

echo "[usage] wrong argument count or missing file"
OUT=$(bash "$CHECK" "$PACK" "$CONFIG" lint 2>&1); ST=$?
assert_exit "three arguments exits 2" 2 $ST "$OUT"
OUT=$(bash "$CHECK" "$FIX/nope.yaml" "$CONFIG" lint 0 2>&1); ST=$?
assert_exit "missing pack exits 2" 2 $ST "$OUT"
OUT=$(bash "$CHECK" "$PACK" "$FIX/nope.yaml" lint 0 2>&1); ST=$?
assert_exit "missing config exits 2" 2 $ST "$OUT"

echo ""
echo "passed: $PASS, failed: $FAIL"
(( FAIL == 0 ))
