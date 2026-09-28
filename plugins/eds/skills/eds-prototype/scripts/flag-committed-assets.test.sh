#!/usr/bin/env bash
# Tests for flag-committed-assets.py. Run with:
#   bash plugins/eds/skills/eds-prototype/scripts/flag-committed-assets.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Each case runs
# the script from inside a throwaway repository whose ignore rules mirror a
# project that ignores drafts/ and commits blocks/ and icons/.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAG="$SCRIPT_DIR/flag-committed-assets.py"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/flag-committed-assets.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
TAB="$(printf '\t')"

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

REPO="$WORK/repo"
mkdir -p "$REPO/blocks/hero" "$REPO/icons" "$REPO/drafts"
git -C "$REPO" init -q
printf 'drafts/\n' > "$REPO/.gitignore"

# Byte fixtures, each a recognised format by its leading bytes.
printf '\377\330\377\340\000\020JFIF\000jpeg-body' > "$REPO/blocks/hero/photo.jpg"
printf '\211PNG\r\n\032\n\000\000\000\rIHDRpng-body' > "$REPO/blocks/hero/shot.png"
printf 'GIF89agif-body' > "$REPO/blocks/hero/anim.gif"
printf 'RIFF\004\000\000\000WEBPVP8 webp-body' > "$REPO/blocks/hero/pic.webp"
printf '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"></svg>\n' > "$REPO/icons/cable-icon.svg"
printf '\377\330\377\340\000\020JFIF\000draft-photo' > "$REPO/drafts/ITEM-1-photo.jpg"
printf '\377\330\377\340\000\020JFIF\000misnamed' > "$REPO/blocks/hero/misnamed.png"
printf '<html><body>not an image</body></html>' > "$REPO/blocks/hero/page.jpg"

size() { wc -c < "$REPO/$1" | tr -d ' '; }

# run <args...> — runs the script from the repository root; sets STATUS
run() {
  (cd "$REPO" && python3 "$FLAG" "$@" >"$WORK/stdout" 2>"$WORK/stderr")
  STATUS=$?
}

# has_line <desc> <line>
has_line() {
  if grep -qxF -- "$2" "$WORK/stdout"; then ok "$1"; else bad "$1" "want: $2" "got: $(cat "$WORK/stdout")"; fi
}

# no_match <desc> <pattern>
no_match() {
  if grep -q -- "$2" "$WORK/stdout"; then bad "$1" "found: $(grep -- "$2" "$WORK/stdout")"; else ok "$1"; fi
}

status_is() {
  if [ "$STATUS" -eq "$2" ]; then ok "$1"; else bad "$1" "want exit $2, got $STATUS" "stderr: $(cat "$WORK/stderr")"; fi
}

stdout_empty() {
  if [ -s "$WORK/stdout" ]; then bad "$1" "stdout: $(cat "$WORK/stdout")"; else ok "$1"; fi
}

line_for() {
  printf '[optimise] %s — %s bytes — %s' "$1" "$(size "$1")" "$2"
}

echo "a committed JPEG is flagged with its size, MIME type and report line"
run scan blocks/hero/photo.jpg
status_is "exits 0" 0
has_line "flag row" "flag${TAB}blocks/hero/photo.jpg${TAB}$(size blocks/hero/photo.jpg)${TAB}image/jpeg${TAB}$(line_for blocks/hero/photo.jpg image/jpeg)"

echo "every committed raster format is flagged"
run scan blocks/hero/shot.png blocks/hero/anim.gif blocks/hero/pic.webp
status_is "exits 0" 0
has_line "png flagged" "flag${TAB}blocks/hero/shot.png${TAB}$(size blocks/hero/shot.png)${TAB}image/png${TAB}$(line_for blocks/hero/shot.png image/png)"
has_line "gif flagged" "flag${TAB}blocks/hero/anim.gif${TAB}$(size blocks/hero/anim.gif)${TAB}image/gif${TAB}$(line_for blocks/hero/anim.gif image/gif)"
has_line "webp flagged" "flag${TAB}blocks/hero/pic.webp${TAB}$(size blocks/hero/pic.webp)${TAB}image/webp${TAB}$(line_for blocks/hero/pic.webp image/webp)"

echo "a committed SVG is reported as committed text, never flagged"
run scan icons/cable-icon.svg
status_is "exits 0" 0
has_line "committed row" "committed${TAB}icons/cable-icon.svg${TAB}$(size icons/cable-icon.svg)${TAB}image/svg+xml"
no_match "no flag row" "^flag"

