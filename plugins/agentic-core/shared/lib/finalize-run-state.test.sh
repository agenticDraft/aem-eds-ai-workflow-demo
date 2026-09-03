#!/usr/bin/env bash
# Tests for finalize-run-state.sh. Run with:
#   bash plugins/agentic-core/shared/lib/finalize-run-state.test.sh
#
# No framework — exits 0 on success, 1 on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FINALIZER="$SCRIPT_DIR/finalize-run-state.sh"

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

TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/finalize-run-state-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== finalize-run-state.sh tests ==="

echo "[delete] an existing state file is removed on a successful terminal state"
STATE="$TMPDIR_TEST/run-state.json"
echo '{}' > "$STATE"
OUT=$(bash "$FINALIZER" "$STATE" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports status: deleted" "status: deleted" "$OUT"
[[ -f "$STATE" ]] && { FAIL=$((FAIL + 1)); echo "  FAIL: file must be gone"; } \
  || { PASS=$((PASS + 1)); echo "  ok: file is gone"; }

echo "[idempotent] finalizing a run with no state file is not an error"
OUT=$(bash "$FINALIZER" "$TMPDIR_TEST/never-existed.json" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports status: not-found" "status: not-found" "$OUT"

echo "[usage] missing argument"
OUT=$(bash "$FINALIZER" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
