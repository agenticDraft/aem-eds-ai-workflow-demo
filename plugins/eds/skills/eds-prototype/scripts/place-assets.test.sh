#!/usr/bin/env bash
# Tests for place-assets.py. Run with:
#   bash plugins/eds/skills/eds-prototype/scripts/place-assets.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Each case builds
# a project root in a temporary directory — a design-reference.json whose
# `assets` list names local files, and the reference code carrying each
# node's layer name — and runs the script from there.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLACE="$SCRIPT_DIR/place-assets.py"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/place-assets.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
TAB="$(printf '\t')"

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

SVG_A='<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><path d="M1 1"/></svg>'
SVG_B='<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><path d="M2 2"/></svg>'

CODE='export default function Frame() {
  return (
    <div data-node-id="1:139" data-name="Benefits section">
      <div data-node-id="1:147" data-name="Cable icon"><img src={imgCable} /></div>
      <div data-node-id="1:152" data-name="Cable  Icon!"><img src={imgOther} /></div>
      <div data-node-id="1:160" data-name="Search"><img src={imgSearch} /></div>
      <div data-node-id="1:170"><img src={imgNameless} /></div>
      <div data-node-id="1:166" data-name="Hero Image"><img src={imgHero} /></div>
      <div data-node-id="1:180" data-name="Twin icon"><img src={imgTwin} /></div>
    </div>
  );
}'

sha16() { shasum -a 256 "$1" | cut -c1-16; }

# project <name> — a project root with five assets; echoes its path
project() {
  local dir="$WORK/$1"
  mkdir -p "$dir/.ai/run-context" "$dir/.ai/figma/assets" "$dir/icons" "$dir/drafts"
  printf '%s' "$CODE" > "$dir/.ai/run-context/design-context.txt"
  printf '%s\n' "$SVG_A" > "$dir/.ai/figma/assets/aaaa.svg"
  printf '%s\n' "$SVG_B" > "$dir/.ai/figma/assets/bbbb.svg"
  printf '%s\n' "$SVG_A" > "$dir/.ai/figma/assets/twin.svg"
  printf '\377\330\377\340\000\020JFIF\000hero-photo' > "$dir/.ai/figma/assets/cccc.jpg"
  printf '<svg xmlns="http://www.w3.org/2000/svg"><circle r="1"/></svg>\n' > "$dir/.ai/figma/assets/dddd.svg"
  jq -n '{source_kind: "design_tool", has_values: true, viewports: null,
    design_context: {code_file: ".ai/run-context/design-context.txt", styles: null},
    assets: [
      {node_id: "1:147", file: ".ai/figma/assets/aaaa.svg", mime: "image/svg+xml"},
      {node_id: "1:152", file: ".ai/figma/assets/bbbb.svg", mime: "image/svg+xml"},
      {node_id: "1:160", file: ".ai/figma/assets/bbbb.svg", mime: "image/svg+xml"},
      {node_id: "1:170", file: ".ai/figma/assets/dddd.svg", mime: "image/svg+xml"},
      {node_id: "1:166", file: ".ai/figma/assets/cccc.jpg", mime: "image/jpeg"},
      {node_id: "1:180", file: ".ai/figma/assets/twin.svg", mime: "image/svg+xml"},
      {node_id: null, file: ".ai/figma/assets/dddd.svg", mime: "image/svg+xml"}
    ]}' > "$dir/.ai/run-context/design-reference.json"
  echo "$dir"
}

# run <dir> <args...> — runs from the project root; sets STATUS
run() {
  local dir="$1"; shift
  (cd "$dir" && python3 "$PLACE" .ai/run-context/design-reference.json "$@" >"$WORK/stdout" 2>"$WORK/stderr")
  STATUS=$?
}

status_is() {
  if [ "$STATUS" -eq "$2" ]; then ok "$1"; else bad "$1" "want exit $2, got $STATUS" "stderr: $(cat "$WORK/stderr")"; fi
}

has_line() {
  if grep -qxF -- "$2" "$WORK/stdout"; then ok "$1"; else bad "$1" "want: $2" "got: $(cat "$WORK/stdout")"; fi
}

stdout_empty() {
  if [ -s "$WORK/stdout" ]; then bad "$1" "stdout: $(cat "$WORK/stdout")"; else ok "$1"; fi
}

same_bytes() {
  if cmp -s "$2" "$3"; then ok "$1"; else bad "$1" "$2 differs from $3"; fi
}

absent() {
  if [ -e "$2" ]; then bad "$1" "exists: $2"; else ok "$1"; fi
}

no_url() {
  if grep -q '://' "$WORK/stdout" "$WORK/stderr"; then bad "$1" "$(cat "$WORK/stdout" "$WORK/stderr")"; else ok "$1"; fi
}

