#!/usr/bin/env bash
# Tests for check-run-state.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-run-state.test.sh
#
# No framework — exits 0 on success, 1 on first failure. mtime-dependent
# fixtures are built and backdated here rather than committed, since git
# does not preserve mtime meaningfully.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/check-run-state.sh"
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

TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/check-run-state-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

backdate() {
  local file="$1" seconds_ago="$2"
  local ts=$(( $(date +%s) - seconds_ago ))
  local stamp
  stamp="$(date -r "$ts" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$ts" +%Y%m%d%H%M.%S)"
  touch -t "$stamp" "$file"
}

echo "=== check-run-state.sh tests ==="

echo "[none] no state file exists"
OUT=$(bash "$CHECKER" "$TMPDIR_TEST/no-such-file.json" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports status: none" "status: none" "$OUT"

echo "[resume] a state file well within the 2-hour window"
FRESH="$TMPDIR_TEST/fresh.json"
bash "$WRITER" "$FRESH" standard "default: standard" implement 6 interactive 1 "2026-09-04T10:00:00Z" >/dev/null
backdate "$FRESH" 3600   # 1 hour old
OUT=$(bash "$CHECKER" "$FRESH" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports status: resume" "status: resume" "$OUT"
assert_contains "reports last_stage" "last_stage: implement" "$OUT"
assert_contains "reports total" "total: 6" "$OUT"
assert_contains "reports route_id" "route_id: standard" "$OUT"
assert_contains "reports rule" "rule: default: standard" "$OUT"
assert_contains "reports mode" "mode: interactive" "$OUT"
assert_contains "reports questions_used" "questions_used: 1" "$OUT"
assert_contains "reports start_time" "start_time: 2026-09-04T10:00:00Z" "$OUT"
[[ -f "$FRESH" ]] && { PASS=$((PASS + 1)); echo "  ok: a resumable file is not deleted"; } \
  || { FAIL=$((FAIL + 1)); echo "  FAIL: a resumable file must survive the check"; }

echo "[resume] just under the 2-hour boundary (7199s)"
BOUNDARY="$TMPDIR_TEST/boundary-fresh.json"
bash "$WRITER" "$BOUNDARY" standard "default: standard" implement 6 interactive 0 "2026-09-04T10:00:00Z" >/dev/null
backdate "$BOUNDARY" 7199
OUT=$(bash "$CHECKER" "$BOUNDARY" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "7199s old still resumes" "status: resume" "$OUT"

echo "[stale] a state file at or past the 2-hour window is deleted"
STALE="$TMPDIR_TEST/stale.json"
bash "$WRITER" "$STALE" standard "default: standard" plan 6 interactive 0 "2026-09-04T06:00:00Z" >/dev/null
backdate "$STALE" 7200   # exactly 2 hours old
OUT=$(bash "$CHECKER" "$STALE" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports status: stale-deleted" "status: stale-deleted" "$OUT"
[[ -f "$STALE" ]] && { FAIL=$((FAIL + 1)); echo "  FAIL: stale state file must be deleted"; } \
  || { PASS=$((PASS + 1)); echo "  ok: stale state file deleted"; }

echo "[stale] well past the window (3 hours)"
OLDER="$TMPDIR_TEST/older.json"
bash "$WRITER" "$OLDER" standard "default: standard" plan 6 interactive 0 "2026-09-04T06:00:00Z" >/dev/null
backdate "$OLDER" 10800
OUT=$(bash "$CHECKER" "$OLDER" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports status: stale-deleted" "status: stale-deleted" "$OUT"

echo "[reject] malformed state file"
BAD="$TMPDIR_TEST/malformed.json"
echo '{ not json at all' > "$BAD"
OUT=$(bash "$CHECKER" "$BAD" 2>&1); ST=$?
assert_exit "malformed state file rejected (exit 1)" 1 $ST "$OUT"

echo "[usage] missing argument"
OUT=$(bash "$CHECKER" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
