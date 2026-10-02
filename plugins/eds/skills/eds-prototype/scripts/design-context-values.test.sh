#!/usr/bin/env bash
# Tests for design-context-values.py. Run with:
#   bash plugins/eds/skills/eds-prototype/scripts/design-context-values.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Each case builds
# a design-reference.json and its reference code in a temporary directory and
# runs the script from there, because design_context.code_file is relative to
# the project root.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TABLE="$SCRIPT_DIR/design-context-values.py"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/design-context-values.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
TAB="$(printf '\t')"
# One opening brace; a JSX double brace is built from two at run time, so this
# file holds no literal template-placeholder marker.
OB='{'

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# case_dir <name> <code> — a case directory whose design-reference.json points
# design_context.code_file at a file holding <code>
case_dir() {
  local dir="$WORK/$1"
  mkdir -p "$dir/.ai/run-context"
  printf '%s' "$2" > "$dir/.ai/run-context/design-context.txt"
  jq -n '{source_kind: "design_tool", has_values: true, variables: {}, geometry: {width: 1},
    design_context: {code_file: ".ai/run-context/design-context.txt", styles: null}}' \
    > "$dir/.ai/run-context/design-reference.json"
  echo "$dir"
}

# run_table <case-dir> — runs the script from inside the case dir; sets STATUS
run_table() {
  (cd "$1" && python3 "$TABLE" .ai/run-context/design-reference.json >"$1/stdout" 2>"$1/stderr")
  STATUS=$?
}

# has_row <desc> <case-dir> <node> <property> <value> [approx, default false]
has_row() {
  local want="$3$TAB$4$TAB$5$TAB${6:-false}"
  if grep -qxF -- "$want" "$2/stdout"; then ok "$1"; else bad "$1" "want: $want" "got: $(cat "$2/stdout")"; fi
}

# no_row_for <desc> <case-dir> <node> <property>
no_row_for() {
  if grep -q "^$3$TAB$4$TAB" "$2/stdout"; then bad "$1" "found: $(grep "^$3$TAB$4$TAB" "$2/stdout")"; else ok "$1"; fi
}

# row_count <desc> <case-dir> <n>
row_count() {
  local got
  got="$(grep -c . "$2/stdout")"
  if [ "$got" -eq "$3" ]; then ok "$1"; else bad "$1" "want $3 rows, got $got" "$(cat "$2/stdout")"; fi
}

echo "spacing"
D="$(case_dir spacing '<div className="flex p-[80px] gap-[40px]" data-node-id="1:10">
  <a className="px-[22px] py-[14px] mt-[8px] gap-x-[12px]" data-node-id="1:11">Go</a>
  <div className="p-[10px_20px]" data-node-id="1:12"></div>
</div>')"
run_table "$D"
if [ "$STATUS" -eq 0 ]; then ok "exits 0"; else bad "exits 0" "got: $STATUS" "stderr: $(cat "$D/stderr")"; fi
has_row "p-[80px] is padding" "$D" "1:10" "padding" "80px"
has_row "gap-[40px] is gap" "$D" "1:10" "gap" "40px"
has_row "px-[22px] is padding-inline" "$D" "1:11" "padding-inline" "22px"
has_row "py-[14px] is padding-block" "$D" "1:11" "padding-block" "14px"
has_row "mt-[8px] is margin-top" "$D" "1:11" "margin-top" "8px"
has_row "gap-x-[12px] is column-gap" "$D" "1:11" "column-gap" "12px"
has_row "an underscore in the value is a space" "$D" "1:12" "padding" "10px 20px"
row_count "one row per property an arbitrary-value class sets, none for flex" "$D" 7

echo "radius"
D="$(case_dir radius '<a className="rounded-[1000px]" data-node-id="1:185"><span className="rounded-tl-[4px]" data-node-id="1:186">x</span></a>')"
run_table "$D"
has_row "rounded-[1000px] is border-radius" "$D" "1:185" "border-radius" "1000px"
has_row "rounded-tl-[4px] is border-top-left-radius" "$D" "1:186" "border-top-left-radius" "4px"

