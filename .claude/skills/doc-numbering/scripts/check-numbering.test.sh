#!/usr/bin/env bash
# Tests for check-numbering.sh. Run with:
#   bash .claude/skills/doc-numbering/scripts/check-numbering.test.sh
#
# No framework — exits 0 on success, 1 if any case failed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-numbering.sh"
TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/check-numbering-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

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

echo "=== check-numbering.sh tests ==="

echo "[usage]"
OUT=$(bash "$CHECK" 2>&1); assert_exit "no argument -> usage error" 2 $? "$OUT"
OUT=$(bash "$CHECK" "$TMPDIR_TEST/nope" 2>&1); assert_exit "missing path -> usage error" 2 $? "$OUT"

echo "[accept] distinct identifiers"
OK="$TMPDIR_TEST/ok"
mkdir -p "$OK"
printf '### G1 — first\n\nbody\n\n### G2 — second\n' > "$OK/gaps.md"
printf '## D1 — a decision\n\nbody\n\n## D2 — another\n' > "$OK/decisions.md"
OUT=$(bash "$CHECK" "$OK" 2>&1); RC=$?
assert_exit "no duplicates -> exit 0" 0 "$RC" "$OUT"
assert_contains "counts what it read" "4 identifiers across 2 files" "$OUT"

echo "[accept] a gap and a decision may share a number"
# G12 and D12 are numbered independently — treating them as a collision
# would force two registers to agree on a counter they do not share.
SHARED="$TMPDIR_TEST/shared"
mkdir -p "$SHARED"
printf '### G12 — a gap\n' > "$SHARED/gaps.md"
printf '## D12 — a decision\n' > "$SHARED/decisions.md"
OUT=$(bash "$CHECK" "$SHARED" 2>&1); RC=$?
assert_exit "G12 alongside D12 -> exit 0" 0 "$RC" "$OUT"

echo "[reject] the same gap number filed twice in one file"
DUP="$TMPDIR_TEST/dup"
mkdir -p "$DUP"
printf '### G7 — one track filed this\n\nbody\n\n### G7 — the other track filed this\n' > "$DUP/gaps.md"
OUT=$(bash "$CHECK" "$DUP" 2>&1); RC=$?
assert_exit "duplicate -> exit 1" 1 "$RC" "$OUT"
assert_contains "names the identifier" "'G7' is claimed more than once" "$OUT"
assert_contains "names the first location" "gaps.md:1" "$OUT"
assert_contains "names the second location" "gaps.md:5" "$OUT"
assert_contains "says what to do about it" "renumber the later one" "$OUT"

echo "[reject] the same decision number across two files"
CROSS="$TMPDIR_TEST/cross"
mkdir -p "$CROSS"
printf '## D42 — core sense\n' > "$CROSS/core.md"
printf '## D42 — platform sense\n' > "$CROSS/platform.md"
OUT=$(bash "$CHECK" "$CROSS" 2>&1); RC=$?
assert_exit "cross-file duplicate -> exit 1" 1 "$RC" "$OUT"
assert_contains "names both files" "core.md:1" "$OUT"
assert_contains "names both files" "platform.md:1" "$OUT"

echo "[reject] two duplicates are both reported"
TWO="$TMPDIR_TEST/two"
mkdir -p "$TWO"
printf '### G1 — a\n### G1 — b\n### G2 — c\n### G2 — d\n' > "$TWO/gaps.md"
OUT=$(bash "$CHECK" "$TWO" 2>&1); RC=$?
assert_exit "still exit 1" 1 "$RC" "$OUT"
assert_contains "reports the first" "'G1' is claimed" "$OUT"
assert_contains "reports the second" "'G2' is claimed" "$OUT"
assert_contains "counts them" "2 duplicated identifier(s)" "$OUT"

echo "[accept] a directory with no numbered headings at all"
EMPTY="$TMPDIR_TEST/empty"
mkdir -p "$EMPTY"
printf '# Just a document\n\nNo numbered headings here.\n' > "$EMPTY/notes.md"
OUT=$(bash "$CHECK" "$EMPTY" 2>&1); RC=$?
assert_exit "nothing to check -> exit 0" 0 "$RC" "$OUT"

echo "[files] naming the owners directly, rather than their directory"
# The intended use: a register owns its numbers, while a spec or a completion
# note that discusses one merely restates the heading. Pointing at the
# directory reports the discussion as a collision; naming the owner does not.
OWNERS="$TMPDIR_TEST/owners"
mkdir -p "$OWNERS"
printf '### G9 — the gap itself\n' > "$OWNERS/register.md"
printf '### G9 — the gap, restated by a document that discusses it\n' > "$OWNERS/discussion.md"
OUT=$(bash "$CHECK" "$OWNERS" 2>&1); RC=$?
assert_exit "the whole directory -> reports the discussion as a duplicate" 1 "$RC" "$OUT"
OUT=$(bash "$CHECK" "$OWNERS/register.md" 2>&1); RC=$?
assert_exit "naming the owning file alone -> exit 0" 0 "$RC" "$OUT"
assert_contains "counts just that file" "1 identifiers across 1 files" "$OUT"

echo "[files] a mix of files and directories"
OUT=$(bash "$CHECK" "$OWNERS/register.md" "$OK" 2>&1); RC=$?
assert_exit "file plus directory -> exit 0" 0 "$RC" "$OUT"

echo "[accept] several directories at once"
OUT=$(bash "$CHECK" "$OK" "$EMPTY" 2>&1); RC=$?
assert_exit "multiple directories -> exit 0" 0 "$RC" "$OUT"
OUT=$(bash "$CHECK" "$OK" "$DUP" 2>&1); RC=$?
assert_exit "a duplicate in any of them -> exit 1" 1 "$RC" "$OUT"

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "=== $PASS passed, 0 failed ==="
  exit 0
fi
echo "=== $PASS passed, $FAIL failed ==="
exit 1
