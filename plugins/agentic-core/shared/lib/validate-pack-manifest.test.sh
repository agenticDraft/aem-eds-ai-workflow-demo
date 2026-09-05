#!/usr/bin/env bash
# Tests for validate-pack-manifest.sh. Run with:
#   bash plugins/agentic-core/shared/lib/validate-pack-manifest.test.sh
#
# No framework — exits 0 on success, 1 on first failure. assert_exit below
# compares expected vs. actual exit code per case, against fixture inputs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-pack-manifest.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/pack-manifest"

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

echo "=== validate-pack-manifest.sh tests ==="

echo "[accept] a well-formed platform manifest"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-valid/pack.yaml" 2>&1); ST=$?
assert_exit "platform-valid accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports kind" "platform" "$OUT"

echo "[reject] platform manifest binds an unknown stage in always_autonomous"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/unknown-stage-always-autonomous/pack.yaml" 2>&1); ST=$?
assert_exit "unknown-stage-always-autonomous rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unknown stage" "publish-gate" "$OUT"

echo "[reject] platform manifest binds an unknown stage as an artifact producer"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/unknown-stage-artifact-producer/pack.yaml" 2>&1); ST=$?
assert_exit "unknown-stage-artifact-producer rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unknown stage" "plan-gate" "$OUT"

echo "[reject] platform manifest names a nonexistent skill"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/dangling-skill/pack.yaml" 2>&1); ST=$?
assert_exit "platform dangling-skill rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing skill" "implement" "$OUT"

echo "[reject] platform manifest names a stage skill that does not declare isolated execution"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/stage-not-isolated/pack.yaml" 2>&1); ST=$?
assert_exit "stage-not-isolated rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the stage" "implement" "$OUT"
assert_contains "reason names the missing declaration" "context: fork" "$OUT"

echo "[reject] pack root contains an unfilled template placeholder"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/unfilled-placeholder/pack.yaml" 2>&1); ST=$?
assert_exit "unfilled-placeholder rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the placeholder" "placeholder" "$OUT"
assert_contains "reason names the offending file" "implement/SKILL.md" "$OUT"

echo "[accept] a well-formed provider manifest"
OUT=$(bash "$VALIDATOR" "$FIXDIR/provider-valid/pack.yaml" 2>&1); ST=$?
assert_exit "provider-valid accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports kind" "provider" "$OUT"

echo "[reject] provider manifest omits an operation without declaring it unsupported"
OUT=$(bash "$VALIDATOR" "$FIXDIR/provider-invalid/missing-operation/pack.yaml" 2>&1); ST=$?
assert_exit "missing-operation rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing operation" "list_types" "$OUT"

echo "[reject] provider manifest implements an operation unknown to its role"
OUT=$(bash "$VALIDATOR" "$FIXDIR/provider-invalid/unknown-operation/pack.yaml" 2>&1); ST=$?
assert_exit "unknown-operation rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unknown operation" "bogus_op" "$OUT"

echo "[reject] provider manifest names a nonexistent skill"
OUT=$(bash "$VALIDATOR" "$FIXDIR/provider-invalid/dangling-skill/pack.yaml" 2>&1); ST=$?
assert_exit "provider dangling-skill rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing skill" "note" "$OUT"

echo "[usage] no argument"
OUT=$(bash "$VALIDATOR" 2>&1); ST=$?
assert_exit "no arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] file not found"
OUT=$(bash "$VALIDATOR" "$FIXDIR/does-not-exist/pack.yaml" 2>&1); ST=$?
assert_exit "missing file -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