echo "font size"
D="$(case_dir size '<h1 className="text-[64px] leading-[1.4] tracking-[-0.35px]" data-node-id="2:1">A</h1><p className="text-[length:2rem]" data-node-id="2:2">B</p><p className="text-[clamp(1rem,2vw,3rem)]" data-node-id="2:3">C</p>')"
run_table "$D"
has_row "text-[64px] is font-size" "$D" "2:1" "font-size" "64px"
has_row "leading-[1.4] is line-height" "$D" "2:1" "line-height" "1.4"
has_row "tracking-[-0.35px] is letter-spacing" "$D" "2:1" "letter-spacing" "-0.35px"
has_row "text-[length:2rem] is font-size, hint dropped" "$D" "2:2" "font-size" "2rem"
has_row "text-[clamp(…)] is font-size" "$D" "2:3" "font-size" "clamp(1rem,2vw,3rem)"
no_row_for "text-[64px] is never a colour" "$D" "2:1" "color"

echo "colour"
D="$(case_dir colour '<p className="text-[#1a1a1a] bg-[#dfecc6]" data-node-id="3:1">A</p><p className="text-[rgba(0,0,0,0.5)]" data-node-id="3:3">B</p><p className="text-[color:var(--ink)] border-[#ccc] border-[2px]" data-node-id="3:2">C</p>')"
run_table "$D"
has_row "text-[#1a1a1a] is color" "$D" "3:1" "color" "#1a1a1a"
has_row "bg-[#dfecc6] is background-color" "$D" "3:1" "background-color" "#dfecc6"
has_row "text-[rgba(…)] is color" "$D" "3:3" "color" "rgba(0,0,0,0.5)"
has_row "text-[color:var(--ink)] is color, hint dropped" "$D" "3:2" "color" "var(--ink)"
has_row "border-[#ccc] is border-color" "$D" "3:2" "border-color" "#ccc"
has_row "border-[2px] is border-width" "$D" "3:2" "border-width" "2px"
no_row_for "text-[#1a1a1a] is never a font size" "$D" "3:1" "font-size"

echo "classes it does not recognise"
D="$(case_dir unknown '<div className="foo-[12px] text-[var(--x)] text-[red] bg-[url(/a.png)] md:px-[10px] hover:text-[#fff] -mt-[4px] !p-[3px] text-[14px]/[1.4] rounded-t-[4px] font-[DM_Sans] flex" data-node-id="4:1"></div>')"
run_table "$D"
if [ "$STATUS" -eq 0 ]; then ok "exits 0"; else bad "exits 0" "got: $STATUS" "stderr: $(cat "$D/stderr")"; fi
row_count "every one is ignored, no property guessed" "$D" 0

echo "arbitrary property and font weight"
D="$(case_dir property '<p className="[word-break:break-word] font-[700] font-['"'"'DM_Sans:Bold'"'"']" data-node-id="5:1">A</p>')"
run_table "$D"
has_row "[word-break:break-word] names its own property" "$D" "5:1" "word-break" "break-word"
has_row "font-[700] is font-weight" "$D" "5:1" "font-weight" "700"
row_count "font-['DM_Sans:Bold'] is ignored" "$D" 2

echo "real reference-code shape"
D="$(case_dir real 'export default function Button() {
  return (
    <a className="bg-[#dfecc6] flex px-[22px] py-[14px] relative rounded-[1000px] size-full" href="https://example.com/x" data-node-id="1:185" target="_blank" data-name="Button">
      <p className="font-bold leading-[1.4] text-[14px] text-black" data-node-id="I1:185;1:543" style='"$OB$OB"' fontVariationSettings: '"'"'"opsz" 14'"'"', x: a > b ? 1 : 2 }}>
        Discover More
      </p>
      <span className="p-[9px]">no node id</span>
    </a>
  );
}')"
run_table "$D"
if [ "$STATUS" -eq 0 ]; then ok "exits 0"; else bad "exits 0" "got: $STATUS" "stderr: $(cat "$D/stderr")"; fi
has_row "padding-inline keyed by the anchor" "$D" "1:185" "padding-inline" "22px"
has_row "padding-block keyed by the anchor" "$D" "1:185" "padding-block" "14px"
has_row "radius keyed by the anchor" "$D" "1:185" "border-radius" "1000px"
has_row "font size keyed by the nested instance node" "$D" "I1:185;1:543" "font-size" "14px"
if grep -q "9px" "$D/stdout"; then bad "an element with no data-node-id gives no row" "$(cat "$D/stdout")"; else ok "an element with no data-node-id gives no row"; fi
row_count "rows in document order, nothing extra" "$D" 6
first="$(head -1 "$D/stdout")"
if [ "$first" = "1:185${TAB}background-color${TAB}#dfecc6${TAB}false" ]; then ok "first row is the first class of the first element"; else bad "first row is the first class of the first element" "got: $first"; fi

