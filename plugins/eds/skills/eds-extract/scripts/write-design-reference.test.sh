#!/usr/bin/env bash
# Tests for write-design-reference.py. Run with:
#   bash plugins/eds/skills/eds-extract/scripts/write-design-reference.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Inputs are built
# in a temporary directory per case. Each case runs the script from its own
# case directory, because the provider JSON names its code file relative to the
# project root.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/write-design-reference.py"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/write-design-reference.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# check <desc> <jq filter that must print true> <json file>
check() {
  local desc="$1" filter="$2" file="$3" got
  got="$(jq -r "$filter" "$file" 2>&1)"
  if [ "$got" = "true" ]; then ok "$desc"; else bad "$desc" "filter: $filter" "got: $got"; fi
}

URL='https://www.figma.com/design/abc123/Mock?node-id=1-185'
STYLES='Text/Link: #000000, Accent/Accent 2: #DFECC6.'

# case_dir <name> — a fresh case directory holding a provider image
case_dir() {
  local dir="$WORK/$1"
  mkdir -p "$dir/.ai/figma" "$dir/.ai/run-context"
  printf 'PNG-BYTES' > "$dir/.ai/figma/abc123-1-185.png"
  echo "$dir"
}

# run_design_tool <case-dir> — runs design_tool mode from inside the case dir
run_design_tool() {
  (cd "$1" && python3 "$WRITER" design_tool "$URL" \
    .ai/figma/abc123-1-185.json .ai/figma/abc123-1-185.png \
    .ai/run-context/design-reference.json .ai/run-context/design-reference.png \
    .ai/run-context/design-context.txt >"$1/stdout" 2>"$1/stderr")
}

echo "design_tool: provider JSON with a code block"
D="$(case_dir code)"
# Unfenced code, a trailing space, a tab, a non-ASCII character and no final
# newline: any rewriting on the way through changes at least one byte.
printf 'export default function Button() {\n  return (\n\t<a className="bg-[#dfecc6] px-[22px] py-[14px] rounded-[1000px]" data-node-id="1:185">Discover More \xe2\x80\x94 </a>\n  );\n}' \
  > "$D/.ai/figma/abc123-1-185.context.txt"
jq -n --arg styles "$STYLES" '{
  reference: "x", file_key: "abc123", node_id: "1-185", node_name: "Button",
  geometry: {x: 0, y: 0, width: 138, height: 48},
  variables: {"Accent/Accent 2": "#DFECC6"},
  design_context: {code_file: ".ai/figma/abc123-1-185.context.txt", styles: $styles}
}' > "$D/.ai/figma/abc123-1-185.json"
if run_design_tool "$D"; then ok "exits 0"; else bad "exits 0" "stderr: $(cat "$D/stderr")"; fi
OUT="$D/.ai/run-context/design-reference.json"
if [ -f "$OUT" ]; then
  check "design_context is an object" '.design_context | type == "object"' "$OUT"
  check "code_file names the run-context copy" \
    '.design_context.code_file == ".ai/run-context/design-context.txt"' "$OUT"
  got="$(jq -r '.design_context.styles' "$OUT")"
  if [ "$got" = "$STYLES" ]; then ok "styles carried verbatim"; else bad "styles carried verbatim" "got: $got"; fi
  check "variables still carried" '.variables == {"Accent/Accent 2": "#DFECC6"}' "$OUT"
  check "geometry still carried" '.geometry.width == 138' "$OUT"
  check "has_values stays true" '.has_values == true' "$OUT"
  check "no viewports key without viewports" 'has("viewports") | not' "$OUT"
  check "no screenshots key without screenshots" 'has("screenshots") | not' "$OUT"
else
  bad "design-reference.json written" "missing: $OUT"
fi
if cmp -s "$D/.ai/figma/abc123-1-185.context.txt" "$D/.ai/run-context/design-context.txt"; then
  ok "design-context.txt is byte-identical to the provider's code"
else
  bad "design-context.txt is byte-identical to the provider's code" \
    "diff: $(diff "$D/.ai/figma/abc123-1-185.context.txt" "$D/.ai/run-context/design-context.txt" 2>&1 | head -5)"
fi

echo "design_tool: provider JSON with design_context: null"
D="$(case_dir null)"
jq -n '{
  reference: "x", file_key: "abc123", node_id: "1-185", node_name: "Button",
  geometry: {x: 0, y: 0, width: 138, height: 48}, variables: {},
  design_context: null
}' > "$D/.ai/figma/abc123-1-185.json"
if run_design_tool "$D"; then ok "exits 0"; else bad "exits 0" "stderr: $(cat "$D/stderr")"; fi
OUT="$D/.ai/run-context/design-reference.json"
if [ -f "$OUT" ]; then
  check "design_context key present and null" 'has("design_context") and .design_context == null' "$OUT"
  check "variables still carried as {}" '.variables == {}' "$OUT"
  check "no viewports key without viewports" 'has("viewports") | not' "$OUT"
  check "no screenshots key without screenshots" 'has("screenshots") | not' "$OUT"
