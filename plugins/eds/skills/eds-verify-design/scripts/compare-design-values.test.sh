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

echo "size mode: a size difference follows an approx line on the same selector and the same dimension only"
# The run's header cells: three approx lines name `th` for `height`. A width
# difference on `th` is not covered by them (the design's columns are equal by
# layout, not by content); a height difference is.
REPORT_SIZE='## Design values

.t th — height — 96px — source: design_context — token: none — node: 1:197
.t th — height — 96px — source: design_context — token: none — node: 1:206
.t th — padding-top — 40px — source: design_context — token: none — node: 1:197
.card img — aspect-ratio — 16/9 — source: design_context — token: none — node: 8:2
'
TSV_SIZE="1:197${TAB}height${TAB}96px${TAB}true
1:206${TAB}height${TAB}96px${TAB}true
1:197${TAB}padding-top${TAB}40px${TAB}false
8:2${TAB}aspect-ratio${TAB}16/9${TAB}true
"
SIZE_JSON='{"target":"x","results":{".t th":{"found":true,"geometry":{"x":40,"y":64,"width":381.703125,"height":96},"computed":{"padding-top":"40px"}},".card img":{"found":true,"geometry":{"x":0,"y":0,"width":320,"height":180},"computed":{}}}}'
D="$(case_dir size "$TSV_SIZE" "$REPORT_SIZE" "$SIZE_JSON")"
# run_size <case-dir> <selector> <dimension> — sets STATUS, writes stdout
run_size() {
  python3 "$CMP" size "$1/values.tsv" "$1/report.md" "$1/measure.json" "$2" "$3" >"$1/stdout" 2>"$1/stderr"
  STATUS=$?
}
run_size "$D" ".t th" width
exit_is "th width: no approx line names width on th → fixable (exit 1)" 1
has_line "th width is fixable, saying why" "$D" \
  "fixable${TAB}.t th${TAB}width${TAB}no approx line names width on this selector"
run_size "$D" ".t th" height
exit_is "th height: an approx line names it → content-dependent (exit 0)" 0
has_line "th height follows the approx line, quoted" "$D" \
  "content-dependent${TAB}.t th${TAB}height${TAB}follows approx line: .t th height: expected 96px, measured box 381.7x96px (node 1:197)"
run_size "$D" ".t td" height
exit_is "a selector no approx line names → fixable" 1
has_line "td height is fixable" "$D" \
  "fixable${TAB}.t td${TAB}height${TAB}no approx line names height on this selector"
run_size "$D" ".card img" width
exit_is "aspect-ratio covers width" 0
has_line "img width follows the aspect-ratio line" "$D" \
  "content-dependent${TAB}.card img${TAB}width${TAB}follows approx line: .card img aspect-ratio: expected 16/9, measured box 320x180px (node 8:2)"
run_size "$D" ".card img" height
exit_is "aspect-ratio covers height" 0
run_size "$D" ".t th" depth
exit_is "a dimension other than width or height is a usage error" 2
run_size "$D" "" width
exit_is "an empty selector is a usage error" 2

echo "variables mode: a design variable is compared on the element its token is written on, never on the wrapper"
# From the run: Text/Headline is written as `--text-headline` on the heading
# text; the wrapper `.table` inherits the body's colour and has no design node.
# Four variables have no line carrying their token and one is a composite.
VARS_REF='{"has_values": true, "variables": {"Accent/Accent 1": "#485C11", "Accent/Accent 4": "#000000", "Background/Background 1": "#FFFFFF", "Captions": "Font(family: \"Roboto Mono\", style: Regular, size: 12, weight: 400, lineHeight: 1.399999976158142, letterSpacing: -1)", "Dividers/Divider 1": "#E9E9E9", "Text/Headline": "#000000"}}'
REPORT_VARS='## Design values

.table.comparison — border-radius — 20px — source: design_context — token: none — node: 1:195
.table.comparison table th:first-child p — color — #000000 — source: variables — token: --text-headline
.table.comparison table th:first-child — background-color — #FFFFFF — source: variables — token: --background-background-1
.table.comparison table td p — color — #000000 — source: variables — token: --accent-accent-4
.table.comparison table td — border-color — #e9e9e9 — source: variables — token: --dividers-divider-1
.table.comparison table th:nth-child(2) p — color — #6f6f6f — source: design_context — token: --text-paragraph — node: 1:207
'
VARS_JSON='{"target":"x","results":{".table":{"found":true,"geometry":{},"computed":{"color":"rgb(19, 19, 19)","background-color":"rgba(0, 0, 0, 0)"}},".table.comparison table th:first-child p":{"found":true,"geometry":{},"computed":{"color":"rgb(0, 0, 0)"}},".table.comparison table th:first-child":{"found":true,"geometry":{},"computed":{"background-color":"rgb(255, 255, 255)"}},".table.comparison table td p":{"found":true,"geometry":{},"computed":{"color":"rgb(0, 0, 0)"}},".table.comparison table td":{"found":true,"geometry":{},"computed":{"color":"rgb(19, 19, 19)"}}}}'
D="$(case_dir vars "" "$REPORT_VARS" "$VARS_JSON")"
printf '%s' "$VARS_REF" > "$D/reference.json"
run_vars() {
  python3 "$CMP" variables "$1/reference.json" "$1/report.md" "$1/measure.json" >"$1/stdout" 2>"$1/stderr"
  STATUS=$?
}
run_vars "$D"
exit_is "every linked variable matches → exit 0" 0
has_line "Text/Headline matches on the heading text" "$D" \
  "match${TAB}Text/Headline${TAB}.table.comparison table th:first-child p${TAB}color${TAB}#000000"
