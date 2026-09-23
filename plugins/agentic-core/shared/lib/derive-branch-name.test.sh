#!/usr/bin/env bash
# Tests for derive-branch-name.sh. Run with:
#   bash plugins/agentic-core/shared/lib/derive-branch-name.test.sh
#
# No framework — exits 0 on success, 1 if any case fails.
#
# The property under test is determinism: the same work item id always yields
# the same branch name, with nothing left to a caller's judgement. The cases
# below are the shapes a real tracker produces, plus the ones that must be
# refused rather than turned into a name nobody could predict.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVE="$SCRIPT_DIR/derive-branch-name.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# assert_name <input> <expected>
assert_name() {
  local input="$1" expected="$2" out status
  out="$(bash "$DERIVE" "$input" 2>&1)"; status=$?
  if [[ "$status" != 0 ]]; then
    bad "'$input' -> '$expected'" "expected exit 0, got $status" "output: $out"; return
  fi
  if [[ "$out" != "$expected" ]]; then
    bad "'$input' -> '$expected'" "got: '$out'"; return
  fi
  if ! git check-ref-format --branch "$out" >/dev/null 2>&1; then
    bad "'$input' -> '$expected'" "'$out' is not a valid git ref name"; return
  fi
  ok "'$input' -> '$expected'"
}

# assert_refused <desc> <input...>
assert_refused() {
  local desc="$1"; shift
  local status
  bash "$DERIVE" "$@" >/dev/null 2>&1; status=$?
  [[ "$status" == 2 ]] && ok "$desc" || bad "$desc" "expected exit 2, got $status"
}

echo "=== derive-branch-name.sh tests ==="

echo "[shapes a tracker actually produces]"
assert_name "ITEM-13"     "item-13"
assert_name "PROJ-1234"  "proj-1234"
assert_name "2416553"    "2416553"
assert_name "AB-1"       "ab-1"

echo "[idempotent — deriving from an already-derived name changes nothing]"
assert_name "item-13"     "item-13"

echo "[normalisation]"
assert_name "ITEM 13"     "item-13"
assert_name "ITEM--13"    "item-13"
assert_name "-ITEM-13-"   "item-13"
assert_name "ITEM_13"     "item-13"
assert_name "ITEM/13"     "item-13"
assert_name "ITEM.13"     "item-13"

echo "[determinism — the same id twice is the same name]"
A="$(bash "$DERIVE" "ITEM-13" 2>/dev/null)"
B="$(bash "$DERIVE" "ITEM-13" 2>/dev/null)"
[[ "$A" == "$B" && -n "$A" ]] && ok "the same id yields the same name" || bad "the same id yields the same name" "'$A' vs '$B'"

echo "[refused — a name nobody could predict is worse than none]"
assert_refused "no argument"
assert_refused "an empty id" ""
assert_refused "an id with nothing usable in it" "!!!"
assert_refused "an id that is only separators" "---"
assert_refused "more than one argument" "ITEM-13" "extra"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
