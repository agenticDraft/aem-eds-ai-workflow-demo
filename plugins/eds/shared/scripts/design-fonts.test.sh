#!/usr/bin/env bash
# Tests for design-fonts.py. Run with:
#   bash plugins/eds/shared/scripts/design-fonts.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Each case builds
# a design-reference.json, its reference code and a project's CSS in a
# temporary directory and runs the script from there, because code_file paths
# are relative to the project root.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FONTS="$SCRIPT_DIR/design-fonts.py"
REPO="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/design-fonts.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# case_dir <name> <code> [variables-json] — a case directory whose
# design-reference.json points design_context.code_file at a file holding <code>
case_dir() {
  local dir="$WORK/$1" vars="${3:-}"
  [[ -n "$vars" ]] || vars='{}'
  mkdir -p "$dir/.ai/run-context"
  printf '%s' "$2" > "$dir/.ai/run-context/design-context.txt"
  jq -n --argjson vars "$vars" '{source_kind: "design_tool", has_values: true, variables: $vars,
    geometry: {width: 1}, design_context: {code_file: ".ai/run-context/design-context.txt", styles: null}}' \
    > "$dir/.ai/run-context/design-reference.json"
  echo "$dir"
}

# css <case-dir> <relative-path> <content> — writes a project CSS file
css() {
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" > "$1/$2"
}

# run_fonts <case-dir> — runs the script from inside the case dir; sets STATUS
run_fonts() {
  (cd "$1" && python3 "$FONTS" .ai/run-context/design-reference.json . >"$1/stdout" 2>"$1/stderr")
  STATUS=$?
}

# out_is <desc> <case-dir> <expected-stdout>
out_is() {
  local got
  got="$(cat "$2/stdout")"
  if [[ "$got" == "$3" ]]; then ok "$1"; else bad "$1" "want: $(printf '%q' "$3")" "got:  $(printf '%q' "$got")"; fi
}

status_is() {
  if [[ "$STATUS" == "$2" ]]; then ok "$1"; else bad "$1" "want exit $2, got $STATUS" "stderr: $(cat "$3/stderr")"; fi
}

echo "a declared family names nothing"
D="$(case_dir declared '<p className="font-['"'"'DM_Sans:Medium'"'"'] text-[12px]" data-node-id="1:1">A</p>')"
css "$D" styles/fonts.css '@font-face { font-family: dm-sans; src: url("../fonts/dm-sans.woff2"); }'
run_fonts "$D"
out_is "DM_Sans in the design, dm-sans declared → nothing" "$D" ""
status_is "exit 0 when every family is declared" 0 "$D"

D="$(case_dir quoted '<p className="font-['"'"'DM_Sans:Medium'"'"']" data-node-id="1:1">A</p>')"
css "$D" blocks/cards/cards.css "@font-face {
  font-family: 'DM Sans';
  src: url('../../fonts/dm-sans.woff2');
}"
run_fonts "$D"
out_is "quoted 'DM Sans' declared in a block's CSS → nothing" "$D" ""

echo "a missing family is named, once"
D="$(case_dir missing '<p className="font-['"'"'Roboto_Mono:Regular'"'"']" data-node-id="1:1">A</p>
<p className="font-['"'"'Roboto_Mono:Regular'"'"']" data-node-id="1:2">B</p>
<p className="font-['"'"'Roboto_Mono:Bold'"'"']" data-node-id="1:3">C</p>' \
  '{"Captions": "Font(family: \"Roboto Mono\", style: Regular, size: 12, weight: 400)"}')"
css "$D" styles/fonts.css '@font-face { font-family: roboto; src: url("../fonts/roboto.woff2"); }'
run_fonts "$D"
out_is "Roboto Mono in three classes and a variable → named once" "$D" "Roboto Mono"
status_is "exit 1 when a family is missing" 1 "$D"

D="$(case_dir used-not-declared '<p className="font-['"'"'Roboto_Mono:Regular'"'"']" data-node-id="1:1">A</p>')"
css "$D" styles/styles.css ':root { --body-font-family: "Roboto Mono", monospace; }
body { font-family: var(--body-font-family); }'
run_fonts "$D"
out_is "a family only used in font-family, never in @font-face → named" "$D" "Roboto Mono"

D="$(case_dir commented '<p className="font-['"'"'Roboto_Mono:Regular'"'"']" data-node-id="1:1">A</p>')"
css "$D" styles/fonts.css '/* @font-face { font-family: roboto-mono; } */'
run_fonts "$D"
out_is "a commented-out @font-face declares nothing" "$D" "Roboto Mono"

