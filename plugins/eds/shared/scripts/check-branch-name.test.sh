#!/usr/bin/env bash
# check-branch-name.test.sh — the branch-name rule (D539, G31). No framework;
# exits 0 when every case passes, 1 otherwise.
#
# Usage:
#   bash check-branch-name.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-branch-name.sh"
LENGTH_CHECK="$SCRIPT_DIR/check-branch-length.sh"
PREVIEW="$SCRIPT_DIR/preview-url.sh"

PASS=0
FAIL=0

ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_eq()  { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2 — got: $3"; fi; }
assert_has() { if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "expected to contain: $2 — got: $3"; fi; }

name_of_length() { printf 'b%.0s' $(seq 1 "$1"); }

run() { OUT=$(bash "$CHECK" "$@" 2>&1); CODE=$?; }

echo "[ok] lower-case letters, digits, '-' and '/', at most 23"
for b in psi-preview-url eds-18 phase-9-task-3 feature/cards "$(name_of_length 23)"; do
  run "$b"
  assert_eq "$b → exit 0" "0" "$CODE"
  assert_has "$b → ok line" "ok: branch=$b" "$OUT"
done

echo "[too-long] 24 characters and a real over-long name"
run "$(name_of_length 24)"
assert_eq "24 → exit 1" "1" "$CODE"
assert_has "24 → too-long line" "too-long: branch=$(name_of_length 24) length=24 limit=23" "$OUT"
run phase-9-task-2-trigger-path
assert_eq "phase-9-task-2-trigger-path → exit 1" "1" "$CODE"
assert_has "names the length" "length=27 limit=23" "$OUT"

echo "[bad-chars] anything else, including upper case"
for b in eds_18 eds.18 'eds+18' 'eds@18' EDS-18 Feature/cards; do
  run "$b"
  assert_eq "$b → exit 3" "3" "$CODE"
  assert_has "$b → bad-chars line" "bad-chars: branch=$b allowed=a-z0-9-/" "$OUT"
done

echo "[both] a long name with a bad character reports the characters first"
run "$(name_of_length 30)_x"
assert_eq "exit 3" "3" "$CODE"

echo "[usage] no argument or an empty one"
run
assert_eq "no argument → exit 2" "2" "$CODE"
run ""
assert_eq "empty argument → exit 2" "2" "$CODE"

echo "[agreement] every name this accepts gets a preview URL from preview-url.sh"
WORK=$(TMPDIR="${TMPDIR:-/tmp}" mktemp -d "${TMPDIR:-/tmp}/check-branch-name.XXXXXX")
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
  bad "temporary directory"
else
  trap 'rm -rf "$WORK"' EXIT
  git init -q -b main "$WORK/r"
  git -C "$WORK/r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  git -C "$WORK/r" switch -q -c work
  mkdir -p "$WORK/r/blocks/a" && echo x > "$WORK/r/blocks/a/a.js"
  AGREE=1
  for b in eds-18 feature/cards "$(name_of_length 23)" "$(name_of_length 24)" eds_18 eds.18; do
    bash "$CHECK" "$b" >/dev/null 2>&1; ACCEPT=$?
    TYPE=$(cd "$WORK/r" && bash "$PREVIEW" --branch "$b" --base main 2>&1 >/dev/null)
    if [ "$ACCEPT" -eq 0 ] && [[ "$TYPE" != *"pr-type: served"* ]]; then
      AGREE=0; bad "$b accepted but gets no URL" "$TYPE"
    fi
  done
  [ "$AGREE" -eq 1 ] && ok "accepted names all get a URL"
fi

echo "[single limit] the length comes from check-branch-length.sh"
LIMIT_LINE=$(bash "$LENGTH_CHECK" x)
run x
assert_has "same limit" "${LIMIT_LINE#ok: branch=x }" "$OUT"

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
