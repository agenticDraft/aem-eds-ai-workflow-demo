#!/usr/bin/env bash
# Tests for compare-design-values.py. Run with:
#   bash plugins/eds/skills/eds-verify-design/scripts/compare-design-values.test.sh
#
# No framework, and no browser — exits 0 when every case passes, 1 otherwise.
# Each case writes a value table, a prototype report and a measurement file in
# a temporary directory, shaped as the prototype and measure operations write
# them.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMP="$SCRIPT_DIR/compare-design-values.py"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/compare-design-values.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
TAB="$(printf '\t')"

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# case_dir <name> <tsv> <report> <measure-json> — writes the three inputs
case_dir() {
  local dir="$WORK/$1"
  mkdir -p "$dir"
  printf '%s' "$2" > "$dir/values.tsv"
  printf '%s' "$3" > "$dir/report.md"
  printf '%s' "$4" > "$dir/measure.json"
  echo "$dir"
}

# run_compare <case-dir> — sets STATUS
run_compare() {
  python3 "$CMP" compare "$1/values.tsv" "$1/report.md" "$1/measure.json" >"$1/stdout" 2>"$1/stderr"
  STATUS=$?
}

# has_line <desc> <case-dir> <line>
has_line() {
  if grep -qxF -- "$3" "$2/stdout"; then ok "$1"; else bad "$1" "want: $3" "got: $(cat "$2/stdout")" "stderr: $(cat "$2/stderr")"; fi
}

# no_line_matching <desc> <case-dir> <regex>
no_line_matching() {
  if grep -qE -- "$3" "$2/stdout"; then bad "$1" "found: $(grep -E -- "$3" "$2/stdout")"; else ok "$1"; fi
}

# exit_is <desc> <want>
exit_is() {
  if [ "$STATUS" -eq "$2" ]; then ok "$1"; else bad "$1" "want exit $2, got $STATUS"; fi
}

REPORT='# Prototype report

Target block: zoki (new)

## Design values

.zoki — padding-inline — 22px — source: design_context — token: none — node: 1:185
.zoki — padding-block — 14px — source: design_context — token: none — node: 1:185
.zoki — border-radius — 1000px — source: design_context — token: none — node: 1:185
.zoki — background-color — var(--accent-2) — source: variables — token: --accent-2
- `.zoki a — font-size — 14px — source: design_context — token: none — node: I1:185;1:543`

Rows: 6.

## Files written

- node: 9:9 is not a design-values line
'

measure_json() {
  # measure_json <.zoki padding-left> <.zoki radius> <.zoki gap>
  cat <<EOF
{
  "target": "http://localhost:3001/drafts/EDS-1",
  "results": {
    ".zoki": {
      "found": true,
      "geometry": { "x": 0, "y": 0, "width": 120, "height": 48 },
      "computed": {
        "color": "rgb(26, 26, 26)",
        "background-color": "rgb(223, 236, 198)",
        "font-family": "Inter, sans-serif",
        "font-size": "16px",
        "font-weight": "400",
        "line-height": "normal",
        "padding-top": "14px",
        "padding-right": "22px",
        "padding-bottom": "14px",
        "padding-left": "$1",
        "gap": "$3",
        "border-radius": "$2"
      }
    },
    ".zoki a": {
      "found": true,
      "geometry": { "x": 22, "y": 14, "width": 76, "height": 20 },
      "computed": {
        "color": "rgb(26, 26, 26)",
        "background-color": "rgba(0, 0, 0, 0)",
        "font-family": "Inter, sans-serif",
        "font-size": "14px",
        "font-weight": "400",
        "line-height": "19.6px",
        "padding-top": "0px",
        "padding-right": "0px",
        "padding-bottom": "0px",
        "padding-left": "0px",
        "gap": "normal",
        "border-radius": "0px"
      }
    }
  }
}
EOF
}

