#!/usr/bin/env bash
# Tests for fetch-assets.py. Run with:
#   bash plugins/figma/skills/fetch-reference/scripts/fetch-assets.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Asset sources
# are local files under a path shaped like the design tool's asset endpoint,
# fetched as file: URLs, so no case touches the network.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FETCH="$SCRIPT_DIR/fetch-assets.py"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/fetch-assets.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# check <desc> <jq filter that must print true> <json file>
check() {
  local got
  got="$(jq -r "$2" "$3" 2>&1)"
  if [ "$got" = "true" ]; then ok "$1"; else bad "$1" "filter: $2" "got: $got"; fi
}

# Opening and closing braces, doubled in the fixtures below to form a style
# object; kept out of this file's own text, where a doubled brace is reserved.
O='{'
C='}'

SRC="$WORK/src/api/mcp/asset/2ee5e0d4"
mkdir -p "$SRC"
PREFIX="file://$SRC"
printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00photo-bytes' > "$SRC/aa824.png"
printf '<svg width="24" height="24" xmlns="http://www.w3.org/2000/svg"><g id="Cable icon"/></svg>' > "$SRC/f590d.svg"
printf '<?xml version="1.0"?>\n<svg width="24" height="24"><g id="Earth icon"/></svg>' > "$SRC/e3303.svg"
printf '<!DOCTYPE html><html>expired</html>' > "$SRC/dead.svg"
sha() { shasum -a 256 "$1" | cut -c1-16; }
PHOTO_HASH="$(sha "$SRC/aa824.png")"
CABLE_HASH="$(sha "$SRC/f590d.svg")"
EARTH_HASH="$(sha "$SRC/e3303.svg")"

# case_dir <name> — a fresh project root
case_dir() { mkdir -p "$WORK/$1/.ai/figma"; echo "$WORK/$1"; }

# fetch <dir> <code file> [env...] — runs fetch mode from inside <dir>
fetch() {
  local dir="$1" code="$2"
  shift 2
  (cd "$dir" && env FETCH_ASSETS_ALLOW_FILE=1 "$@" python3 "$FETCH" fetch \
    .ai/figma/k-1-139.context.txt .ai/figma/assets .ai/figma/k-1-139.assets.json \
    < "$code" > "$dir/stdout" 2> "$dir/stderr")
}

nothing_written() {
  local dir="$1"
  if [ -e "$dir/.ai/figma/k-1-139.context.txt" ] || [ -e "$dir/.ai/figma/k-1-139.assets.json" ] \
     || [ -n "$(ls -A "$dir/.ai/figma/assets" 2>/dev/null)" ]; then
    bad "writes nothing" "found: $(ls -R "$dir/.ai/figma")"
  else
    ok "writes nothing"
  fi
}

no_source_in_output() {
  if grep -q 'api/mcp/asset' "$1/stdout" "$1/stderr"; then
    bad "no asset URL on stdout or stderr" "stdout: $(cat "$1/stdout")" "stderr: $(cat "$1/stderr")"
  else
    ok "no asset URL on stdout or stderr"
  fi
}

