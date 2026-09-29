#!/usr/bin/env bash
# Tests for check-design-relevance.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-design-relevance.test.sh
#
# No framework. Confirms: the tokenisation rules one by one (word split,
# lower case, camel case, the fixed stop-word list, minimum length, digits,
# plurals, hyphens); a matching pair; a mismatching pair, including copy
# inside the design context that shares the item's words and is never
# counted; the threshold at exactly 1 and exactly 2; the three name
# prefixes stripped; image mode and an item with no design reported as not
# run; every outcome exiting 0; and the usage errors.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-design-relevance.sh"
FIX="$SCRIPT_DIR/../fixtures/design-relevance"

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

assert_eq() {
  local desc="$1" want="$2" got="$3"
  if [[ "$want" == "$got" ]]; then ok "$desc"; else bad "$desc" "want: [$want]" "got:  [$got]"; fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then ok "$desc"; else bad "$desc" "want to contain: $needle" "got: $haystack"; fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then ok "$desc"; else bad "$desc" "must not contain: $needle" "got: $haystack"; fi
}

tokens() { bash "$CHECK" --tokens "$1" 2>&1 | tr '\n' ' ' | sed 's/ $//'; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-design-relevance.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

echo "=== check-design-relevance.sh tests ==="

echo "[tokens] split, case, length, digits"
assert_eq "split on spaces and punctuation, lower-cased" "feature comparison table" "$(tokens 'Feature, comparison: TABLE!')"
assert_eq "hyphenated and slashed names split" "comparison table hero banner" "$(tokens 'comparison-table hero/banner')"
assert_eq "underscores split" "table item" "$(tokens 'table_item')"
assert_eq "camel case splits" "table item check icon" "$(tokens 'TableItem checkIcon')"
assert_eq "tokens shorter than 3 dropped" "cta" "$(tokens 'UI ok cta')"
assert_eq "digit-only tokens dropped" "column" "$(tokens 'Column 12')"
assert_eq "letters and digits together kept" "h1title utf8" "$(tokens 'h1title utf8')"

echo "[tokens] plurals"
assert_eq "a trailing s is dropped" "icon card table" "$(tokens 'icons cards tables')"
assert_eq "a trailing ss is kept" "class" "$(tokens 'class')"
assert_eq "a 3-letter word keeps its s" "bus" "$(tokens 'bus')"

echo "[tokens] the fixed stop-word list"
WANT_STOP="and are but component desktop for from has have into its mobile not onto our per should that the their this via was were will with your"
GOT_STOP=$(bash "$CHECK" --stop-words 2>&1 | tr '\n' ' ' | sed 's/ $//')
assert_eq "--stop-words prints exactly the stated list" "$WANT_STOP" "$GOT_STOP"
LEFT=""
for w in $WANT_STOP; do
  t=$(tokens "$w")
  [[ -n "$t" ]] && LEFT="$LEFT $w"
done
assert_eq "every stop word yields no token" "" "$LEFT"
assert_eq "stop words dropped from a sentence" "table check icon" "$(tokens 'The table with a check icon for the desktop')"

echo "[match] a table item against a table design"
OUT=$(bash "$CHECK" "$FIX" spec-table.md facts-table.yaml reference-table.json 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_eq "first line is the decision" "relevance: match (3 of 4 design names share an item keyword; threshold 2)" "$(head -1 <<< "$OUT")"
assert_contains "names the item keywords (summary and components)" "item keywords: cell, check, comparison, icon, table" "$OUT"
assert_contains "names the design keywords" "design keywords: check, column, icon, item, table" "$OUT"
assert_contains "names the matching names" "matching names: check icon; table; table item" "$OUT"

echo "[low] a button item against a table design"
OUT=$(bash "$CHECK" "$FIX" spec-button.md facts-button.yaml reference-table.json 2>&1); ST=$?
assert_eq "exit 0 -- a low score is never a failure" 0 "$ST"
assert_eq "first line is the decision" "relevance: low (0 of 4 design names share an item keyword; threshold 2)" "$(head -1 <<< "$OUT")"
assert_contains "names the item keywords, components included" "item keywords: button, cta, hover, primary, state" "$OUT"
assert_contains "names the design keywords" "design keywords: check, column, icon, item, table" "$OUT"
assert_contains "no matching name" "matching names: none" "$OUT"
assert_not_contains "copy inside the design is not a design keyword" "button" "$(grep '^design keywords:' <<< "$OUT")"

echo "[threshold] exactly 2 matches, prefixes stripped"
OUT=$(bash "$CHECK" "$FIX" spec-pricing.md facts-pricing.yaml reference-card.json 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_eq "2 is a match" "relevance: match (2 of 3 design names share an item keyword; threshold 2)" "$(head -1 <<< "$OUT")"
assert_contains "Component/ and Mobile/ stripped from names" "matching names: card; pricing" "$OUT"
assert_contains "no prefix word among design keywords" "design keywords: card, image, pricing, wrapper" "$OUT"

echo "[threshold] exactly 1 match"
printf '# Card layout\n\nitem: DEMO-5 (Story)\n' > "$WORK/spec-card.md"
cp "$FIX/facts-pricing.yaml" "$FIX/reference-card.json" "$FIX/context-card.txt" "$WORK/"
OUT=$(bash "$CHECK" "$WORK" spec-card.md facts-pricing.yaml reference-card.json 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_eq "1 is low" "relevance: low (1 of 3 design names share an item keyword; threshold 2)" "$(head -1 <<< "$OUT")"
assert_contains "names the one match" "matching names: card" "$OUT"

echo "[paths] absolute paths are used as given"
OUT=$(bash "$CHECK" "$FIX" "$FIX/spec-table.md" "$FIX/facts-table.yaml" "$FIX/reference-table.json" 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "same decision" "relevance: match (3 of 4" "$OUT"

echo "[not run] image mode: no design context"
OUT=$(bash "$CHECK" "$FIX" spec-table.md facts-table.yaml reference-image.json 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_eq "reported as not run" "relevance: not run (the design reference has no design context)" "$OUT"

echo "[not run] the item has no design reference"
OUT=$(bash "$CHECK" "$FIX" spec-table.md facts-no-design.yaml reference-table.json 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_eq "reported as not run, even with a reference file present" "relevance: not run (the item has no design reference)" "$OUT"

echo "[not run] no design reference file"
OUT=$(bash "$CHECK" "$FIX" spec-table.md facts-table.yaml absent-reference.json 2>&1); ST=$?
assert_eq "exit 0" 0 "$ST"
assert_contains "reported as not run, naming the path" "relevance: not run (no design reference at " "$OUT"

echo "[usage]"
OUT=$(bash "$CHECK" 2>&1); ST=$?
assert_eq "no arguments: exit 2" 2 "$ST"
assert_contains "prints usage" "usage:" "$OUT"
OUT=$(bash "$CHECK" "$FIX" absent-spec.md facts-table.yaml reference-table.json 2>&1); ST=$?
assert_eq "missing spec: exit 2" 2 "$ST"
OUT=$(bash "$CHECK" "$FIX" spec-table.md absent-facts.yaml reference-table.json 2>&1); ST=$?
assert_eq "missing fact record: exit 2" 2 "$ST"
OUT=$(bash "$CHECK" "$FIX" spec-no-summary.md facts-table.yaml reference-table.json 2>&1); ST=$?
assert_eq "spec with no summary heading: exit 2" 2 "$ST"
assert_contains "names the missing summary" "summary" "$OUT"
OUT=$(bash "$CHECK" "$FIX" spec-table.md facts-table.yaml reference-missing-code.json 2>&1); ST=$?
assert_eq "design context names a missing file: exit 2" 2 "$ST"
assert_contains "names the missing file" "absent-context.txt" "$OUT"
printf 'not json' > "$WORK/broken.json"
OUT=$(bash "$CHECK" "$WORK" "$FIX/spec-table.md" "$FIX/facts-table.yaml" broken.json 2>&1); ST=$?
assert_eq "reference that is not JSON: exit 2" 2 "$ST"

echo ""
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
