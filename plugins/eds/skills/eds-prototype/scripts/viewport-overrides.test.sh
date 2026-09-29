#!/usr/bin/env bash
# Tests for viewport-overrides.py. Run with:
#   bash plugins/eds/skills/eds-prototype/scripts/viewport-overrides.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Each case builds
# a design-reference.json and one reference-code file per variant in a
# temporary directory and runs the script from there, because every context
# path is relative to the project root.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERRIDES="$SCRIPT_DIR/viewport-overrides.py"
TABLE="$SCRIPT_DIR/design-context-values.py"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/viewport-overrides.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
TAB="$(printf '\t')"

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# new_case <name> — an empty case directory; prints its path
new_case() {
  local dir="$WORK/$1"
  mkdir -p "$dir/.ai/run-context"
  echo "[]" > "$dir/viewports.json"
  echo "$dir"
}

# add_variant <case-dir> <name> <node-id> <width> <code|-> — appends a
# viewport; `-` gives it context null
add_variant() {
  local dir="$1" name="$2" node="$3" width="$4" code="$5" ctx="null"
  local hy="${node//:/-}"
  : > "$dir/.ai/run-context/design-reference-$hy.png"
  if [ "$code" != "-" ]; then
    printf '%s' "$code" > "$dir/.ai/run-context/design-context-$hy.txt"
    ctx="\".ai/run-context/design-context-$hy.txt\""
  fi
  jq --arg n "$name" --arg id "$hy" --argjson w "$width" --argjson c "$ctx" \
    '. + [{name: $n, node_id: $id, width: $w, image: (".ai/run-context/design-reference-" + $id + ".png"), context: $c}]' \
    "$dir/viewports.json" > "$dir/viewports.tmp" && mv "$dir/viewports.tmp" "$dir/viewports.json"
}

# write_ref <case-dir> — writes design-reference.json from the variants added
write_ref() {
  local dir="$1"
  : > "$dir/.ai/run-context/design-reference.png"
  jq -n --slurpfile v "$dir/viewports.json" '{source_kind: "design_tool", has_values: true,
    reference_image: ".ai/run-context/design-reference.png", variables: {}, geometry: {width: 1},
    design_context: null} + (if ($v[0] | length) > 0 then {viewports: $v[0]} else {} end)' \
    > "$dir/.ai/run-context/design-reference.json"
}

# run_overrides <case-dir> <breakpoints> — sets STATUS
run_overrides() {
  (cd "$1" && python3 "$OVERRIDES" .ai/run-context/design-reference.json "$2" >"$1/stdout" 2>"$1/stderr")
  STATUS=$?
}

status_is() {
  if [ "$STATUS" -eq "$3" ]; then ok "$1"; else bad "$1" "want exit $3, got $STATUS" "stderr: $(cat "$2/stderr")" "stdout: $(cat "$2/stdout")"; fi
}

# has_line <desc> <case-dir> <tab-separated fields...>
has_line() {
  local desc="$1" dir="$2"; shift 2
  local want
  want="$(IFS="$TAB"; echo "$*")"
  if grep -qxF -- "$want" "$dir/stdout"; then ok "$desc"; else bad "$desc" "want: $want" "got:" "$(cat "$dir/stdout")"; fi
}

# no_match <desc> <case-dir> <regex>
no_match() {
  if grep -qE -- "$3" "$2/stdout"; then bad "$1" "found: $(grep -E -- "$3" "$2/stdout")"; else ok "$1"; fi
}

# count_is <desc> <case-dir> <regex> <n>
count_is() {
  local got
  got="$(grep -cE -- "$3" "$2/stdout")"
  if [ "$got" -eq "$4" ]; then ok "$1"; else bad "$1" "want $4 lines matching $3, got $got" "$(cat "$2/stdout")"; fi
}

MOBILE='<div className="flex flex-col p-[16px] gap-[24px]" data-node-id="1:430" data-name="Mobile">
  <header className="flex pt-[40px]" data-node-id="1:431" data-name="Header">
    <h1 className="text-[48px] leading-[0.9] tracking-[-2px]" data-node-id="1:432">Browse everything.</h1>
  </header>
  <a className="bg-[#dfecc6] px-[22px] py-[14px] rounded-[1000px]" data-node-id="1:440" data-name="Button">
    <p className="text-[14px]" data-node-id="I1:440;1:543">Go</p>
  </a>
</div>'

