#!/usr/bin/env bash
# Tests for measure.cjs. Run with:
#   bash plugins/playwright/skills/measure/scripts/measure.test.sh
#
# No browser — exits 0 on success, 1 if anything failed. Checks the fixed
# property set, holds_text and broken_words against a fake page, the
# arguments, and the paths that end before a browser is launched.

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
  "color,background-color,font-family,font-size,font-weight,line-height,padding-top,padding-right,padding-bottom,padding-left,gap,border-radius,min-width" \
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
  createRange: () => ({ setStart() {}, setEnd() {}, getClientRects: () => [] }),
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

# A fake page with a fake layout: each text node carries `lines`, the line
# index of every character. A range's client rects are one rect per line its
# characters sit on, so a word whose characters sit on two lines is broken.
BROKEN_JS='
const { readSelectors } = require(process.argv[1]);
const text = (v, lines) => ({ nodeType: 3, nodeValue: v, lines: lines || [...v].map(() => 0), childNodes: [] });
const el = (...kids) => ({ nodeType: 1, childNodes: kids });
const at = (v, breakAt) => text(v, [...v].map((_, i) => (i < breakAt ? 0 : 1)));
const shared = at("Ultra-fast WebSurge", 13);
const pages = {
  ".mid-word": [el(at("WebSurge HyperView", 4))],
  ".at-space": [el(at("WebSurge HyperView", 9))],
  ".at-hyphen": [el(at("Ultra-fast", 6))],
  ".after-hyphen": [el(at("Ultra-fast", 8))],
  ".two-nodes": [el(el(at("One Two", 5)), el(at("Three", 2)))],
  ".nested": [el(shared), el(el(shared))],
  ".hidden": [el({ nodeType: 3, nodeValue: "Gone", lines: null, childNodes: [] })],
  ".plain": [el(text("Nothing broken here"))],
};
global.document = {
  querySelectorAll: (sel) => pages[sel] || [],
  fonts: { status: "loaded" },
  createRange: () => {
    const r = {};
    r.setStart = (node, offset) => { r.node = node; r.start = offset; };
    r.setEnd = (node, offset) => { r.end = offset; };
    r.getClientRects = () => {
      if (!r.node.lines) return [];
      const seen = [...new Set(r.node.lines.slice(r.start, r.end))];
      return seen.map((line) => ({ top: line * 20 + 0.25, width: 10, height: 20 }));
    };
    return r;
  },
};
global.getComputedStyle = () => ({ getPropertyValue: () => "", visibility: "visible" });
for (const e of Object.values(pages).flat()) {
  e.getBoundingClientRect = () => ({ x: 0, y: 0, width: 1, height: 1 });
}
const sels = Object.keys(pages);
const { results } = readSelectors({ sels, props: [] });
process.stdout.write(sels.map((s) => `${s}=[${results[s].broken_words.join(",")}]`).join(" "));
'

echo "[broken_words] a word whose characters sit on two lines, each text node once"
assert_eq "broken_words per selector" \
  ".mid-word=[WebSurge] .at-space=[] .at-hyphen=[] .after-hyphen=[fast] .two-nodes=[Two,Three] .nested=[WebSurge] .hidden=[] .plain=[]" \
  "$(node -e "$BROKEN_JS" "$MEASURE" 2>&1)"

echo "[broken_words] a not-found selector carries no broken_words"
assert_eq "not found has only found" '{"found":false}' "$(node -e "$NOT_FOUND_JS" "$MEASURE" 2>&1)"

ARGS_JS='
const { parseArgs } = require(process.argv[1]);
const show = (argv) => { const a = parseArgs(argv); return a.error ? `error:${a.error}` : `${a.width}|${a.target}|${a.selectors.join(",")}`; };
process.stdout.write([
  show(["http://h/", ".a", ".b"]),
  show(["--width", "375", "http://h/", ".a"]),
  show(["http://h/", ".a", "--width", "768"]),
  show(["--width", "0", "http://h/", ".a"]),
  show(["--width", "37.5", "http://h/", ".a"]),
  show(["--width"]),
  show(["http://h/"]),
].join("\n"));
'