has_line "Background/Background 1 matches on the header cell" "$D" \
  "match${TAB}Background/Background 1${TAB}.table.comparison table th:first-child${TAB}background-color${TAB}#FFFFFF"
has_line "Accent/Accent 4 matches on the cell text" "$D" \
  "match${TAB}Accent/Accent 4${TAB}.table.comparison table td p${TAB}color${TAB}#000000"
no_line_matching "the wrapper is never a comparison element" "$D" "${TAB}\.table${TAB}"
has_line "a variable written as a property measure does not report is unmeasured" "$D" \
  "unmeasured${TAB}Dividers/Divider 1${TAB}.table.comparison table td${TAB}border-color${TAB}#E9E9E9: not in measure's property set"
has_line "a variable no line carries is unmeasured" "$D" \
  "unmeasured${TAB}Accent/Accent 1${TAB}-${TAB}-${TAB}#485C11: no design-values line carries its token"
has_line "a composite variable is unmeasured" "$D" \
  "unmeasured${TAB}Captions${TAB}-${TAB}-${TAB}Font(family: \"Roboto Mono\", style: Regular, size: 12, weight: 400, lineHeight: 1.399999976158142, letterSpacing: -1): no design-values line carries its token"
no_line_matching "a design_context line with a token is the value table's, not a variable's" "$D" \
  "th:nth-child\(2\) p"
# the wrapper rule would have failed Text/Headline: rgb(19, 19, 19) is not #000000
D2="$(case_dir varsmis "" "$REPORT_VARS" "${VARS_JSON//rgb(0, 0, 0)/rgb(19, 19, 19)}")"
printf '%s' "$VARS_REF" > "$D2/reference.json"
run_vars "$D2"
exit_is "a variable mismatch on its own element exits 1" 1
has_line "the mismatch names the element and both values" "$D2" \
  "mismatch${TAB}Text/Headline${TAB}.table.comparison table th:first-child p${TAB}color${TAB}expected #000000, measured rgb(19, 19, 19)"
D3="$(case_dir varsnone "" "$REPORT_VARS" "$VARS_JSON")"
printf '{"has_values": false}' > "$D3/reference.json"
run_vars "$D3"
exit_is "a reference without variables exits 0 and prints nothing" 0
if [ ! -s "$D3/stdout" ]; then ok "no variables, no lines"; else bad "no variables, no lines" "got: $(cat "$D3/stdout")"; fi

echo "selectors mode lists the selectors of variables-sourced lines too"
D="$(case_dir selvars "" "$REPORT_VARS" "{}")"
python3 "$CMP" selectors "$D/report.md" >"$D/stdout" 2>"$D/stderr"
STATUS=$?
exit_is "exits 0" 0
got="$(cat "$D/stdout")"
want=".table.comparison
.table.comparison table th:first-child p
.table.comparison table th:first-child
.table.comparison table td p
.table.comparison table td
.table.comparison table th:nth-child(2) p"
if [ "$got" = "$want" ]; then ok "node-bearing and variables-sourced selectors, once, in order"; else bad "node-bearing and variables-sourced selectors, once, in order" "want: $want" "got: $got"; fi

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

echo "a node: tail that is not one node id is an error, in both modes"
tail_report() {
  printf '# Prototype report\n\n## Design values\n\n- .t th — padding — 8px — source: design_context — token: none — %s\n' "$1"
}
printf '1:196%spadding%s8px%sfalse\n' "$TAB" "$TAB" "$TAB" > "$WORK/tail.tsv"
printf '{"target":"x","results":{}}' > "$WORK/tail.json"
for tail in 'node: 1:196, 1:205' 'node: 1:199–1:204' 'node:'; do
  tail_report "$tail" > "$WORK/tail.md"
  python3 "$CMP" selectors "$WORK/tail.md" >"$WORK/tail.out" 2>"$WORK/tail.err"
  STATUS=$?
  exit_is "selectors: '$tail' exits 2" 2
  if grep -qF -- "$tail" "$WORK/tail.err"; then ok "selectors: stderr names '$tail'"; else bad "selectors: stderr names '$tail'" "stderr: $(cat "$WORK/tail.err")"; fi
  python3 "$CMP" compare "$WORK/tail.tsv" "$WORK/tail.md" "$WORK/tail.json" >"$WORK/tail.out" 2>"$WORK/tail.err"
  STATUS=$?
  exit_is "compare: '$tail' exits 2" 2
  if grep -qF -- "$tail" "$WORK/tail.err"; then ok "compare: stderr names '$tail'"; else bad "compare: stderr names '$tail'" "stderr: $(cat "$WORK/tail.err")"; fi
done
for tail in 'node: 1:196' 'node: I1:199;1:564'; do
  tail_report "$tail" > "$WORK/tail.md"
  python3 "$CMP" selectors "$WORK/tail.md" >"$WORK/tail.out" 2>"$WORK/tail.err"
  STATUS=$?
  exit_is "selectors: '$tail' still exits 0" 0
  if [ "$(cat "$WORK/tail.out")" = ".t th" ]; then ok "selectors: '$tail' still yields its selector"; else bad "selectors: '$tail' still yields its selector" "got: $(cat "$WORK/tail.out")"; fi
done
printf '# Prototype report\n\n## Design values\n\n- .t th — color — #000 — source: variables — token: --text\n' > "$WORK/tail.md"
python3 "$CMP" selectors "$WORK/tail.md" >"$WORK/tail.out" 2>"$WORK/tail.err"
STATUS=$?
exit_is "selectors: a line with no node: part is still skipped, exit 0" 0

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
