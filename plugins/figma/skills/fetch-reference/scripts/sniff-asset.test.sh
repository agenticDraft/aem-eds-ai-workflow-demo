#!/usr/bin/env bash
# Tests for sniff-asset.py. Run with:
#   bash plugins/figma/skills/fetch-reference/scripts/sniff-asset.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNIFF="$SCRIPT_DIR/sniff-asset.py"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sniff-asset.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# sniffs <desc> <file> <expected stdout>
sniffs() {
  local out status
  out="$(python3 "$SNIFF" "$2" 2>"$WORK/stderr")"
  status=$?
  if [ "$status" -eq 0 ] && [ "$out" = "$3" ]; then
    ok "$1"
  else
    bad "$1" "expected: $3 (exit 0)" "got: $out (exit $status)" "stderr: $(cat "$WORK/stderr")"
  fi
}

# refuses <desc> <file>
refuses() {
  local out status
  out="$(python3 "$SNIFF" "$2" 2>"$WORK/stderr")"
  status=$?
  if [ "$status" -eq 2 ] && [ -z "$out" ] && [ -s "$WORK/stderr" ]; then
    ok "$1"
  else
    bad "$1" "expected: exit 2, empty stdout, a reason on stderr" "got: $out (exit $status)"
  fi
}

TAB="$(printf '\t')"

echo "raster formats, by their leading bytes"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR' > "$WORK/a"
sniffs "PNG" "$WORK/a" "png${TAB}image/png"
printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00' > "$WORK/b"
sniffs "JPEG (JFIF)" "$WORK/b" "jpg${TAB}image/jpeg"
printf '\xff\xd8\xff\xe1\x00\x10Exif\x00' > "$WORK/b2"
sniffs "JPEG (Exif)" "$WORK/b2" "jpg${TAB}image/jpeg"
printf 'GIF89a\x01\x00\x01\x00' > "$WORK/c"
sniffs "GIF89a" "$WORK/c" "gif${TAB}image/gif"
printf 'GIF87a\x01\x00\x01\x00' > "$WORK/c2"
sniffs "GIF87a" "$WORK/c2" "gif${TAB}image/gif"
printf 'RIFF\x24\x00\x00\x00WEBPVP8 ' > "$WORK/d"
sniffs "WebP" "$WORK/d" "webp${TAB}image/webp"

echo "SVG, by its root element"
printf '<svg width="24" height="24" xmlns="http://www.w3.org/2000/svg"><path d="M0 0"/></svg>' > "$WORK/e"
sniffs "bare svg root" "$WORK/e" "svg${TAB}image/svg+xml"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg"></svg>' > "$WORK/f"
sniffs "leading XML declaration" "$WORK/f" "svg${TAB}image/svg+xml"
printf '\n\t  \r\n<svg>\n</svg>\n' > "$WORK/g"
sniffs "leading whitespace" "$WORK/g" "svg${TAB}image/svg+xml"
printf '\xef\xbb\xbf<?xml version="1.0"?>\n<svg></svg>' > "$WORK/h"
sniffs "byte-order mark, then XML declaration" "$WORK/h" "svg${TAB}image/svg+xml"
printf '\xef\xbb\xbf  <svg\n  width="1"></svg>' > "$WORK/h2"
sniffs "byte-order mark, whitespace, root split over lines" "$WORK/h2" "svg${TAB}image/svg+xml"
printf '<?xml version="1.0"?>\n<!-- exported -->\n<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "x.dtd">\n<svg></svg>' > "$WORK/i"
sniffs "comment and doctype before the root" "$WORK/i" "svg${TAB}image/svg+xml"

echo "a name or suffix is never read"
printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00' > "$WORK/photo.png"
sniffs "JPEG bytes named .png are JPEG" "$WORK/photo.png" "jpg${TAB}image/jpeg"
printf '\x89PNG\r\n\x1a\n\x00' > "$WORK/icon.svg"
sniffs "PNG bytes named .svg are PNG" "$WORK/icon.svg" "png${TAB}image/png"

echo "refused"
: > "$WORK/empty"
refuses "an empty file" "$WORK/empty"
printf '<!DOCTYPE html><html><body>expired</body></html>' > "$WORK/html"
refuses "an HTML page" "$WORK/html"
printf '<?xml version="1.0"?><rss></rss>' > "$WORK/xml"
refuses "XML whose root is not svg" "$WORK/xml"
printf '<svgfoo></svgfoo>' > "$WORK/svgish"
refuses "an element whose name only starts with svg" "$WORK/svgish"
printf '<SVG></SVG>' > "$WORK/upper"
refuses "an upper-case SVG root" "$WORK/upper"
printf '%%PDF-1.7\n' > "$WORK/pdf"
refuses "a PDF" "$WORK/pdf"
printf 'RIFF\x24\x00\x00\x00WAVEfmt ' > "$WORK/wav"
refuses "RIFF that is not WebP" "$WORK/wav"
printf '\x89PNG' > "$WORK/shortpng"
refuses "a truncated PNG signature" "$WORK/shortpng"
printf 'hello' > "$WORK/text"
refuses "plain text" "$WORK/text"
refuses "a file that does not exist" "$WORK/nope"
python3 "$SNIFF" >/dev/null 2>&1
if [ $? -eq 2 ]; then ok "no argument exits 2"; else bad "no argument exits 2"; fi

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
