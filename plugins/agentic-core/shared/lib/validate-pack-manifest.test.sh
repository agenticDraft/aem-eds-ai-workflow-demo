#!/usr/bin/env bash
# Tests for validate-pack-manifest.sh. Run with:
#   bash plugins/agentic-core/shared/lib/validate-pack-manifest.test.sh
#
# No framework — exits 0 on success, 1 if any case failed. assert_exit below
# compares expected vs. actual exit code per case, against fixture inputs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-pack-manifest.sh"
EVALUATOR="$SCRIPT_DIR/evaluate-stage-conditions.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/pack-manifest"
FACT_CONTRACT="$SCRIPT_DIR/../fact-record.md"

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

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

echo "=== validate-pack-manifest.sh tests ==="

# --- accepted shapes --------------------------------------------------------

echo "[accept] a platform manifest whose stages are all always-on"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-valid/pack.yaml" 2>&1); ST=$?
assert_exit "platform-valid accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports kind" "platform" "$OUT"

echo "[accept] a platform manifest with a conditional stage"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-valid-conditions/pack.yaml" 2>&1); ST=$?
assert_exit "platform-valid-conditions accepted (exit 0)" 0 $ST "$OUT"

echo "[accept] a platform manifest declaring all fifteen stages"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-valid-full-route/pack.yaml" 2>&1); ST=$?
assert_exit "platform-valid-full-route accepted (exit 0)" 0 $ST "$OUT"

echo "[accept] a well-formed provider manifest"
OUT=$(bash "$VALIDATOR" "$FIXDIR/provider-valid/pack.yaml" 2>&1); ST=$?
assert_exit "provider-valid accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports kind" "provider" "$OUT"

# --- committed rejection fixtures -------------------------------------------

echo "[reject] always_autonomous binds an unknown stage"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/unknown-stage-always-autonomous/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unknown stage" "publish-gate" "$OUT"

echo "[reject] an artifact producer that is not a declared stage"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/unknown-stage-artifact-producer/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unknown stage" "prototype" "$OUT"

echo "[reject] a stage naming a nonexistent skill"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/dangling-skill/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing skill" "nonexistent" "$OUT"

echo "[reject] a stage skill that does not declare isolated execution"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/stage-not-isolated/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing declaration" "context: fork" "$OUT"

echo "[reject] an unfilled template placeholder under the pack root"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/unfilled-placeholder/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the placeholder" "placeholder" "$OUT"

echo "[reject] validator 1 — a stage id outside the fifteen"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/stage-id-not-in-vocabulary/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the id" "deploy" "$OUT"
assert_contains "reason names the vocabulary" "fifteen" "$OUT"

echo "[reject] validator 12 — a when: key that is not a fact-record field"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/when-unknown-field/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the field" "design_requested" "$OUT"

echo "[reject] validator 13 — no readiness_criteria at all"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/no-readiness-criteria/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason explains the consequence" "fail every item" "$OUT"

echo "[reject] validator 13 — a criterion requiring a field the record lacks"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/readiness-criteria-unknown-field/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the field" "has_mockup" "$OUT"

echo "[reject] validator 14 — a digraph node that is not a declared stage"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/digraph-node-not-a-stage/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the node" "lint" "$OUT"

echo "[reject] validator 14 — a declared stage with no node"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/digraph-missing-node/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the stage" "implement" "$OUT"

