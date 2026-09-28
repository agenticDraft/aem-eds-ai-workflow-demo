#!/usr/bin/env bash
# Tests for pair-viewports.py. Run with:
#   bash plugins/eds/shared/scripts/pair-viewports.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Design
# references and stylesheets are written per case into a temporary directory.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAIR="$SCRIPT_DIR/pair-viewports.py"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pair-viewports.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
TAB="$(printf '\t')"

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# run <args...> — sets STATUS, OUT, ERR
run() {
  python3 "$PAIR" "$@" >"$WORK/stdout" 2>"$WORK/stderr"
  STATUS=$?
  OUT="$(cat "$WORK/stdout")"
  ERR="$(cat "$WORK/stderr")"
}

exits() {
  if [ "$STATUS" -eq "$1" ]; then ok "exits $1"; else bad "exits $1" "got: $STATUS" "stdout: $OUT" "stderr: $ERR"; fi
}

same() {
  if [ "$OUT" = "$2" ]; then ok "$1"; else bad "$1" "expected:" "$2" "got:" "$OUT"; fi
}

no_output() {
  if [ -z "$OUT" ]; then ok "prints nothing on stdout"; else bad "prints nothing on stdout" "$OUT"; fi
}

# reference <name> <viewports-json|none> [screenshots-json] — a design reference file
reference() {
  local file="$WORK/$1.json"
  if [ "$2" = none ]; then
    jq -n --argjson shots "${3:-null}" '{
      source_kind: "design_tool", has_values: true, variables: {},
      geometry: {width: 1280, height: 700}, design_context: null,
      reference_image: ".ai/run-context/design-reference.png"
    } + (if $shots == null then {} else {screenshots: $shots} end)' > "$file"
  else
    jq -n --argjson vp "$2" --argjson shots "${3:-null}" '{
      source_kind: "design_tool", has_values: true, variables: {},
      geometry: {width: 2711, height: 8996}, design_context: null,
      reference_image: ".ai/run-context/design-reference.png",
      viewports: $vp
    } + (if $shots == null then {} else {screenshots: $shots} end)' > "$file"
  fi
  echo "$file"
}

# vp <name> <node-id> <width> — one viewport entry, image named after the node
vp() {
  printf '{"name": "%s", "node_id": "%s", "width": %s, "image": ".ai/run-context/design-reference-%s.png", "context": null}' \
    "$1" "$2" "$3" "$2"
}

ZOKI="[$(vp Desktop 1-118 1280), $(vp Tablet 1-274 800), $(vp Mobile 1-430 375)]"

echo "breakpoints: one rule in the stylesheet"
cat > "$WORK/one.css" <<'EOF'
body { margin: 0; }
@media (width >= 900px) {
  body { font-size: 20px; }
}
header { color: red; }
@media (width >= 900px) {
  header { color: blue; }
}
EOF
run breakpoints "$WORK/one.css"
exits 0
same "the one adopted breakpoint, once" "900"

echo "breakpoints: several rules, printed ascending"
cat > "$WORK/two.css" <<'EOF'
@media (width >= 1200px) { a { color: red; } }
@media (width>=600px) { a { color: blue; } }
@media (prefers-reduced-motion: reduce) { a { transition: none; } }
EOF
run breakpoints "$WORK/two.css"
exits 0
same "comma-separated, ascending, spaces around >= optional" "600,1200"

echo "breakpoints: a stylesheet with none"
printf 'a { color: red; }\n' > "$WORK/none.css"
run breakpoints "$WORK/none.css"
exits 0
same "a dash when there is no breakpoint" "-"

echo "breakpoints: a missing stylesheet"
run breakpoints "$WORK/absent.css"
exits 2
no_output

echo "pair: Desktop 1280, Tablet 800, Mobile 375 under the 900 breakpoint"
REF="$(reference zoki "$ZOKI")"
run pair "$REF" 375,768,1440 900
exits 0
same "375 Mobile, 768 Tablet, 1440 Desktop, each image used once" \
"375${TAB}variant${TAB}1:430${TAB}375${TAB}.ai/run-context/design-reference-1-430.png${TAB}unknown${TAB}-${TAB}Mobile
768${TAB}variant${TAB}1:274${TAB}800${TAB}.ai/run-context/design-reference-1-274.png${TAB}unknown${TAB}-${TAB}Tablet
1440${TAB}variant${TAB}1:118${TAB}1280${TAB}.ai/run-context/design-reference-1-118.png${TAB}unknown${TAB}-${TAB}Desktop"