else
  bad "design-reference.json written" "missing: $OUT"
fi
if [ -e "$D/.ai/run-context/design-context.txt" ]; then
  bad "writes no design-context.txt" "found one"
else
  ok "writes no design-context.txt"
fi

echo "design_tool: provider JSON names a code file that does not exist"
D="$(case_dir missing)"
jq -n '{geometry: {width: 1}, variables: {},
  design_context: {code_file: ".ai/figma/absent.context.txt", styles: null}}' \
  > "$D/.ai/figma/abc123-1-185.json"
run_design_tool "$D"
status=$?
if [ "$status" -eq 2 ]; then ok "exits 2"; else bad "exits 2" "got: $status"; fi
if [ -e "$D/.ai/run-context/design-reference.json" ]; then
  bad "writes no design-reference.json" "found one"
else
  ok "writes no design-reference.json"
fi

# variant <case-dir> <node-id> [code] — a variant's image, and its code file when asked
variant() {
  printf 'PNG-%s' "$2" > "$1/.ai/figma/abc123-$2.png"
  if [ "${3:-}" = code ]; then printf 'code\tfor %s \xe2\x80\x94' "$2" > "$1/.ai/figma/abc123-$2.context.txt"; fi
}

# provider_with_viewports <case-dir> <viewports-json> — a provider JSON whose
# own design_context is the widest variant's
provider_with_viewports() {
  jq -n --arg styles "$STYLES" --argjson vp "$2" '{
    reference: "x", file_key: "abc123", node_id: "1-586", node_name: "Home",
    geometry: {x: 0, y: 0, width: 2711, height: 8996},
    variables: {"Accent/Accent 2": "#DFECC6"},
    design_context: {code_file: ".ai/figma/abc123-1-118.context.txt", styles: $styles},
    viewports: $vp
  }' > "$1/.ai/figma/abc123-1-185.json"
}

VP3='[
  {"name": "Tablet", "node_id": "1-274", "width": 800, "image": ".ai/figma/abc123-1-274.png", "context": null},
  {"name": "Desktop", "node_id": "1-118", "width": 1280, "image": ".ai/figma/abc123-1-118.png", "context": ".ai/figma/abc123-1-118.context.txt"},
  {"name": "Mobile", "node_id": "1-430", "width": 375, "image": ".ai/figma/abc123-1-430.png", "context": ".ai/figma/abc123-1-430.context.txt"}
]'

echo "design_tool: provider JSON with three viewport variants"
D="$(case_dir viewports)"
variant "$D" 1-118 code; variant "$D" 1-274; variant "$D" 1-430 code
provider_with_viewports "$D" "$VP3"
if run_design_tool "$D"; then ok "exits 0"; else bad "exits 0" "stderr: $(cat "$D/stderr")"; fi
OUT="$D/.ai/run-context/design-reference.json"
if [ -f "$OUT" ]; then
  check "viewports is a list of three" '.viewports | type == "array" and length == 3' "$OUT"
  check "each entry has exactly name, node_id, width, image, context" \
    'all(.viewports[]; (keys == ["context","image","name","node_id","width"]))' "$OUT"
  check "sorted widest first" '[.viewports[].width] == [1280, 800, 375]' "$OUT"
  check "names and node ids carried" \
    '[.viewports[] | .name + "=" + .node_id] == ["Desktop=1-118", "Tablet=1-274", "Mobile=1-430"]' "$OUT"
  check "each image is a run-context copy of its own" \
    '[.viewports[].image] == [".ai/run-context/design-reference-1-118.png", ".ai/run-context/design-reference-1-274.png", ".ai/run-context/design-reference-1-430.png"]' "$OUT"
  check "each context is a run-context copy of its own, or null" \
    '[.viewports[].context] == [".ai/run-context/design-context-1-118.txt", null, ".ai/run-context/design-context-1-430.txt"]' "$OUT"
  check "top-level fields unchanged" \
    '.geometry.width == 2711 and .variables == {"Accent/Accent 2": "#DFECC6"} and .design_context.code_file == ".ai/run-context/design-context.txt" and .reference_image == ".ai/run-context/design-reference.png"' "$OUT"
  for id in 1-118 1-274 1-430; do
    if cmp -s "$D/.ai/figma/abc123-$id.png" "$D/.ai/run-context/design-reference-$id.png"; then
      ok "image $id copied byte-for-byte"
    else
      bad "image $id copied byte-for-byte" "missing or different"
    fi
  done
  for id in 1-118 1-430; do
    if cmp -s "$D/.ai/figma/abc123-$id.context.txt" "$D/.ai/run-context/design-context-$id.txt"; then
      ok "context $id copied byte-for-byte"
    else
      bad "context $id copied byte-for-byte" "missing or different"
    fi
  done
  if [ -e "$D/.ai/run-context/design-context-1-274.txt" ]; then
    bad "no context file for a structure-only variant" "found one"
  else
    ok "no context file for a structure-only variant"
  fi