echo "[reject] validator 14 — an edge label that disagrees with the when:"
OUT=$(bash "$VALIDATOR" "$FIXDIR/platform-invalid/digraph-label-mismatch/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason prints the actual label" "is 'design_source=true'" "$OUT"
assert_contains "reason prints the expected rendering" "design_source=true OR design_mentioned=true" "$OUT"

echo "[reject] provider manifest omits an operation without declaring it unsupported"
OUT=$(bash "$VALIDATOR" "$FIXDIR/provider-invalid/missing-operation/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing operation" "list_types" "$OUT"

echo "[reject] provider manifest implements an operation unknown to its role"
OUT=$(bash "$VALIDATOR" "$FIXDIR/provider-invalid/unknown-operation/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the unknown operation" "bogus_op" "$OUT"

echo "[reject] provider manifest names a nonexistent skill"
OUT=$(bash "$VALIDATOR" "$FIXDIR/provider-invalid/dangling-skill/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the missing skill" "note" "$OUT"

# --- inline shape errors ----------------------------------------------------
# One-block edits to an otherwise valid manifest. A fixture directory each
# would multiply the tree to prove one regex apiece.

TMP="$(mktemp -d "${TMPDIR:-/tmp}/validate-pack-manifest.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cp -R "$FIXDIR/platform-valid-conditions/." "$TMP/"

# stage_list <lines…> — rewrite the manifest with a replacement stage list,
# keeping the trailing keys the valid fixture already carries.
stage_list() {
  {
    printf 'kind: platform\nstages:\n'
    printf '%s\n' "$@"
    sed -n '/^always_autonomous:/,$p' "$FIXDIR/platform-valid-conditions/pack.yaml"
  } > "$TMP/pack.yaml"
}

echo "[reject] the pre-list manifest shape (stages as a mapping)"
stage_list '  intake: intake' '  deliver: deliver'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "old map shape rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] the same stage declared twice"
stage_list '  - id: intake' '    skill: intake' '  - id: intake' '    skill: intake' \
           '  - id: deliver' '    skill: deliver'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "duplicate stage rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says twice" "twice" "$OUT"

echo "[reject] a list that does not begin with intake"
stage_list '  - id: implement' '    skill: implement' '  - id: deliver' '    skill: deliver'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names intake" "begin with 'intake'" "$OUT"

echo "[reject] a list that does not end with deliver"
stage_list '  - id: intake' '    skill: intake' '  - id: implement' '    skill: implement'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names deliver" "end with 'deliver'" "$OUT"

echo "[reject] a mandatory stage carrying a condition"
stage_list '  - id: intake' '    skill: intake' '    when:' '      - { design_source: true }' \
           '  - id: deliver' '    skill: deliver'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names intake" "intake" "$OUT"

echo "[reject] when: present with no blocks"
stage_list '  - id: intake' '    skill: intake' '  - id: extract' '    skill: extract' '    when:' \
           '  - id: deliver' '    skill: deliver'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] a list field compared against a boolean"
stage_list '  - id: intake' '    skill: intake' '  - id: extract' '    skill: extract' '    when:' \
           '      - { components: true }' '  - id: deliver' '    skill: deliver'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the right values" "present" "$OUT"

echo "[reject] a boolean field compared against present"
stage_list '  - id: intake' '    skill: intake' '  - id: extract' '    skill: extract' '    when:' \
           '      - { design_source: present }' '  - id: deliver' '    skill: deliver'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the right values" "true" "$OUT"

echo "[reject] a non-positive fix_attempts"
stage_list '  - id: intake' '    skill: intake' '  - id: implement' '    skill: implement' \
           '    fix_attempts: 0' '  - id: deliver' '    skill: deliver'
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] a trailing top-level key"
{
  cat "$FIXDIR/platform-valid-conditions/pack.yaml"
  printf 'unexpected: true\n'
} > "$TMP/pack.yaml"
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the trailing content" "unexpected" "$OUT"

echo "[reject] a platform pack shipping no route.dot"
cp -R "$FIXDIR/platform-valid/." "$TMP/"
rm -f "$TMP/route.dot"
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "missing route.dot rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the file" "route.dot" "$OUT"

echo "[reject] an always-on stage drawn dashed"
cp -R "$FIXDIR/platform-valid/." "$TMP/"
sed 's/"implement" \[shape=box\]/"implement" [shape=box, style=dashed]/' \
  "$FIXDIR/platform-valid/route.dot" > "$TMP/route.dot"
OUT=$(bash "$VALIDATOR" "$TMP/pack.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason says it carries no condition" "carries no 'when:'" "$OUT"

# --- drift guards -----------------------------------------------------------
# The validator hardcodes the fact-record field list the way it hardcodes each
# role's operations. These two cases are what stop that copy silently drifting
# from the contract it is supposed to enforce.

echo "[drift] the validator's field list equals fact-record.md's Format block"
CONTRACT_FIELDS="$(
  sed -n '/^## Format$/,/^## Field rules$/p' "$FACT_CONTRACT" \
    | grep -oE '^[a-z_]+:' | tr -d ':' | tr '\n' ' '
)"
VALIDATOR_FIELDS="$(
  sed -n '/^FACT_FIELDS=(/,/)$/p' "$VALIDATOR" \
    | tr '\n' ' ' | sed 's/FACT_FIELDS=(//; s/)//' | tr -s ' '
)"
assert_eq "field lists agree" "$(echo $CONTRACT_FIELDS)" "$(echo $VALIDATOR_FIELDS)"

echo "[drift] the validator and the evaluator share one field/kind table"
V_TABLE="$(sed -n '/^FACT_KINDS=(/,/)$/p' "$VALIDATOR" | tr -s ' \n' ' ')"
E_TABLE="$(sed -n '/^FACT_KINDS=(/,/)$/p' "$EVALUATOR" | tr -s ' \n' ' ')"
assert_eq "kind tables agree" "$V_TABLE" "$E_TABLE"

# --- usage ------------------------------------------------------------------

echo "[usage] no argument"
OUT=$(bash "$VALIDATOR" 2>&1); ST=$?
assert_exit "no arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] file not found"
OUT=$(bash "$VALIDATOR" "$FIXDIR/does-not-exist/pack.yaml" 2>&1); ST=$?
assert_exit "missing file -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