echo "pair: the variants are listed in any order"
REF="$(reference zoki-shuffled "[$(vp Mobile 1-430 375), $(vp Desktop 1-118 1280), $(vp Tablet 1-274 800)]")"
run pair "$REF" 375,768,1440 900
exits 0
if [ "$(printf '%s\n' "$OUT" | cut -f1,3 | tr '\t\n' ' |')" = "375 1:430|768 1:274|1440 1:118|" ]; then
  ok "same pairing"
else
  bad "same pairing" "$OUT"
fi

echo "pair: a single-width reference pairs every capture with its one image, and says so"
REF="$(reference single none)"
run pair "$REF" 375,768,1440 900
exits 0
same "status single; each row names the other widths the image is also compared at" \
"375${TAB}single${TAB}-${TAB}-${TAB}.ai/run-context/design-reference.png${TAB}unknown${TAB}768,1440${TAB}-
768${TAB}single${TAB}-${TAB}-${TAB}.ai/run-context/design-reference.png${TAB}unknown${TAB}375,1440${TAB}-
1440${TAB}single${TAB}-${TAB}-${TAB}.ai/run-context/design-reference.png${TAB}unknown${TAB}375,768${TAB}-"

echo "pair: an empty viewports list is a single width"
REF="$(reference emptyvp '[]')"
run pair "$REF" 1440 900
exits 0
same "status single" "1440${TAB}single${TAB}-${TAB}-${TAB}.ai/run-context/design-reference.png${TAB}unknown${TAB}-${TAB}-"

echo "pair: a capture with no variant in its interval"
REF="$(reference wide "[$(vp Desktop 5-1 1440), $(vp Wide 5-2 1920)]")"
run pair "$REF" 375,768,1440 900
exits 0
same "375 and 768 have none; 1440 takes the nearest desktop variant" \
"375${TAB}none${TAB}-${TAB}-${TAB}-${TAB}-${TAB}-${TAB}-
768${TAB}none${TAB}-${TAB}-${TAB}-${TAB}-${TAB}-${TAB}-
1440${TAB}variant${TAB}5:1${TAB}1440${TAB}.ai/run-context/design-reference-5-1.png${TAB}unknown${TAB}-${TAB}Desktop"

echo "pair: two variants in one interval — the nearest in width"
REF="$(reference nearest "[$(vp Desktop 6-1 1280), $(vp Small 6-2 600), $(vp Mobile 6-3 375)]")"
run pair "$REF" 375,768,1440 900
exits 0
if [ "$(printf '%s\n' "$OUT" | cut -f1,3,8 | tr '\t\n' ' |')" = "375 6:3 Mobile|768 6:2 Small|1440 6:1 Desktop|" ]; then
  ok "768 takes Small (600), not Mobile (375)"
else
  bad "768 takes Small (600), not Mobile (375)" "$OUT"
fi

echo "pair: two variants equally near — the wider"
REF="$(reference tie "[$(vp A 7-1 700), $(vp B 7-2 836)]")"
run pair "$REF" 768 900
exits 0
if [ "$(printf '%s\n' "$OUT" | cut -f3,8)" = "7:2${TAB}B" ]; then
  ok "768 is 68 from both; 836 wins"
else
  bad "768 is 68 from both; 836 wins" "$OUT"
fi

echo "pair: one variant image paired with two captures names the other width"
REF="$(reference reuse "[$(vp Desktop 8-1 1440), $(vp Mobile 8-2 375)]")"
run pair "$REF" 375,768,1440 900
exits 0
same "375 and 768 both use Mobile, each naming the other" \
"375${TAB}variant${TAB}8:2${TAB}375${TAB}.ai/run-context/design-reference-8-2.png${TAB}unknown${TAB}768${TAB}Mobile
768${TAB}variant${TAB}8:2${TAB}375${TAB}.ai/run-context/design-reference-8-2.png${TAB}unknown${TAB}375${TAB}Mobile
1440${TAB}variant${TAB}8:1${TAB}1440${TAB}.ai/run-context/design-reference-8-1.png${TAB}unknown${TAB}-${TAB}Desktop"

echo "pair: several breakpoints make several intervals"
REF="$(reference multi "[$(vp Desktop 9-1 1280), $(vp Tablet 9-2 800), $(vp Mobile 9-3 375)]")"
run pair "$REF" 375,768,1440 600,1200
exits 0
if [ "$(printf '%s\n' "$OUT" | cut -f1,3 | tr '\t\n' ' |')" = "375 9:3|768 9:2|1440 9:1|" ]; then
  ok "<600, 600-1199, >=1200"
