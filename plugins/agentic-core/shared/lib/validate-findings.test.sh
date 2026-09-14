#!/usr/bin/env bash
# Tests for validate-findings.sh. Run with:
#   bash plugins/agentic-core/shared/lib/validate-findings.test.sh
#
# No framework — exits 0 on success, 1 on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/validate-findings.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/audit-taxonomy"

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3" output="$4"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected exit=$expected, got exit=$actual"
    [[ -n "$output" ]] && echo "    output: $output"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected to contain: $needle"
    echo "    got: $haystack"
  fi
}

echo "=== validate-findings.sh tests ==="

echo "[valid] all four classes, both severities"
OUT=$(bash "$SCRIPT" "$FIXDIR/valid.yaml" 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_contains "reports 4 entries" "4 entries" "$OUT"

echo "[valid] an empty findings list is a normal result"
OUT=$(bash "$SCRIPT" "$FIXDIR/empty.yaml" 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_contains "reports 0 entries" "0 entries" "$OUT"

for f in no-diff unknown-class unknown-severity judgment-missing-default \
         needs-the-human-missing-question mechanical-with-question duplicate-id; do
  echo "[invalid] $f"
  OUT=$(bash "$SCRIPT" "$FIXDIR/invalid/$f.yaml" 2>&1); ST=$?
  assert_exit "$f -> contract violation (exit 1)" 1 $ST "$OUT"
done

echo "[usage] file not found"
OUT=$(bash "$SCRIPT" "$FIXDIR/does-not-exist.yaml" 2>&1); ST=$?
assert_exit "missing file -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] no argument"
OUT=$(bash "$SCRIPT" 2>&1); ST=$?
assert_exit "no argument -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
