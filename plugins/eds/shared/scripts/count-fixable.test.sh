#!/usr/bin/env bash
# count-fixable.test.sh — the fixable-mismatch counter (D536). No framework;
# exits 0 when every case passes, 1 otherwise.
#
# Usage:
#   bash count-fixable.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COUNT="$SCRIPT_DIR/count-fixable.sh"

TMP_ROOT="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "$TMP_ROOT/count-fixable.XXXXXX") || { echo "mktemp failed" >&2; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "no work dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_eq() { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2 — got: $3"; fi; }

# check <name> <content> — writes a check file, runs the counter on it
check() {
  F="$WORK/$1.txt"
  printf '%s' "$2" > "$F"
  OUT=$(bash "$COUNT" "$F" 2>&1); CODE=$?
}

echo "[zero] only [content-asset gap] lines"
check gaps-only $'[content-asset gap] 1440 vs the reference: text geometry, with DM Sans not declared\n[content-asset gap] 1440 vs the reference: the hero photo is absent from the project\n'
assert_eq "two gap lines → exit 0" "0" "$CODE"
assert_eq "two gap lines → nothing-fixable line" "nothing-fixable: fixable=0 gaps=2 approx=0" "$OUT"

echo "[one] one [fixable] among gaps"
check one-fixable $'[content-asset gap] 1440 vs the reference: text geometry\n[fixable] .table th padding-top: expected 12px, measured 8px\n'
assert_eq "one fixable → exit 1" "1" "$CODE"
assert_eq "one fixable → fixable line" "fixable: fixable=1 gaps=1 approx=0" "$OUT"

echo "[untagged] a line with no tag counts as fixable"
check untagged $'[content-asset gap] 1440 vs the reference: text geometry\nthe header row is 4px taller than the design\n'
assert_eq "untagged → exit 1" "1" "$CODE"
assert_eq "untagged → counted as fixable" "fixable: fixable=1 gaps=1 approx=0" "$OUT"

echo "[untagged] a gap tag that does not start the line is not a tag"
check tag-mid-line $'1440 vs the reference [content-asset gap]: text geometry\n'
assert_eq "tag mid-line → exit 1" "1" "$CODE"
assert_eq "tag mid-line → fixable" "fixable: fixable=1 gaps=0 approx=0" "$OUT"

echo "[empty] an empty file"
check empty ""
assert_eq "empty → exit 0" "0" "$CODE"
assert_eq "empty → zero" "nothing-fixable: fixable=0 gaps=0 approx=0" "$OUT"

echo "[blank] blank and whitespace-only lines are not mismatches"
check blanks $'\n   \n[content-asset gap] missing photo\n\n'
assert_eq "blanks → exit 0" "0" "$CODE"
assert_eq "blanks → one gap, zero fixable" "nothing-fixable: fixable=0 gaps=1 approx=0" "$OUT"

echo "[leading space] leading whitespace before a tag is allowed"
check indented $'  [content-asset gap] missing photo\n\t[fixable] color: expected #000, measured #111\n'
assert_eq "indented → exit 1" "1" "$CODE"
assert_eq "indented → one of each" "fixable: fixable=1 gaps=1 approx=0" "$OUT"

echo "[crlf] a CRLF file counts the same"
check crlf $'[content-asset gap] missing photo\r\n\r\n'
assert_eq "crlf → exit 0" "0" "$CODE"
assert_eq "crlf → one gap" "nothing-fixable: fixable=0 gaps=1 approx=0" "$OUT"

echo "[no final newline] the last line still counts"
check no-newline $'[content-asset gap] a\n[fixable] b'
assert_eq "no final newline → exit 1" "1" "$CODE"
assert_eq "no final newline → last line counted" "fixable: fixable=1 gaps=1 approx=0" "$OUT"

echo "[several] every fixable line counts"
check several $'[fixable] a\n[fixable] b\nc\n[content-asset gap] d\n'
assert_eq "three fixable → exit 1" "1" "$CODE"
assert_eq "three fixable" "fixable: fixable=3 gaps=1 approx=0" "$OUT"

echo "[approx] [content-dependent] lines are listed, never fixable"
check approx-only $'[content-dependent] .t td p width: expected 94px, measured box 120x20px\n[content-dependent] .t th height: expected 96px, measured box 400x104px\n'
assert_eq "only content-dependent → exit 0" "0" "$CODE"
assert_eq "only content-dependent → nothing fixable, counted apart" "nothing-fixable: fixable=0 gaps=0 approx=2" "$OUT"

echo "[approx] content-dependent among gaps and a fixable"
check approx-mix $'[content-dependent] .t td p width: expected 94px, measured box 120x20px\n[content-asset gap] missing photo\n[fixable] .t th padding-top: expected 40px, measured 32px\n'
assert_eq "mixed → exit 1" "1" "$CODE"
assert_eq "mixed → each counted in its own bucket" "fixable: fixable=1 gaps=1 approx=1" "$OUT"

echo "[approx] content-dependent with gaps only"
check approx-gaps $'  [content-dependent] a\n[content-asset gap] b\r\n'
assert_eq "content-dependent + gap → exit 0" "0" "$CODE"
assert_eq "content-dependent + gap → nothing fixable" "nothing-fixable: fixable=0 gaps=1 approx=1" "$OUT"

echo "[approx] the tag must start the line"
check approx-mid $'width [content-dependent]: expected 94px\n'
assert_eq "tag mid-line → exit 1" "1" "$CODE"
assert_eq "tag mid-line → fixable" "fixable: fixable=1 gaps=0 approx=0" "$OUT"

echo "[usage] missing argument, missing file"
OUT=$(bash "$COUNT" 2>&1); CODE=$?
assert_eq "no argument → exit 2" "2" "$CODE"
OUT=$(bash "$COUNT" "$WORK/does-not-exist.txt" 2>&1); CODE=$?
assert_eq "missing file → exit 2" "2" "$CODE"

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
