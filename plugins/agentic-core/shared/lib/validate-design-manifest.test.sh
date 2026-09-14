#!/usr/bin/env bash
# Tests for validate-design-manifest.sh. Run with:
#   bash plugins/agentic-core/shared/lib/validate-design-manifest.test.sh
#
# No framework — exits 0 on success, 1 on first failure. assert_exit below
# compares expected vs. actual exit code per case, against fixture inputs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-design-manifest.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/design-manifest"

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

echo "=== validate-design-manifest.sh tests ==="

echo "[accept] a well-formed design manifest"
OUT=$(bash "$VALIDATOR" "$FIXDIR/valid.yaml" 2>&1); ST=$?
assert_exit "valid.yaml accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports token and frame counts" "3 tokens, 1 frames" "$OUT"

echo "[reject] unknown top-level key"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/unknown-top-level-key.yaml" 2>&1); ST=$?
assert_exit "unknown-top-level-key.yaml rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unexpected content" "unexpected content" "$OUT"

echo "[reject] a provenance value other than resolved-value-set"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/bad-provenance.yaml" 2>&1); ST=$?
assert_exit "bad-provenance.yaml rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the expected literal" "resolved-value-set" "$OUT"

echo "[reject] the same name in both values and unresolvable"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/duplicate-name.yaml" 2>&1); ST=$?
assert_exit "duplicate-name.yaml rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the duplicate" "Accent/Accent 4" "$OUT"

echo "[reject] frames with no entries"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/no-frames.yaml" 2>&1); ST=$?
assert_exit "no-frames.yaml rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names frames" "frames" "$OUT"

echo "[reject] a non-positive frame width"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/non-positive-width.yaml" 2>&1); ST=$?
assert_exit "non-positive-width.yaml rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the width" "width" "$OUT"

echo "[reject] an empty list not written as []"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/empty-list-not-bracket.yaml" 2>&1); ST=$?
assert_exit "empty-list-not-bracket.yaml rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the [] convention" "values: []" "$OUT"

echo "[usage] no argument"
OUT=$(bash "$VALIDATOR" 2>&1); ST=$?
assert_exit "no arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] file not found"
OUT=$(bash "$VALIDATOR" "$FIXDIR/does-not-exist.yaml" 2>&1); ST=$?
assert_exit "missing file -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