echo "an ignored raster is reported as ignored, never flagged"
run scan drafts/ITEM-1-photo.jpg
status_is "exits 0" 0
has_line "ignored row" "ignored${TAB}drafts/ITEM-1-photo.jpg${TAB}$(size drafts/ITEM-1-photo.jpg)${TAB}image/jpeg"
no_match "no flag row" "^flag"

echo "the MIME type comes from the bytes, never the name"
run scan blocks/hero/misnamed.png
has_line "JPEG bytes named .png flag as image/jpeg" "flag${TAB}blocks/hero/misnamed.png${TAB}$(size blocks/hero/misnamed.png)${TAB}image/jpeg${TAB}$(line_for blocks/hero/misnamed.png image/jpeg)"

echo "rows follow argument order, one per path"
run scan icons/cable-icon.svg drafts/ITEM-1-photo.jpg blocks/hero/photo.jpg
got="$(cut -f1,2 "$WORK/stdout" | tr '\t\n' ' |')"
want="committed icons/cable-icon.svg|ignored drafts/ITEM-1-photo.jpg|flag blocks/hero/photo.jpg|"
if [ "$got" = "$want" ]; then ok "order kept"; else bad "order kept" "want: $want" "got: $got"; fi

echo "a tracked file under an ignored directory is committed, so it is flagged"
printf '\377\330\377\340\000\020JFIF\000forced' > "$REPO/drafts/forced.jpg"
git -C "$REPO" add -f drafts/forced.jpg
run scan drafts/forced.jpg
has_line "force-added raster flagged" "flag${TAB}drafts/forced.jpg${TAB}$(size drafts/forced.jpg)${TAB}image/jpeg${TAB}$(line_for drafts/forced.jpg image/jpeg)"

echo "refusals exit 2 and print nothing on stdout"
run scan
status_is "no path: exits 2" 2
stdout_empty "no path: stdout empty"
run scan blocks/hero/absent.jpg
status_is "missing file: exits 2" 2
stdout_empty "missing file: stdout empty"
run scan blocks/hero/photo.jpg blocks/hero/page.jpg
status_is "not an image: exits 2" 2
stdout_empty "not an image: no partial output"
run scan "$REPO/blocks/hero/photo.jpg"
status_is "absolute path: exits 2" 2
run scan blocks/../blocks/hero/photo.jpg
status_is "parent segment: exits 2" 2
run scan blocks/hero
status_is "directory: exits 2" 2
run nonsense blocks/hero/photo.jpg
status_is "unknown mode: exits 2" 2
OUTSIDE="$WORK/outside"; mkdir -p "$OUTSIDE"
printf '\377\330\377\340\000\020JFIF\000x' > "$OUTSIDE/p.jpg"
(cd "$OUTSIDE" && GIT_CEILING_DIRECTORIES="$WORK" python3 "$FLAG" scan p.jpg >"$WORK/stdout" 2>"$WORK/stderr")
STATUS=$?
status_is "outside a repository: exits 2" 2
stdout_empty "outside a repository: stdout empty"

echo "check passes when the report carries every flag line"
{
  echo "# Prototype report"
  echo
  echo "## Committed binaries"
  echo
  echo "- $(line_for blocks/hero/photo.jpg image/jpeg)"
} > "$REPO/report.md"
git -C "$REPO" add report.md 2>/dev/null
run check report.md blocks/hero/photo.jpg icons/cable-icon.svg drafts/ITEM-1-photo.jpg
status_is "exits 0" 0

echo "check fails, naming the path, when a flag line is missing"
run check report.md blocks/hero/photo.jpg blocks/hero/shot.png
status_is "exits 1" 1
if grep -q "blocks/hero/shot.png" "$WORK/stderr"; then ok "names the unflagged path"; else bad "names the unflagged path" "stderr: $(cat "$WORK/stderr")"; fi

echo "check fails when the line carries a stale size"
printf -- '- [optimise] blocks/hero/photo.jpg — 1 bytes — image/jpeg\n' > "$REPO/stale.md"
run check stale.md blocks/hero/photo.jpg
status_is "exits 1" 1

echo "check needs no line for ignored or SVG files"
printf '# empty\n' > "$REPO/empty.md"
run check empty.md icons/cable-icon.svg drafts/ITEM-1-photo.jpg
status_is "exits 0" 0

echo "check refuses a missing report"
run check absent.md blocks/hero/photo.jpg
status_is "exits 2" 2

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
