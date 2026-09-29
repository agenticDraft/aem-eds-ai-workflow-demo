#!/usr/bin/env bash
# Tests for copy-upstream-blocks.sh. Run with:
#   bash plugins/eds/shared/scripts/copy-upstream-blocks.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. prototype, plan
# and implement all call the script; whichever runs first copies, the later
# ones find the block present (the reuse check answers `reuse=`) and leave
# it alone (D528).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPY="$SCRIPT_DIR/copy-upstream-blocks.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/copy-upstream.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

SHA="69d7d50839009376687f105cf1e323e05f4ecad2"
COL="$WORK/collection"
mkdir -p "$COL/blocks/table" "$COL/blocks/tabs"
printf 'Apache License\nVersion 2.0, January 2004\n' > "$COL/LICENSE"
printf 'repo=https://example.invalid/c.git\ncommit=%s\nblock=table\nblock=tabs\n' "$SHA" > "$COL/manifest.txt"
echo ".table { upstream: 1 }" > "$COL/blocks/table/table.css"
echo "export default function decorate() {}" > "$COL/blocks/table/table.js"
echo ".tabs {}" > "$COL/blocks/tabs/tabs.css"

fact() {
  local f="$WORK/$1.fact.yaml"
  printf 'item_id: "EDS-1"\nitem_type: Story\nlabels: []\ncomponents: [%s]\nfiles_named: [%s]\n' "$2" "$3" > "$f"
  echo "$f"
}
project() { local r="$WORK/$1.root"; mkdir -p "$r/blocks/cards"; echo ".cards {}" > "$r/blocks/cards/cards.css"; echo "$r"; }

run() { OUT="$(bash "$COPY" "$@" 2>&1)"; RC=$?; }
has() { grep -qxF "$1" <<< "$OUT"; }

echo "=== copy-upstream-blocks.sh tests ==="

echo "-- absent from blocks/, in the collection -> copied"
R="$(project first)"
run "$(fact first "table, cards" "blocks/table/table.css, blocks/table/, styles/styles.css")" "$R" "$COL/manifest.txt"
if [[ "$RC" == 0 ]] && has "copied=blocks/table/table.css" && has "copied=blocks/table/table.js"; then
  ok "each vendored file reported copied"
else
  bad "each vendored file reported copied" "exit=$RC" "$OUT"
fi
NOTICE_LINE="/* Changed in this project. Derived from https://example.invalid/c blocks/table/table.css at $SHA, Apache-2.0. */"
if [[ "$(head -n 1 "$R/blocks/table/table.css")" == "$NOTICE_LINE" ]]; then
  ok "first line is the Apache-2.0 change notice naming source, path and commit"
else
  bad "first line is the Apache-2.0 change notice naming source, path and commit" \
    "want: $NOTICE_LINE" "got:  $(head -n 1 "$R/blocks/table/table.css")"
fi
if tail -n +2 "$R/blocks/table/table.css" | cmp -s - "$COL/blocks/table/table.css" \
    && tail -n +2 "$R/blocks/table/table.js" | cmp -s - "$COL/blocks/table/table.js"; then
  ok "below the notice, the upstream bytes unchanged"
else
  bad "below the notice, the upstream bytes unchanged"
fi
if [[ "$(grep -c '^copied=blocks/table/table.css$' <<< "$OUT")" == 1 ]]; then
  ok "a block named three ways is copied once"
else
  bad "a block named three ways is copied once" "$OUT"
fi
if [[ ! -e "$R/blocks/tabs" ]]; then ok "an unnamed collection block is not copied"; else bad "an unnamed collection block is not copied"; fi
if [[ "$(cat "$R/blocks/cards/cards.css")" == ".cards {}" ]]; then ok "a reused block is untouched"; else bad "a reused block is untouched"; fi

echo "-- a later stage finds it present"
echo ".table { changed-by-prototype: 1 }" > "$R/blocks/table/table.css"
run "$(fact first "table" "")" "$R" "$COL/manifest.txt"
if [[ "$RC" == 0 ]] && has "copied=(none)" \
    && [[ "$(cat "$R/blocks/table/table.css")" == ".table { changed-by-prototype: 1 }" ]]; then
  ok "present block never overwritten"
else
  bad "present block never overwritten" "exit=$RC" "$OUT"
fi

echo "-- nothing upstream"
R="$(project nothing)"
run "$(fact nothing "cards, widget" "")" "$R" "$COL/manifest.txt"
if [[ "$RC" == 0 ]] && has "copied=(none)" && [[ ! -e "$R/blocks/widget" ]]; then
  ok "reuse and new names -> copied=(none)"
else
  bad "reuse and new names -> copied=(none)" "exit=$RC" "$OUT"
fi

echo "-- manifest unavailable"
R="$(project missing)"
run "$(fact missing "table" "")" "$R" "$WORK/nowhere/manifest.txt"
if [[ "$RC" == 0 ]] && has "upstream_unknown=table" && has "copied=(none)" && [[ ! -e "$R/blocks/table" ]]; then
  ok "missing manifest -> upstream_unknown, nothing copied, exit 0"
else
  bad "missing manifest -> upstream_unknown, nothing copied, exit 0" "exit=$RC" "$OUT"
fi

echo "-- usage"
run
if [[ "$RC" == 2 ]]; then ok "no argument -> exit 2"; else bad "no argument -> exit 2" "got exit=$RC"; fi

echo
echo "passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]]
