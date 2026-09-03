#!/usr/bin/env bash
# Tests for print-progress-line.sh. Run with:
#   bash plugins/agentic-core/shared/lib/print-progress-line.test.sh
#
# No framework — exits 0 on success, 1 on first failure. assert_exit/
# assert_contains follow the same pattern as run-stage.test.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRINTER="$SCRIPT_DIR/print-progress-line.sh"
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
    echo "    expected: $expected"
    echo "    got:      $actual"
  fi
}

echo "=== print-progress-line.sh tests ==="

echo "[format] the first stage of a six-stage route, no skips"
OUT=$(bash "$PRINTER" "$FIXDIR/route-no-skip.txt" intake pass "Fetched the work item." 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_equals "prints the exact line format" \
  "Stage 1/6: intake — pass · Fetched the work item." "$OUT"

echo "[format] a mid-route stage, no skips"
OUT=$(bash "$PRINTER" "$FIXDIR/route-no-skip.txt" implement warn "Implemented with one caveat." 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_equals "position counts all preceding stages" \
  "Stage 4/6: implement — warn · Implemented with one caveat." "$OUT"

echo "[format] the last stage of the route"
OUT=$(bash "$PRINTER" "$FIXDIR/route-no-skip.txt" deliver pass "Published." 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_equals "n equals total on the last stage" \
  "Stage 6/6: deliver — pass · Published." "$OUT"

echo "[recompute] a route with one stage marked skipped"
OUT=$(bash "$PRINTER" "$FIXDIR/route-with-skip.txt" implement pass "Implemented the change." 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_equals "total excludes the skipped stage; position does too" \
  "Stage 3/5: implement — pass · Implemented the change." "$OUT"

OUT=$(bash "$PRINTER" "$FIXDIR/route-with-skip.txt" deliver pass "Published." 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_equals "the counter never lies: total stays 5, not the stale 6" \
  "Stage 5/5: deliver — pass · Published." "$OUT"

echo "[recompute] a route with two stages marked skipped"
OUT=$(bash "$PRINTER" "$FIXDIR/route-multi-skip.txt" deliver pass "Published." 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_equals "total drops by one per skip" \
  "Stage 4/4: deliver — pass · Published." "$OUT"

echo "[verdict] question is a valid literal"
OUT=$(bash "$PRINTER" "$FIXDIR/route-no-skip.txt" plan-gate question "Needs a scope call." 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_equals "prints the question verdict verbatim" \
  "Stage 3/6: plan-gate — question · Needs a scope call." "$OUT"

echo "[reject] stage id absent from the route file"
OUT=$(bash "$PRINTER" "$FIXDIR/route-no-skip.txt" no-such-stage pass "x" 2>&1); ST=$?
assert_exit "unresolvable stage id -> usage error (exit 2)" 2 $ST "$OUT"

echo "[reject] stage id present but marked skipped"
OUT=$(bash "$PRINTER" "$FIXDIR/route-with-skip.txt" plan-gate pass "x" 2>&1); ST=$?
assert_exit "printing a completion for a skipped stage -> usage error (exit 2)" 2 $ST "$OUT"

echo "[reject] unknown verdict literal"
OUT=$(bash "$PRINTER" "$FIXDIR/route-no-skip.txt" intake done "x" 2>&1); ST=$?
assert_exit "verdict outside pass|warn|fail|question -> usage error (exit 2)" 2 $ST "$OUT"

echo "[reject] empty summary"
OUT=$(bash "$PRINTER" "$FIXDIR/route-no-skip.txt" intake pass "" 2>&1); ST=$?
assert_exit "empty summary -> usage error (exit 2)" 2 $ST "$OUT"

echo "[reject] summary exceeding 200 characters"
LONG=$(printf 'a%.0s' {1..201})
OUT=$(bash "$PRINTER" "$FIXDIR/route-no-skip.txt" intake pass "$LONG" 2>&1); ST=$?
assert_exit "over-length summary -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] missing arguments"
OUT=$(bash "$PRINTER" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] route file not found"
OUT=$(bash "$PRINTER" "$FIXDIR/does-not-exist.txt" intake pass "x" 2>&1); ST=$?
assert_exit "missing route file -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
