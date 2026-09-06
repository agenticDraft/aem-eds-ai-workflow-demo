#!/usr/bin/env bash
# Tests for finalize-orchestration-flag.sh. Run with:
#   bash plugins/agentic-core/shared/lib/finalize-orchestration-flag.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FINALIZER="$SCRIPT_DIR/finalize-orchestration-flag.sh"
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

TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/finalize-orchestration-flag-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== finalize-orchestration-flag.sh tests ==="

echo "[deleted] marker exists"
FLAG="$TMPDIR_TEST/orchestrating.flag"
bash "$WRITER" "$FLAG" >/dev/null
OUT=$(bash "$FINALIZER" "$FLAG" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports status: deleted" "status: deleted" "$OUT"
[[ -f "$FLAG" ]] && { FAIL=$((FAIL + 1)); echo "  FAIL: marker must be removed"; } \
  || { PASS=$((PASS + 1)); echo "  ok: marker removed"; }

echo "[not-found] marker already absent — idempotent"
OUT=$(bash "$FINALIZER" "$FLAG" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports status: not-found" "status: not-found" "$OUT"

echo "[not-found] a terminal state that never had a marker at all"
OUT=$(bash "$FINALIZER" "$TMPDIR_TEST/never-existed.flag" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports status: not-found" "status: not-found" "$OUT"

echo "[usage] missing argument"
OUT=$(bash "$FINALIZER" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
