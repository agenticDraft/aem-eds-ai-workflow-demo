#!/usr/bin/env bash
# Tests for evaluate-stage-conditions.sh. Run with:
#   bash plugins/agentic-core/shared/lib/evaluate-stage-conditions.test.sh
#
# No framework — exits 0 on success, 1 if any case failed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVAL="$SCRIPT_DIR/evaluate-stage-conditions.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/pack-manifest"
FACTDIR="$SCRIPT_DIR/../fixtures/fact-record"
FULL="$FIXDIR/platform-valid-full-route/pack.yaml"

PASS=0
FAIL=0

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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/evaluate-stage-conditions.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

echo "=== evaluate-stage-conditions.sh tests ==="

# --- the acceptance scenario ------------------------------------------------
# A work item with no design reference, no design language and no component
# named: every conditional stage in the fifteen falls away, and nothing else
# does.

echo "[scenario] no design source, no design mention, no components"
OUT=$(bash "$EVAL" "$FULL" "$FACTDIR/no-design-no-components.yaml"); ST=$?
assert_exit "evaluated (exit 0)" 0 $ST "$OUT"
assert_eq "exactly four stages skipped" "4" "$(grep -c '^skipped:' <<< "$OUT")"
assert_eq "eleven stages run" "11" "$(grep -c '^run:' <<< "$OUT")"
assert_eq "the four are the conditional ones" \
  "extract baseline prototype verify-design" \
  "$(grep '^skipped:' <<< "$OUT" | sed 's/^skipped: //; s/ —.*//' | tr '\n' ' ' | sed 's/ $//')"
assert_contains "each skip names its own condition" \
  "skipped: baseline — components=present" "$OUT"
assert_contains "the design skips name the whole disjunction" \
  "skipped: extract — design_source=true OR design_mentioned=true" "$OUT"

echo "[scenario] the same item, but naming a component"
OUT=$(bash "$EVAL" "$FULL" "$FACTDIR/no-design-with-component.yaml")
assert_eq "three stages skipped" "3" "$(grep -c '^skipped:' <<< "$OUT")"
assert_eq "twelve stages run" "12" "$(grep -c '^run:' <<< "$OUT")"
assert_contains "the component-gated stage runs" "run: baseline" "$OUT"

echo "[scenario] a design reference present"
cat > "$TMP/design.yaml" <<'EOF'
item_id: "3001"
item_type: task
labels: []
components: []
files_named: []
design_source: true
design_mentioned: false
has_description: true
has_acceptance_criteria: true
has_reproduction_url: false
has_reproduction_steps: false
EOF
OUT=$(bash "$EVAL" "$FULL" "$TMP/design.yaml")
assert_contains "extract runs on a present reference" "run: extract" "$OUT"
assert_contains "prototype runs" "run: prototype" "$OUT"
assert_contains "verify-design runs" "run: verify-design" "$OUT"
assert_eq "only the component-gated stage skips" "1" "$(grep -c '^skipped:' <<< "$OUT")"

echo "[scenario] wanted but absent — the text asks, nothing is attached"
sed 's/design_source: true/design_source: false/; s/design_mentioned: false/design_mentioned: true/' \
  "$TMP/design.yaml" > "$TMP/wanted.yaml"
OUT=$(bash "$EVAL" "$FULL" "$TMP/wanted.yaml")
assert_contains "the second block of the disjunction still runs it" "run: extract" "$OUT"

# --- grammar semantics ------------------------------------------------------

mkpack() { # <name> <stage-lines…>
  local name="$1"; shift
  mkdir -p "$TMP/$name"
  { printf 'kind: platform\nstages:\n'; printf '%s\n' "$@"; } > "$TMP/$name/pack.yaml"
  echo "$TMP/$name/pack.yaml"
}

echo "[semantics] a stage with no when: always runs"
P=$(mkpack nowhen '  - id: intake' '    skill: intake' '  - id: lint' '    skill: lint' \
                  '  - id: deliver' '    skill: deliver')
OUT=$(bash "$EVAL" "$P" "$FACTDIR/no-design-no-components.yaml")
assert_eq "nothing skipped" "0" "$(grep -c '^skipped:' <<< "$OUT")"