DESKTOP='<div className="flex flex-col p-[40px] gap-[24px]" data-node-id="1:118" data-name="Desktop">
  <header className="flex pt-[120px]" data-node-id="1:120" data-name="Header">
    <h1 className="text-[160px] leading-[0.9] tracking-[-6.8px]" data-node-id="1:121">Browse everything.</h1>
  </header>
  <a className="bg-[#DFECC6] px-[22px] py-[14px] rounded-[1000px]" data-node-id="1:150" data-name="Button">
    <p className="text-[14px]" data-node-id="I1:150;1:543">Go</p>
  </a>
</div>'

TABLET='<div className="flex flex-col p-[24px] gap-[24px]" data-node-id="1:274" data-name="Tablet">
  <header className="flex pt-[80px]" data-node-id="1:275" data-name="Header">
    <h1 className="text-[96px] leading-[0.9] tracking-[-4px]" data-node-id="1:276">Browse everything.</h1>
  </header>
  <a className="bg-[#dfecc6] px-[22px] py-[14px] rounded-[1000px]" data-node-id="1:290" data-name="Button">
    <p className="text-[14px]" data-node-id="I1:290;1:543">Go</p>
  </a>
</div>'

echo "two variants in two intervals: base plus one override"
D="$(new_case two-intervals)"
add_variant "$D" Desktop 1:118 1280 "$DESKTOP"
add_variant "$D" Mobile 1:430 375 "$MOBILE"
write_ref "$D"
run_overrides "$D" 900
status_is "exits 0" "$D" 0
has_line "the narrowest variant is the base" "$D" base Mobile 1:430 375
has_line "the wider variant is an override at the adopted breakpoint" "$D" media 900 Desktop 1:118 1280
has_line "base carries the mobile padding" "$D" value base 1:430 padding 16px 1:430 /
has_line "base carries the mobile heading size" "$D" value base 1:432 font-size 48px 1:432 '/Header#1/<h1>#1'
has_line "override carries the desktop padding on the base node" "$D" value 900 1:430 padding 40px 1:118 /
has_line "override carries the desktop heading size, matched by layer path" "$D" value 900 1:432 font-size 160px 1:121 '/Header#1/<h1>#1'
has_line "an instance's inner node is matched by its path, not its id" "$D" value base 'I1:440;1:543' font-size 14px 'I1:440;1:543' '/Button#1/<p>#1'
count_is "exactly one override block" "$D" '^media' 1
count_is "no finding" "$D" '^(same-interval|unmatched|missing|not-overridden|no-context)' 0

echo "a property equal across variants emits no override"
has_line "gap is in the base" "$D" value base 1:430 gap 24px 1:430 /
no_match "no override for the equal gap" "$D" "^value${TAB}900${TAB}1:430${TAB}gap${TAB}"
no_match "no override for the equal line-height" "$D" "^value${TAB}900${TAB}1:432${TAB}line-height${TAB}"
no_match "no override for the button (hex case differs only)" "$D" "^value${TAB}900${TAB}1:440${TAB}"
count_is "four overrides: padding, padding-top, heading size and tracking" "$D" "^value${TAB}900${TAB}" 4

echo "a frame width is never a threshold"
no_match "no media line names a variant width" "$D" "^media${TAB}(1280|375)${TAB}"

echo "two variants in one interval: a finding, not an override"
D="$(new_case one-interval)"
add_variant "$D" Tablet 1:274 800 "$TABLET"
add_variant "$D" Mobile 1:430 375 "$MOBILE"
write_ref "$D"
run_overrides "$D" 900
status_is "exits 0" "$D" 0
has_line "the narrowest of the interval is the base" "$D" base Mobile 1:430 375
has_line "the extra variant is a finding with a derived threshold" "$D" same-interval Tablet 1:274 800 Mobile 550
has_line "the finding names a differing property with both values" "$D" differs Tablet 1:430 padding 24px 16px 1:274 /
has_line "the finding names the heading size" "$D" differs Tablet 1:432 font-size 96px 48px 1:276 '/Header#1/<h1>#1'
no_match "no override block" "$D" '^media'
no_match "the extra variant's values are not in the base" "$D" "^value${TAB}base${TAB}1:430${TAB}padding${TAB}24px"
no_match "an equal property is not a difference" "$D" "^differs${TAB}Tablet${TAB}1:430${TAB}gap${TAB}"
no_match "the proposed threshold is not the frame width" "$D" "^same-interval${TAB}Tablet${TAB}1:274${TAB}800${TAB}Mobile${TAB}800$"

