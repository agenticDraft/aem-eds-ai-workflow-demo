#!/usr/bin/env bash
# check-size-origin.test.sh — the size-origin check (a fixed width or height on
# an element that holds text comes only from its node's design value). No
# framework; exits 0 when every case passes, 1 otherwise.
#
# Usage:
#   bash check-size-origin.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-size-origin.py"
FIX="$SCRIPT_DIR/fixtures/size-origin"

TMP_ROOT="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "$TMP_ROOT/check-size-origin.XXXXXX") || { echo "mktemp failed" >&2; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "no work dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_eq() { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2 — got: $3"; fi; }

# run <args...> — runs the check, keeps stdout, stderr and the exit code
run() {
  OUT=$(python3 "$CHECK" "$@" 2>"$WORK/err"); CODE=$?
  ERR=$(cat "$WORK/err")
}

# hits — the `hit` lines of the last run, one per line
hits() { printf '%s\n' "$OUT" | grep '^hit' || true; }

T=$'\t'

# A small report and table: node 9:1 carries height 96px and width 120px.
cat > "$WORK/report.md" <<'EOF'
# Prototype report

## Design values

.b th — height — 96px — source: design_context — token: none — node: 9:1
.b .card — width — 120px — source: design_context — token: none — node: 9:1
.b .one, .b .two — height — 96px — source: design_context — token: none — node: 9:1
.b .derived — height — 16px — source: design_context — token: none — node: 9:1

## Assets
EOF
printf '9:1\theight\t96px\ttrue\n9:1\twidth\t120px\tfalse\n' > "$WORK/values.tsv"

# measure <file> <selector=holds_text>... — writes a measurement file
measure() {
  local file="$1"; shift
  local first=1
  { printf '{"results": {'
    for pair in "$@"; do
      [ $first -eq 1 ] || printf ','
      first=0
      printf '"%s": {"found": true, "geometry": {"x": 0, "y": 0, "width": 50, "height": 20}, "computed": {}, "holds_text": %s}' "${pair%=*}" "${pair##*=}"
    done
    printf '}}'
  } > "$file"
}

echo "[eds-18] measured: exactly the 16 px line is reported"
run check "$FIX/eds-18.css" "$FIX/eds-18-report.md" "$FIX/eds-18-values.tsv" "$FIX/eds-18-measure.json"
assert_eq "exit 1" "1" "$CODE"
assert_eq "one hit, th p height 16px" \
  "hit${T}.table.comparison table th p${T}height${T}16px${T}no report line ties it to a node" "$(hits)"

echo "[eds-18] measured: th { height: 96px } on node 1:197 is not reported"
printf '%s\n' "$OUT" | grep -q "^hit${T}.table.comparison table th${T}" \
  && bad "th 96px reported" "$OUT" || ok "th 96px not a hit"

echo "[eds-18] measured: the grown header is listed, not a hit"
assert_eq "grown line" \
  "grown${T}.table.comparison table th${T}height${T}design 96px, measured 98px" \
  "$(printf '%s\n' "$OUT" | grep '^grown')"

echo "[eds-18] measured: the icon holds no text, so its 14 px is not reported"
printf '%s\n' "$OUT" | grep -q "td .icon" && bad "icon reported" "$OUT" || ok "icon not reported"

echo "[eds-18] measured: min-width 200px is never reported"
printf '%s\n' "$OUT" | grep -q "min-width" && bad "min-width reported" "$OUT" || ok "min-width not reported"

echo "[eds-18] strict (no measurement): every untied fixed size is a hit"
run check "$FIX/eds-18.css" "$FIX/eds-18-report.md" "$FIX/eds-18-values.tsv"
assert_eq "exit 1" "1" "$CODE"
assert_eq "three hits: 16px and the icon's two sizes" \
  "hit${T}.table.comparison table th p${T}height${T}16px${T}no report line ties it to a node
hit${T}.table.comparison table td .icon${T}width${T}14px${T}no report line ties it to a node
hit${T}.table.comparison table td .icon${T}height${T}14px${T}no report line ties it to a node" "$(hits)"
printf '%s\n' "$OUT" | grep -q '^grown' && bad "grown without a measurement" "$OUT" || ok "no grown line without a measurement"

echo "[eds-18] selectors: every selector carrying a fixed width or height, once"
run selectors "$FIX/eds-18.css"
assert_eq "exit 0" "0" "$CODE"
assert_eq "three selectors" ".table.comparison table th
.table.comparison table th p
.table.comparison table td .icon" "$OUT"

echo "[min] a min-height, max-width or min-width is never reported, in either mode"
printf '.b p { min-height: 16px; max-width: 40px; min-width: 3px; max-height: 9px; }\n' > "$WORK/min.css"
measure "$WORK/min.json" ".b p=true"
run check "$WORK/min.css" "$WORK/report.md" "$WORK/values.tsv" "$WORK/min.json"
assert_eq "measured exit 0" "0" "$CODE"
assert_eq "measured no output" "" "$OUT"
run check "$WORK/min.css" "$WORK/report.md" "$WORK/values.tsv"
assert_eq "strict exit 0" "0" "$CODE"
assert_eq "strict no output" "" "$OUT"
run selectors "$WORK/min.css"
assert_eq "no selectors" "" "$OUT"

echo "[forms] auto, a percentage and content keywords are not fixed sizes"
printf '.b p { width: auto; height: 50%%; width: fit-content; height: max-content; width: calc(100%% - 8px); }\n' > "$WORK/forms.css"
run check "$WORK/forms.css" "$WORK/report.md" "$WORK/values.tsv"
assert_eq "exit 0" "0" "$CODE"
assert_eq "no output" "" "$OUT"

echo "[derived] a value not on the node is refused, however it was reached"
printf '.b .derived { height: 16px; }\n.b th { height: 80px; }\n.b .calc { height: calc(96px - 80px); }\n' > "$WORK/derived.css"
run check "$WORK/derived.css" "$WORK/report.md" "$WORK/values.tsv"
assert_eq "exit 1" "1" "$CODE"
assert_eq "three hits" \
  "hit${T}.b .derived${T}height${T}16px${T}node 9:1 has no height 16px row
hit${T}.b th${T}height${T}80px${T}node 9:1 has no height 80px row
hit${T}.b .calc${T}height${T}calc(96px - 80px)${T}no report line ties it to a node" "$(hits)"

echo "[tied] a value on its node passes, in either unit spelling"
printf '.b th { height: 96px; }\n.b .card { width: 120.0px !important; }\n' > "$WORK/tied.css"
run check "$WORK/tied.css" "$WORK/report.md" "$WORK/values.tsv"
assert_eq "exit 0" "0" "$CODE"
assert_eq "no hits" "" "$(hits)"

echo "[property] a report line for another property does not tie a size"
printf '.b .card { height: 120px; }\n' > "$WORK/prop.css"
run check "$WORK/prop.css" "$WORK/report.md" "$WORK/values.tsv"
assert_eq "hit" "hit${T}.b .card${T}height${T}120px${T}no report line ties it to a node" "$(hits)"

echo "[lists] a selector list is split, and each selector needs its own tie"
printf '.b .one, .b .three { height: 96px; }\n.b  .two { height: 96px; }\n' > "$WORK/lists.css"
run check "$WORK/lists.css" "$WORK/report.md" "$WORK/values.tsv"
assert_eq "exit 1" "1" "$CODE"
assert_eq "only .three" "hit${T}.b .three${T}height${T}96px${T}no report line ties it to a node" "$(hits)"
run selectors "$WORK/lists.css"
assert_eq "selectors split and whitespace collapsed" ".b .one
.b .three
.b .two" "$OUT"

echo "[at-rules] a rule inside @media is read; @keyframes and @font-face are not"
cat > "$WORK/at.css" <<'EOF'
/* a comment with { braces } and height: 5px */
@media (width >= 900px) {
  .b .wide { width: 300px; }
}
@keyframes grow { from { height: 1px; } to { height: 10px; } }
@font-face { font-family: x; src: url("a{b}.woff2"); }
.b .q::before { content: "height: 7px; }"; }
EOF
run check "$WORK/at.css" "$WORK/report.md" "$WORK/values.tsv"
assert_eq "exit 1" "1" "$CODE"
assert_eq "only the @media rule" "hit${T}.b .wide${T}width${T}300px${T}no report line ties it to a node" "$(hits)"

echo "[text] measured: only a selector whose elements hold text can be a hit"
printf '.b .img { width: 30px; }\n.b .txt { width: 30px; }\n.b .gone { width: 30px; }\n' > "$WORK/text.css"
printf '{"results": {".b .img": {"found": true, "geometry": {"x":0,"y":0,"width":30,"height":30}, "computed": {}, "holds_text": false}, ".b .txt": {"found": true, "geometry": {"x":0,"y":0,"width":30,"height":30}, "computed": {}, "holds_text": true}, ".b .gone": {"found": false}}}' > "$WORK/text.json"
run check "$WORK/text.css" "$WORK/report.md" "$WORK/values.tsv" "$WORK/text.json"
assert_eq "exit 1" "1" "$CODE"
assert_eq "only .txt" "hit${T}.b .txt${T}width${T}30px${T}no report line ties it to a node" "$(hits)"

echo "[text] measured: a selector hidden at this width is never a hit, even holding text"
printf '{"results": {".b .img": {"found": true, "geometry": {"x":0,"y":0,"width":30,"height":30}, "computed": {}, "holds_text": false}, ".b .txt": {"found": true, "hidden": true, "geometry": {"x":0,"y":0,"width":0,"height":0}, "computed": {}, "holds_text": true}, ".b .gone": {"found": false}}}' > "$WORK/hidden.json"
run check "$WORK/text.css" "$WORK/report.md" "$WORK/values.tsv" "$WORK/hidden.json"
assert_eq "exit 0" "0" "$CODE"
assert_eq "no hit" "" "$(hits)"

echo "[text] measured: a selector the measurement does not carry counts as holding text"
measure "$WORK/partial.json" ".b .img=false"
run check "$WORK/text.css" "$WORK/report.md" "$WORK/values.tsv" "$WORK/partial.json"
assert_eq "exit 1" "1" "$CODE"
assert_eq ".txt reported as not measured" \
  "hit${T}.b .txt${T}width${T}30px${T}no report line ties it to a node (not measured)" \
  "$(hits | grep '\.txt')"

echo "[grown] measured: a tied size is listed only when the box is larger"
printf '.b th { height: 96px; }\n' > "$WORK/fit.css"
printf '{"results": {".b th": {"found": true, "geometry": {"x":0,"y":0,"width":10,"height":96}, "computed": {}, "holds_text": true}}}' > "$WORK/fit.json"
run check "$WORK/fit.css" "$WORK/report.md" "$WORK/values.tsv" "$WORK/fit.json"
assert_eq "exit 0" "0" "$CODE"
assert_eq "no output at the design's size" "" "$OUT"

echo "[no table] - means no value table: every fixed size is untied"
run check "$WORK/tied.css" "$WORK/report.md" -
assert_eq "exit 1" "1" "$CODE"
assert_eq "two hits" "2" "$(hits | grep -c 'has no\|no report line')"

echo "[usage] malformed inputs exit 2"
run check "$WORK/nope.css" "$WORK/report.md" "$WORK/values.tsv"
assert_eq "missing css → 2" "2" "$CODE"
run check "$WORK/tied.css" "$WORK/report.md"
assert_eq "missing table → 2" "2" "$CODE"
printf '{"results": {".b th": {"found": true, "geometry": {"x":0,"y":0,"width":1,"height":1}, "computed": {}}}}' > "$WORK/old.json"
run check "$WORK/tied.css" "$WORK/report.md" "$WORK/values.tsv" "$WORK/old.json"
assert_eq "found result without holds_text → 2" "2" "$CODE"
assert_eq "names holds_text" "1" "$(printf '%s' "$ERR" | grep -c 'holds_text')"
printf '.b p { height: 16px;\n' > "$WORK/open.css"
run check "$WORK/open.css" "$WORK/report.md" "$WORK/values.tsv"
assert_eq "unclosed block → 2" "2" "$CODE"
printf '.b { .c { height: 16px; } }\n' > "$WORK/nested.css"
run check "$WORK/nested.css" "$WORK/report.md" "$WORK/values.tsv"
assert_eq "nested rule → 2" "2" "$CODE"
run
assert_eq "no arguments → 2" "2" "$CODE"

# --- --base: only what the run added or changed (G162, D548) ---------------

REPO="$WORK/repo"
mkdir -p "$REPO/blocks/fc"
git -C "$REPO" init -q -b main . && git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t \
  || { echo "git init failed" >&2; exit 1; }
FCSS="$REPO/blocks/fc/fc.css"
cat > "$FCSS" <<'EOF'
.fc .content ol li::before { flex: none; width: 2em; }
.fc .content img { width: 100%; }
EOF
git -C "$REPO" add -A && git -C "$REPO" commit -qm base
git -C "$REPO" switch -qc run
cat > "$WORK/fc-report.md" <<'EOF'
# Prototype report

## Design values

.fc .content img — height — 711px — source: design_context — token: none — node: 1:187
EOF
printf '1:187\theight\t711px\ttrue\n' > "$WORK/fc-values.tsv"
CHECK_BASE=(check "$FCSS" "$WORK/fc-report.md" "$WORK/fc-values.tsv" --base main)

echo "[base] without --base the pre-existing 2em is a hit (the unchanged strict form)"
run check "$FCSS" "$WORK/fc-report.md" "$WORK/fc-values.tsv"
assert_eq "exit 1" "1" "$CODE"
assert_eq "the 2em hit" "hit${T}.fc .content ol li::before${T}width${T}2em${T}no report line ties it to a node" "$(hits)"

echo "[base] nothing changed since the base: exit 0, however many untied sizes the file already had"
run "${CHECK_BASE[@]}"
assert_eq "exit 0" "0" "$CODE"
assert_eq "no output" "" "$OUT"

echo "[base] the run adds a tied height; the pre-existing untied 2em is not reported"
printf '.fc .content img { width: 100%%; height: 711px; }\n' >> "$FCSS"
sed -i.bak 's/^\.fc \.content img { width: 100%; }$//' "$FCSS" && rm -f "$FCSS.bak"
run "${CHECK_BASE[@]}"
assert_eq "exit 0" "0" "$CODE"
assert_eq "no output" "" "$OUT"

echo "[base] the run adds an untied fixed width: only that one is a hit"
printf '.fc .badge { width: 40px; }\n' >> "$FCSS"
run "${CHECK_BASE[@]}"
assert_eq "exit 1" "1" "$CODE"
assert_eq "one hit, the new width" "hit${T}.fc .badge${T}width${T}40px${T}no report line ties it to a node" "$(hits)"

echo "[base] a commit on the run's branch does not hide the run's own change"
git -C "$REPO" commit -qam "run work"
run "${CHECK_BASE[@]}"
assert_eq "exit 1" "1" "$CODE"
assert_eq "still the new width" "hit${T}.fc .badge${T}width${T}40px${T}no report line ties it to a node" "$(hits)"
run check "$FCSS" "$WORK/fc-report.md" "$WORK/fc-values.tsv" --base HEAD
assert_eq "a base of HEAD itself sees nothing (why HEAD is not the base)" "0" "$CODE"

echo "[base] the run edits a pre-existing untied size: it is a hit"
git -C "$REPO" switch -q main && git -C "$REPO" switch -qc run2
sed -i.bak 's/width: 2em/width: 3em/' "$FCSS" && rm -f "$FCSS.bak"
run "${CHECK_BASE[@]}"
assert_eq "exit 1" "1" "$CODE"
assert_eq "the edited 3em" "hit${T}.fc .content ol li::before${T}width${T}3em${T}no report line ties it to a node" "$(hits)"

echo "[base] a block file the base does not have: every fixed size is the run's"
mkdir -p "$REPO/blocks/new"
printf '.n a { width: 5px; }\n' > "$REPO/blocks/new/new.css"
run check "$REPO/blocks/new/new.css" "$WORK/fc-report.md" "$WORK/fc-values.tsv" --base main
assert_eq "exit 1" "1" "$CODE"
assert_eq "the 5px hit" "hit${T}.n a${T}width${T}5px${T}no report line ties it to a node" "$(hits)"

echo "[base] an unknown base, or --base without a value, exits 2"
run check "$FCSS" "$WORK/fc-report.md" "$WORK/fc-values.tsv" --base no-such-rev
assert_eq "unknown rev → 2" "2" "$CODE"
run check "$FCSS" "$WORK/fc-report.md" "$WORK/fc-values.tsv" --base
assert_eq "no value → 2" "2" "$CODE"

echo ""
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