echo "a new icon is placed under icons/ by its slugified layer name"
D="$(project new-icon)"
run "$D" ITEM-1 1:147
status_is "exits 0" 0
has_line "placed row" "placed${TAB}1:147${TAB}image/svg+xml${TAB}icons/cable-icon.svg${TAB}<span class=\"icon icon-cable-icon\"></span>"
same_bytes "icon bytes copied" "$D/icons/cable-icon.svg" "$D/.ai/figma/assets/aaaa.svg"
no_url "no URL printed"

echo "an icon already present with identical bytes is reused, not rewritten"
D="$(project same-icon)"
cp "$D/.ai/figma/assets/aaaa.svg" "$D/icons/cable-icon.svg"
touch -t 202001010000 "$D/icons/cable-icon.svg"
before="$(ls -l "$D/icons/cable-icon.svg")"
run "$D" ITEM-1 1:147
status_is "exits 0" 0
has_line "reused row" "reused${TAB}1:147${TAB}image/svg+xml${TAB}icons/cable-icon.svg${TAB}<span class=\"icon icon-cable-icon\"></span>"
if [ "$(ls -l "$D/icons/cable-icon.svg")" = "$before" ]; then ok "file untouched"; else bad "file untouched"; fi

echo "an icon present with different bytes is a collision; nothing is written"
D="$(project diff-icon)"
printf '%s\n' "$SVG_B" > "$D/icons/cable-icon.svg"
run "$D" ITEM-1 1:147 1:166
status_is "exits 4" 4
has_line "collision row names both files" "collision${TAB}1:147${TAB}image/svg+xml${TAB}icons/cable-icon.svg${TAB}.ai/figma/assets/aaaa.svg${TAB}icons/cable-icon.svg"
same_bytes "existing icon not overwritten" "$D/icons/cable-icon.svg" "$D/.ai/figma/assets/bbbb.svg"
absent "no other asset written either" "$D/drafts/ITEM-1-$(sha16 "$D/.ai/figma/assets/cccc.jpg").jpg"

echo "two layers slugifying to one name with different bytes collide; nothing is written"
D="$(project twin-slug)"
run "$D" ITEM-1 1:147 1:152
status_is "exits 4" 4
has_line "second layer collides with the first's file" "collision${TAB}1:152${TAB}image/svg+xml${TAB}icons/cable-icon.svg${TAB}.ai/figma/assets/bbbb.svg${TAB}.ai/figma/assets/aaaa.svg"
has_line "first layer's row still listed" "placed${TAB}1:147${TAB}image/svg+xml${TAB}icons/cable-icon.svg${TAB}<span class=\"icon icon-cable-icon\"></span>"
absent "nothing written" "$D/icons/cable-icon.svg"

echo "two layers slugifying to one name with identical bytes share one file"
D="$(project twin-same)"
jq '.assets[5].node_id = "1:180" | .assets += [{node_id: "1:152", file: ".ai/figma/assets/twin.svg", mime: "image/svg+xml"}] | .assets |= map(select(.file != ".ai/figma/assets/bbbb.svg" or .node_id != "1:152"))' \
  "$D/.ai/run-context/design-reference.json" > "$D/r.json" && mv "$D/r.json" "$D/.ai/run-context/design-reference.json"
run "$D" ITEM-1 1:147 1:152
status_is "exits 0" 0
has_line "first placed" "placed${TAB}1:147${TAB}image/svg+xml${TAB}icons/cable-icon.svg${TAB}<span class=\"icon icon-cable-icon\"></span>"
has_line "second reuses it" "reused${TAB}1:152${TAB}image/svg+xml${TAB}icons/cable-icon.svg${TAB}<span class=\"icon icon-cable-icon\"></span>"

echo "an existing project icon with another name is never touched"
D="$(project project-icon)"
printf '<svg xmlns="http://www.w3.org/2000/svg">project</svg>\n' > "$D/icons/search.svg"
run "$D" ITEM-1 1:160
status_is "exits 4" 4
has_line "collision with the project's own icon" "collision${TAB}1:160${TAB}image/svg+xml${TAB}icons/search.svg${TAB}.ai/figma/assets/bbbb.svg${TAB}icons/search.svg"

echo "a layer with no name is named by the asset's content hash"
D="$(project nameless)"
h="$(sha16 "$D/.ai/figma/assets/dddd.svg")"
run "$D" ITEM-1 1:170
status_is "exits 0" 0
has_line "hash-named icon" "placed${TAB}1:170${TAB}image/svg+xml${TAB}icons/$h.svg${TAB}<span class=\"icon icon-$h\"></span>"

