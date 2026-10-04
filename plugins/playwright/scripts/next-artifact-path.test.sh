#!/usr/bin/env bash
# Tests for next-artifact-path.cjs. Run with:
#   bash plugins/playwright/scripts/next-artifact-path.test.sh
#
# No framework, and no browser — exits 0 on success, 1 if anything failed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEXT="$SCRIPT_DIR/next-artifact-path.cjs"
TMP_ROOT="${TMPDIR:-/tmp}"
WORK="$(mktemp -d "${TMP_ROOT%/}/next-artifact-path-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    got:      $actual"
  fi
}

# A fresh directory per case, so no case sees another's files.
case_dir() {
  local d="$WORK/$1"
  mkdir -p "$d"
  echo "$d"
}

echo "=== next-artifact-path.cjs tests ==="

echo "[first] an empty directory gives -1"
D=$(case_dir empty)
assert_eq "suffix 1" "$D/capture-x-1440-1.png" "$(node "$NEXT" "$D" capture-x-1440 png)"

echo "[next] an existing -1 gives -2"
D=$(case_dir one); touch "$D/capture-x-1440-1.png"
assert_eq "suffix 2" "$D/capture-x-1440-2.png" "$(node "$NEXT" "$D" capture-x-1440 png)"

echo "[gap] -1 and -3 existing gives -2"
D=$(case_dir gap); touch "$D/capture-x-1440-1.png" "$D/capture-x-1440-3.png"
assert_eq "fills the gap" "$D/capture-x-1440-2.png" "$(node "$NEXT" "$D" capture-x-1440 png)"

echo "[independent] a different width does not advance the count"
D=$(case_dir width); touch "$D/capture-x-375-1.png" "$D/capture-x-375-2.png"
assert_eq "1440 starts at 1" "$D/capture-x-1440-1.png" "$(node "$NEXT" "$D" capture-x-1440 png)"

echo "[independent] a different target does not advance the count"
D=$(case_dir target); touch "$D/capture-y-1440-1.png"
assert_eq "x starts at 1" "$D/capture-x-1440-1.png" "$(node "$NEXT" "$D" capture-x-1440 png)"

echo "[independent] a base that extends this one does not advance the count"
D=$(case_dir prefix); touch "$D/capture-x-14400-1.png"
assert_eq "1440 starts at 1" "$D/capture-x-1440-1.png" "$(node "$NEXT" "$D" capture-x-1440 png)"

echo "[independent] a different extension does not advance the count"
D=$(case_dir ext); touch "$D/render-x-1.json"
assert_eq "png starts at 1" "$D/render-x-1.png" "$(node "$NEXT" "$D" render-x png)"

echo "[reserve] the returned path exists on return, so two calls never share a name"
D=$(case_dir reserve)
FIRST=$(node "$NEXT" "$D" capture-x-1440 png)
[[ -e "$FIRST" ]] && R=yes || R=no
assert_eq "the first path is reserved" "yes" "$R"
assert_eq "the second call gets -2" "$D/capture-x-1440-2.png" "$(node "$NEXT" "$D" capture-x-1440 png)"

echo "[mkdir] a missing directory is created"
D="$WORK/missing/nested"
assert_eq "suffix 1 in a new directory" "$D/measure-x-1.json" "$(node "$NEXT" "$D" measure-x json)"

echo "[usage] wrong argument count or a malformed extension exits 2"
node "$NEXT" "$WORK" capture-x >/dev/null 2>&1; assert_eq "two arguments" "2" "$?"
node "$NEXT" "$WORK" capture-x .png >/dev/null 2>&1; assert_eq "an extension with a dot" "2" "$?"
node "$NEXT" "$WORK" "" png >/dev/null 2>&1; assert_eq "an empty base" "2" "$?"

echo ""
echo "passed: $PASS, failed: $FAIL"
(( FAIL == 0 ))
