#!/usr/bin/env bash
# Tests for check-onboarding-gate.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-onboarding-gate.test.sh
#
# No framework — exits 0 on success, 1 on first failure. assert_exit/
# assert_contains below compare expected vs. actual exit code and output
# against fixture inputs. Every fixture directory under
# ../fixtures/pre-flight/onboarding/ doubles as the "project root" the
# declared paths resolve against — the script resolves relative to the
# current working directory, so each case cd's into its own fixture dir
# before invoking it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-onboarding-gate.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/pre-flight/onboarding"

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3" output="$4"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected exit=$expected, got exit=$actual"
    [[ -n "$output" ]] && echo "    output: $output"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected output to contain: $needle"
    echo "    got: $haystack"
  fi
}

run_in() {
  # run_in <fixture-dir-name> — cd's into the fixture (the "project root")
  # and runs the check against its own pack.yaml, combining stdout+stderr.
  local dir="$FIXDIR/$1"
  (cd "$dir" && bash "$CHECK" "$dir/pack.yaml" 2>&1)
}

echo "=== check-onboarding-gate.sh tests ==="

echo "[accept] a platform pack declaring neither path — ungated"
OUT=$(run_in ungated); ST=$?
assert_exit "not-gated (exit 0)" 0 $ST "$OUT"
assert_contains "reports not-gated" "not-gated" "$OUT"

echo "[accept] onboarding_state_path declared and present"
OUT=$(run_in onboarding-present); ST=$?
assert_exit "ready (exit 0)" 0 $ST "$OUT"
assert_contains "reports ok" "onboarding: ok" "$OUT"

echo "[accept] onboarding_state_path declared but absent — warns, never blocks"
OUT=$(run_in onboarding-absent); ST=$?
assert_exit "still exit 0" 0 $ST "$OUT"
assert_contains "reports a warning" "onboarding: warn" "$OUT"
assert_contains "names confidence capped low" "confidence is capped low" "$OUT"

echo "[accept] audit_findings_path declared but absent — nothing to block on yet"
OUT=$(run_in audit-absent); ST=$?
assert_exit "still exit 0" 0 $ST "$OUT"
assert_contains "reports ok, no audit yet" "audit: ok — no audit yet" "$OUT"

echo "[accept] audit_findings_path declared, present, no poisoning finding"
OUT=$(run_in audit-clean); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_contains "reports ok" "audit: ok" "$OUT"

echo "[reject] audit_findings_path declared, present, one open poisoning finding"
OUT=$(run_in audit-poisoning); ST=$?
assert_exit "blocked (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the finding id" "F2" "$OUT"
assert_contains "reason names the contradiction" "breakpoint claim" "$OUT"
assert_contains "reason names the file" "AGENTS.project.md" "$OUT"
assert_contains "reason names the remedy" "onboarding-completion flow" "$OUT"

echo "[accept] both paths declared, both present, no poisoning finding"
OUT=$(run_in both-declared); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_contains "onboarding ok" "onboarding: ok" "$OUT"
assert_contains "audit ok" "audit: ok" "$OUT"

echo "[usage] no argument"
OUT=$(bash "$CHECK" 2>&1); ST=$?
assert_exit "no arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] manifest file not found"
OUT=$(bash "$CHECK" "$FIXDIR/does-not-exist/pack.yaml" 2>&1); ST=$?
assert_exit "missing manifest -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