echo "a raster photo is placed next to the draft and referenced relatively"
D="$(project raster)"
h="$(sha16 "$D/.ai/figma/assets/cccc.jpg")"
run "$D" ITEM-1 1:166
status_is "exits 0" 0
has_line "placed row" "placed${TAB}1:166${TAB}image/jpeg${TAB}drafts/ITEM-1-$h.jpg${TAB}./ITEM-1-$h.jpg"
same_bytes "photo bytes copied" "$D/drafts/ITEM-1-$h.jpg" "$D/.ai/figma/assets/cccc.jpg"
absent "not placed under icons/" "$D/icons/hero-image.jpg"

echo "a second run reuses the placed photo"
run "$D" ITEM-1 1:166
has_line "reused row" "reused${TAB}1:166${TAB}image/jpeg${TAB}drafts/ITEM-1-$h.jpg${TAB}./ITEM-1-$h.jpg"

echo "rows follow argument order; a repeated node is placed once"
D="$(project order)"
run "$D" ITEM-1 1:166 1:147 1:166
got="$(cut -f1,2 "$WORK/stdout" | tr '\t\n' ' |')"
if [ "$got" = "placed 1:166|placed 1:147|" ]; then ok "order kept"; else bad "order kept" "got: $got"; fi

echo "the layer name also comes from a viewport variant's reference code"
D="$(project variant)"
printf '<div data-node-id="9:1" data-name="Earth Icon"></div>' > "$D/.ai/run-context/variant.txt"
jq '.viewports = [{name: "Mobile", node_id: "9:0", width: 375, image: "x.png", context: ".ai/run-context/variant.txt"}] | .assets += [{node_id: "9:1", file: ".ai/figma/assets/aaaa.svg", mime: "image/svg+xml"}]' \
  "$D/.ai/run-context/design-reference.json" > "$D/r.json" && mv "$D/r.json" "$D/.ai/run-context/design-reference.json"
run "$D" ITEM-1 9:1
has_line "variant layer name used" "placed${TAB}9:1${TAB}image/svg+xml${TAB}icons/earth-icon.svg${TAB}<span class=\"icon icon-earth-icon\"></span>"

echo "refusals exit 2 and write nothing"
D="$(project refuse)"
run "$D" ITEM-1
status_is "no node: exits 2" 2
run "$D" ITEM-1 7:7
status_is "node not in assets: exits 2" 2
stdout_empty "node not in assets: stdout empty"
run "$D" ../x 1:166
status_is "item id with a parent segment: exits 2" 2
run "$D" a/b 1:166
status_is "item id with a slash: exits 2" 2
absent "nothing written for a refused item id" "$D/drafts/a"
jq '.assets[4].file = "https://example.invalid/asset.jpg"' "$D/.ai/run-context/design-reference.json" > "$D/r.json"
(cd "$D" && python3 "$PLACE" r.json ITEM-1 1:166 >"$WORK/stdout" 2>"$WORK/stderr"); STATUS=$?
status_is "a URL in place of a file: exits 2" 2
jq '.assets[4].file = ".ai/figma/assets/absent.jpg"' "$D/.ai/run-context/design-reference.json" > "$D/r.json"
(cd "$D" && python3 "$PLACE" r.json ITEM-1 1:166 >"$WORK/stdout" 2>"$WORK/stderr"); STATUS=$?
status_is "missing asset file: exits 2" 2
jq '.assets[4].mime = "application/pdf"' "$D/.ai/run-context/design-reference.json" > "$D/r.json"
(cd "$D" && python3 "$PLACE" r.json ITEM-1 1:166 >"$WORK/stdout" 2>"$WORK/stderr"); STATUS=$?
status_is "unsupported MIME type: exits 2" 2
jq 'del(.assets)' "$D/.ai/run-context/design-reference.json" > "$D/r.json"
(cd "$D" && python3 "$PLACE" r.json ITEM-1 1:166 >"$WORK/stdout" 2>"$WORK/stderr"); STATUS=$?
status_is "no assets key: exits 2" 2
(cd "$D" && python3 "$PLACE" absent.json ITEM-1 1:166 >"$WORK/stdout" 2>"$WORK/stderr"); STATUS=$?
status_is "missing reference: exits 2" 2
h="$(sha16 "$D/.ai/figma/assets/cccc.jpg")"
printf 'other bytes' > "$D/drafts/ITEM-1-$h.jpg"
run "$D" ITEM-1 1:166
status_is "a draft photo name holding other bytes: exits 2" 2
if [ "$(cat "$D/drafts/ITEM-1-$h.jpg")" = "other bytes" ]; then ok "not overwritten"; else bad "not overwritten"; fi

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