else
  bad "design-reference.json written" "missing: $OUT"
fi

echo "design_tool: an empty viewports list is a single width"
D="$(case_dir emptyvp)"
jq -n '{geometry: {width: 138}, variables: {}, design_context: null, viewports: []}' \
  > "$D/.ai/figma/abc123-1-185.json"
if run_design_tool "$D"; then ok "exits 0"; else bad "exits 0" "stderr: $(cat "$D/stderr")"; fi
OUT="$D/.ai/run-context/design-reference.json"
if [ -f "$OUT" ]; then
  check "no viewports key" 'has("viewports") | not' "$OUT"
else
  bad "design-reference.json written" "missing: $OUT"
fi

# refused <desc> <case-name> <viewports-json> — exit 2, and nothing written
refused() {
  local dir status
  dir="$(case_dir "$2")"
  variant "$dir" 1-118 code; variant "$dir" 1-274; variant "$dir" 1-430 code
  provider_with_viewports "$dir" "$3"
  echo "design_tool: $1"
  run_design_tool "$dir"
  status=$?
  if [ "$status" -eq 2 ]; then ok "exits 2"; else bad "exits 2" "got: $status"; fi
  if [ -e "$dir/.ai/run-context/design-reference.json" ] || [ -e "$dir/.ai/run-context/design-reference.png" ]; then
    bad "writes nothing" "found output"
  else
    ok "writes nothing"
  fi
}

refused "a variant whose image is missing" noimg \
  '[{"name": "Desktop", "node_id": "1-118", "width": 1280, "image": ".ai/figma/absent.png", "context": null},
    {"name": "Mobile", "node_id": "1-430", "width": 375, "image": ".ai/figma/abc123-1-430.png", "context": null}]'
refused "a variant whose context file is missing" noctx \
  '[{"name": "Desktop", "node_id": "1-118", "width": 1280, "image": ".ai/figma/abc123-1-118.png", "context": ".ai/figma/absent.txt"},
    {"name": "Mobile", "node_id": "1-430", "width": 375, "image": ".ai/figma/abc123-1-430.png", "context": null}]'
refused "a variant with no numeric width" nowidth \
  '[{"name": "Desktop", "node_id": "1-118", "width": "1280", "image": ".ai/figma/abc123-1-118.png", "context": null},
    {"name": "Mobile", "node_id": "1-430", "width": 375, "image": ".ai/figma/abc123-1-430.png", "context": null}]'
refused "a variant missing a key" nokey \
  '[{"name": "Desktop", "node_id": "1-118", "width": 1280, "image": ".ai/figma/abc123-1-118.png"},
    {"name": "Mobile", "node_id": "1-430", "width": 375, "image": ".ai/figma/abc123-1-430.png", "context": null}]'
refused "two variants with one node id" dupid \
  '[{"name": "Desktop", "node_id": "1-118", "width": 1280, "image": ".ai/figma/abc123-1-118.png", "context": null},
    {"name": "Mobile", "node_id": "1-118", "width": 375, "image": ".ai/figma/abc123-1-430.png", "context": null}]'
refused "a node id that is not a node id" badid \
  '[{"name": "Desktop", "node_id": "../x", "width": 1280, "image": ".ai/figma/abc123-1-118.png", "context": null},
    {"name": "Mobile", "node_id": "1-430", "width": 375, "image": ".ai/figma/abc123-1-430.png", "context": null}]'
refused "viewports that is not a list" notlist '{"Desktop": 1280}'

# shot <node-id> <w> <h> <ow> <oh> <downscaled> — one provider screenshot size entry
shot() {
  printf '{"node_id": "%s", "width": %s, "height": %s, "original_width": %s, "original_height": %s, "downscaled": %s}' "$@"
}

echo "design_tool: a single node's screenshot size is carried against its run-context image"
D="$(case_dir shotsingle)"
jq -n --argjson shots "[$(shot 1-185 138 48 138 48 false)]" '{
  reference: "x", file_key: "abc123", node_id: "1-185", node_name: "Button",
  geometry: {x: 0, y: 0, width: 138, height: 48}, variables: {},
  design_context: null, screenshots: $shots
}' > "$D/.ai/figma/abc123-1-185.json"
if run_design_tool "$D"; then ok "exits 0"; else bad "exits 0" "stderr: $(cat "$D/stderr")"; fi
OUT="$D/.ai/run-context/design-reference.json"
if [ -f "$OUT" ]; then
  check "one entry, keyed by the run-context image" \
    '.screenshots == [{"image": ".ai/run-context/design-reference.png", "width": 138, "height": 48, "original_width": 138, "original_height": 48, "downscaled": false}]' "$OUT"
