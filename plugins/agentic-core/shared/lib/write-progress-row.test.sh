#!/usr/bin/env bash
# Tests for write-progress-row.sh. Run with:
#   bash plugins/agentic-core/shared/lib/write-progress-row.test.sh
#
# No framework — exits 0 on success, 1 on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/write-progress-row.sh"
TABLE="$SCRIPT_DIR/print-status-table.sh"

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

assert_file_equals() {
  local desc="$1" expected="$2" path="$3"
  local actual
  actual="$(cat "$path" 2>/dev/null || echo "<no file>")"
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    --- expected ---"
    echo "$expected"
    echo "    --- actual ---"
    echo "$actual"
  fi
}

TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/write-progress-row-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== write-progress-row.sh tests ==="

echo "[create] first row creates the file"
PROGRESS="$TMPDIR_TEST/progress.md"
OUT=$(bash "$WRITER" "$PROGRESS" intake pending 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports written" "written" "$OUT"
assert_file_equals "file has exactly the one row" "intake: pending" "$PROGRESS"

echo "[append] a new stage id is appended in call order"
OUT=$(bash "$WRITER" "$PROGRESS" plan pending 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports updated" "updated" "$OUT"
assert_file_equals "second row appended after the first" "intake: pending
plan: pending" "$PROGRESS"

echo "[transition] updating an existing stage's status replaces it in place"
OUT=$(bash "$WRITER" "$PROGRESS" intake running 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_file_equals "intake's row updated, plan's row and order untouched" "intake: running
plan: pending" "$PROGRESS"

OUT=$(bash "$WRITER" "$PROGRESS" intake done 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_file_equals "intake transitions to done without duplicating the row" "intake: done
plan: pending" "$PROGRESS"

echo "[compose] the written file is valid input to print-status-table.sh"
bash "$WRITER" "$PROGRESS" plan-gate skipped >/dev/null
bash "$WRITER" "$PROGRESS" implement failed >/dev/null
OUT=$(bash "$TABLE" "$PROGRESS" 2>&1); ST=$?
assert_exit "print-status-table.sh accepts it (exit 0)" 0 $ST "$OUT"
assert_contains "table includes a row this script wrote" "| implement | failed |" "$OUT"

echo "[reject] status outside the five literals"
OUT=$(bash "$WRITER" "$PROGRESS" intake bogus 2>&1); ST=$?
assert_exit "unknown status -> usage error (exit 2)" 2 $ST "$OUT"

echo "[reject] stage id with characters outside the route-id charset"
OUT=$(bash "$WRITER" "$PROGRESS" "bad id" pending 2>&1); ST=$?
assert_exit "invalid stage id -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] missing arguments"
OUT=$(bash "$WRITER" "$PROGRESS" intake 2>&1); ST=$?
assert_exit "missing status -> usage error (exit 2)" 2 $ST "$OUT"

echo "[create] parent directory does not exist yet — script creates it"
NESTED="$TMPDIR_TEST/nested/dir/progress.md"
OUT=$(bash "$WRITER" "$NESTED" intake pending 2>&1); ST=$?
assert_exit "create under a missing parent directory succeeds (exit 0)" 0 $ST "$OUT"
[[ -f "$NESTED" ]] && { PASS=$((PASS + 1)); echo "  ok: file exists under the newly created parent directory"; } \
  || { FAIL=$((FAIL + 1)); echo "  FAIL: file was not created"; }

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
