#!/usr/bin/env bash
# Tests for check-readiness-criteria.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-readiness-criteria.test.sh
#
# No framework — exits 0 on success, 1 on first failure. Confirms: a fact
# record satisfying its item_type's declared criteria passes; an item_type
# with no declared criteria fails naming it; a declared field that does not
# hold fails naming it; the fixed design-wanted-but-absent rule fails
# independent of the pack's own declared criteria; and the usage errors.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-readiness-criteria.sh"
PACK="$SCRIPT_DIR/../fixtures/pack-manifest/platform-valid-full-route/pack.yaml"
FACTDIR="$SCRIPT_DIR/../fixtures/fact-record"
FIXDIR="$SCRIPT_DIR/../fixtures/readiness-criteria"

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

echo "=== check-readiness-criteria.sh tests ==="

echo "[accept] item_type's declared criteria all hold"
OUT=$(bash "$CHECK" "$PACK" "$FACTDIR/valid.yaml" 2>&1); ST=$?
assert_exit "valid.yaml accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports item_type and field count" "valid: readiness (task, 2 fields checked)" "$OUT"

echo "[reject] item_type has no declared readiness criteria"
OUT=$(bash "$CHECK" "$PACK" "$FIXDIR/undeclared-item-type.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the undeclared item_type" "item_type 'story' has no declared readiness criteria" "$OUT"

echo "[reject] a required boolean field is false"
OUT=$(bash "$CHECK" "$PACK" "$FIXDIR/missing-required-field.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the failing field" "requires 'has_acceptance_criteria' to be true, found false" "$OUT"

echo "[reject] design_mentioned is true but design_source is false"
OUT=$(bash "$CHECK" "$PACK" "$FIXDIR/design-wanted-absent.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason states the fixed rule" "design_mentioned is true but design_source is false" "$OUT"

echo "[usage] no arguments"
OUT=$(bash "$CHECK" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] fact record file not found"
OUT=$(bash "$CHECK" "$PACK" "$FIXDIR/does-not-exist.yaml" 2>&1); ST=$?
assert_exit "missing file -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] pack manifest has no readiness_criteria key"
BAD_PACK="$(mktemp "${TMPDIR:-/tmp}/no-readiness-criteria.XXXXXX.yaml")"
printf 'kind: platform\nstages:\n  - id: intake\n    skill: eds-intake\n' > "$BAD_PACK"
OUT=$(bash "$CHECK" "$BAD_PACK" "$FACTDIR/valid.yaml" 2>&1); ST=$?
assert_exit "no 'readiness_criteria:' key -> usage error (exit 2)" 2 $ST "$OUT"
rm -f "$BAD_PACK"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
