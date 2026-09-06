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

echo "[accept] a platform manifest declaring skip_when_missing"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-valid-skip-conditions/pack.yaml" 2>&1); ST=$?
assert_exit "platform-valid-skip-conditions accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports kind" "platform" "$OUT"

echo "[reject] skip_when_missing binds an unknown stage"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/skip-condition-unknown-stage/pack.yaml" 2>&1); ST=$?
assert_exit "skip-condition-unknown-stage rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unknown stage" "publish-gate" "$OUT"
assert_contains "reason names the key" "skip_when_missing" "$OUT"

# The remaining skip_when_missing rejection cases are shape errors inside the
# block itself, written inline rather than committed as fixture directories:
# each needs only a two-line manifest edit, and a fixture directory per case
# would triple the fixture tree to prove one regex each.
SKIPTMP="$(mktemp -d "${TMPDIR:-/tmp}/validate-pack-manifest-skip.XXXXXX")"
trap 'rm -rf "$SKIPTMP"' EXIT
cp -R "$FIXDIR/platform-valid-skip-conditions/." "$SKIPTMP/"

skip_block_manifest() {
  {
    sed '/^skip_when_missing:$/,$d' "$FIXDIR/platform-valid-skip-conditions/pack.yaml"
    printf '%s\n' "$@"
  } > "$SKIPTMP/pack.yaml"
}

echo "[reject] skip_when_missing declares the same stage twice"
skip_block_manifest "skip_when_missing:" \
  '  implement: ".ai/one.yaml"' \
  '  implement: ".ai/two.yaml"'
OUT=$(bash "$VALIDATOR" "$SKIPTMP/pack.yaml" 2>&1); ST=$?
assert_exit "duplicate stage rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says twice" "twice" "$OUT"

echo "[reject] skip_when_missing declares a mandatory stage skippable"
for mandatory in intake deliver; do
  skip_block_manifest "skip_when_missing:" "  $mandatory: \".ai/absent.yaml\""
  OUT=$(bash "$VALIDATOR" "$SKIPTMP/pack.yaml" 2>&1); ST=$?
  assert_exit "'$mandatory' rejected (exit 1)" 1 $ST "$OUT"
  assert_contains "reason names '$mandatory'" "$mandatory" "$OUT"
done

echo "[reject] skip_when_missing declares an absolute path"
skip_block_manifest "skip_when_missing:" '  implement: "/etc/passwd"'
OUT=$(bash "$VALIDATOR" "$SKIPTMP/pack.yaml" 2>&1); ST=$?
assert_exit "absolute path rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says absolute" "absolute" "$OUT"

echo "[reject] skip_when_missing is present but empty"
skip_block_manifest "skip_when_missing:"
OUT=$(bash "$VALIDATOR" "$SKIPTMP/pack.yaml" 2>&1); ST=$?
assert_exit "empty block rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says no entries" "no entries" "$OUT"

echo "[reject] a top-level key after skip_when_missing"
skip_block_manifest "skip_when_missing:" '  implement: ".ai/one.yaml"' "unexpected: true"
OUT=$(bash "$VALIDATOR" "$SKIPTMP/pack.yaml" 2>&1); ST=$?
assert_exit "trailing key rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the trailing content" "unexpected" "$OUT"

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
