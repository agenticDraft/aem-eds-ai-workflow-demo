#!/usr/bin/env bash
# Tests for classify-node.py. Run with:
#   bash plugins/figma/skills/fetch-reference/scripts/classify-node.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. The fixtures
# under fixtures/ are real metadata responses, trimmed to the depth the
# classifier reads; the inline cases cover shapes no real file here has.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFY="$SCRIPT_DIR/classify-node.py"
FX="$SCRIPT_DIR/fixtures"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/classify-node.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
TAB="$(printf '\t')"

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# run <xml-file> [flag] — sets STATUS, OUT, ERR
run() {
  python3 "$CLASSIFY" "$@" >"$WORK/stdout" 2>"$WORK/stderr"
  STATUS=$?
  OUT="$(cat "$WORK/stdout")"
  ERR="$(cat "$WORK/stderr")"
}

# inline <name> — writes stdin to a fixture file and prints its path
inline() { cat > "$WORK/$1.xml"; echo "$WORK/$1.xml"; }

exits() {
  if [ "$STATUS" -eq "$1" ]; then ok "exits $1"; else bad "exits $1" "got: $STATUS" "stderr: $ERR"; fi
}

has_class() {
  local first; first="$(head -1 "$WORK/stdout")"
  if [ "$first" = "class${TAB}$1" ]; then ok "class $1"; else bad "class $1" "got: $first"; fi
}

has_node() {
  if grep -qxF "node${TAB}$1${TAB}$2${TAB}$3${TAB}$4" "$WORK/stdout"; then ok "node $2 $4"
  else bad "node $2 $4" "$OUT"; fi
}

# has_child <id> <width> <role> <rule> <name>
has_child() {
  if grep -qxF "child${TAB}$1${TAB}$2${TAB}$3${TAB}$4${TAB}$5" "$WORK/stdout"; then ok "child $5: $3 $4"
  else bad "child $5: $3 $4" "$OUT"; fi
}

child_count() {
  local n; n="$(grep -c "^child${TAB}" "$WORK/stdout")"
  if [ "$n" -eq "$1" ]; then ok "$1 children listed"; else bad "$1 children listed" "got: $n" "$OUT"; fi
}

has_line() {
  if grep -qxF "$2" "$WORK/stdout"; then ok "$1"; else bad "$1" "want: $2" "$OUT"; fi
}

echo "a page is a question, naming every frame on it"
run "$FX/page.xml"
exits 0
has_class page
has_node canvas 0:1 0 "Page 1"
child_count 3
has_child 1:586 2711 candidate none Home
has_child 1:1003 1260 candidate none Styles
has_child 1:1172 1920 candidate none Thumbnail
if grep -q "1:118" "$WORK/stdout"; then bad "a grandchild is never listed" "$OUT"; else ok "a grandchild is never listed"; fi

echo "the page's question and options"
run "$FX/page.xml" --question
exits 0
has_line "question names every candidate" \
  "The design reference is a page holding 3 frames; which one is the reference? Home (1:586); Styles (1:1003); Thumbnail (1:1172)"
run "$FX/page.xml" --options
exits 0
if [ "$OUT" = "Home (1:586)
Styles (1:1003)
Thumbnail (1:1172)" ]; then ok "one option per candidate, in document order"; else bad "one option per candidate, in document order" "$OUT"; fi

echo "a section of Desktop, Tablet and Mobile frames is viewport variants"
run "$FX/section-variants.xml"
exits 0
has_class variants
has_node section 1:586 2711 Home
child_count 3
has_child 1:118 1280 variant name:keyword=desktop Desktop
has_child 1:274 800 variant name:keyword=tablet Tablet
has_child 1:430 375 variant name:keyword=mobile Mobile
run "$FX/section-variants.xml" --question
if [ "$STATUS" -eq 0 ] && [ -z "$OUT" ]; then ok "variants raise no question"; else bad "variants raise no question" "status $STATUS" "$OUT"; fi

echo "a frame whose children are its own sections is a single frame"
run "$FX/frame-sections.xml"
exits 0
has_class single
has_node frame 1:118 1280 Desktop
child_count 5
has_child 1:120 1200 - none Header
has_child 1:269 399 - none "Nav Items"
run "$FX/frame-sections.xml" --options
if [ "$STATUS" -eq 0 ] && [ -z "$OUT" ]; then ok "a single frame offers no options"; else bad "a single frame offers no options" "status $STATUS" "$OUT"; fi

echo "one child named for a viewport, among different content, is not a variant"
run "$FX/frame-styles.xml"
exits 0
has_class single
has_child 1:1089 1220 - name:keyword=mobile "Navigation mobile"
has_child 1:1077 1240 - none Navigation
has_child 1:1026 408 - none Icons
has_child 1:1045 31.750835418701172 - none Logo

echo "an instance with a text child is a single frame"
run "$FX/instance.xml"
exits 0
has_class single
has_node instance 1:185 138 Button
child_count 0

echo "naming patterns"
F="$(inline patterns <<'XML'
<frame id="2:1" name="Hero" x="0" y="0" width="3000" height="900">
  <frame id="2:2" name="Hero / Desktop" x="0" y="0" width="1440" height="900" />
  <frame id="2:3" name="Hero - Mobile" x="1500" y="0" width="375" height="900" />
  <frame id="2:4" name="Hero @tablet" x="2000" y="0" width="768" height="900" />
</frame>
XML
)"
run "$F"
has_class variants
has_child 2:2 1440 variant name:pattern=desktop "Hero / Desktop"
has_child 2:3 375 variant name:pattern=mobile "Hero - Mobile"
has_child 2:4 768 variant name:pattern=tablet "Hero @tablet"

