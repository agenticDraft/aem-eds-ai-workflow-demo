#!/usr/bin/env bash
# Tests for check-orchestration-flag.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-orchestration-flag.test.sh
#
# mtime-dependent fixtures are built and backdated here rather than
# committed, since git does not preserve mtime meaningfully — the same
# practice check-run-state.test.sh follows.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/check-orchestration-flag.sh"
WRITER="$SCRIPT_DIR/write-orchestration-flag.sh"

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

TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/check-orchestration-flag-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

backdate() {
  local file="$1" seconds_ago="$2"
  local ts=$(( $(date +%s) - seconds_ago ))
  local stamp
  stamp="$(date -r "$ts" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$ts" +%Y%m%d%H%M.%S)"
  touch -t "$stamp" "$file"
}

echo "=== check-orchestration-flag.sh tests ==="

echo "[none] no marker exists"
OUT=$(bash "$CHECKER" "$TMPDIR_TEST/no-such-file.flag" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports status: none" "status: none" "$OUT"

echo "[fresh] a marker well within the 2-hour window"
FRESH="$TMPDIR_TEST/fresh.flag"
bash "$WRITER" "$FRESH" >/dev/null
backdate "$FRESH" 3600   # 1 hour old
OUT=$(bash "$CHECKER" "$FRESH" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports status: fresh" "status: fresh" "$OUT"
[[ -f "$FRESH" ]] && { PASS=$((PASS + 1)); echo "  ok: a fresh marker is not deleted"; } \
  || { FAIL=$((FAIL + 1)); echo "  FAIL: a fresh marker must survive the check"; }

echo "[fresh] just under the 2-hour boundary (7199s)"
BOUNDARY="$TMPDIR_TEST/boundary-fresh.flag"
bash "$WRITER" "$BOUNDARY" >/dev/null
backdate "$BOUNDARY" 7199
OUT=$(bash "$CHECKER" "$BOUNDARY" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "7199s old still fresh" "status: fresh" "$OUT"

echo "[stale] a marker at or past the 2-hour window is deleted"
STALE="$TMPDIR_TEST/stale.flag"
bash "$WRITER" "$STALE" >/dev/null
backdate "$STALE" 7200   # exactly 2 hours old
OUT=$(bash "$CHECKER" "$STALE" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports status: stale-deleted" "status: stale-deleted" "$OUT"
[[ -f "$STALE" ]] && { FAIL=$((FAIL + 1)); echo "  FAIL: stale marker must be deleted"; } \
  || { PASS=$((PASS + 1)); echo "  ok: stale marker deleted"; }

echo "[stale] well past the window (3 hours)"
OLDER="$TMPDIR_TEST/older.flag"
bash "$WRITER" "$OLDER" >/dev/null
backdate "$OLDER" 10800
OUT=$(bash "$CHECKER" "$OLDER" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports status: stale-deleted" "status: stale-deleted" "$OUT"

echo "[usage] missing argument"
OUT=$(bash "$CHECKER" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