echo "a padding mismatch is named numerically"
TSV="1:185${TAB}padding-inline${TAB}22px${TAB}false
1:185${TAB}padding-block${TAB}14px${TAB}false
1:185${TAB}border-radius${TAB}1000px${TAB}false
"
D="$(case_dir padmismatch "$TSV" "$REPORT" "$(measure_json 20px 1000px normal)")"
run_compare "$D"
exit_is "exits 1 on a mismatch" 1
has_line "padding-left 22px vs 20px names both numbers" "$D" \
  "mismatch${TAB}1:185${TAB}.zoki${TAB}padding-left${TAB}expected 22px, measured 20px (table: padding-inline 22px)"
has_line "padding-right from the same shorthand matches" "$D" \
  "match${TAB}1:185${TAB}.zoki${TAB}padding-right${TAB}22px"
has_line "padding-block expands to padding-top" "$D" \
  "match${TAB}1:185${TAB}.zoki${TAB}padding-top${TAB}14px"
has_line "padding-block expands to padding-bottom" "$D" \
  "match${TAB}1:185${TAB}.zoki${TAB}padding-bottom${TAB}14px"
has_line "border-radius compared as one length" "$D" \
  "match${TAB}1:185${TAB}.zoki${TAB}border-radius${TAB}1000px"
no_line_matching "a shorthand is never a compared property" "$D" "${TAB}padding-(inline|block)${TAB}"

echo "everything matches"
D="$(case_dir allmatch "$TSV" "$REPORT" "$(measure_json 22px 1000px normal)")"
run_compare "$D"
exit_is "exits 0 when nothing mismatches" 0
no_line_matching "no mismatch line" "$D" "^mismatch"

