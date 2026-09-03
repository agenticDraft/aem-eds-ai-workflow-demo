#!/usr/bin/env bash
# Tests for run-stage.sh. Run with:
#   bash plugins/agentic-core/shared/lib/run-stage.test.sh
#
# No framework — assert_exit/assert_contains follow the same pattern as
# resolve-route.test.sh and validate-pack-manifest.test.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/run-stage.sh"
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

echo "=== run-stage.sh tests ==="

echo "[continue] a stub adapter returning verdict: pass"
OUT=$(bash "$RUNNER" "$PACKFIX" intake "$ENVFIX/pass.md" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "resolves the stage's adapter" "adapter: intake" "$OUT"
assert_contains "reports the verdict" "verdict: pass" "$OUT"
assert_contains "decides to continue" "decision: continue" "$OUT"

echo "[continue-warn] a stub adapter returning verdict: warn"
OUT=$(bash "$RUNNER" "$PACKFIX" implement "$ENVFIX/warn.md" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "resolves the stage's adapter" "adapter: implement" "$OUT"
assert_contains "decides to continue and record the warning" "decision: continue-warn" "$OUT"

echo "[terminate-failed] a stub adapter returning verdict: fail"
OUT=$(bash "$RUNNER" "$PACKFIX" deliver "$ENVFIX/fail.md" 2>&1); ST=$?
assert_exit "exits 3" 3 $ST "$OUT"
assert_contains "decides to terminate as failed" "decision: terminate-failed" "$OUT"

echo "[terminate-contract-violation] an unparseable return"
OUT=$(bash "$RUNNER" "$PACKFIX" intake "$ENVFIX/invalid/unknown-verdict.md" 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "decides to terminate as a contract violation" "decision: terminate-contract-violation" "$OUT"

echo "[terminate-contract-violation] a stage id absent from the manifest"
OUT=$(bash "$RUNNER" "$PACKFIX" nonexistent-stage "$ENVFIX/pass.md" 2>&1); ST=$?
assert_exit "exits 1" 1 $ST "$OUT"
assert_contains "reason names the unresolved stage" "nonexistent-stage" "$OUT"
assert_contains "decides to terminate as a contract violation" "decision: terminate-contract-violation" "$OUT"

echo "[reject-if] the runner never reads a file the stage produced"
OUT=$(bash "$RUNNER" "$PACKFIX" intake "$ENVFIX/pass.md" 2>&1); ST=$?
assert_exit "still exits 0 with no artifact path opened" 0 $ST "$OUT"
FACT_PATH="$SCRIPT_DIR/../../.ai-does-not-exist/fact-record.yaml"
if [[ ! -e "$FACT_PATH" ]]; then
  PASS=$((PASS + 1))
  echo "  ok: the pass.md fixture's artifacts path was never touched"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: something created the artifact path listed in the envelope"
fi

echo "[usage] no arguments"
OUT=$(bash "$RUNNER" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] pack manifest not found"
OUT=$(bash "$RUNNER" "$SCRIPT_DIR/../fixtures/pack-manifest/does-not-exist.yaml" intake "$ENVFIX/pass.md" 2>&1); ST=$?
assert_exit "missing manifest -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] envelope path not found"
OUT=$(bash "$RUNNER" "$PACKFIX" intake "$ENVFIX/does-not-exist.md" 2>&1); ST=$?
assert_exit "missing envelope -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
