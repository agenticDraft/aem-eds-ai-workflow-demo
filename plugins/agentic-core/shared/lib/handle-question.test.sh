#!/usr/bin/env bash
# Tests for handle-question.sh. Run with:
#   bash plugins/agentic-core/shared/lib/handle-question.test.sh
#
# No framework — assert_exit/assert_contains follow the same pattern as
# run-stage.test.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HANDLER="$SCRIPT_DIR/handle-question.sh"
PACKFIX="$SCRIPT_DIR/../fixtures/pack-manifest/platform-valid/pack.yaml"
ENVFIX="$SCRIPT_DIR/../fixtures/result-envelope"

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

echo "=== handle-question.sh tests ==="

echo "[ask] interactive mode, budget available, non-always-autonomous stage"
OUT=$(bash "$HANDLER" "$PACKFIX" interactive intake "$ENVFIX/question.md" 0 1 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "decides to ask" "decision: ask" "$OUT"
assert_contains "carries the question text" "question: Which pack should own the tracker role for this project?" "$OUT"
assert_contains "carries the first option" "  - Use the pack already declared for scm" "$OUT"
assert_contains "carries the second option" "  - List available tracker packs" "$OUT"
assert_contains "reports the incremented budget" "questions_used: 1" "$OUT"

echo "[terminate-blocked] interactive mode, budget exhausted"
OUT=$(bash "$HANDLER" "$PACKFIX" interactive intake "$ENVFIX/question.md" 1 1 2>&1); ST=$?
assert_exit "exits 4" 4 $ST "$OUT"
assert_contains "decides to terminate as blocked" "decision: terminate-blocked" "$OUT"
assert_contains "reason names the exhausted budget" "budget exhausted" "$OUT"

echo "[terminate-blocked] autonomous mode writes the blocker back, never asks"
OUT=$(bash "$HANDLER" "$PACKFIX" autonomous intake "$ENVFIX/question.md" 0 5 2>&1); ST=$?
assert_exit "exits 4" 4 $ST "$OUT"
assert_contains "decides to terminate as blocked" "decision: terminate-blocked" "$OUT"
assert_contains "carries the blocker to write back" "write-blocker: packs.tracker is unset in project config" "$OUT"
if [[ "$OUT" == *"decision: ask"* ]]; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: autonomous mode must never ask"
else
  PASS=$((PASS + 1))
  echo "  ok: autonomous mode never asks"
fi

echo "[terminate-failed] always-autonomous stage, interactive mode"
OUT=$(bash "$HANDLER" "$PACKFIX" interactive deliver "$ENVFIX/question.md" 0 5 2>&1); ST=$?
assert_exit "exits 3" 3 $ST "$OUT"
assert_contains "decides to terminate as failed" "decision: terminate-failed" "$OUT"

echo "[terminate-failed] always-autonomous stage, autonomous mode too"
OUT=$(bash "$HANDLER" "$PACKFIX" autonomous deliver "$ENVFIX/question.md" 0 5 2>&1); ST=$?
assert_exit "exits 3" 3 $ST "$OUT"
assert_contains "decides to terminate as failed" "decision: terminate-failed" "$OUT"

echo "[reject] envelope verdict is not question"
OUT=$(bash "$HANDLER" "$PACKFIX" interactive intake "$ENVFIX/pass.md" 0 5 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "reason names the mismatched verdict" "verdict: question" "$OUT"

echo "[reject] unknown mode"
OUT=$(bash "$HANDLER" "$PACKFIX" curious intake "$ENVFIX/question.md" 0 5 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "reason names mode" "mode" "$OUT"

echo "[reject] questions-used is not an integer"
OUT=$(bash "$HANDLER" "$PACKFIX" interactive intake "$ENVFIX/question.md" zero 5 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "reason names questions-used" "questions" "$OUT"

echo "[reject] questions-cap is not an integer"
OUT=$(bash "$HANDLER" "$PACKFIX" interactive intake "$ENVFIX/question.md" 0 many 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "reason names questions-cap" "questions" "$OUT"

echo "[usage] wrong argument count"
OUT=$(bash "$HANDLER" "$PACKFIX" interactive intake "$ENVFIX/question.md" 0 2>&1); ST=$?
assert_exit "wrong arg count -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] pack manifest not found"
OUT=$(bash "$HANDLER" "$SCRIPT_DIR/../fixtures/pack-manifest/does-not-exist.yaml" interactive intake "$ENVFIX/question.md" 0 5 2>&1); ST=$?
assert_exit "missing manifest -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] envelope path not found"
OUT=$(bash "$HANDLER" "$PACKFIX" interactive intake "$ENVFIX/does-not-exist.md" 0 5 2>&1); ST=$?
assert_exit "missing envelope -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
