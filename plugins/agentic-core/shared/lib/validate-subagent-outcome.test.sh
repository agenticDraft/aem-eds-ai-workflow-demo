#!/usr/bin/env bash
# Tests for validate-subagent-outcome.sh. Run with:
#   bash plugins/agentic-core/shared/lib/validate-subagent-outcome.test.sh
#
# No framework — exits 0 on success, 1 on first failure. assert_exit below
# compares expected vs. actual exit code per case, against fixture inputs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-subagent-outcome.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/subagent-outcome"

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

echo "=== validate-subagent-outcome.sh tests ==="

echo "[accept] the three status fixtures"
for status in success warning failure; do
  OUT=$(bash "$VALIDATOR" "$FIXDIR/$status.md" 2>&1); ST=$?
  assert_exit "$status.md accepted (exit 0)" 0 $ST "$OUT"
  assert_contains "$status.md reports its own status" "status: $status" "$OUT"
done

echo "[reject] unknown status literal"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/unknown-status.md" 2>&1); ST=$?
assert_exit "unknown status rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the bad literal" "done" "$OUT"

echo "[reject] a result-envelope verdict used as this contract's status"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/outer-literal.md" 2>&1); ST=$?
assert_exit "outer literal rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names it as a result-envelope verdict" "result-envelope verdict" "$OUT"

echo "[reject] multi-line summary"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/multiline-summary.md" 2>&1); ST=$?
assert_exit "multi-line summary rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] missing artifacts list"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/missing-artifacts.md" 2>&1); ST=$?
assert_exit "missing artifacts list rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] text after the block"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/trailing-text.md" 2>&1); ST=$?
assert_exit "trailing text rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] status: failure with no blocker"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/missing-blocker.md" 2>&1); ST=$?
assert_exit "missing blocker rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] blocker present without status: failure"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/blocker-without-failure.md" 2>&1); ST=$?
assert_exit "unearned blocker rejected (exit 1)" 1 $ST "$OUT"

echo "[usage] no argument"
OUT=$(bash "$VALIDATOR" 2>&1); ST=$?
assert_exit "no arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] file not found"
OUT=$(bash "$VALIDATOR" "$FIXDIR/does-not-exist.md" 2>&1); ST=$?
assert_exit "missing file -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
