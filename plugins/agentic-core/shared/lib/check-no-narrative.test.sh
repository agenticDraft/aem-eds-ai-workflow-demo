#!/usr/bin/env bash
# Tests for check-no-narrative.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-no-narrative.test.sh
#
# No framework — exits 0 on success, 1 if anything failed.
#
# Half of these cases are near-misses rather than violations. Both rules were
# written, run against the real tree, and found to fire on files that were
# fine — a heading listing input files, and a fixture holding a plausible URL.
# A check that cries wolf gets ignored, so the cases that must NOT fire are
# kept here as the guard against tightening it back into noise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-no-narrative.sh"
FIX="$SCRIPT_DIR/../fixtures/no-narrative"

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

echo "=== check-no-narrative.sh tests ==="

# --- usage ------------------------------------------------------------------
OUT="$(bash "$CHECK" 2>&1)"; assert_exit "no argument -> usage error" 2 $? "$OUT"
OUT="$(bash "$CHECK" "$FIX/does-not-exist" 2>&1)"
assert_exit "root that is not a directory -> usage error" 2 $? "$OUT"
assert_contains "and says so" "not a directory" "$OUT"

# --- the clean case ---------------------------------------------------------
echo "[accept] a shipped file naming only what the repository publishes"
OUT="$(bash "$CHECK" "$FIX/clean" 2>&1)"; ST=$?
assert_exit "accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports what it scanned" "valid: no narrative" "$OUT"

# --- rule 1 -----------------------------------------------------------------
echo "[reject] a shipped file citing a path this repository does not publish"
OUT="$(bash "$CHECK" "$FIX/cites-unpublished" 2>&1)"; ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "names the path" "01-core-contracts.md" "$OUT"
assert_contains "says why it matters" "cannot open it" "$OUT"

# --- rule 2 -----------------------------------------------------------------
echo "[reject] a shipped file carrying its own rationale section"
OUT="$(bash "$CHECK" "$FIX/provenance-section" 2>&1)"; ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "names the section" "Rationale" "$OUT"
assert_contains "says where it belongs" "belongs with the task" "$OUT"

# --- the near-misses --------------------------------------------------------
# Both of these were real false positives before the rules were narrowed, found
# by running the check against the tree rather than by imagining cases.
echo "[accept] a heading that begins with a flagged word but is not a rationale"
OUT="$(bash "$CHECK" "$FIX/near-misses" 2>&1)"; ST=$?
assert_exit "'## Source files' is not flagged (exit 0)" 0 $ST "$OUT"
[[ "$OUT" != *"Source"* ]]
assert_exit "and is not mentioned at all" 0 $? "$OUT"

echo "[accept] a path-shaped string that resolves to nothing is not a citation"
[[ "$OUT" != *"drafts/4001"* ]]
assert_exit "a fixture URL is not flagged" 0 $? "$OUT"

# --- the real tree ----------------------------------------------------------
# The point of the check is the shipped packs, so it runs against them here.
# If this ever fails, the finding is real and belongs in the pack, not here.
echo "[accept] every shipped pack in this repository"
for pack in agentic-core eds; do
  OUT="$(bash "$CHECK" "$SCRIPT_DIR/../../../$pack" 2>&1)"; ST=$?
  assert_exit "plugins/$pack is clean (exit 0)" 0 $ST "$OUT"
done

if [[ "$FAIL" -eq 0 ]]; then
  echo "=== $PASS passed, 0 failed ==="
  exit 0
fi
echo "=== $PASS passed, $FAIL failed ==="
exit 1