else
  bad "<600, 600-1199, >=1200" "$OUT"
fi

echo "pair: no breakpoints is one interval"
run pair "$REF" 768 -
exits 0
if [ "$(printf '%s\n' "$OUT" | cut -f3)" = "9:2" ]; then ok "nearest overall"; else bad "nearest overall" "$OUT"; fi

echo "pair: a width exactly on a breakpoint belongs to the interval above it"
REF="$(reference edge "[$(vp Desktop 10-1 900), $(vp Mobile 10-2 899)]")"
run pair "$REF" 900,899 900
exits 0
if [ "$(printf '%s\n' "$OUT" | cut -f1,3 | tr '\t\n' ' |')" = "900 10:1|899 10:2|" ]; then
  ok "900 with 900, 899 with 899"
else
  bad "900 with 900, 899 with 899" "$OUT"
fi

echo "pair: resolution comes from the recorded screenshot sizes"
SHOTS='[
  {"image": ".ai/run-context/design-reference-1-118.png", "width": 1280, "height": 7389, "original_width": 1280, "original_height": 7388.66748046875, "downscaled": false},
  {"image": ".ai/run-context/design-reference-1-274.png", "width": 93, "height": 1024, "original_width": 800, "original_height": 8824.921875, "downscaled": true}
]'
REF="$(reference sized "$ZOKI" "$SHOTS")"
run pair "$REF" 375,768,1440 900
exits 0
if [ "$(printf '%s\n' "$OUT" | cut -f1,6 | tr '\t\n' ' |')" = "375 unknown|768 reduced|1440 full|" ]; then
  ok "full, reduced, and unknown where nothing was recorded"
else
  bad "full, reduced, and unknown where nothing was recorded" "$OUT"
fi

echo "pair: a single-width reference with a recorded size"
REF="$(reference single-sized none '[{"image": ".ai/run-context/design-reference.png", "width": 178, "height": 1024, "original_width": 1280, "original_height": 7389, "downscaled": true}]')"
run pair "$REF" 1440 900
exits 0
if [ "$(printf '%s\n' "$OUT" | cut -f6)" = "reduced" ]; then ok "reduced"; else bad "reduced" "$OUT"; fi

echo "targets: one per variant, widest first, at the variant's own width"
REF="$(reference targets "[$(vp Mobile 1-430 375), $(vp Desktop 1-118 1280), $(vp Tablet 1-274 800)]" "$SHOTS")"
run targets "$REF" 1440
exits 0
same "capture width, node, variant width, image, resolution, name" \
"1280${TAB}1:118${TAB}1280${TAB}.ai/run-context/design-reference-1-118.png${TAB}full${TAB}Desktop
800${TAB}1:274${TAB}800${TAB}.ai/run-context/design-reference-1-274.png${TAB}reduced${TAB}Tablet
375${TAB}1:430${TAB}375${TAB}.ai/run-context/design-reference-1-430.png${TAB}unknown${TAB}Mobile"

echo "targets: a fractional variant width is captured at the nearest whole pixel"
REF="$(reference frac "[$(vp Desktop 11-1 1440), $(vp Tablet 11-2 767.5)]")"
run targets "$REF" 1440
exits 0
if [ "$(printf '%s\n' "$OUT" | cut -f1,3 | tr '\t\n' ' |')" = "1440 1440|768 767.5|" ]; then
  ok "767.5 captured at 768, variant width kept"
else
  bad "767.5 captured at 768, variant width kept" "$OUT"
fi

echo "targets: a single-width reference is one target at the given width"
REF="$(reference single2 none)"
run targets "$REF" 1440
exits 0
same "the given width and the one image" "1440${TAB}-${TAB}-${TAB}.ai/run-context/design-reference.png${TAB}unknown${TAB}-"

echo "refusals"
REF="$(reference ok "$ZOKI")"
run pair "$REF" 375,abc 900
exits 2
no_output
run pair "$REF" 375 900,x
exits 2
run pair "$REF" 0 900
exits 2
run targets "$REF" 14.5
exits 2
printf 'not json' > "$WORK/bad.json"
run pair "$WORK/bad.json" 375 900
exits 2
run pair "$WORK/absent.json" 375 900
exits 2
REF="$(reference noimage none)"
jq 'del(.reference_image)' "$REF" > "$WORK/noimage2.json"
run pair "$WORK/noimage2.json" 375 900
exits 2
run frobnicate "$REF"
exits 2
run pair "$REF" 375
exits 2

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
