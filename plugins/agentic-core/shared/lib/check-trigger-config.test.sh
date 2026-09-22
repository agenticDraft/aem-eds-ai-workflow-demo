#!/usr/bin/env bash
# Tests for check-trigger-config.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-trigger-config.test.sh
#
# No framework — exits 0 on success, 1 on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/check-trigger-config.sh"
CFGDIR="$SCRIPT_DIR/../fixtures/project-config"
RULEDIR="$SCRIPT_DIR/../fixtures/trigger-config"

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

echo "=== check-trigger-config.sh tests ==="

echo "[accept] rule carries the config's token"
OUT=$(bash "$CHECKER" "$CFGDIR/valid.yaml" "$RULEDIR/rule-with-token.json" 2>&1); ST=$?
assert_exit "matching token accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports agreement" "agrees" "$OUT"

echo "[reject] rule carries a different token"
OUT=$(bash "$CHECKER" "$CFGDIR/valid.yaml" "$RULEDIR/rule-without-token.json" 2>&1); ST=$?
assert_exit "mismatched token rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the config token" "@example-run" "$OUT"

echo "[usage] missing arguments"
OUT=$(bash "$CHECKER" "$CFGDIR/valid.yaml" 2>&1); ST=$?
assert_exit "one arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] rule file not found"
OUT=$(bash "$CHECKER" "$CFGDIR/valid.yaml" "$RULEDIR/nope.json" 2>&1); ST=$?
assert_exit "missing rule file -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