echo "three variants, the project's own breakpoint (the reference-file shape)"
D="$(new_case three)"
add_variant "$D" Desktop 1:118 1280 "$DESKTOP"
add_variant "$D" Tablet 1:274 800 "$TABLET"
add_variant "$D" Mobile 1:430 375 "$MOBILE"
write_ref "$D"
run_overrides "$D" 900
status_is "exits 0" "$D" 0
has_line "base is Mobile" "$D" base Mobile 1:430 375
has_line "Desktop overrides at 900" "$D" media 900 Desktop 1:118 1280
has_line "Tablet is raised, threshold 550" "$D" same-interval Tablet 1:274 800 Mobile 550
has_line "Desktop's override is against the base, not Tablet" "$D" value 900 1:430 padding 40px 1:118 /

echo "a single-width reference: no overrides"
D="$(new_case single)"
write_ref "$D"
run_overrides "$D" 900
status_is "exits 0" "$D" 0
has_line "prints single" "$D" single
count_is "and nothing else" "$D" '.' 1
D="$(new_case single-empty)"
write_ref "$D"
jq '. + {viewports: []}' "$D/.ai/run-context/design-reference.json" > "$D/r.json" && mv "$D/r.json" "$D/.ai/run-context/design-reference.json"
run_overrides "$D" 900
has_line "an empty list is single too" "$D" single

echo "no adopted breakpoint: every wider variant is a finding"
D="$(new_case no-breakpoint)"
add_variant "$D" Desktop 1:118 1280 "$DESKTOP"
add_variant "$D" Mobile 1:430 375 "$MOBILE"
write_ref "$D"
run_overrides "$D" -
status_is "exits 0" "$D" 0
has_line "Desktop is raised with a derived threshold" "$D" same-interval Desktop 1:118 1280 Mobile 700
no_match "no override block" "$D" '^media'

echo "several breakpoints cascade"
D="$(new_case cascade)"
add_variant "$D" Desktop 1:118 1280 "$DESKTOP"
add_variant "$D" Tablet 1:274 700 "$TABLET"
add_variant "$D" Mobile 1:430 375 "$MOBILE"
write_ref "$D"
run_overrides "$D" 600,900
has_line "Tablet overrides at 600" "$D" media 600 Tablet 1:274 700
has_line "Desktop overrides at 900" "$D" media 900 Desktop 1:118 1280
has_line "Tablet padding against the base" "$D" value 600 1:430 padding 24px 1:274 /
has_line "Desktop padding against Tablet's" "$D" value 900 1:430 padding 40px 1:118 /
no_match "no finding" "$D" '^same-interval'

echo "a variant wider than every breakpoint gap still uses the adopted breakpoint"
D="$(new_case gap-interval)"
add_variant "$D" Desktop 1:118 1280 "$DESKTOP"
add_variant "$D" Mobile 1:430 375 "$MOBILE"
write_ref "$D"
run_overrides "$D" 600,900
has_line "Desktop overrides at 900, the lower bound of its own interval" "$D" media 900 Desktop 1:118 1280
no_match "nothing at 600" "$D" "^media${TAB}600"

echo "elements that do not match"
D="$(new_case unmatched)"
add_variant "$D" Desktop 1:118 1280 '<div className="p-[40px]" data-node-id="1:118" data-name="Desktop">
  <nav className="h-[148px]" data-node-id="1:119" data-name="Navigation"></nav>
  <h2 className="text-[54px]" data-node-id="1:130">Title</h2>
  <div className="gap-[8px]" data-node-id="1:140" data-name="Row"></div>
</div>'
add_variant "$D" Mobile 1:430 375 '<div className="p-[16px]" data-node-id="1:430" data-name="Mobile">
  <nav className="h-[64px]" data-node-id="1:431" data-name="Navigation mobile"></nav>
  <p className="text-[32px]" data-node-id="1:432">Title</p>
  <div className="gap-[8px] pt-[4px]" data-node-id="1:433" data-name="Row"></div>
</div>'
write_ref "$D"
run_overrides "$D" 900
status_is "exits 0" "$D" 0
has_line "a wider-only element is unmatched" "$D" unmatched Desktop 1:119 '/Navigation#1'
has_line "a base element absent from the wider variant is missing" "$D" missing Desktop 1:431 '/Navigation mobile#1'
has_line "a text element of another tag is not matched by its text" "$D" unmatched Desktop 1:130 '/<h2>#1'
has_line "a base value the wider variant does not set is reported" "$D" not-overridden 900 1:433 padding-top 4px 1:140 '/Row#1'
no_match "no override is written for an unmatched element" "$D" "^value${TAB}900${TAB}1:43[12]"

