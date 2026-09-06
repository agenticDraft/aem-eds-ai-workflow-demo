#!/usr/bin/env bash
# Tests for validate-contracts.sh. Run with:
#   bash plugins/agentic-core/shared/lib/validate-contracts.test.sh
#
# No framework — exits 0 on success, 1 on first failure. Confirms: a branching
# fixture with matching nodes/headings passes; a linear fixture with neither
# section passes trivially; a missing heading and an orphan heading are each
# caught and named; the real core (plugins/agentic-core) passes as built;
# single-file mode and directory mode agree; and injecting a mismatch into a
# real shipped skill, then reverting, makes that same check fail and pass
# again.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-contracts.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/skill-authoring"
CORE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

echo "=== validate-contracts.sh tests ==="

echo "[accept] a branching fixture whose nodes and headings match"
OUT=$(bash "$VALIDATOR" "$FIXDIR/clean" 2>&1); ST=$?
assert_exit "clean fixture accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports files scanned / branching" "valid: skill-authoring" "$OUT"

echo "[accept] the same fixture, checked as a single file"
OUT=$(bash "$VALIDATOR" "$FIXDIR/clean/SKILL.md" 2>&1); ST=$?
assert_exit "single-file mode accepted (exit 0)" 0 $ST "$OUT"

echo "[accept] a linear fixture with no ## Flow / ## Node Details at all"
OUT=$(bash "$VALIDATOR" "$FIXDIR/clean-linear" 2>&1); ST=$?
assert_exit "linear fixture accepted trivially (exit 0)" 0 $ST "$OUT"

echo "[reject] a digraph node with no matching ### heading"
OUT=$(bash "$VALIDATOR" "$FIXDIR/violation-missing-heading" 2>&1); ST=$?
assert_exit "missing-heading fixture rejected (exit 1)" 1 $ST "$OUT"
assert_contains "names the node" "'Do the thing'" "$OUT"
assert_contains "names the direction" "no matching '### heading'" "$OUT"

echo "[reject] a ### heading with no matching digraph node"
OUT=$(bash "$VALIDATOR" "$FIXDIR/violation-orphan-heading" 2>&1); ST=$?
assert_exit "orphan-heading fixture rejected (exit 1)" 1 $ST "$OUT"
assert_contains "names the heading" "'Never reached'" "$OUT"
assert_contains "names the direction" "no matching digraph node" "$OUT"

echo "[accept] the real core, as built"
OUT=$(bash "$VALIDATOR" "$CORE_ROOT" 2>&1); ST=$?
assert_exit "plugins/agentic-core accepted (exit 0)" 0 $ST "$OUT"
assert_contains "run-route counted as branching" "branching)" "$OUT"

echo "[reject then accept] dropping a ### heading from a real shipped skill, then reverting"
PROBE="$CORE_ROOT/skills/run-route/SKILL.md"
if [[ ! -f "$PROBE" ]]; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: probe file not found: $PROBE"
else
  BACKUP="$(mktemp "${TMPDIR:-/tmp}/validate-contracts-probe.XXXXXX")"
  cp "$PROBE" "$BACKUP"
  trap 'cp "$BACKUP" "$PROBE"; rm -f "$BACKUP"' EXIT

  # Remove the "### blocked" heading — its digraph node stays, so this is now a
  # node with no matching heading.
  awk '
    /^### blocked$/ { skip = 1; next }
    skip && /^### / { skip = 0 }
    !skip
  ' "$PROBE" > "$PROBE.tmp" && mv "$PROBE.tmp" "$PROBE"

  OUT=$(bash "$VALIDATOR" "$PROBE" 2>&1); ST=$?
  cp "$BACKUP" "$PROBE"
  assert_exit "run-route with the dropped heading rejected (exit 1)" 1 $ST "$OUT"
  assert_contains "reason names the orphaned node" "'blocked'" "$OUT"

  OUT=$(bash "$VALIDATOR" "$PROBE" 2>&1); ST=$?
  assert_exit "run-route accepted again after revert (exit 0)" 0 $ST "$OUT"

  trap - EXIT
  rm -f "$BACKUP"
fi

echo "[usage] missing argument"
OUT=$(bash "$VALIDATOR" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] path not found"
OUT=$(bash "$VALIDATOR" "$SCRIPT_DIR/does-not-exist" 2>&1); ST=$?
assert_exit "missing path -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
