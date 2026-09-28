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
h4() { shasum -a 256 "$1" | cut -c1-4; }
h8() { shasum -a 256 "$1" | cut -c1-8; }

# Two SVGs whose SHA-256 (with the trailing newline) both begin f81b
TIE_1='<svg xmlns="http://www.w3.org/2000/svg"><path d="M177 0"/></svg>'
TIE_2='<svg xmlns="http://www.w3.org/2000/svg"><path d="M369 0"/></svg>'

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

no_collision() {
  if grep -q '^collision' "$WORK/stdout"; then bad "$1" "$(cat "$WORK/stdout")"; else ok "$1"; fi
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

echo "an icon present with different bytes counts as one more design: the new one splits off"
D="$(project diff-icon)"
printf '%s\n' "$SVG_B" > "$D/icons/cable-icon.svg"
a="$(h4 "$D/.ai/figma/assets/aaaa.svg")"
run "$D" ITEM-1 1:147 1:166
status_is "exits 0" 0
has_line "placed under the hash4 name" "placed${TAB}1:147${TAB}image/svg+xml${TAB}icons/cable-icon-$a.svg${TAB}<span class=\"icon icon-cable-icon-$a\"></span>"
has_line "split row" "split${TAB}icons/cable-icon.svg${TAB}icons/cable-icon-$a.svg"
same_bytes "existing icon not overwritten" "$D/icons/cable-icon.svg" "$D/.ai/figma/assets/bbbb.svg"
same_bytes "new icon written" "$D/icons/cable-icon-$a.svg" "$D/.ai/figma/assets/aaaa.svg"
no_collision "no collision row"

echo "two layers slugifying to one name with different bytes both split; no base file"
D="$(project twin-slug)"
a="$(h4 "$D/.ai/figma/assets/aaaa.svg")"; b="$(h4 "$D/.ai/figma/assets/bbbb.svg")"
run "$D" ITEM-1 1:147 1:152
status_is "exits 0" 0
has_line "first layer hash-named" "placed${TAB}1:147${TAB}image/svg+xml${TAB}icons/cable-icon-$a.svg${TAB}<span class=\"icon icon-cable-icon-$a\"></span>"
has_line "second layer hash-named" "placed${TAB}1:152${TAB}image/svg+xml${TAB}icons/cable-icon-$b.svg${TAB}<span class=\"icon icon-cable-icon-$b\"></span>"
absent "no base file" "$D/icons/cable-icon.svg"

echo "two layers slugifying to one name with identical bytes share one file"
D="$(project twin-same)"
jq '.assets[5].node_id = "1:180" | .assets += [{node_id: "1:152", file: ".ai/figma/assets/twin.svg", mime: "image/svg+xml"}] | .assets |= map(select(.file != ".ai/figma/assets/bbbb.svg" or .node_id != "1:152"))' \
  "$D/.ai/run-context/design-reference.json" > "$D/r.json" && mv "$D/r.json" "$D/.ai/run-context/design-reference.json"
run "$D" ITEM-1 1:147 1:152
status_is "exits 0" 0
has_line "first placed" "placed${TAB}1:147${TAB}image/svg+xml${TAB}icons/cable-icon.svg${TAB}<span class=\"icon icon-cable-icon\"></span>"
has_line "second reuses it" "reused${TAB}1:152${TAB}image/svg+xml${TAB}icons/cable-icon.svg${TAB}<span class=\"icon icon-cable-icon\"></span>"

echo "a project icon holding the base name is never touched; the design splits off"
D="$(project project-icon)"
printf '<svg xmlns="http://www.w3.org/2000/svg">project</svg>\n' > "$D/icons/search.svg"
before="$(cat "$D/icons/search.svg")"
b="$(h4 "$D/.ai/figma/assets/bbbb.svg")"
run "$D" ITEM-1 1:160
status_is "exits 0" 0
has_line "placed beside the project's icon" "placed${TAB}1:160${TAB}image/svg+xml${TAB}icons/search-$b.svg${TAB}<span class=\"icon icon-search-$b\"></span>"
if [ "$(cat "$D/icons/search.svg")" = "$before" ]; then ok "project icon untouched"; else bad "project icon untouched"; fi

# checks <name> <file>... — a project whose layers 2:1..2:N are all named
# "Check icon", layer i carrying the i-th file given (EDS-18's shape)
checks() {
  local dir; dir="$(project "$1")"; shift
  local code='<div data-node-id="2:0" data-name="Card">' assets='[]' i=1 f
  for f in "$@"; do
    code="$code<div data-node-id=\"2:$i\" data-name=\"Check icon\"></div>"
    assets="$(jq -c --arg n "2:$i" --arg f ".ai/figma/assets/$f" '. + [{node_id: $n, file: $f, mime: "image/svg+xml"}]' <<<"$assets")"
    i=$((i + 1))
  done
  printf '%s</div>' "$code" > "$dir/.ai/run-context/design-context.txt"
  jq --argjson a "$assets" '.assets = $a' "$dir/.ai/run-context/design-reference.json" > "$dir/r.json" \
    && mv "$dir/r.json" "$dir/.ai/run-context/design-reference.json"
  echo "$dir"
}

echo "three distinct designs under one layer name: three hash4 files, no base file, exit 0"
D="$(checks three aaaa.svg aaaa.svg bbbb.svg dddd.svg bbbb.svg dddd.svg)"
a="$(h4 "$D/.ai/figma/assets/aaaa.svg")"; b="$(h4 "$D/.ai/figma/assets/bbbb.svg")"; d="$(h4 "$D/.ai/figma/assets/dddd.svg")"
run "$D" ITEM-1 2:1 2:2 2:3 2:4 2:5 2:6
status_is "exits 0" 0
same_bytes "first design" "$D/icons/check-icon-$a.svg" "$D/.ai/figma/assets/aaaa.svg"
same_bytes "second design" "$D/icons/check-icon-$b.svg" "$D/.ai/figma/assets/bbbb.svg"
same_bytes "third design" "$D/icons/check-icon-$d.svg" "$D/.ai/figma/assets/dddd.svg"
absent "no base file" "$D/icons/check-icon.svg"
has_line "a copy reuses its design's file" "reused${TAB}2:2${TAB}image/svg+xml${TAB}icons/check-icon-$a.svg${TAB}<span class=\"icon icon-check-icon-$a\"></span>"
split="$(printf 'icons/check-icon-%s.svg\n' "$a" "$b" "$d" | sort | tr '\n' "$TAB")"
has_line "one split row listing every name, sorted" "split${TAB}icons/check-icon.svg${TAB}${split%"$TAB"}"
no_collision "no collision row"
forward="$(ls "$D/icons")"

echo "reversed layer order gives the same names"
D="$(checks reversed dddd.svg bbbb.svg dddd.svg bbbb.svg aaaa.svg aaaa.svg)"
run "$D" ITEM-1 2:6 2:5 2:4 2:3 2:2 2:1
status_is "exits 0" 0
if [ "$(ls "$D/icons")" = "$forward" ]; then ok "same file names"; else bad "same file names" "forward: $forward" "reversed: $(ls "$D/icons")"; fi
same_bytes "each design keeps its name" "$D/icons/check-icon-$a.svg" "$D/.ai/figma/assets/aaaa.svg"

echo "identical copies under one layer name keep one base file"
D="$(checks copies aaaa.svg twin.svg aaaa.svg)"
run "$D" ITEM-1 2:1 2:2 2:3
status_is "exits 0" 0
same_bytes "one base file" "$D/icons/check-icon.svg" "$D/.ai/figma/assets/aaaa.svg"
if ls "$D/icons" | grep -q '^check-icon-'; then bad "no hash-named file" "$(ls "$D/icons")"; else ok "no hash-named file"; fi
if grep -q "^split" "$WORK/stdout"; then bad "no split row" "$(cat "$WORK/stdout")"; else ok "no split row"; fi

echo "two designs sharing a hash4 both widen to 8"
D="$(checks tie tie1.svg tie2.svg)"
printf '%s\n' "$TIE_1" > "$D/.ai/figma/assets/tie1.svg"
printf '%s\n' "$TIE_2" > "$D/.ai/figma/assets/tie2.svg"
run "$D" ITEM-1 2:1 2:2
status_is "exits 0" 0
if [ "$(h4 "$D/.ai/figma/assets/tie1.svg")" = "$(h4 "$D/.ai/figma/assets/tie2.svg")" ]; then ok "fixture ties at 4"; else bad "fixture ties at 4"; fi
same_bytes "first widened" "$D/icons/check-icon-$(h8 "$D/.ai/figma/assets/tie1.svg").svg" "$D/.ai/figma/assets/tie1.svg"
same_bytes "second widened" "$D/icons/check-icon-$(h8 "$D/.ai/figma/assets/tie2.svg").svg" "$D/.ai/figma/assets/tie2.svg"
absent "no 4-wide name" "$D/icons/check-icon-$(h4 "$D/.ai/figma/assets/tie1.svg").svg"

echo "a project file holding the hash4 name with other bytes widens that name to 8"
D="$(checks held4 aaaa.svg bbbb.svg)"
a="$(h4 "$D/.ai/figma/assets/aaaa.svg")"; b="$(h4 "$D/.ai/figma/assets/bbbb.svg")"
printf 'squatter\n' > "$D/icons/check-icon-$a.svg"
run "$D" ITEM-1 2:1 2:2
status_is "exits 0" 0
same_bytes "widened" "$D/icons/check-icon-$(h8 "$D/.ai/figma/assets/aaaa.svg").svg" "$D/.ai/figma/assets/aaaa.svg"
same_bytes "the other keeps hash4" "$D/icons/check-icon-$b.svg" "$D/.ai/figma/assets/bbbb.svg"
if [ "$(cat "$D/icons/check-icon-$a.svg")" = "squatter" ]; then ok "squatter not overwritten"; else bad "squatter not overwritten"; fi

# literal <name> <file> — checks' project with aaaa.svg and bbbb.svg under
# "Check icon" (2:1, 2:2), plus 2:3 literally named check-icon-<hash4 of aaaa>
# carrying <file>
literal() {
  local dir a; dir="$(checks "$1" aaaa.svg bbbb.svg "$2")"
  a="$(h4 "$dir/.ai/figma/assets/aaaa.svg")"
  sed "s/data-node-id=\"2:3\" data-name=\"Check icon\"/data-node-id=\"2:3\" data-name=\"check-icon-$a\"/" \
    "$dir/.ai/run-context/design-context.txt" > "$dir/c.txt" && mv "$dir/c.txt" "$dir/.ai/run-context/design-context.txt"
  echo "$dir"
}

echo "a layer literally named like a split name, other bytes: exit 4, same collision row in either order"
D="$(literal cross dddd.svg)"
a="$(h4 "$D/.ai/figma/assets/aaaa.svg")"
run "$D" ITEM-1 2:1 2:2 2:3
status_is "exits 4" 4
forward_row="$(grep '^collision' "$WORK/stdout")"
absent "nothing written" "$D/icons/check-icon-$a.svg"
run "$D" ITEM-1 2:3 2:2 2:1
status_is "reversed: exits 4" 4
if [ "$(grep '^collision' "$WORK/stdout")" = "$forward_row" ] && [ -n "$forward_row" ]; then ok "the same node collides in either order"; else bad "the same node collides in either order" "forward:  $forward_row" "reversed: $(grep '^collision' "$WORK/stdout")"; fi

echo "a layer literally named like a split name, same bytes: reused"
D="$(literal cross-same twin.svg)"
a="$(h4 "$D/.ai/figma/assets/aaaa.svg")"
run "$D" ITEM-1 2:1 2:2 2:3
status_is "exits 0" 0
has_line "reuses the split file" "reused${TAB}2:3${TAB}image/svg+xml${TAB}icons/check-icon-$a.svg${TAB}<span class=\"icon icon-check-icon-$a\"></span>"

echo "the 8-wide name also held by other bytes is a collision: exit 4, nothing written"
D="$(checks held8 aaaa.svg bbbb.svg)"
a="$(h4 "$D/.ai/figma/assets/aaaa.svg")"; a8="$(h8 "$D/.ai/figma/assets/aaaa.svg")"; b="$(h4 "$D/.ai/figma/assets/bbbb.svg")"
printf 'squatter\n' > "$D/icons/check-icon-$a.svg"
printf 'squatter\n' > "$D/icons/check-icon-$a8.svg"
run "$D" ITEM-1 2:1 2:2
status_is "exits 4" 4
has_line "collision row" "collision${TAB}2:1${TAB}image/svg+xml${TAB}icons/check-icon-$a8.svg${TAB}.ai/figma/assets/aaaa.svg${TAB}icons/check-icon-$a8.svg"
absent "nothing written" "$D/icons/check-icon-$b.svg"

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