D="$(case_dir outside '<p className="font-['"'"'Roboto_Mono:Regular'"'"']" data-node-id="1:1">A</p>')"
css "$D" drafts/x.css '@font-face { font-family: roboto-mono; }'
css "$D" node_modules/pkg/pkg.css '@font-face { font-family: roboto-mono; }'
run_fonts "$D"
out_is "@font-face outside styles/ and blocks/ does not count" "$D" "Roboto Mono"

echo "generic families are never named"
D="$(case_dir generic '<p className="font-[monospace] [font-family:DM_Sans,sans-serif]" data-node-id="1:1">A</p>
<p className="font-['"'"'sans-serif'"'"'] font-[700]" data-node-id="1:2">B</p>' \
  '{"Mono": "Font(family: \"monospace\", style: Regular, size: 12)", "Ui": "Font(family: \"system-ui\", size: 12)"}')"
run_fonts "$D"
out_is "sans-serif, monospace, system-ui never named; DM Sans is; font-[700] is a weight" "$D" "DM Sans"

echo "families in design_context.styles and viewport variants"
D="$(case_dir styles-and-variants '<p data-node-id="1:1">A</p>')"
printf '%s' '<p className="font-['"'"'Inter:Regular'"'"']" data-node-id="2:1">A</p>' > "$D/.ai/run-context/design-context-2-1.txt"
jq '.design_context.styles = "Body: Font(family: \"Rethink Sans\", style: Medium, size: 16)"
  | .viewports = [{name: "Mobile", node_id: "2:1", width: 390, image: "x.png", context: ".ai/run-context/design-context-2-1.txt"},
                  {name: "Tablet", node_id: "2:2", width: 768, image: "y.png", context: null}]' \
  "$D/.ai/run-context/design-reference.json" > "$D/ref.json" && mv "$D/ref.json" "$D/.ai/run-context/design-reference.json"
run_fonts "$D"
out_is "styles string, then a variant's code; a null variant context is skipped" "$D" "Rethink Sans
Inter"

echo "no design code"
D="$WORK/image"
mkdir -p "$D/.ai/run-context"
jq -n '{source_kind: "image", has_values: false, variables: null, design_context: null}' \
  > "$D/.ai/run-context/design-reference.json"
run_fonts "$D"
out_is "an image reference names nothing" "$D" ""
status_is "exit 0 for an image reference" 0 "$D"

echo "EDS-18"
# The four font classes and the Captions variable exactly as the EDS-18 run's
# .ai/run-context held them (design-context.txt lines 11, 19, 66, 121;
# design-reference.json line 124), against this repository's own styles/.
D="$(case_dir eds-18 '<div className="[word-break:break-word] flex flex-col font-['"'"'DM_Sans:Medium'"'"'] font-medium justify-center leading-[0] relative shrink-0 text-[25.714px] text-black tracking-[-2.0571px] whitespace-nowrap" data-node-id="1:198">
<p className="[word-break:break-word] font-['"'"'Roboto_Mono:Regular'"'"'] font-normal leading-[1.4] relative shrink-0 text-[12px] text-black text-center tracking-[-0.12px] whitespace-nowrap" data-node-id="I1:199;1:564">x</p>
<div className="[word-break:break-word] flex flex-col font-['"'"'Rethink_Sans:Medium'"'"'] font-medium justify-center leading-[0] relative shrink-0 text-[#6f6f6f] text-[22.857px] tracking-[-1.8286px] whitespace-nowrap" data-node-id="1:207">
<div className="[word-break:break-word] flex flex-col font-['"'"'Reddit_Mono:Medium'"'"'] font-medium justify-center leading-[0] relative shrink-0 text-[#6f6f6f] text-[21.654px] tracking-[-1.7323px] whitespace-nowrap" data-node-id="1:216">' \
  '{"Captions": "Font(family: \"Roboto Mono\", style: Regular, size: 12, weight: 400, lineHeight: 1.399999976158142, letterSpacing: -1)"}')"
mkdir -p "$D/styles"
cp "$REPO/styles/fonts.css" "$REPO/styles/styles.css" "$D/styles/"
run_fonts "$D"
out_is "names DM Sans, Roboto Mono, Rethink Sans, Reddit Mono — in first-seen order" "$D" "Roboto Mono
DM Sans
Rethink Sans
Reddit Mono"

echo "usage"
(cd "$WORK" && python3 "$FONTS" >/dev/null 2>&1); STATUS=$?
status_is "no argument → exit 2" 2 "$WORK"
(cd "$WORK" && python3 "$FONTS" nope.json . >/dev/null 2>&1); STATUS=$?
status_is "missing design reference → exit 2" 2 "$WORK"
D="$(case_dir gone-code '')"
rm "$D/.ai/run-context/design-context.txt"
run_fonts "$D"
status_is "a code_file that does not exist → exit 2" 2 "$D"

echo
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