# with_assets <case-dir> <json array> — sets the reference's assets list
with_assets() {
  jq --argjson a "$2" '.assets = $a' "$1/.ai/run-context/design-reference.json" > "$1/ref.json" \
    && mv "$1/ref.json" "$1/.ai/run-context/design-reference.json"
}

echo "approx: a text node's width is content-dependent"
D="$(case_dir approxtext '<p className="w-[94px] h-[20px] min-h-[20px] px-[4px] gap-[2px] mt-[3px] text-[14px]" data-node-id="I1:185;1:543">Learn More</p>')"
run_table "$D"
if [ "$STATUS" -eq 0 ]; then ok "exits 0"; else bad "exits 0" "got: $STATUS" "stderr: $(cat "$D/stderr")"; fi
has_row "width on a text node is approx" "$D" "I1:185;1:543" "width" "94px" true
has_row "height on a text node is approx" "$D" "I1:185;1:543" "height" "20px" true
has_row "min-height on a text node is approx" "$D" "I1:185;1:543" "min-height" "20px" true
has_row "padding on a text node is never approx" "$D" "I1:185;1:543" "padding-inline" "4px" false
has_row "gap on a text node is never approx" "$D" "I1:185;1:543" "gap" "2px" false
has_row "margin on a text node is never approx" "$D" "I1:185;1:543" "margin-top" "3px" false
has_row "font-size on a text node is not approx" "$D" "I1:185;1:543" "font-size" "14px" false

echo "approx: a frame that contains a text node"
D="$(case_dir approxcontains 'export default function Cell() {
  const label = "not rendered";
  return (
    <div className="h-[96px] w-[400px] px-[30px] py-[40px] rounded-[20px]" data-node-id="1:197" data-name="table item">
      <div className="w-[51px] max-w-[60px]" data-node-id="1:198">
        <p className="leading-[1.2]">Area</p>
      </div>
    </div>
  );
}')"
run_table "$D"
has_row "a frame's height is approx when a descendant holds text" "$D" "1:197" "height" "96px" true
has_row "a frame's width is approx when a descendant holds text" "$D" "1:197" "width" "400px" true
has_row "the frame's padding is never approx" "$D" "1:197" "padding-inline" "30px" false
has_row "the frame's radius is not approx" "$D" "1:197" "border-radius" "20px" false
has_row "a text node whose copy sits in a child without a node id" "$D" "1:198" "width" "51px" true
has_row "max-width is never approx" "$D" "1:198" "max-width" "60px" false

echo "approx: a frame with no text and no image"
D="$(case_dir approxstruct '<>
  <div className="w-[320px] h-[200px] min-h-[100px] p-[16px]" data-node-id="6:1">
    <div className="w-[10px] h-[10px]" data-node-id="6:2" />
    <div className="h-[4px]" data-node-id="6:3">{/* a comment is not copy */}</div>
    <span className="w-[2px]" data-node-id="6:4">   </span>
  </div>
  <p data-node-id="6:5">copy after the frame closes</p>
</>')"
run_table "$D"
has_row "a box with no copy keeps an exact width" "$D" "6:1" "width" "320px" false
has_row "a box with no copy keeps an exact height" "$D" "6:1" "height" "200px" false
has_row "a box with no copy keeps an exact min-height" "$D" "6:1" "min-height" "100px" false
has_row "a self-closing child is not text" "$D" "6:2" "width" "10px" false
has_row "a JSX comment is not text" "$D" "6:3" "height" "4px" false
has_row "whitespace is not text" "$D" "6:4" "width" "2px" false

