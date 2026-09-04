#!/usr/bin/env bash
# Tests for check-plan-criteria.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-plan-criteria.test.sh
#
# No framework — exits 0 on success, 1 on first failure. Confirms: a clean
# plan (every requirement mapped, every stage requested) passes; a plan
# missing a stage for one requirement fails naming that requirement; a plan
# containing a stage no requirement asked for fails naming that stage,
# whether the stage names an unknown requirement or an empty list; two
# requirements sharing an id fail; and the two usage errors.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-plan-criteria.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/plan-criteria"

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

echo "=== check-plan-criteria.sh tests ==="

echo "[accept] a clean plan — every requirement mapped, every stage requested"
OUT=$(bash "$CHECK" "$FIXDIR/clean.yaml" 2>&1); ST=$?
assert_exit "clean.yaml accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports counts" "valid: plan (2 requirements, 2 stages)" "$OUT"

echo "[reject] a requirement with no stage satisfying it"
OUT=$(bash "$CHECK" "$FIXDIR/invalid/missing-stage-for-requirement.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unmapped requirement" "'req-logging'" "$OUT"
assert_contains "reason says no stage" "maps to no stage" "$OUT"

echo "[reject] a stage satisfying a requirement that does not exist"
OUT=$(bash "$CHECK" "$FIXDIR/invalid/unrequested-stage.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unrequested stage" "'implement-metrics'" "$OUT"
assert_contains "reason says unrequested" "unrequested" "$OUT"

echo "[reject] a stage with no requirement in its 'satisfies' list"
OUT=$(bash "$CHECK" "$FIXDIR/invalid/empty-satisfies.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unrequested stage" "'unrelated-cleanup'" "$OUT"

echo "[reject] two requirements sharing an id"
OUT=$(bash "$CHECK" "$FIXDIR/invalid/duplicate-requirement.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the duplicate" "duplicate requirement id" "$OUT"

echo "[usage] no argument"
OUT=$(bash "$CHECK" 2>&1); ST=$?
assert_exit "no arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] file not found"
OUT=$(bash "$CHECK" "$FIXDIR/does-not-exist.yaml" 2>&1); ST=$?
assert_exit "missing file -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