# A fake page where each element carries its own box and visibility: a
# selector is hidden when no match is visible; geometry comes from the first
# visible match, or the first match when none is.
HIDDEN_JS='
const { readSelectors } = require(process.argv[1]);
const text = (v) => ({ nodeType: 3, nodeValue: v, childNodes: [] });
const el = (rect, vis, ...kids) => ({ nodeType: 1, childNodes: kids, rect, vis });
const shown = () => el({ x: 0, y: 0, width: 40, height: 20 }, "visible", text("Shown"));
const gone = () => el({ x: 0, y: 0, width: 0, height: 0 }, "visible", text("Gone"));
const veiled = () => el({ x: 0, y: 0, width: 40, height: 20 }, "hidden", text("Veiled"));
const pages = {
  ".visible": [shown()],
  ".display-none": [gone()],
  ".visibility-hidden": [veiled()],
  ".all-hidden": [gone(), veiled()],
  ".mixed": [gone(), el({ x: 5, y: 7, width: 30, height: 10 }, "visible", text("Second"))],
};
global.document = {
  querySelectorAll: (sel) => pages[sel] || [],
  fonts: { status: "loaded" },
  createRange: () => ({ setStart() {}, setEnd() {}, getClientRects: () => [] }),
};
global.getComputedStyle = (e) => ({ getPropertyValue: () => "", visibility: e.vis });
for (const e of Object.values(pages).flat()) e.getBoundingClientRect = () => e.rect;
const sels = [...Object.keys(pages), ".none"];
const snapshot = readSelectors({ sels, props: [] });
const { results } = snapshot;
const show = (s) => { const r = results[s]; return r.found ? `${r.hidden}@${r.geometry.x},${r.geometry.y},${r.geometry.width}x${r.geometry.height}` : "not-found"; };
process.stdout.write(sels.map((s) => `${s}=${show(s)}`).join(" ") + "\n" + Object.keys(snapshot).sort().join(","));
'

echo "[hidden] a selector is hidden when no match is visible; geometry is the first visible match's"
assert_eq "hidden and geometry per selector, and no visibility state beside the results" \
  ".visible=false@0,0,40x20 .display-none=true@0,0,0x0 .visibility-hidden=true@0,0,40x20 .all-hidden=true@0,0,0x0 .mixed=false@5,7,30x10 .none=not-found
fontsLoading,results" \
  "$(node -e "$HIDDEN_JS" "$MEASURE" 2>&1)"

echo "[hidden] a not-found selector carries no hidden"
assert_eq "not found has only found" '{"found":false}' "$(node -e "$NOT_FOUND_JS" "$MEASURE" 2>&1)"

echo "[args] the width is an optional flag, anywhere; target and selectors keep their order"
assert_eq "parsed arguments" \
  "null|http://h/|.a,.b
375|http://h/|.a
768|http://h/|.a
error:width
error:width
error:usage
error:usage" \
  "$(node -e "$ARGS_JS" "$MEASURE" 2>&1)"

echo "[width] a width that is not a positive integer fails in the envelope, naming it"
OUT="$(node "$MEASURE" --width abc http://localhost:1/ .x 2>&1)"
assert_eq "verdict fail" "verdict: fail" "$(printf '%s\n' "$OUT" | grep '^verdict:')"
assert_eq "summary names the width" "summary: the given width is not a positive integer: abc" \
  "$(printf '%s\n' "$OUT" | grep '^summary:')"

echo "[usage] --width with no value exits 2"
node "$MEASURE" --width >/dev/null 2>&1
assert_eq "exit code" "2" "$?"

echo "[usage] no selector exits 2"
node "$MEASURE" http://localhost:1/ >/dev/null 2>&1
assert_eq "exit code" "2" "$?"

echo "[target] a non-http target fails in the envelope"
OUT="$(node "$MEASURE" file:///nowhere.html .x 2>&1)"
assert_eq "verdict fail" "verdict: fail" "$(printf '%s\n' "$OUT" | grep '^verdict:')"

echo ""
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
