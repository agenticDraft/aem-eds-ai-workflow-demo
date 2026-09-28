#!/usr/bin/env bash
# Tests for screenshot-size.py. Run with:
#   bash plugins/figma/skills/fetch-reference/scripts/screenshot-size.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIZE="$SCRIPT_DIR/screenshot-size.py"
FX="$SCRIPT_DIR/fixtures"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/screenshot-size.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

run() {
  python3 "$SIZE" "$@" >"$WORK/stdout" 2>"$WORK/stderr"
  STATUS=$?
  OUT="$(cat "$WORK/stdout")"
  ERR="$(cat "$WORK/stderr")"
}

exits() {
  if [ "$STATUS" -eq "$1" ]; then ok "exits $1"; else bad "exits $1" "got: $STATUS" "stdout: $OUT" "stderr: $ERR"; fi
}

same() {
  if [ "$OUT" = "$2" ]; then ok "$1"; else bad "$1" "expected: $2" "got: $OUT"; fi
}

check() {
  local got
  got="$(printf '%s' "$OUT" | jq -r "$2" 2>&1)"
  if [ "$got" = "true" ]; then ok "$1"; else bad "$1" "filter: $2" "got: $got"; fi
}

echo "max: a variant child, by its colon id"
run max "$FX/section-variants.xml" 1:118
exits 0
same "the longer edge, rounded up (7388.67 -> 7389)" "7389"

echo "max: the same child by its hyphen id"
run max "$FX/section-variants.xml" 1-118
exits 0
same "7389" "7389"

echo "max: the root node"
run max "$FX/section-variants.xml" 1:586
exits 0
same "8996.47 -> 8997" "8997"

echo "max: a wide, short node — the width is the longer edge"
cat > "$WORK/wide.xml" <<'EOF'
<frame id="2:1" name="Banner" x="0" y="0" width="1440.2" height="300" />
EOF
run max "$WORK/wide.xml" 2:1
exits 0
same "1441" "1441"

echo "max: a node past the tool's limit is capped"
cat > "$WORK/tall.xml" <<'EOF'
<frame id="3:1" name="Long" x="0" y="0" width="375" height="90000" />
EOF
run max "$WORK/tall.xml" 3:1
exits 0
same "65536" "65536"

echo "max: text around the XML is ignored"
{ printf 'Here is the metadata:\n'; cat "$FX/section-variants.xml"; } > "$WORK/wrapped.xml"
run max "$WORK/wrapped.xml" 1:430
exits 0
same "8832.47 -> 8833" "8833"

echo "max: refusals"
run max "$FX/section-variants.xml" 9:9
exits 2
cat > "$WORK/nosize.xml" <<'EOF'
<frame id="4:1" name="No size" />
EOF
run max "$WORK/nosize.xml" 4:1
exits 2
run max "$WORK/absent.xml" 1:1
exits 2
run max "$FX/section-variants.xml"
exits 2

echo "list: sizes as returned, each marked downscaled or not"
run list '1-118=1280x7389/1280x7388.66748046875' '1-430=44x1024/375x8832.46875'
exits 0
check "a JSON array of two" 'type == "array" and length == 2'
check "each entry has exactly node_id, width, height, original_width, original_height, downscaled" \
  'all(.[]; keys == ["downscaled","height","node_id","original_height","original_width","width"])'
check "a render within a pixel of the original is not downscaled" \
  '.[0] == {"node_id": "1-118", "width": 1280, "height": 7389, "original_width": 1280, "original_height": 7388.66748046875, "downscaled": false}'
check "a render smaller than the original is downscaled" \
  '.[1].node_id == "1-430" and .[1].downscaled == true and .[1].width == 44'

echo "list: a colon id is written in hyphen form"
run list '1:118=178x1024/1280x7389'
exits 0
check "hyphen form, downscaled" '.[0].node_id == "1-118" and .[0].downscaled == true'

echo "list: refusals"
run list '1-118=1280x7389'
exits 2
run list '1-118=1280x/1280x7389'
exits 2
run list '1-118=0x7389/1280x7389'
exits 2
run list '1-118=1280x7389/1280x7389' '1:118=1280x7389/1280x7389'
exits 2
run list '../x=1x1/1x1'
exits 2
run list
exits 2

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