else
  bad "design-reference.json written" "missing: $OUT"
fi

echo "design_tool: each variant's screenshot size is carried against its own image"
D="$(case_dir shotvariants)"
variant "$D" 1-118 code; variant "$D" 1-274; variant "$D" 1-430 code
provider_with_viewports "$D" "$VP3"
jq --argjson shots "[$(shot 1-430 44 1024 375 8832.46875 true), $(shot 1-118 1280 7389 1280 7388.66748046875 false), $(shot 1-274 800 8825 800 8824.921875 false)]" \
  '. + {screenshots: $shots}' "$D/.ai/figma/abc123-1-185.json" > "$D/p.json" && mv "$D/p.json" "$D/.ai/figma/abc123-1-185.json"
if run_design_tool "$D"; then ok "exits 0"; else bad "exits 0" "stderr: $(cat "$D/stderr")"; fi
OUT="$D/.ai/run-context/design-reference.json"
if [ -f "$OUT" ]; then
  check "three entries, widest variant first" \
    '[.screenshots[].image] == [".ai/run-context/design-reference-1-118.png", ".ai/run-context/design-reference-1-274.png", ".ai/run-context/design-reference-1-430.png"]' "$OUT"
  check "downscaled carried" '[.screenshots[].downscaled] == [false, false, true]' "$OUT"
  check "sizes carried" '.screenshots[2].width == 44 and .screenshots[2].original_width == 375' "$OUT"
  check "viewport entries keep exactly their five keys" \
    'all(.viewports[]; (keys == ["context","image","name","node_id","width"]))' "$OUT"
else
  bad "design-reference.json written" "missing: $OUT"
fi

# refused_shots <desc> <case-name> <screenshots-json> — exit 2, and nothing written
refused_shots() {
  local dir status
  dir="$(case_dir "$2")"
  jq -n --argjson shots "$3" '{
    reference: "x", file_key: "abc123", node_id: "1-185", node_name: "Button",
    geometry: {x: 0, y: 0, width: 138, height: 48}, variables: {},
    design_context: null, screenshots: $shots
  }' > "$dir/.ai/figma/abc123-1-185.json"
  echo "design_tool: $1"
  run_design_tool "$dir"
  status=$?
  if [ "$status" -eq 2 ]; then ok "exits 2"; else bad "exits 2" "got: $status"; fi
  if [ -e "$dir/.ai/run-context/design-reference.json" ]; then bad "writes nothing" "found output"; else ok "writes nothing"; fi
}

refused_shots "a screenshot size for a node that has no image" shotunknown "[$(shot 9-9 10 10 10 10 false)]"
refused_shots "downscaled that contradicts the sizes" shotlie "[$(shot 1-185 69 24 138 48 false)]"
refused_shots "a screenshot size that is not a number" shotnan '[{"node_id": "1-185", "width": "138", "height": 48, "original_width": 138, "original_height": 48, "downscaled": false}]'
refused_shots "a screenshot entry missing a key" shotkey '[{"node_id": "1-185", "width": 138, "height": 48, "original_width": 138, "downscaled": false}]'
refused_shots "two sizes for one node" shotdup "[$(shot 1-185 138 48 138 48 false), $(shot 1-185 138 48 138 48 false)]"
refused_shots "screenshots that is not a list" shotnotlist '{"1-185": 138}'

echo "image mode"
D="$(case_dir image)"
(cd "$D" && python3 "$WRITER" image design-reference.png image/png \
  .ai/figma/abc123-1-185.png .ai/run-context/design-reference.json >"$D/stdout" 2>"$D/stderr")
status=$?
if [ "$status" -eq 0 ]; then ok "exits 0"; else bad "exits 0" "stderr: $(cat "$D/stderr")"; fi
OUT="$D/.ai/run-context/design-reference.json"
if [ -f "$OUT" ]; then
  check "design_context key present and null" 'has("design_context") and .design_context == null' "$OUT"
  check "variables null, has_values false" '.variables == null and .has_values == false' "$OUT"
  check "no viewports key" 'has("viewports") | not' "$OUT"
else
  bad "design-reference.json written" "missing: $OUT"
fi
if [ -e "$D/.ai/run-context/design-context.txt" ]; then
  bad "writes no design-context.txt" "found one"
else
  ok "writes no design-context.txt"
fi

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
