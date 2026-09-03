#!/usr/bin/env bash
# Tests for resolve-route.sh. Run with:
#   bash plugins/agentic-core/shared/lib/resolve-route.test.sh
#
# No framework — exits 0 on success, 1 on first failure. assert_exit/
# assert_contains follow the same pattern as validate-project-config.test.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-route.sh"
RRFIX="$SCRIPT_DIR/../fixtures/route-resolution"
CONFIGFIX="$SCRIPT_DIR/../fixtures/project-config"

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

echo "=== resolve-route.sh tests ==="

echo "[resolve] explicit route wins over a contradicting signal table"
OUT=$(bash "$RESOLVER" "$CONFIGFIX/valid.yaml" "$RRFIX/fact-explicit-route.yaml" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "resolves to the explicit route" "route: design-change" "$OUT"
assert_contains "records explicit_route as the fired rule" "rule: explicit_route: design-change" "$OUT"

echo "[resolve] a fact record matching two rows takes the first"
OUT=$(bash "$RESOLVER" "$RRFIX/config-overlapping.yaml" "$RRFIX/fact-overlap.yaml" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "resolves to the first matching row" "route: by-label" "$OUT"
assert_contains "records the signal table id that fired" "rule: signal_table: by-label" "$OUT"

echo "[resolve] an unmatched record takes the default"
OUT=$(bash "$RESOLVER" "$CONFIGFIX/valid.yaml" "$RRFIX/fact-unmatched.yaml" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "resolves to the default route" "route: standard" "$OUT"
assert_contains "records default as the fired rule" "rule: default: standard" "$OUT"
assert_contains "reports the resolved route's stages" "stages: [intake, implement, publish-gate, deliver]" "$OUT"

echo "[resolve] an earlier row requiring labels does not match a record with none, later row still checked"
OUT=$(bash "$RESOLVER" "$RRFIX/config-multi-label.yaml" "$RRFIX/fact-empty-labels-multi-type.yaml" 2>&1); ST=$?
assert_exit "exits 0" 0 $ST "$OUT"
assert_contains "resolves past the unmatched labels row" "route: multi-type" "$OUT"

echo "[reject] explicit route names an id not in the table"
OUT=$(bash "$RESOLVER" "$CONFIGFIX/valid.yaml" "$RRFIX/fact-explicit-unknown.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unresolved id" "nonexistent-route" "$OUT"

echo "[usage] no arguments"
OUT=$(bash "$RESOLVER" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] fact record not found"
OUT=$(bash "$RESOLVER" "$CONFIGFIX/valid.yaml" "$RRFIX/does-not-exist.yaml" 2>&1); ST=$?
assert_exit "missing fact record -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
