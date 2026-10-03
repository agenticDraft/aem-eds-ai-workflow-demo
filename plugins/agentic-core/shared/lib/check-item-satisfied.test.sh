#!/usr/bin/env bash
# Tests for check-item-satisfied.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-item-satisfied.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Each case writes
# a check_status envelope in the shape the operation emits.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-item-satisfied.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-item-satisfied.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

envelope() {  # envelope <file> <verdict> <summary> [change_state]
  {
    printf '## Result\nverdict: %s\nsummary: %s\nartifacts: []\nnext_action: none\n' "$2" "$3"
    [[ -n "${4:-}" ]] && printf 'change_state: %s\n' "$4"
  } > "$1"
}
run() { OUT="$(bash "$CHECK" "$@" 2>&1)"; STATUS=$?; }

echo "# a merged change for the item's branch"
envelope "$WORK/merged.txt" pass "Retrieved checks for item-18 (#170: 3 pass)." merged
run "$WORK/merged.txt" ITEM-18
[[ "$STATUS" -eq 1 ]] && ok "exits 1" || bad "exits 1" "got $STATUS" "$OUT"
grep -q "^satisfied	the change for this item is already merged (Retrieved checks for item-18 (#170: 3 pass).)$" <<<"$OUT" \
  && ok "the satisfied line carries the lookup's summary" || bad "the satisfied line carries the lookup's summary" "$OUT"
grep -q "^note	Already satisfied: the change for ITEM-18 is merged (Retrieved checks for item-18 (#170: 3 pass).). Nothing is left to deliver" <<<"$OUT" \
  && ok "the note names the item and the change" || bad "the note names the item and the change" "$OUT"
grep -q "Close the item, or say what is still missing" <<<"$OUT" && ok "the note says what a person does next" || bad "the note says what a person does next" "$OUT"

echo "# a change that is not merged"
for state in open closed none; do
  envelope "$WORK/$state.txt" pass "some summary" "$state"
  run "$WORK/$state.txt" ITEM-1
  [[ "$STATUS" -eq 0 && "$OUT" == "continue	change_state=$state" ]] && ok "$state → continue" || bad "$state → continue" "got $STATUS: $OUT"
done

echo "# a lookup that did not succeed"
envelope "$WORK/nostate.txt" fail "could not look up a pull request for branch item-1 (gh error)."
run "$WORK/nostate.txt" ITEM-1
[[ "$STATUS" -eq 0 ]] && ok "exits 0: unknown is never satisfied" || bad "exits 0: unknown is never satisfied" "got $STATUS"
grep -q "^unknown	the lookup carried no change_state (verdict fail: could not look up" <<<"$OUT" && ok "unknown names the lookup's own reason" || bad "unknown names the lookup's own reason" "$OUT"
envelope "$WORK/odd.txt" pass "x" archived
run "$WORK/odd.txt" ITEM-1
[[ "$STATUS" -eq 0 && "$OUT" == "unknown	unrecognised change_state archived" ]] && ok "an unrecognised state is unknown, never satisfied" || bad "an unrecognised state is unknown, never satisfied" "got $STATUS: $OUT"

echo "# usage errors"
run
[[ "$STATUS" -eq 2 ]] && ok "no argument → exit 2" || bad "no argument → exit 2" "got $STATUS"
run "$WORK/merged.txt"
[[ "$STATUS" -eq 2 ]] && ok "no item id → exit 2" || bad "no item id → exit 2" "got $STATUS"
run "$WORK/missing.txt" ITEM-1
[[ "$STATUS" -eq 2 ]] && ok "a missing file → exit 2" || bad "a missing file → exit 2" "got $STATUS"
printf 'verdict: pass\nchange_state: merged\n' > "$WORK/noblock.txt"
run "$WORK/noblock.txt" ITEM-1
[[ "$STATUS" -eq 2 ]] && ok "a file without a ## Result block → exit 2, never satisfied" || bad "a file without a ## Result block → exit 2, never satisfied" "got $STATUS: $OUT"

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