echo "a variant with no reference code"
D="$(new_case no-context)"
add_variant "$D" Desktop 1:118 1280 -
add_variant "$D" Mobile 1:430 375 "$MOBILE"
write_ref "$D"
run_overrides "$D" 900
status_is "exits 0" "$D" 0
has_line "the variant is reported" "$D" no-context Desktop 1:118 1280
no_match "and gets no override block" "$D" '^media'

echo "helper definitions outside the exported frame"
HELPER='function ButtonLinkout({ className }) {
  return (
    <div className={className || "px-[22px]"} data-node-id="1:9">
      <p className="text-[14px]" data-node-id="1:10">Learn</p>
    </div>
  );
}
'
D="$(new_case helper)"
add_variant "$D" Desktop 1:118 1280 "${HELPER}export default function Desktop() {
  return (
    <div className=\"p-[40px]\" data-node-id=\"1:118\" data-name=\"Desktop\"><ButtonLinkout className=\"w-full\" /></div>
  );
}"
add_variant "$D" Mobile 1:430 375 "${HELPER}export default function Mobile() {
  return (
    <div className=\"p-[16px]\" data-node-id=\"1:430\" data-name=\"Mobile\"><ButtonLinkout className=\"w-full\" /></div>
  );
}"
write_ref "$D"
run_overrides "$D" 900
status_is "exits 0" "$D" 0
has_line "a definition's node is keyed by its own id" "$D" value base 1:10 font-size 14px 1:10 'def:1:10'
has_line "the exported frame is the root" "$D" value 900 1:430 padding 40px 1:118 /
no_match "an identical definition is no override" "$D" "^value${TAB}900${TAB}1:10"

echo "rows agree with the value table"
D="$(new_case agree)"
add_variant "$D" Mobile 1:430 375 "$MOBILE"
add_variant "$D" Desktop 1:118 1280 "$DESKTOP"
write_ref "$D"
run_overrides "$D" -
jq '. + {design_context: {code_file: ".ai/run-context/design-context-1-430.txt", styles: null}}' \
  "$D/.ai/run-context/design-reference.json" > "$D/single.json"
(cd "$D" && python3 "$TABLE" single.json | cut -f1-3 | sort > "$D/table.tsv")
awk -F"$TAB" '$1 == "value" && $2 == "base" { print $3 "\t" $4 "\t" $5 }' "$D/stdout" | sort > "$D/base.tsv"
if [ -s "$D/table.tsv" ] && cmp -s "$D/table.tsv" "$D/base.tsv"; then ok "base rows are the value table's rows"; else
  bad "base rows are the value table's rows" "table: $(cat "$D/table.tsv")" "base: $(cat "$D/base.tsv")"; fi

echo "refusals"
D="$(new_case refuse)"
add_variant "$D" Desktop 1:118 1280 "$DESKTOP"
add_variant "$D" Mobile 1:430 375 "$MOBILE"
write_ref "$D"
run_overrides "$D" 900px
status_is "a breakpoint with a unit is refused" "$D" 2
run_overrides "$D" ""
status_is "an empty breakpoint list is refused" "$D" 2
(cd "$D" && python3 "$OVERRIDES" .ai/run-context/design-reference.json >"$D/stdout" 2>"$D/stderr"); STATUS=$?
status_is "a missing argument is refused" "$D" 2
(cd "$D" && python3 "$OVERRIDES" missing.json 900 >"$D/stdout" 2>"$D/stderr"); STATUS=$?
status_is "a missing reference is refused" "$D" 2
rm "$D/.ai/run-context/design-context-1-430.txt"
run_overrides "$D" 900
status_is "a missing context file is refused" "$D" 2
D="$(new_case no-export)"
add_variant "$D" Desktop 1:118 1280 '<div className="p-[40px]" data-node-id="1:118"></div>'
add_variant "$D" Mobile 1:430 375 "$MOBILE"
write_ref "$D"
run_overrides "$D" 900
status_is "reference code with no exported function uses its first element" "$D" 0
has_line "and matches it as the root" "$D" value 900 1:430 padding 40px 1:118 /

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
