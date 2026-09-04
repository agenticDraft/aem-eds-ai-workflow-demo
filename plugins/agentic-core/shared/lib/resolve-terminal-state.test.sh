#!/usr/bin/env bash
# Tests for resolve-terminal-state.sh. Run with:
#   bash plugins/agentic-core/shared/lib/resolve-terminal-state.test.sh
#
# No framework — assert_exit/assert_contains follow the same pattern as
# handle-question.test.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-terminal-state.sh"
PROGRESS_FIX="$SCRIPT_DIR/../fixtures/progress/status-table-mixed.txt"

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

echo "=== resolve-terminal-state.sh tests ==="

echo "[delivered] deliver returned pass"
OUT=$(bash "$RESOLVER" delivered "$PROGRESS_FIX" "https://example.invalid/pr/42" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports the terminal state" "terminal: delivered" "$OUT"
assert_contains "prints the status table" "| Stage | Status |" "$OUT"
assert_contains "prints the published location" "published: https://example.invalid/pr/42" "$OUT"

echo "[blocked] question unanswered / budget exhausted / pre-flight failure"
OUT=$(bash "$RESOLVER" blocked "packs.tracker is unset in project config" "work item TICKET-1 (post_note)" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports the terminal state" "terminal: blocked" "$OUT"
assert_contains "prints what is missing" "missing: packs.tracker is unset in project config" "$OUT"
assert_contains "prints where it was recorded" "recorded: work item TICKET-1 (post_note)" "$OUT"

echo "[failed] a stage returned fail, or a contract violation"
OUT=$(bash "$RESOLVER" failed implement "lint failed after 3 attempts" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "reports the terminal state" "terminal: failed" "$OUT"
assert_contains "prints the failing stage" "stage: implement" "$OUT"
assert_contains "prints its summary" "summary: lint failed after 3 attempts" "$OUT"

echo "[reject] warn is never a terminal state"
OUT=$(bash "$RESOLVER" warn implement "still working" 2>&1); ST=$?
assert_exit "warn is rejected (exit 2)" 2 $ST "$OUT"
assert_contains "reason names warn" "warn" "$OUT"

echo "[reject] an outcome outside the three terminal states"
OUT=$(bash "$RESOLVER" done implement "finished" 2>&1); ST=$?
assert_exit "unknown state is rejected (exit 2)" 2 $ST "$OUT"

echo "[usage] missing state argument"
OUT=$(bash "$RESOLVER" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] delivered missing an argument"
OUT=$(bash "$RESOLVER" delivered "$PROGRESS_FIX" 2>&1); ST=$?
assert_exit "wrong arg count -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] blocked missing an argument"
OUT=$(bash "$RESOLVER" blocked "missing thing" 2>&1); ST=$?
assert_exit "wrong arg count -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] failed missing an argument"
OUT=$(bash "$RESOLVER" failed implement 2>&1); ST=$?
assert_exit "wrong arg count -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] delivered progress file not found"
OUT=$(bash "$RESOLVER" delivered "$SCRIPT_DIR/../fixtures/progress/does-not-exist.txt" "https://example.invalid" 2>&1); ST=$?
assert_exit "missing progress file -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