echo "approx: a string expression is copy"
D="$(case_dir approxexpr '<p className="w-[40px]" data-node-id="7:1">'"$OB"'"Dr. Jekyll"}</p><p className="w-[41px]" data-node-id="7:2">'"$OB"'label}</p>')"
run_table "$D"
has_row "a string literal in braces is text" "$D" "7:1" "width" "40px" true
has_row "a bare identifier in braces decides nothing" "$D" "7:2" "width" "41px" false

echo "approx: an image fill"
D="$(case_dir approximage 'const imgHero = ".ai/figma/assets/aa.png";
const imgIcon = ".ai/figma/assets/bb.svg";
export default function Card() {
  return (
    <div className="p-[24px]" data-node-id="8:1">
      <div className="aspect-[16/9] w-[320px] rounded-[8px] gap-[4px]" data-node-id="8:2" data-name="Hero">
        <img alt="" className="absolute inset-0 size-full" src='"$OB"'imgHero} />
      </div>
      <div className="w-[14px] h-[14px]" data-node-id="I8:3;1:563" data-name="Check icon">
        <img alt="" src='"$OB"'imgIcon} />
      </div>
      <div className="h-[48px]" data-node-id="8:4">
        <img alt="" src='"$OB"'imgHero} />
      </div>
    </div>
  );
}')"
with_assets "$D" '[{"node_id":"8:2","file":".ai/figma/assets/aa.png","mime":"image/png"},
  {"node_id":"I8:3;1:563","file":".ai/figma/assets/bb.svg","mime":"image/svg+xml"}]'
run_table "$D"
if [ "$STATUS" -eq 0 ]; then ok "exits 0"; else bad "exits 0" "got: $STATUS" "stderr: $(cat "$D/stderr")"; fi
has_row "aspect-[16/9] is aspect-ratio" "$D" "8:2" "aspect-ratio" "16/9" true
has_row "an image fill's width is approx" "$D" "8:2" "width" "320px" true
has_row "an image fill's radius is not approx" "$D" "8:2" "border-radius" "8px" false
has_row "an image fill's gap is never approx" "$D" "8:2" "gap" "4px" false
has_row "a vector asset is not an image fill" "$D" "I8:3;1:563" "width" "14px" false
has_row "an image the assets list does not name decides nothing" "$D" "8:4" "height" "48px" false
has_row "the parent of an image fill is not approx by it" "$D" "8:1" "padding" "24px" false

echo "size: one class sets width and height"
D="$(case_dir sizebox '<div className="relative shrink-0 size-[14px]" data-node-id="I1:199;1:563" data-name="Check icon"></div>
<div className="size-[length:2rem]" data-node-id="10:2"></div>
<div className="size-[calc(1rem_+_2px)]" data-node-id="10:3"></div>')"
run_table "$D"
if [ "$STATUS" -eq 0 ]; then ok "exits 0"; else bad "exits 0" "got: $STATUS" "stderr: $(cat "$D/stderr")"; fi
has_row "size-[14px] is width" "$D" "I1:199;1:563" "width" "14px"
has_row "size-[14px] is height" "$D" "I1:199;1:563" "height" "14px"
has_row "size-[length:2rem] is width, hint dropped" "$D" "10:2" "width" "2rem"
has_row "size-[length:2rem] is height, hint dropped" "$D" "10:2" "height" "2rem"
has_row "size-[calc(…)] decodes underscores" "$D" "10:3" "width" "calc(1rem + 2px)"
row_count "two rows per size class" "$D" 6
first="$(head -1 "$D/stdout")"
if [ "$first" = "I1:199;1:563${TAB}width${TAB}14px${TAB}false" ]; then ok "width row comes before height"; else bad "width row comes before height" "got: $first"; fi

