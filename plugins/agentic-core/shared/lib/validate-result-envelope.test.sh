#!/usr/bin/env bash
# Tests for validate-result-envelope.sh. Run with:
#   bash plugins/agentic-core/shared/lib/validate-result-envelope.test.sh
#
# No framework — exits 0 on success, 1 on first failure. assert_exit below
# compares expected vs. actual exit code per case, against fixture inputs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-result-envelope.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/result-envelope"

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

echo "=== validate-result-envelope.sh tests ==="

echo "[accept] the four Phase 2 / Task 2 fixtures"
for verdict in pass warn fail question; do
  OUT=$(bash "$VALIDATOR" "$FIXDIR/$verdict.md" 2>&1); ST=$?
  assert_exit "$verdict.md accepted (exit 0)" 0 $ST "$OUT"
  assert_contains "$verdict.md reports its own verdict" "verdict: $verdict" "$OUT"
done

echo "[reject] unknown verdict literal"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/unknown-verdict.md" 2>&1); ST=$?
assert_exit "unknown verdict rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the bad literal" "success" "$OUT"

echo "[reject] multi-line summary"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/multiline-summary.md" 2>&1); ST=$?
assert_exit "multi-line summary rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] missing artifacts list"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/missing-artifacts.md" 2>&1); ST=$?
assert_exit "missing artifacts list rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] artifacts written as an inline scalar instead of a list"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/artifacts-inline-scalar.md" 2>&1); ST=$?
assert_exit "artifacts inline scalar rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names artifacts, not summary" "'artifacts:' must be a list" "$OUT"

echo "[reject] text after the block"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/trailing-text.md" 2>&1); ST=$?
assert_exit "trailing text rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] a subagent-outcome status used as this contract's verdict"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/inner-literal.md" 2>&1); ST=$?
assert_exit "inner literal rejected (exit 1)" 1 $ST "$OUT"

echo "[accept] error_class on the two verdicts it is valid with"
for fx in fail-error-class question-error-class; do
  OUT=$(bash "$VALIDATOR" "$FIXDIR/$fx.md" 2>&1); ST=$?
  assert_exit "$fx.md accepted (exit 0)" 0 $ST "$OUT"
done

echo "[reject] an error_class literal the contract does not define"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/unknown-error-class.md" 2>&1); ST=$?
assert_exit "unknown error_class rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the bad literal" "RETRYABLE" "$OUT"
assert_contains "reason names the three it accepts" "TRANSIENT, VALIDATION or PERMANENT" "$OUT"

echo "[reject] error_class on a verdict it is not valid with"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/error-class-with-pass.md" 2>&1); ST=$?
assert_exit "error_class with verdict: pass rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the field, not the verdict" "'error_class:' is only valid" "$OUT"

echo "[accept] question_id on a question verdict"
OUT=$(bash "$VALIDATOR" "$FIXDIR/question-id.md" 2>&1); ST=$?
assert_exit "question-id.md accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports verdict question" "verdict: question" "$OUT"

echo "[reject] question_id on a verdict it is not valid with"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/question-id-with-pass.md" 2>&1); ST=$?
assert_exit "question_id with verdict: pass rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the field" "'question_id:' is only valid" "$OUT"

echo "[reject] a question_id that is not a lowercase id"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/malformed-question-id.md" 2>&1); ST=$?
assert_exit "malformed question_id rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names question_id" "question_id" "$OUT"

echo "[reject] a question_id longer than 40 characters"
LONG_FX="$(mktemp "${TMPDIR:-/tmp}/qid-long.XXXXXX")"
sed 's/^question_id: .*/question_id: a-question-id-that-runs-well-past-forty-chars/' "$FIXDIR/question-id.md" > "$LONG_FX"
OUT=$(bash "$VALIDATOR" "$LONG_FX" 2>&1); ST=$?
rm -f "$LONG_FX"
assert_exit "over-long question_id rejected (exit 1)" 1 $ST "$OUT"

echo "[accept] change_state before metrics (D534)"
OUT=$(bash "$VALIDATOR" "$FIXDIR/change-state.md" 2>&1); ST=$?
assert_exit "change-state.md accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports verdict pass" "verdict: pass" "$OUT"

echo "[accept] every change_state literal, on pass and on fail"
CS_FX="$(mktemp "${TMPDIR:-/tmp}/change-state.XXXXXX")"
for state in open merged closed none; do
  sed "s/^change_state: .*/change_state: $state/" "$FIXDIR/change-state.md" > "$CS_FX"
  OUT=$(bash "$VALIDATOR" "$CS_FX" 2>&1); ST=$?
  assert_exit "change_state: $state accepted (exit 0)" 0 $ST "$OUT"
done
printf '## Result\nverdict: fail\nsummary: Checks could not be read.\nartifacts: []\nnext_action: none\nerror_class: TRANSIENT\nchange_state: open\n' > "$CS_FX"
OUT=$(bash "$VALIDATOR" "$CS_FX" 2>&1); ST=$?
assert_exit "change_state after error_class on a fail accepted (exit 0)" 0 $ST "$OUT"
rm -f "$CS_FX"

echo "[reject] a change_state literal the contract does not define"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/unknown-change-state.md" 2>&1); ST=$?
assert_exit "unknown change_state rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the bad literal" "abandoned" "$OUT"

echo "[reject] change_state after metrics"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/change-state-after-metrics.md" 2>&1); ST=$?
assert_exit "change_state after metrics rejected (exit 1)" 1 $ST "$OUT"

echo "[usage] no argument"
OUT=$(bash "$VALIDATOR" 2>&1); ST=$?
assert_exit "no arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] file not found"
OUT=$(bash "$VALIDATOR" "$FIXDIR/does-not-exist.md" 2>&1); ST=$?
assert_exit "missing file -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