echo "view suffix and width tokens"
F="$(inline views <<'XML'
<section id="3:1" name="Views" x="0" y="0" width="3000" height="900">
  <frame id="3:2" name="Desktop View" x="0" y="0" width="1440" height="900" />
  <frame id="3:3" name="Mobile View" x="1500" y="0" width="390" height="900" />
</section>
XML
)"
run "$F"
has_class variants
has_child 3:2 1440 variant name:pattern=desktop "Desktop View"
has_child 3:3 390 variant name:pattern=mobile "Mobile View"
F="$(inline widths <<'XML'
<section id="4:1" name="Widths" x="0" y="0" width="3000" height="900">
  <frame id="4:2" name="Home 1440" x="0" y="0" width="1440" height="900" />
  <frame id="4:3" name="Home 375px" x="1500" y="0" width="375" height="900" />
</section>
XML
)"
run "$F"
has_class variants
has_child 4:2 1440 variant name:width=1440 "Home 1440"
has_child 4:3 375 variant name:width=375 "Home 375px"

echo "a word that only contains a viewport word does not match"
F="$(inline webinar <<'XML'
<frame id="5:1" name="Page" x="0" y="0" width="1440" height="900">
  <frame id="5:2" name="Webinar" x="0" y="0" width="1440" height="300" />
  <frame id="5:3" name="Mobilecta" x="0" y="300" width="1440" height="300" />
  <frame id="5:4" name="Web" x="0" y="600" width="1440" height="300" />
</frame>
XML
)"
run "$F"
has_class single
has_child 5:2 1440 - none Webinar
has_child 5:3 1440 - none Mobilecta
has_child 5:4 1440 - name:keyword=web Web

echo "size decides only between siblings of the same name"
F="$(inline size <<'XML'
<frame id="6:1" name="Card" x="0" y="0" width="2000" height="900">
  <frame id="6:2" name="Frame 1" x="0" y="0" width="1440" height="900" />
  <frame id="6:3" name="Frame 2" x="1500" y="0" width="375" height="900" />
</frame>
XML
)"
run "$F"
has_class variants
has_child 6:2 1440 variant size "Frame 1"
has_child 6:3 375 variant size "Frame 2"
F="$(inline header-footer <<'XML'
<section id="7:1" name="Parts" x="0" y="0" width="2000" height="900">
  <frame id="7:2" name="Header" x="0" y="0" width="1440" height="200" />
  <frame id="7:3" name="Footer" x="0" y="300" width="400" height="200" />
</section>
XML
)"
run "$F"
has_class multi-frame
has_child 7:2 1440 candidate none Header
has_child 7:3 400 candidate none Footer
run "$F" --question
has_line "a section's question names its frames" \
  "The design reference is a section holding 2 frames; which one is the reference? Header (7:2); Footer (7:3)"

echo "variants plus an unrelated frame is a question"
F="$(inline mixed <<'XML'
<section id="8:1" name="Home" x="0" y="0" width="3000" height="900">
  <frame id="8:2" name="Desktop" x="0" y="0" width="1440" height="900" />
  <frame id="8:3" name="Mobile" x="1500" y="0" width="375" height="900" />
  <frame id="8:4" name="Notes" x="2000" y="0" width="600" height="900" />
</section>
XML
)"
run "$F"
has_class multi-frame
has_child 8:2 1440 variant name:keyword=desktop Desktop
has_child 8:4 600 candidate none Notes

echo "two variant groups of different content is a question"
F="$(inline two-groups <<'XML'
<frame id="9:1" name="Board" x="0" y="0" width="3000" height="900">
  <frame id="9:2" name="Hero - Desktop" x="0" y="0" width="1440" height="900" />
  <frame id="9:3" name="Hero - Mobile" x="0" y="0" width="375" height="900" />
  <frame id="9:4" name="Card - Desktop" x="0" y="0" width="1440" height="900" />
  <frame id="9:5" name="Card - Mobile" x="0" y="0" width="375" height="900" />
</frame>
XML
)"
run "$F"
has_class multi-frame
child_count 4

echo "a page holding only viewport variants is still a question"
F="$(inline page-variants <<'XML'
<canvas id="0:2" name="Page 2" x="0" y="0" width="0" height="0">
  <frame id="10:2" name="Desktop" x="0" y="0" width="1440" height="900" />
  <frame id="10:3" name="Mobile" x="1500" y="0" width="375" height="900" />
</canvas>
XML
)"
run "$F"
has_class page
has_child 10:2 1440 variant name:keyword=desktop Desktop
has_child 10:3 375 variant name:keyword=mobile Mobile
run "$F" --options
if [ "$OUT" = "Desktop (10:2)
Mobile (10:3)" ]; then ok "every frame is an option, variants included"; else bad "every frame is an option, variants included" "$OUT"; fi

echo "a section holding one frame is still a question"
F="$(inline one <<'XML'
<section id="11:1" name="Only" x="0" y="0" width="1500" height="900">
  <frame id="11:2" name="Landing" x="0" y="0" width="1440" height="900" />
</section>
XML
)"
run "$F"
has_class multi-frame
has_child 11:2 1440 candidate none Landing

echo "input that cannot be classified"
run "$WORK/does-not-exist.xml"
exits 2
F="$(printf 'no xml here\n' | inline none)"
run "$F"
exits 2
F="$(inline broken <<'XML'
<frame id="12:1" name="Broken" width="10">
  <frame id="12:2" name="Child"
XML
)"
run "$F"
exits 2
F="$(inline doctype <<'XML'
<!DOCTYPE frame [<!ENTITY a "aaaa">]>
<frame id="13:1" name="&a;" x="0" y="0" width="10" height="10" />
XML
)"
run "$F"
exits 2
run "$FX/page.xml" --bogus
exits 2
run
exits 2

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