cat > "$WORK/benefits.jsx" <<EOF
const assetPathPrefix = "$PREFIX";
const imgHeroImage = \`\${assetPathPrefix}/aa824.png\`;
const imgCableIcon = \`\${assetPathPrefix}/f590d.svg\`;
const imgEarthIcon = \`\${assetPathPrefix}/e3303.svg\`;

export default function BenefitsSection() {
  return (
    <div className="flex flex-col" data-node-id="1:139" data-name="Benefits section">
      <section className="border-t" data-node-id="1:146" data-name="Icon lockup 1">
        <div className="relative size-[24px]" data-node-id="1:147" data-name="Cable icon">
          <img alt="" className="absolute block inset-0" src={imgCableIcon} />
        </div>
        <p className="text-[18px]" data-node-id="1:149">Amplify Insights — a => b</p>
      </section>
      <section className="border-t" data-node-id="1:151" data-name="Icon lockup 2">
        <div className="relative size-[24px]" data-node-id="1:152" data-name="Earth icon">
          <img alt="" className="absolute block inset-0" src={imgEarthIcon} />
        </div>
        <p className="text-[15px]" data-node-id="1:155" style=${O}${O} fontVariationSettings: '"opsz" 14' ${C}${C}>Text</p>
      </section>
      <section className="border-t" data-node-id="1:156" data-name="Icon lockup 3">
        <div className="relative size-[24px]" data-node-id="1:157" data-name="Earth icon again">
          <img alt="" className="absolute block inset-0" src={imgEarthIcon} />
        </div>
      </section>
      <div className="h-[620px] rounded-[30px]" data-node-id="1:166" data-name="Hero Image">
        <img alt="A mountain range" className="absolute inset-0 object-cover" src={imgHeroImage} />
      </div>
    </div>
  );
}
EOF

echo "fetch: a photo and icons referenced by the code"
D="$(case_dir benefits)"
if fetch "$D" "$WORK/benefits.jsx"; then ok "exits 0"; else bad "exits 0" "stderr: $(cat "$D/stderr")"; fi
A="$D/.ai/figma/k-1-139.assets.json"
if [ -f "$A" ]; then
  check "one entry per node that uses an asset, in code order" \
    '[.[].node_id] == ["1:147", "1:152", "1:157", "1:166"]' "$A"
  check "the photo is JPEG, named by its bytes, not its .png suffix" \
    ".[3] == {\"node_id\": \"1:166\", \"file\": \".ai/figma/assets/$PHOTO_HASH.jpg\", \"mime\": \"image/jpeg\"}" "$A"
  check "the icon is SVG" \
    ".[0] == {\"node_id\": \"1:147\", \"file\": \".ai/figma/assets/$CABLE_HASH.svg\", \"mime\": \"image/svg+xml\"}" "$A"
  check "one icon used by two nodes is one file" \
    ".[1].file == \".ai/figma/assets/$EARTH_HASH.svg\" and .[2].file == .[1].file" "$A"
  check "every entry has exactly node_id, file, mime" 'all(.[]; keys == ["file", "mime", "node_id"])' "$A"
else
  bad "assets JSON written" "missing: $A"
fi
if cmp -s "$SRC/aa824.png" "$D/.ai/figma/assets/$PHOTO_HASH.jpg"; then ok "photo bytes identical"; else bad "photo bytes identical"; fi
if cmp -s "$SRC/f590d.svg" "$D/.ai/figma/assets/$CABLE_HASH.svg"; then ok "icon bytes identical"; else bad "icon bytes identical"; fi
n="$(ls "$D/.ai/figma/assets" | wc -l | tr -d ' ')"
if [ "$n" = "3" ]; then ok "three files for three distinct byte strings"; else bad "three files" "got: $n"; fi
C="$D/.ai/figma/k-1-139.context.txt"
if grep -q 'api/mcp/asset\|file://' "$C"; then bad "the context file holds no asset URL" "$(grep -n 'api/mcp/asset\|file://' "$C")"; else ok "the context file holds no asset URL"; fi
if grep -qF "const imgHeroImage = \".ai/figma/assets/$PHOTO_HASH.jpg\";" "$C"; then ok "the photo constant names its local file"; else bad "the photo constant names its local file" "$(grep -n imgHeroImage "$C" | head -1)"; fi
if grep -qF 'const assetPathPrefix = ".ai/figma/assets";' "$C"; then ok "the prefix constant names the assets directory"; else bad "the prefix constant names the assets directory" "$(head -1 "$C")"; fi
grep -v '^const ' "$WORK/benefits.jsx" > "$WORK/expected.rest"
grep -v '^const ' "$C" > "$WORK/got.rest" 2>/dev/null
if cmp -s "$WORK/expected.rest" "$WORK/got.rest"; then
  ok "every other line is unchanged"
else
  bad "every other line is unchanged" "$(diff "$WORK/expected.rest" "$WORK/got.rest" | head -5)"
fi
no_source_in_output "$D"

echo "fetch: a second call with the same bytes reuses the files and replaces none"
before="$(ls -li "$D/.ai/figma/assets" | awk '{print $1, $NF}')"
mv "$D/.ai/figma/k-1-139.context.txt" "$D/first.context.txt"
mv "$D/.ai/figma/k-1-139.assets.json" "$D/first.assets.json"
if fetch "$D" "$WORK/benefits.jsx"; then ok "exits 0"; else bad "exits 0" "stderr: $(cat "$D/stderr")"; fi
after="$(ls -li "$D/.ai/figma/assets" | awk '{print $1, $NF}')"
if [ "$before" = "$after" ]; then ok "same files, same inodes"; else bad "same files, same inodes" "before: $before" "after: $after"; fi
if cmp -s "$D/first.assets.json" "$D/.ai/figma/k-1-139.assets.json"; then ok "same list"; else bad "same list"; fi

echo "fetch: a file already under an asset's name with other bytes is refused"
D="$(case_dir collide)"
mkdir -p "$D/.ai/figma/assets"
printf 'other bytes' > "$D/.ai/figma/assets/$CABLE_HASH.svg"
fetch "$D" "$WORK/benefits.jsx"
status=$?
if [ "$status" -eq 2 ]; then ok "exits 2"; else bad "exits 2" "got: $status"; fi
if [ "$(cat "$D/.ai/figma/assets/$CABLE_HASH.svg")" = "other bytes" ]; then ok "the earlier file is untouched"; else bad "the earlier file is untouched"; fi
if [ -e "$D/.ai/figma/k-1-139.assets.json" ] || [ -e "$D/.ai/figma/k-1-139.context.txt" ]; then bad "writes no list or context"; else ok "writes no list or context"; fi

echo "fetch: code with no assets"
D="$(case_dir none)"
printf 'export default function Button() {\n\treturn <a data-node-id="1:185">Go \xe2\x80\x94 </a>;\n}' > "$WORK/none.jsx"
if fetch "$D" "$WORK/none.jsx"; then ok "exits 0"; else bad "exits 0" "stderr: $(cat "$D/stderr")"; fi
check "the list is empty" '. == []' "$D/.ai/figma/k-1-139.assets.json"
if cmp -s "$WORK/none.jsx" "$D/.ai/figma/k-1-139.context.txt"; then ok "the context is byte-identical"; else bad "the context is byte-identical"; fi

echo "fetch: a constant holding the whole URL, and a background image"
D="$(case_dir literal)"
cat > "$WORK/literal.jsx" <<EOF
const imgBg = "$PREFIX/aa824.png";
export default function Card() {
  return <div data-node-id="2:1" style=${O}${O} backgroundImage: \`url('\${imgBg}')\` ${C}${C} />;
}
EOF
if fetch "$D" "$WORK/literal.jsx"; then ok "exits 0"; else bad "exits 0" "stderr: $(cat "$D/stderr")"; fi
check "the element carrying the style owns the asset" \
  ".[0] == {\"node_id\": \"2:1\", \"file\": \".ai/figma/assets/$PHOTO_HASH.jpg\", \"mime\": \"image/jpeg\"}" "$D/.ai/figma/k-1-139.assets.json"
if grep -q 'file://' "$D/.ai/figma/k-1-139.context.txt"; then bad "no URL left"; else ok "no URL left"; fi

echo "fetch: a declared asset no element uses"
D="$(case_dir unused)"
cat > "$WORK/unused.jsx" <<EOF
const assetPathPrefix = "$PREFIX";
const imgSpare = \`\${assetPathPrefix}/f590d.svg\`;
export default function X() { return <div data-node-id="3:1" />; }
EOF
if fetch "$D" "$WORK/unused.jsx"; then ok "exits 0"; else bad "exits 0" "stderr: $(cat "$D/stderr")"; fi
check "downloaded, with node_id null" \
  ".[0] == {\"node_id\": null, \"file\": \".ai/figma/assets/$CABLE_HASH.svg\", \"mime\": \"image/svg+xml\"}" "$D/.ai/figma/k-1-139.assets.json"

# refused <desc> <case> <code file> <expected exit> [env...]
refused() {
  local desc="$1" dir status expect="$4" code="$3"
  dir="$(case_dir "$2")"
  shift 4
  echo "fetch: $desc"
  fetch "$dir" "$code" "$@"
  status=$?
  if [ "$status" -eq "$expect" ]; then ok "exits $expect"; else bad "exits $expect" "got: $status" "stderr: $(cat "$dir/stderr")"; fi
  nothing_written "$dir"
  no_source_in_output "$dir"
}

cat > "$WORK/dead.jsx" <<EOF
const assetPathPrefix = "$PREFIX";
const imgOk = \`\${assetPathPrefix}/f590d.svg\`;
const imgDead = \`\${assetPathPrefix}/dead.svg\`;
export default function X() { return <div data-node-id="4:1"><img src={imgOk} /><img src={imgDead} /></div>; }
EOF
refused "bytes that are no known image format" dead "$WORK/dead.jsx" 2

cat > "$WORK/missing.jsx" <<EOF
const assetPathPrefix = "$PREFIX";
const imgGone = \`\${assetPathPrefix}/gone.png\`;
export default function X() { return <div data-node-id="4:2"><img src={imgGone} /></div>; }
EOF
refused "a download that fails" missing "$WORK/missing.jsx" 3

cat > "$WORK/inline.jsx" <<EOF
const assetPathPrefix = "$PREFIX";
const imgOk = \`\${assetPathPrefix}/f590d.svg\`;
export default function X() { return <div data-node-id="4:3"><img src={imgOk} /><img src="$PREFIX/e3303.svg" /></div>; }
EOF
refused "an asset URL outside a constant" inline "$WORK/inline.jsx" 2

refused "a file: URL outside tests" noenv "$WORK/benefits.jsx" 2 FETCH_ASSETS_ALLOW_FILE=

cat > "$WORK/http.jsx" <<'EOF'
const imgPlain = "http://example.test/api/mcp/asset/x/a.png";
export default function X() { return <img data-node-id="4:4" src={imgPlain} />; }
EOF
refused "a plain http URL" http "$WORK/http.jsx" 2

echo "list: merges per-target lists, dropping repeated entries"
D="$(case_dir list)"
printf '[{"node_id": "1:147", "file": ".ai/figma/assets/a.svg", "mime": "image/svg+xml"}, {"node_id": "1:166", "file": ".ai/figma/assets/b.jpg", "mime": "image/jpeg"}]' > "$D/one.json"
printf '[{"node_id": "1:166", "file": ".ai/figma/assets/b.jpg", "mime": "image/jpeg"}, {"node_id": "1:300", "file": ".ai/figma/assets/b.jpg", "mime": "image/jpeg"}]' > "$D/two.json"
printf '[]' > "$D/empty.json"
(cd "$D" && python3 "$FETCH" list one.json empty.json two.json > out.json 2> err)
if [ $? -eq 0 ]; then ok "exits 0"; else bad "exits 0" "stderr: $(cat "$D/err")"; fi
check "first-seen order, each entry once" \
  '[.[] | "\(.node_id) \(.file)"] == ["1:147 .ai/figma/assets/a.svg", "1:166 .ai/figma/assets/b.jpg", "1:300 .ai/figma/assets/b.jpg"]' "$D/out.json"
(cd "$D" && python3 "$FETCH" list empty.json > none.json)
check "only empty lists give []" '. == []' "$D/none.json"

# list_refused <desc> <json>
list_refused() {
  printf '%s' "$2" > "$D/bad.json"
  (cd "$D" && python3 "$FETCH" list bad.json > /dev/null 2>&1)
  if [ $? -eq 2 ]; then ok "list refuses $1"; else bad "list refuses $1"; fi
}
list_refused "a URL as a file" '[{"node_id": "1:1", "file": "https://www.figma.com/api/mcp/asset/x/a.png", "mime": "image/png"}]'
list_refused "an entry missing a key" '[{"node_id": "1:1", "file": ".ai/figma/assets/a.png"}]'
list_refused "an unknown MIME type" '[{"node_id": "1:1", "file": ".ai/figma/assets/a.pdf", "mime": "application/pdf"}]'
list_refused "a non-list" '{"node_id": "1:1"}'

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