echo "[semantics] within one block, every key must match"
P=$(mkpack andblock '  - id: intake' '    skill: intake' \
    '  - id: extract' '    skill: extract' '    when:' \
    '      - { design_source: true, has_description: true }' \
    '  - id: deliver' '    skill: deliver')
OUT=$(bash "$EVAL" "$P" "$TMP/design.yaml")
assert_contains "both keys matching runs it" "run: extract" "$OUT"
sed 's/has_description: true/has_description: false/' "$TMP/design.yaml" > "$TMP/one-off.yaml"
OUT=$(bash "$EVAL" "$P" "$TMP/one-off.yaml")
assert_contains "one key failing skips it" "skipped: extract" "$OUT"
assert_contains "the rendering keeps both keys, in field order" \
  "design_source=true AND has_description=true" "$OUT"

echo "[semantics] a field the record does not carry matches nothing"
cat > "$TMP/sparse.yaml" <<'EOF'
item_id: "4001"
item_type: task
EOF
P=$(mkpack missing '  - id: intake' '    skill: intake' \
    '  - id: extract' '    skill: extract' '    when:' '      - { design_source: true }' \
    '  - id: deliver' '    skill: deliver')
OUT=$(bash "$EVAL" "$P" "$TMP/sparse.yaml")
assert_contains "absent boolean skips the stage" "skipped: extract" "$OUT"

echo "[semantics] an absent list and an empty list are both 'empty'"
P=$(mkpack listempty '  - id: intake' '    skill: intake' \
    '  - id: baseline' '    skill: baseline' '    when:' '      - { components: empty }' \
    '  - id: deliver' '    skill: deliver')
OUT=$(bash "$EVAL" "$P" "$TMP/sparse.yaml")
assert_contains "an absent list counts as empty" "run: baseline" "$OUT"
OUT=$(bash "$EVAL" "$P" "$FACTDIR/no-design-with-component.yaml")
assert_contains "a populated list does not" "skipped: baseline" "$OUT"

echo "[semantics] a null value matches nothing"
cat > "$TMP/nulled.yaml" <<'EOF'
item_id: "4002"
item_type: task
design_source: null
EOF
P=$(mkpack nulled '  - id: intake' '    skill: intake' \
    '  - id: extract' '    skill: extract' '    when:' '      - { design_source: true }' \
    '  - id: deliver' '    skill: deliver')
OUT=$(bash "$EVAL" "$P" "$TMP/nulled.yaml")
assert_contains "null skips the stage" "skipped: extract" "$OUT"

# --- contract violations ----------------------------------------------------

echo "[reject] a when: key that is not a fact-record field"
P=$(mkpack badkey '  - id: intake' '    skill: intake' \
    '  - id: extract' '    skill: extract' '    when:' '      - { design_requested: true }' \
    '  - id: deliver' '    skill: deliver')
OUT=$(bash "$EVAL" "$P" "$FACTDIR/valid.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the field" "design_requested" "$OUT"

echo "[reject] a list field compared against a boolean"
P=$(mkpack badlist '  - id: intake' '    skill: intake' \
    '  - id: baseline' '    skill: baseline' '    when:' '      - { components: true }' \
    '  - id: deliver' '    skill: deliver')
OUT=$(bash "$EVAL" "$P" "$FACTDIR/valid.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the right values" "present" "$OUT"

echo "[reject] a boolean field compared against a list value"
P=$(mkpack badbool '  - id: intake' '    skill: intake' \
    '  - id: extract' '    skill: extract' '    when:' '      - { design_source: empty }' \
    '  - id: deliver' '    skill: deliver')
OUT=$(bash "$EVAL" "$P" "$FACTDIR/valid.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"

echo "[reject] when: present with no blocks"
P=$(mkpack emptywhen '  - id: intake' '    skill: intake' \
    '  - id: extract' '    skill: extract' '    when:' \
    '  - id: deliver' '    skill: deliver')
OUT=$(bash "$EVAL" "$P" "$FACTDIR/valid.yaml" 2>&1); ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"

# --- usage ------------------------------------------------------------------

echo "[usage] missing arguments"
OUT=$(bash "$EVAL" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"
OUT=$(bash "$EVAL" "$FULL" 2>&1); ST=$?
assert_exit "one arg -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] a file that does not exist"
OUT=$(bash "$EVAL" "$FULL" "$TMP/absent.yaml" 2>&1); ST=$?
assert_exit "missing fact record -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
