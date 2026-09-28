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

# has_row <desc> <case-dir> <node> <property> <value>
has_row() {
  local want="$3$TAB$4$TAB$5"
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
row_count "one row per arbitrary-value class, none for flex" "$D" 7

echo "radius"
D="$(case_dir radius '<a className="rounded-[1000px]" data-node-id="1:185"><span className="rounded-tl-[4px]" data-node-id="1:186">x</span></a>')"
run_table "$D"
has_row "rounded-[1000px] is border-radius" "$D" "1:185" "border-radius" "1000px"
has_row "rounded-tl-[4px] is border-top-left-radius" "$D" "1:186" "border-top-left-radius" "4px"

echo "font size"
D="$(case_dir size '<h1 className="text-[64px] leading-[1.4] tracking-[-0.35px]" data-node-id="2:1">A</h1><p className="text-[length:2rem] text-[clamp(1rem,2vw,3rem)]" data-node-id="2:2">B</p>')"
run_table "$D"
has_row "text-[64px] is font-size" "$D" "2:1" "font-size" "64px"
has_row "leading-[1.4] is line-height" "$D" "2:1" "line-height" "1.4"
has_row "tracking-[-0.35px] is letter-spacing" "$D" "2:1" "letter-spacing" "-0.35px"
has_row "text-[length:2rem] is font-size, hint dropped" "$D" "2:2" "font-size" "2rem"
has_row "text-[clamp(…)] is font-size" "$D" "2:2" "font-size" "clamp(1rem,2vw,3rem)"
no_row_for "text-[64px] is never a colour" "$D" "2:1" "color"

echo "colour"
D="$(case_dir colour '<p className="text-[#1a1a1a] bg-[#dfecc6]" data-node-id="3:1">A</p><p className="text-[rgba(0,0,0,0.5)] text-[color:var(--ink)] border-[#ccc] border-[2px]" data-node-id="3:2">B</p>')"
run_table "$D"
has_row "text-[#1a1a1a] is color" "$D" "3:1" "color" "#1a1a1a"
has_row "bg-[#dfecc6] is background-color" "$D" "3:1" "background-color" "#dfecc6"
has_row "text-[rgba(…)] is color" "$D" "3:2" "color" "rgba(0,0,0,0.5)"
has_row "text-[color:var(--ink)] is color, hint dropped" "$D" "3:2" "color" "var(--ink)"
has_row "border-[#ccc] is border-color" "$D" "3:2" "border-color" "#ccc"
has_row "border-[2px] is border-width" "$D" "3:2" "border-width" "2px"
no_row_for "text-[#1a1a1a] is never a font size" "$D" "3:1" "font-size"

echo "classes it does not recognise"
D="$(case_dir unknown '<div className="foo-[12px] text-[var(--x)] text-[red] bg-[url(/a.png)] md:px-[10px] hover:text-[#fff] -mt-[4px] !p-[3px] size-[24px] text-[14px]/[1.4] rounded-t-[4px] font-[DM_Sans] flex" data-node-id="4:1"></div>')"
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
if [ "$first" = "1:185${TAB}background-color${TAB}#dfecc6" ]; then ok "first row is the first class of the first element"; else bad "first row is the first class of the first element" "got: $first"; fi

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
