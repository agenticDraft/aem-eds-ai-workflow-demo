#!/usr/bin/env bash
# Tests for validate-artifact-registry.sh. Run with:
#   bash plugins/agentic-core/shared/lib/validate-artifact-registry.test.sh
#
# No framework — exits 0 on success, 1 on first failure. Confirms: a
# well-formed registry passes, naming each of the five core producers; an
# entry with no producer fails; an entry naming a producer that does not
# exist fails; an entry missing a required field fails; two entries
# sharing an id fail; and the real registry this task ships passes as
# built.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-artifact-registry.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/artifact-registry"
REAL_REGISTRY="$SCRIPT_DIR/artifact-registry.yaml"

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

echo "=== validate-artifact-registry.sh tests ==="

echo "[accept] a well-formed registry naming every core producer"
OUT=$(bash "$VALIDATOR" "$FIXDIR/valid.yaml" 2>&1); ST=$?
assert_exit "valid.yaml accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports entry count" "valid: artifact registry (5 entries)" "$OUT"

echo "[reject] an entry with no producer"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/no-producer.yaml" 2>&1); ST=$?
assert_exit "no-producer rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the artifact" "fact-record" "$OUT"
assert_contains "reason says no producer" "no producer" "$OUT"

echo "[reject] an entry naming a producer that does not exist"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/unknown-producer.yaml" 2>&1); ST=$?
assert_exit "unknown-producer rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unknown producer" "'implement'" "$OUT"

echo "[reject] an entry missing a required field"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/missing-field.yaml" 2>&1); ST=$?
assert_exit "missing-field rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing field" "validation" "$OUT"

echo "[reject] two entries sharing an id"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/duplicate-id.yaml" 2>&1); ST=$?
assert_exit "duplicate-id rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the duplicate" "duplicate artifact id" "$OUT"

echo "[accept] the real core registry, as shipped"
OUT=$(bash "$VALIDATOR" "$REAL_REGISTRY" 2>&1); ST=$?
assert_exit "artifact-registry.yaml accepted (exit 0)" 0 $ST "$OUT"

echo "[usage] no argument"
OUT=$(bash "$VALIDATOR" 2>&1); ST=$?
assert_exit "no arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] file not found"
OUT=$(bash "$VALIDATOR" "$FIXDIR/does-not-exist.yaml" 2>&1); ST=$?
assert_exit "missing file -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