echo "radius and gap"
TSV="1:185${TAB}border-radius${TAB}8px${TAB}false
1:185${TAB}gap${TAB}8.0px${TAB}false
"
# the report's radius line carries the table's value, so the line is unsplit
D="$(case_dir radius "$TSV" "${REPORT//1000px/8px}" "$(measure_json 22px 1000px 8px)")"
run_compare "$D"
exit_is "exits 1" 1
has_line "a radius mismatch names both values" "$D" \
  "mismatch${TAB}1:185${TAB}.zoki${TAB}border-radius${TAB}expected 8px, measured 1000px"
has_line "gap 8.0px equals measured 8px after normalising" "$D" \
  "match${TAB}1:185${TAB}.zoki${TAB}gap${TAB}8px"

echo "unequal corners are compared as the browser's string"
TSV="1:185${TAB}border-radius${TAB}4px 8px${TAB}false
"
D="$(case_dir corners "$TSV" "${REPORT//1000px/4px 8px}" "$(measure_json 22px '4px 8px' normal)")"
run_compare "$D"
exit_is "exits 0" 0
has_line "two-value radius string matches" "$D" \
  "match${TAB}1:185${TAB}.zoki${TAB}border-radius${TAB}4px 8px"

echo "padding shorthand, one to four values"
TSV="1:185${TAB}padding${TAB}14px 22px 10px${TAB}false
"
D="$(case_dir padding3 "$TSV" "$REPORT" "$(measure_json 22px 1000px normal)")"
run_compare "$D"
has_line "three-value padding: top" "$D" "match${TAB}1:185${TAB}.zoki${TAB}padding-top${TAB}14px"
has_line "three-value padding: right" "$D" "match${TAB}1:185${TAB}.zoki${TAB}padding-right${TAB}22px"
has_line "three-value padding: bottom mismatches" "$D" \
  "mismatch${TAB}1:185${TAB}.zoki${TAB}padding-bottom${TAB}expected 10px, measured 14px (table: padding 14px 22px 10px)"
has_line "three-value padding: left is the right value" "$D" "match${TAB}1:185${TAB}.zoki${TAB}padding-left${TAB}22px"

echo "the older properties, by form"
TSV="1:185${TAB}background-color${TAB}#DFECC6${TAB}false
I1:185;1:543${TAB}font-size${TAB}14px${TAB}false
I1:185;1:543${TAB}line-height${TAB}1.4${TAB}false
I1:185;1:543${TAB}color${TAB}#1a1a1a${TAB}false
"
D="$(case_dir older "$TSV" "$REPORT" "$(measure_json 22px 1000px normal)")"
run_compare "$D"
exit_is "exits 0" 0
has_line "a hex colour equals the measured rgb()" "$D" \
  "match${TAB}1:185${TAB}.zoki${TAB}background-color${TAB}#DFECC6"
has_line "a nested node is compared on its own selector" "$D" \
  "match${TAB}I1:185;1:543${TAB}.zoki a${TAB}font-size${TAB}14px"
has_line "a unitless line-height is not compared against a px value" "$D" \
  "unmeasured${TAB}I1:185;1:543${TAB}.zoki a${TAB}line-height${TAB}1.4: not comparable to the computed value"
has_line "a colour on the nested node" "$D" \
  "match${TAB}I1:185;1:543${TAB}.zoki a${TAB}color${TAB}#1a1a1a"

echo "a property outside the measured set is never compared"
TSV="1:185${TAB}margin-top${TAB}8px${TAB}false
1:185${TAB}column-gap${TAB}12px${TAB}false
1:185${TAB}letter-spacing${TAB}-0.35px${TAB}false
1:185${TAB}border-top-left-radius${TAB}4px${TAB}false
1:185${TAB}width${TAB}120px${TAB}false
"
D="$(case_dir outside "$TSV" "$REPORT" "$(measure_json 22px 1000px normal)")"
run_compare "$D"
exit_is "exits 0" 0
has_line "margin-top is unmeasured" "$D" \
  "unmeasured${TAB}1:185${TAB}-${TAB}margin-top${TAB}8px: not in measure's property set"
has_line "column-gap is unmeasured" "$D" \
  "unmeasured${TAB}1:185${TAB}-${TAB}column-gap${TAB}12px: not in measure's property set"
has_line "a per-corner radius is unmeasured, never inferred" "$D" \
  "unmeasured${TAB}1:185${TAB}-${TAB}border-top-left-radius${TAB}4px: not in measure's property set"
no_line_matching "no match or mismatch line at all" "$D" "^(match|mismatch)${TAB}"

echo "a node the report names no selector for"
TSV="7:7${TAB}padding${TAB}8px${TAB}false
"
D="$(case_dir nosel "$TSV" "$REPORT" "$(measure_json 22px 1000px normal)")"
run_compare "$D"
exit_is "exits 0" 0
has_line "unmeasured, naming the reason" "$D" \
  "unmeasured${TAB}7:7${TAB}-${TAB}padding${TAB}8px: no selector recorded for this node"

echo "a selector the measurement did not find, or did not measure"
REPORT_NF='## Design values

.missing — padding — 8px — source: design_context — token: none — node: 5:5
'
TSV="5:5${TAB}padding-top${TAB}8px${TAB}false
"
D="$(case_dir notfound "$TSV" "$REPORT_NF" '{"target":"x","results":{".missing":{"found":false}}}')"
run_compare "$D"
exit_is "exits 0" 0
has_line "found: false is unmeasured" "$D" \
  "unmeasured${TAB}5:5${TAB}.missing${TAB}padding-top${TAB}8px: selector not found on the page"
D="$(case_dir oldshape "$TSV" "$REPORT_NF" '{"target":"x","results":{".missing":{"found":true,"geometry":{},"computed":{"color":"rgb(0, 0, 0)"}}}}')"
run_compare "$D"
has_line "a measurement without the property is unmeasured" "$D" \
  "unmeasured${TAB}5:5${TAB}.missing${TAB}padding-top${TAB}8px: not in the measurement"

echo "values the table form cannot decide"
TSV="1:185${TAB}padding${TAB}1rem${TAB}false
1:185${TAB}gap${TAB}var(--space)${TAB}false
"
D="$(case_dir nondecidable "$TSV" "$REPORT" "$(measure_json 22px 1000px normal)")"
run_compare "$D"
exit_is "exits 0" 0
has_line "rem is not converted" "$D" \
  "unmeasured${TAB}1:185${TAB}.zoki${TAB}padding-top${TAB}1rem: not comparable to the computed value"
has_line "a var() is not resolved" "$D" \
  "unmeasured${TAB}1:185${TAB}.zoki${TAB}gap${TAB}var(--space): not comparable to the computed value"

echo "a node's radius split over two selectors, as applied (EDS-18 node 1:196)"
REPORT_SPLIT='## Design values

.t th:first-child, .t td:first-child — border-inline (colour) — var(--divider) — source: design_context — token: --divider — node: 1:196
.t th:first-child — border-radius — 20px 20px 0 0 — source: design_context — token: none — node: 1:196
.t tr:last-child td:first-child — border-radius — 0 0 20px 20px — source: design_context — token: none — node: 1:196
'
# split_json <th radius> <last td radius>
split_json() {
  cat <<EOF
{
  "target": "http://localhost:3001/drafts/EDS-18",
  "results": {
    ".t th:first-child, .t td:first-child": { "found": true, "geometry": {}, "computed": { "border-radius": "$1" } },
    ".t th:first-child": { "found": true, "geometry": {}, "computed": { "border-radius": "$1" } },
    ".t tr:last-child td:first-child": { "found": true, "geometry": {}, "computed": { "border-radius": "$2" } }
  }
}
EOF
}
TSV="1:196${TAB}border-radius${TAB}20px${TAB}false
"
D="$(case_dir split "$TSV" "$REPORT_SPLIT" "$(split_json '20px 20px 0px 0px' '0px 0px 20px 20px')")"
run_compare "$D"
exit_is "a correct split render exits 0" 0
has_line "top corners match the line's own value" "$D" \
  "match${TAB}1:196${TAB}.t th:first-child${TAB}border-radius${TAB}20px 20px 0px 0px"
has_line "bottom corners match the line's own value" "$D" \
  "match${TAB}1:196${TAB}.t tr:last-child td:first-child${TAB}border-radius${TAB}0px 0px 20px 20px"
no_line_matching "a selector whose line carries another property is not compared on radius" "$D" \
  "^[a-z]+${TAB}1:196${TAB}\.t th:first-child, \.t td:first-child${TAB}border-radius${TAB}"

D="$(case_dir splitwrong "$TSV" "$REPORT_SPLIT" "$(split_json '20px 20px 0px 0px' '0px 0px 8px 8px')")"
run_compare "$D"
exit_is "a wrong render of a split line exits 1" 1
has_line "the wrong split is a mismatch against the line's own value" "$D" \
  "mismatch${TAB}1:196${TAB}.t tr:last-child td:first-child${TAB}border-radius${TAB}expected 0px 0px 20px 20px, measured 0px 0px 8px 8px (split of 20px)"
has_line "the correct half still matches" "$D" \
  "match${TAB}1:196${TAB}.t th:first-child${TAB}border-radius${TAB}20px 20px 0px 0px"

echo "a split line whose non-zero component is not the node's value"
REPORT_OVER='## Design values

.t th:first-child — border-radius — 24px 24px 0 0 — source: design_context — token: none — node: 1:196
'
D="$(case_dir splitover "$TSV" "$REPORT_OVER" "$(split_json '24px 24px 0px 0px' '0px')")"
run_compare "$D"
exit_is "exits 1 even though the render matches the line" 1
has_line "the line is refused, naming the node's value" "$D" \
  "mismatch${TAB}1:196${TAB}.t th:first-child${TAB}border-radius${TAB}expected 20px, measured 24px 24px 0px 0px (line: 24px 24px 0 0 is not a split of 20px)"

echo "an unsplit line keeps today's rule"
REPORT_WHOLE='## Design values

.t th:first-child — border-radius — 20px — source: design_context — token: none — node: 1:196
'
D="$(case_dir unsplit "$TSV" "$REPORT_WHOLE" "$(split_json '20px 20px 0px 0px' '0px')")"
run_compare "$D"
exit_is "exits 1" 1
has_line "compared against the node's value" "$D" \
  "mismatch${TAB}1:196${TAB}.t th:first-child${TAB}border-radius${TAB}expected 20px, measured 20px 20px 0px 0px"
D="$(case_dir unsplitok "$TSV" "$REPORT_WHOLE" "$(split_json '20px' '0px')")"
run_compare "$D"
exit_is "a correct unsplit render exits 0" 0
has_line "matches the node's value" "$D" \
  "match${TAB}1:196${TAB}.t th:first-child${TAB}border-radius${TAB}20px"

echo "a line still in the old qualifier shape is compared, never dropped"
REPORT_QUAL='## Design values

.t th:first-child — border-radius (top) — 20px — source: design_context — token: none — node: 1:196
'
D="$(case_dir qualifier "$TSV" "$REPORT_QUAL" "$(split_json '20px 20px 0px 0px' '0px')")"
run_compare "$D"
exit_is "exits 1" 1
has_line "the qualifier is ignored and the node's value expected" "$D" \
  "mismatch${TAB}1:196${TAB}.t th:first-child${TAB}border-radius${TAB}expected 20px, measured 20px 20px 0px 0px"

echo "a line value the comparer cannot decide falls back to the node's value"
REPORT_VAR='## Design values

.t th:first-child — border-radius — var(--radius-l) — source: design_context — token: --radius-l — node: 1:196
'
D="$(case_dir splitvar "$TSV" "$REPORT_VAR" "$(split_json '20px' '0px')")"
run_compare "$D"
exit_is "exits 0" 0
has_line "compared as the node's value" "$D" \
  "match${TAB}1:196${TAB}.t th:first-child${TAB}border-radius${TAB}20px"

echo "a width that is not approx stays unmeasured"
TSV="1:185${TAB}width${TAB}120px${TAB}false
"
D="$(case_dir structwidth "$TSV" "$REPORT" "$(measure_json 22px 1000px normal)")"
run_compare "$D"
exit_is "exits 0" 0
has_line "a structural width is unmeasured, never listed as approx" "$D" \
  "unmeasured${TAB}1:185${TAB}-${TAB}width${TAB}120px: not in measure's property set"
no_line_matching "no approx line" "$D" "^approx"

echo "an approx value is listed, not graded"
TSV="I1:185;1:543${TAB}width${TAB}94px${TAB}true
1:185${TAB}padding-inline${TAB}22px${TAB}false
I1:185;1:543${TAB}height${TAB}20px${TAB}true
"
D="$(case_dir approx "$TSV" "$REPORT" "$(measure_json 22px 1000px normal)")"
run_compare "$D"
exit_is "an approx mismatch alone exits 0" 0
has_line "the text width is listed with both values" "$D" \
  "approx${TAB}I1:185;1:543${TAB}.zoki a${TAB}width${TAB}expected 94px, measured box 76x20px"
has_line "an approx value equal to the box is listed too" "$D" \
  "approx${TAB}I1:185;1:543${TAB}.zoki a${TAB}height${TAB}expected 20px, measured box 76x20px"
no_line_matching "an approx value is never a mismatch" "$D" "^mismatch${TAB}I1:185;1:543${TAB}"
no_line_matching "an approx value is never unmeasured" "$D" "^unmeasured${TAB}I1:185;1:543${TAB}"
got="$(cut -f1 "$D/stdout" | tr '\n' ' ')"
if [ "$got" = "match match approx approx " ]; then ok "approx lines follow every graded line, in their own block"; else bad "approx lines follow every graded line, in their own block" "got: $got"; fi

echo "an approx value next to a graded mismatch"
D="$(case_dir approxmix "$TSV" "$REPORT" "$(measure_json 20px 1000px normal)")"
run_compare "$D"
exit_is "the graded mismatch alone decides exit 1" 1
has_line "the padding mismatch is graded" "$D" \
  "mismatch${TAB}1:185${TAB}.zoki${TAB}padding-left${TAB}expected 22px, measured 20px (table: padding-inline 22px)"
has_line "the width is still listed as approx" "$D" \
  "approx${TAB}I1:185;1:543${TAB}.zoki a${TAB}width${TAB}expected 94px, measured box 76x20px"

echo "approx aspect ratio and min-height of an image fill"
REPORT_IMG='## Design values

.card img — aspect-ratio — 16/9 — source: design_context — token: none — node: 8:2
'
TSV="8:2${TAB}aspect-ratio${TAB}16/9${TAB}true
8:2${TAB}min-height${TAB}180px${TAB}true
"
D="$(case_dir approximg "$TSV" "$REPORT_IMG" '{"target":"x","results":{".card img":{"found":true,"geometry":{"x":0,"y":0,"width":320.5,"height":200.25},"computed":{}}}}')"
run_compare "$D"
exit_is "exits 0" 0
has_line "aspect-ratio listed against the box" "$D" \
  "approx${TAB}8:2${TAB}.card img${TAB}aspect-ratio${TAB}expected 16/9, measured box 320.5x200.25px"
has_line "min-height listed against the box" "$D" \
  "approx${TAB}8:2${TAB}.card img${TAB}min-height${TAB}expected 180px, measured box 320.5x200.25px"

echo "an approx value that cannot be located is still listed"
TSV="7:7${TAB}width${TAB}50px${TAB}true
5:5${TAB}height${TAB}10px${TAB}true
"
D="$(case_dir approxnowhere "$TSV" "$REPORT_NF" '{"target":"x","results":{".missing":{"found":false}}}')"
run_compare "$D"
exit_is "exits 0" 0
has_line "no selector for the node" "$D" \
  "approx${TAB}7:7${TAB}-${TAB}width${TAB}50px: no selector recorded for this node"
has_line "selector not on the page" "$D" \
  "approx${TAB}5:5${TAB}.missing${TAB}height${TAB}10px: selector not found on the page"
D="$(case_dir approxnobox "$TSV" "$REPORT_NF" '{"target":"x","results":{".missing":{"found":true,"geometry":{},"computed":{}}}}')"
run_compare "$D"
has_line "a measurement without a box" "$D" \
  "approx${TAB}5:5${TAB}.missing${TAB}height${TAB}10px: no box in the measurement"

echo "selectors mode"
D="$(case_dir selectors "" "$REPORT" "{}")"
python3 "$CMP" selectors "$D/report.md" >"$D/stdout" 2>"$D/stderr"
STATUS=$?
exit_is "exits 0" 0
got="$(cat "$D/stdout")"
want=".zoki
.zoki a"
if [ "$got" = "$want" ]; then ok "one selector per node-bearing line, once, in order"; else bad "one selector per node-bearing line, once, in order" "want: $want" "got: $got"; fi

echo "usage errors"
D="$(case_dir usage "" "$REPORT" "not json")"
run_compare "$D"
exit_is "unreadable measurement exits 2" 2
python3 "$CMP" compare "$D/values.tsv" >/dev/null 2>&1
STATUS=$?
exit_is "missing arguments exit 2" 2
printf 'only-two%scolumns\n' "$TAB" > "$D/values.tsv"
printf '{"target":"x","results":{}}' > "$D/measure.json"
run_compare "$D"
exit_is "a malformed table row exits 2" 2
printf '1:185%spadding%s8px\n' "$TAB" "$TAB" > "$D/values.tsv"
run_compare "$D"
exit_is "a row without the approx column exits 2" 2
printf '1:185%spadding%s8px%syes\n' "$TAB" "$TAB" "$TAB" > "$D/values.tsv"
run_compare "$D"
exit_is "an approx column other than true or false exits 2" 2
for prop in padding-inline gap margin-top border-radius; do
  printf '1:185%s%s%s8px%strue\n' "$TAB" "$prop" "$TAB" "$TAB" > "$D/values.tsv"
  run_compare "$D"
  exit_is "approx true on $prop is refused (exit 2)" 2
done

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
