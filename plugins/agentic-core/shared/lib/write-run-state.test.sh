#!/usr/bin/env bash
# Tests for write-run-state.sh. Run with:
#   bash plugins/agentic-core/shared/lib/write-run-state.test.sh
#
# No framework — exits 0 on success, 1 on first failure. Mirrors the harness
# in write-detected-config.test.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/write-run-state.sh"

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

TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/write-run-state-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== write-run-state.sh tests ==="

echo "[create] fresh file gets all seven fields"
STATE="$TMPDIR_TEST/run-state.json"
OUT=$(bash "$WRITER" "$STATE" standard "default: standard" implement 6 interactive 0 "2026-09-04T10:00:00Z" 2>&1); ST=$?
assert_exit "fresh create succeeds (exit 0)" 0 $ST "$OUT"
assert_contains "reports the path written" "$STATE" "$OUT"
for pair in '"route_id": "standard"' '"rule": "default: standard"' '"last_stage": "implement"' \
            '"total": 6' '"mode": "interactive"' '"questions_used": 0' \
            '"start_time": "2026-09-04T10:00:00Z"'; do
  assert_contains "file contains $pair" "$pair" "$(cat "$STATE")"
done

echo "[create] parent directory does not exist yet — script creates it"
NESTED="$TMPDIR_TEST/nested/dir/run-state.json"
OUT=$(bash "$WRITER" "$NESTED" standard "default: standard" intake 6 interactive 0 "2026-09-04T10:00:00Z" 2>&1); ST=$?
assert_exit "create under a missing parent directory succeeds (exit 0)" 0 $ST "$OUT"
[[ -f "$NESTED" ]] && { PASS=$((PASS + 1)); echo "  ok: file exists under the newly created parent directory"; } \
  || { FAIL=$((FAIL + 1)); echo "  FAIL: file was not created"; }

echo "[refresh] rewriting an existing file updates its mtime"
OLD_TS=$(( $(date +%s) - 10000 ))
touch -t "$(date -r "$OLD_TS" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$OLD_TS" +%Y%m%d%H%M.%S)" "$STATE"
OUT=$(bash "$WRITER" "$STATE" standard "default: standard" deliver 6 interactive 1 "2026-09-04T10:00:00Z" 2>&1); ST=$?
assert_exit "rewrite succeeds (exit 0)" 0 $ST "$OUT"
NEW_MTIME=$(date -r "$STATE" +%s 2>/dev/null)
NOW=$(date +%s)
AGE=$(( NOW - NEW_MTIME ))
if (( AGE < 60 )); then
  PASS=$((PASS + 1)); echo "  ok: mtime refreshed to now (age ${AGE}s)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: mtime not refreshed (age ${AGE}s)"
fi

echo "[reject] total is not an integer"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/bad-total.json" standard "default: standard" implement six interactive 0 "2026-09-04T10:00:00Z" 2>&1); ST=$?
assert_exit "non-integer total rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names total" "total" "$OUT"

echo "[reject] questions_used is not an integer"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/bad-questions.json" standard "default: standard" implement 6 interactive zero "2026-09-04T10:00:00Z" 2>&1); ST=$?
assert_exit "non-integer questions_used rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names questions_used" "questions_used" "$OUT"

echo "[reject] mode outside interactive|autonomous"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/bad-mode.json" standard "default: standard" implement 6 curious 0 "2026-09-04T10:00:00Z" 2>&1); ST=$?
assert_exit "unknown mode rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names mode" "mode" "$OUT"

echo "[reject] a string field containing a double quote"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/bad-quote.json" 'standard"' "default: standard" implement 6 interactive 0 "2026-09-04T10:00:00Z" 2>&1); ST=$?
assert_exit "quote-containing value rejected (exit 1)" 1 $ST "$OUT"

echo "[usage] wrong argument count"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/x.json" only-one-value 2>&1); ST=$?
assert_exit "wrong arg count -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