echo "size: forms that are ignored"
D="$(case_dir sizeignored '<div className="md:size-[14px] hover:size-[15px] -size-[16px] !size-[17px] size-[18px]/[2] size-[var(--icon)] size-[#fff] size-[auto] size-full" data-node-id="10:4"></div>')"
run_table "$D"
if [ "$STATUS" -eq 0 ]; then ok "exits 0"; else bad "exits 0" "got: $STATUS" "stderr: $(cat "$D/stderr")"; fi
row_count "variant, negative, important, modifier and non-length values give no row" "$D" 0

echo "size: approx follows the node"
D="$(case_dir sizeapprox '<div className="size-[14px]" data-node-id="I8:3;1:563" data-name="Check icon"><img alt="" src='"$OB"'imgIcon} /></div>
<p className="size-[40px]" data-node-id="11:2">Copy</p>
<div className="size-[64px]" data-node-id="11:3"></div>')"
with_assets "$D" '[{"node_id":"I8:3;1:563","file":".ai/figma/assets/bb.svg","mime":"image/svg+xml"},
  {"node_id":"11:3","file":".ai/figma/assets/cc.png","mime":"image/png"}]'
run_table "$D"
has_row "size on an SVG-asset node: width not approx" "$D" "I8:3;1:563" "width" "14px" false
has_row "size on an SVG-asset node: height not approx" "$D" "I8:3;1:563" "height" "14px" false
has_row "size on a text node: width approx" "$D" "11:2" "width" "40px" true
has_row "size on a text node: height approx" "$D" "11:2" "height" "40px" true
has_row "size on a raster image fill: width approx" "$D" "11:3" "width" "64px" true
has_row "size on a raster image fill: height approx" "$D" "11:3" "height" "64px" true

echo "a property set twice with different values on one element"
D="$(case_dir conflict '<div className="w-[10px] size-[14px] p-[4px] p-[8px] gap-[2px]" data-node-id="12:1"></div>
<div className="w-[14px] size-[14px]" data-node-id="12:2"></div>')"
run_table "$D"
if [ "$STATUS" -eq 0 ]; then ok "exits 0"; else bad "exits 0" "got: $STATUS" "stderr: $(cat "$D/stderr")"; fi
no_row_for "a conflicting width gives no row" "$D" "12:1" "width"
no_row_for "a conflicting padding gives no row" "$D" "12:1" "padding"
has_row "the property the size class sets alone stays" "$D" "12:1" "height" "14px"
has_row "an unrelated property stays" "$D" "12:1" "gap" "2px"
has_row "the same value twice is not a conflict" "$D" "12:2" "width" "14px"
row_count "nothing else" "$D" 4
if grep -qxF "conflict: 12:1 width 10px 14px" "$D/stderr" && grep -qxF "conflict: 12:1 padding 4px 8px" "$D/stderr"; then ok "stderr names each conflict"; else bad "stderr names each conflict" "got: $(cat "$D/stderr")"; fi
if grep -q "12:2" "$D/stderr"; then bad "an agreeing pair is not reported" "got: $(cat "$D/stderr")"; else ok "an agreeing pair is not reported"; fi

echo "design_context: null, with a stale reference-code file present"
D="$(case_dir null '<a className="px-[99px]" data-node-id="9:9">stale</a>')"
jq '.design_context = null' "$D/.ai/run-context/design-reference.json" > "$D/ref.json" \
  && mv "$D/ref.json" "$D/.ai/run-context/design-reference.json"
run_table "$D"
if [ "$STATUS" -eq 3 ]; then ok "exits 3"; else bad "exits 3" "got: $STATUS"; fi
row_count "prints no rows — the stale file is not read" "$D" 0

echo "design_context names a code file that does not exist"
D="$(case_dir missing '')"
jq '.design_context.code_file = ".ai/run-context/absent.txt"' "$D/.ai/run-context/design-reference.json" > "$D/ref.json" \
  && mv "$D/ref.json" "$D/.ai/run-context/design-reference.json"
run_table "$D"
if [ "$STATUS" -eq 2 ]; then ok "exits 2"; else bad "exits 2" "got: $STATUS"; fi

echo "no design-reference.json"
D="$WORK/none"; mkdir -p "$D"
run_table "$D"
if [ "$STATUS" -eq 2 ]; then ok "exits 2"; else bad "exits 2" "got: $STATUS"; fi

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
