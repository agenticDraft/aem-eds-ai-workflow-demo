#!/usr/bin/env bash
# Tests for validate-naming-rule.sh. Run with:
#   bash plugins/agentic-core/shared/lib/validate-naming-rule.test.sh
#
# No framework — exits 0 on success, 1 on first failure. Confirms: a clean
# fixture passes; a bare product name fails and names the term and location;
# this project's own borrowed-material source (dx-aem-flow, dx-core) fails
# exactly the same way, no exception; the real core (plugins/agentic-core)
# passes as built; and injecting a product name into a real core file, then
# reverting it, makes that same check fail and pass again.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-naming-rule.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/naming-rule"
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

echo "=== validate-naming-rule.sh tests ==="

echo "[accept] a fixture naming roles only, no product"
OUT=$(bash "$VALIDATOR" "$FIXDIR/clean" 2>&1); ST=$?
assert_exit "clean fixture accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports files/terms scanned" "valid: naming rule" "$OUT"

echo "[reject] a fixture naming a tracker product directly"
OUT=$(bash "$VALIDATOR" "$FIXDIR/violation" 2>&1); ST=$?
assert_exit "violation fixture rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names the term" "'Jira'" "$OUT"
assert_contains "reason names the file" "note.md" "$OUT"

echo "[reject] dx-aem-flow and dx-core, this project's own borrowed-material source — no exception"
OUT=$(bash "$VALIDATOR" "$FIXDIR/bare-dx-terms" 2>&1); ST=$?
assert_exit "bare-dx-terms rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names dx-aem-flow" "'dx-aem-flow'" "$OUT"
assert_contains "reason names dx-core" "'dx-core'" "$OUT"

echo "[accept] the real core, as built"
OUT=$(bash "$VALIDATOR" "$CORE_ROOT" 2>&1); ST=$?
assert_exit "plugins/agentic-core accepted (exit 0)" 0 $ST "$OUT"

echo "[reject then accept] injecting a product name into a real core file, then reverting"
PROBE="$CORE_ROOT/shared/pack-manifest.md"
if [[ ! -f "$PROBE" ]]; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: probe file not found: $PROBE"
else
  BACKUP="$(mktemp "${TMPDIR:-/tmp}/validate-naming-rule-probe.XXXXXX")"
  cp "$PROBE" "$BACKUP"
  trap 'cp "$BACKUP" "$PROBE"; rm -f "$BACKUP"' EXIT

  printf '\n# TEMP: this line names Figma directly, for validator self-test only\n' >> "$PROBE"
  OUT=$(bash "$VALIDATOR" "$CORE_ROOT" 2>&1); ST=$?
  cp "$BACKUP" "$PROBE"
  assert_exit "core with the injected name rejected (exit 1)" 1 $ST "$OUT"
  assert_contains "reason names the injected term" "'Figma'" "$OUT"

  OUT=$(bash "$VALIDATOR" "$CORE_ROOT" 2>&1); ST=$?
  assert_exit "core accepted again after revert (exit 0)" 0 $ST "$OUT"

  trap - EXIT
  rm -f "$BACKUP"
fi

echo "[usage] missing argument"
OUT=$(bash "$VALIDATOR" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] directory not found"
OUT=$(bash "$VALIDATOR" "$SCRIPT_DIR/does-not-exist" 2>&1); ST=$?
assert_exit "missing directory -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
