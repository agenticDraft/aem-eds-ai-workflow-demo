#!/usr/bin/env bash
# check-branch-length.test.sh — the branch-length checker (D539). No
# framework; exits 0 when every case passes, 1 otherwise.
#
# Usage:
#   bash check-branch-length.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-branch-length.sh"
REPO="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

PASS=0
FAIL=0

ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_eq()  { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2 — got: $3"; fi; }
assert_has() { if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "expected to contain: $2 — got: $3"; fi; }

# name_of_length <n> — a branch name exactly <n> characters long
name_of_length() { printf 'b%.0s' $(seq 1 "$1"); }

run() { OUT=$(bash "$CHECK" "$@" 2>&1); CODE=$?; }

echo "[ok] 22 and 23 characters"
run "$(name_of_length 22)"
assert_eq "22 → exit 0" "0" "$CODE"
assert_has "22 → ok line" "ok: branch=$(name_of_length 22) length=22 limit=23" "$OUT"
run "$(name_of_length 23)"
assert_eq "23 → exit 0" "0" "$CODE"
assert_has "23 → ok line" "ok: branch=$(name_of_length 23) length=23 limit=23" "$OUT"

echo "[too-long] 24 characters"
run "$(name_of_length 24)"
assert_eq "24 → exit 1" "1" "$CODE"
assert_has "24 → too-long line" "too-long: branch=$(name_of_length 24) length=24 limit=23" "$OUT"

echo "[real names] this task's branch and Task 3's"
run "phase-28-task-4-verify"
assert_eq "phase-28-task-4-verify (22) → ok" "0" "$CODE"
run "phase-28-task-3-draft-server"
assert_eq "phase-28-task-3-draft-server (28) → too-long" "1" "$CODE"
assert_has "names the length" "length=28 limit=23" "$OUT"

echo "[slash] a slash counts as one character, as the dev server replaces it with '-'"
run "feature/$(name_of_length 16)"
assert_eq "feature/ + 16 = 24 → too-long" "1" "$CODE"
assert_has "length 24" "length=24" "$OUT"

echo "[usage] no argument or an empty one"
run
assert_eq "no argument → exit 2" "2" "$CODE"
run ""
assert_eq "empty argument → exit 2" "2" "$CODE"

echo "[formula] 23 is 63 minus --<repo>--<owner> for this repository's origin"
ORIGIN=$(git -C "$REPO" remote get-url origin 2>/dev/null)
PATH_PART=$(printf '%s' "$ORIGIN" | sed -E 's#^[a-z+]+://[^/]+/##; s#^[^@]+@[^:]+:##; s#\.git$##')
OWNER=${PATH_PART%%/*}
NAME=${PATH_PART#*/}
if [ -z "$ORIGIN" ] || [ -z "$OWNER" ] || [ "$OWNER" == "$PATH_PART" ]; then
  bad "origin resolves to <owner>/<repo>" "origin: '$ORIGIN'"
else
  SUFFIX="--${NAME}--${OWNER}"
  FORMULA=$(( 63 - ${#SUFFIX} ))
  assert_eq "suffix is 40 characters" "40" "${#SUFFIX}"
  assert_eq "formula for this origin gives 23" "23" "$FORMULA"
  run "$(name_of_length 1)"
  assert_has "the checker's limit equals the formula" "limit=$FORMULA" "$OUT"
fi

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
