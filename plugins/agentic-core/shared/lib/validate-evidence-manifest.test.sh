#!/usr/bin/env bash
# Tests for validate-evidence-manifest.sh. Run with:
#   bash plugins/agentic-core/shared/lib/validate-evidence-manifest.test.sh
#
# No framework — exits 0 on success, 1 on first failure. assert_exit below
# compares expected vs. actual exit code per case, against fixture inputs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-evidence-manifest.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/evidence-manifest"

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

echo "=== validate-evidence-manifest.sh tests ==="

echo "[accept] a well-formed evidence manifest"
OUT=$(bash "$VALIDATOR" "$FIXDIR/valid.json" 2>&1); ST=$?
assert_exit "valid.json accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports attachment and coverage-gap counts" "2 attachments, 1 coverage gaps" "$OUT"

echo "[accept] an empty attachments list, written as []"
OUT=$(bash "$VALIDATOR" "$FIXDIR/valid-empty-attachments.json" 2>&1); ST=$?
assert_exit "valid-empty-attachments.json accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports zero attachments" "0 attachments, 0 coverage gaps" "$OUT"

echo "[accept] an attachment path that does not exist on disk"
OUT=$(bash "$VALIDATOR" "$FIXDIR/valid-nonexistent-attachment-path.json" 2>&1); ST=$?
assert_exit "valid-nonexistent-attachment-path.json accepted (exit 0)" 0 $ST "$OUT"

echo "[reject] each required top-level field missing, one case each"
for field in version item_id target target_reachable target_reachable_reason coverage_gaps attachments; do
  OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/missing-${field}.json" 2>&1); ST=$?
  assert_exit "missing-${field}.json rejected (exit 1)" 1 $ST "$OUT"
  assert_contains "reason names '${field}'" "$field" "$OUT"
done

echo "[reject] target_reachable given as a string, not a boolean"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/target_reachable-wrong-type.json" 2>&1); ST=$?
assert_exit "target_reachable-wrong-type.json rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the boolean requirement" "boolean" "$OUT"

echo "[reject] an attachment missing its path"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/attachment-missing-path.json" 2>&1); ST=$?
assert_exit "attachment-missing-path.json rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the path" "path" "$OUT"

echo "[reject] an attachment missing its width"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/attachment-missing-width.json" 2>&1); ST=$?
assert_exit "attachment-missing-width.json rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the width" "width" "$OUT"

echo "[reject] an attachment missing its label"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/attachment-missing-label.json" 2>&1); ST=$?
assert_exit "attachment-missing-label.json rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the label" "label" "$OUT"

echo "[reject] an attachment with a non-positive width"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/attachment-non-positive-width.json" 2>&1); ST=$?
assert_exit "attachment-non-positive-width.json rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the width" "width" "$OUT"

echo "[usage] not valid JSON at all"
OUT=$(bash "$VALIDATOR" "$FIXDIR/invalid/not-json.json" 2>&1); ST=$?
assert_exit "not-json.json rejected (exit 2)" 2 $ST "$OUT"

echo "[usage] no argument"
OUT=$(bash "$VALIDATOR" 2>&1); ST=$?
assert_exit "no arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] file not found"
OUT=$(bash "$VALIDATOR" "$FIXDIR/does-not-exist.json" 2>&1); ST=$?
assert_exit "missing file -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
