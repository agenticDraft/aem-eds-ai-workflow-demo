#!/usr/bin/env bash
# Tests for print-status-table.sh. Run with:
#   bash plugins/agentic-core/shared/lib/print-status-table.test.sh
#
# No framework — exits 0 on success, 1 on first failure. assert_exit/
# assert_contains follow the same pattern as run-stage.test.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TABLE="$SCRIPT_DIR/print-status-table.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/progress"

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
    echo "    expected:"
    echo "$expected" | sed 's/^/      /'
    echo "    got:"
    echo "$actual" | sed 's/^/      /'
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

echo "=== print-status-table.sh tests ==="

echo "[format] a mixed-status progress file"
OUT=$(bash "$TABLE" "$FIXDIR/status-table-mixed.txt" 2>&1); ST=$?
EXPECTED="| Stage | Status |
| --- | --- |
| intake | done |
| plan | done |
| plan-gate | skipped |
| implement | running |
| publish-gate | pending |
| deliver | pending |"
assert_exit "exits 0" 0 $ST "$OUT"
assert_equals "renders one row per stage, in file order" "$EXPECTED" "$OUT"

echo "[single-emission] one invocation prints the table exactly once"
OUT=$(bash "$TABLE" "$FIXDIR/status-table-mixed.txt" 2>&1)
COUNT=$(grep -c '^| Stage | Status |$' <<< "$OUT")
assert_equals "the header line appears exactly once" "1" "$COUNT"

echo "[reject] unknown status literal"
OUT=$(bash "$TABLE" "$FIXDIR/status-table-invalid-status.txt" 2>&1); ST=$?
assert_exit "status outside done|skipped|failed|running|pending -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] missing argument"
OUT=$(bash "$TABLE" 2>&1); ST=$?
assert_exit "no arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] progress file not found"
OUT=$(bash "$TABLE" "$FIXDIR/does-not-exist.txt" 2>&1); ST=$?
assert_exit "missing file -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
