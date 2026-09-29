#!/usr/bin/env bash
# Tests for measure.cjs. Run with:
#   bash plugins/playwright/skills/measure/scripts/measure.test.sh
#
# No browser — exits 0 on success, 1 if anything failed. Checks the fixed
# property set, holds_text against a fake page, and the paths that end
# before a browser is launched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEASURE="$SCRIPT_DIR/measure.cjs"

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

echo "=== measure.cjs tests ==="

echo "[properties] exactly the fixed set, in order"
assert_eq "property list" \
  "color,background-color,font-family,font-size,font-weight,line-height,padding-top,padding-right,padding-bottom,padding-left,gap,border-radius" \
  "$(node -e "process.stdout.write(require(process.argv[1]).PROPERTIES.join(','))" "$MEASURE" 2>&1)"

echo "[properties] no shorthand padding is reported"
assert_eq "no padding shorthand" "" \
  "$(node -e "process.stdout.write(require(process.argv[1]).PROPERTIES.filter((p) => /^padding(-inline|-block)?$/.test(p)).join(','))" "$MEASURE" 2>&1)"

echo "[require] loading the module runs no measurement"
assert_eq "no output on require" "" \
  "$(node -e "require(process.argv[1])" "$MEASURE" 2>&1)"

# A fake page for readSelectors: elements by selector, each a tree of
# { nodeType, nodeValue, childNodes }. No browser.
HOLDS_TEXT_JS='
const { readSelectors } = require(process.argv[1]);
const text = (v) => ({ nodeType: 3, nodeValue: v, childNodes: [] });
const el = (...kids) => ({ nodeType: 1, childNodes: kids });
const pages = {
  ".deep": [el(el(el(text("Area"))))],
  ".blank": [el(text("  \n\t "), el(text(" ")))],
  ".icon": [el(el())],
  ".second": [el(), el(text("x"))],
  ".comment": [el({ nodeType: 8, nodeValue: "hidden", childNodes: [] })],
};
global.document = {
  querySelectorAll: (sel) => pages[sel] || [],
  fonts: { status: "loaded" },
};
global.getComputedStyle = () => ({ getPropertyValue: () => "", visibility: "visible" });
for (const e of Object.values(pages).flat()) {
  e.getBoundingClientRect = () => ({ x: 0, y: 0, width: 1, height: 1 });
}
const sels = [...Object.keys(pages), ".none"];
const { results } = readSelectors({ sels, props: [] });
process.stdout.write(sels.map((s) => `${s}=${results[s].found ? results[s].holds_text : "not-found"}`).join(" "));
'

echo "[holds_text] any match with a non-whitespace text node descendant"
assert_eq "holds_text per selector" \
  ".deep=true .blank=false .icon=false .second=true .comment=false .none=not-found" \
  "$(node -e "$HOLDS_TEXT_JS" "$MEASURE" 2>&1)"

NOT_FOUND_JS='
const { readSelectors } = require(process.argv[1]);
global.document = { querySelectorAll: () => [], fonts: { status: "loaded" } };
process.stdout.write(JSON.stringify(readSelectors({ sels: [".x"], props: [] }).results[".x"]));
'

echo "[holds_text] a not-found selector carries no holds_text"
assert_eq "not found has only found" '{"found":false}' "$(node -e "$NOT_FOUND_JS" "$MEASURE" 2>&1)"

echo "[usage] no selector exits 2"
node "$MEASURE" http://localhost:1/ >/dev/null 2>&1
assert_eq "exit code" "2" "$?"

echo "[target] a non-http target fails in the envelope"
OUT="$(node "$MEASURE" file:///nowhere.html .x 2>&1)"
assert_eq "verdict fail" "verdict: fail" "$(printf '%s\n' "$OUT" | grep '^verdict:')"

echo ""
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
