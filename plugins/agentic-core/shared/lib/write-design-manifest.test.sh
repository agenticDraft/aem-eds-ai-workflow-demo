#!/usr/bin/env bash
# Tests for write-design-manifest.sh. Run with:
#   bash plugins/agentic-core/shared/lib/write-design-manifest.test.sh
#
# No framework — exits 0 on success, 1 on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/write-design-manifest.sh"
VALIDATOR="$SCRIPT_DIR/validate-design-manifest.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/design-manifest/artifacts"

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
    echo "    expected to contain: $needle"
    echo "    got: $haystack"
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected NOT to contain: $needle"
    echo "    got: $haystack"
  fi
}

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

echo "=== write-design-manifest.sh tests ==="

echo "[write] two frames, one shared value, one unresolvable, no conflict"
OUTDIR="$TMPDIR_ROOT/happy"
OUT=$(bash "$WRITER" "$OUTDIR" "$FIXDIR/frame-a.json" "$FIXDIR/frame-b.json" 2>&1); ST=$?
assert_exit "writer succeeds (exit 0)" 0 $ST "$OUT"

MANIFEST_OUT=$(bash "$VALIDATOR" "$OUTDIR/design-system.md" 2>&1); MANIFEST_ST=$?
assert_exit "produced manifest validates" 0 $MANIFEST_ST "$MANIFEST_OUT"
assert_contains "reports 3 resolvable + 1 unresolvable = 4 distinct tokens, 2 frames" "4 tokens, 2 frames" "$MANIFEST_OUT"

MANIFEST_CONTENT=$(cat "$OUTDIR/design-system.md")
assert_contains "shared value deduplicated, not repeated" "Accent/Accent 4" "$MANIFEST_CONTENT"
assert_contains "the Font composite went to unresolvable" "Heading 1" "$MANIFEST_CONTENT"
assert_contains "unresolvable reason is stated, not blank" "not a recognized color or dimension" "$MANIFEST_CONTENT"

CSS_CONTENT=$(cat "$OUTDIR/proposed-tokens.css")
assert_contains "resolved color became a custom property" "--accent-accent-4: #000000;" "$CSS_CONTENT"
assert_not_contains "the unresolvable composite never reached the CSS file" "Font(" "$CSS_CONTENT"

BREAKPOINTS_CONTENT=$(cat "$OUTDIR/proposed-breakpoints.md")
assert_contains "frame-a's width recorded" "width 1220" "$BREAKPOINTS_CONTENT"
assert_contains "frame-b's width recorded" "width 1280" "$BREAKPOINTS_CONTENT"

echo "[write] a frame with no variables at all is a normal result"
OUTDIR2="$TMPDIR_ROOT/no-vars"
OUT=$(bash "$WRITER" "$OUTDIR2" "$FIXDIR/no-variables.json" 2>&1); ST=$?
assert_exit "writer succeeds on an empty-variables frame (exit 0)" 0 $ST "$OUT"
MANIFEST2=$(cat "$OUTDIR2/design-system.md")
assert_contains "values written as the empty-list literal" "values: []" "$MANIFEST2"
assert_contains "unresolvable written as the empty-list literal" "unresolvable: []" "$MANIFEST2"

echo "[reject] the same variable name resolving to two different values"
OUTDIR3="$TMPDIR_ROOT/conflict"
OUT=$(bash "$WRITER" "$OUTDIR3" "$FIXDIR/conflict-a.json" "$FIXDIR/conflict-b.json" 2>&1); ST=$?
assert_exit "writer refuses on a conflict (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the conflicting name" "Accent/Accent 4" "$OUT"
assert_contains "reason names both conflicting values" "#000000" "$OUT"
[[ -f "$OUTDIR3/design-system.md" ]] && { FAIL=$((FAIL + 1)); echo "  FAIL: no manifest should be written on a conflict"; } || { PASS=$((PASS + 1)); echo "  ok: no manifest written on a conflict"; }

echo "[usage] an artifact missing a required field"
OUTDIR4="$TMPDIR_ROOT/missing-field"
OUT=$(bash "$WRITER" "$OUTDIR4" "$FIXDIR/missing-field.json" 2>&1); ST=$?
assert_exit "missing geometry.width -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] too few arguments"
OUT=$(bash "$WRITER" "$TMPDIR_ROOT/nothing" 2>&1); ST=$?
assert_exit "no artifacts given -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
