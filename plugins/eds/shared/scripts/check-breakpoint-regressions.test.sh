#!/usr/bin/env bash
# Tests for check-breakpoint-regressions.py. Run with:
#   bash plugins/eds/shared/scripts/check-breakpoint-regressions.test.sh
#
# No framework, no browser — exits 0 when every case passes, 1 otherwise.
# Measurements and stylesheets are written per case into a temporary directory.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-breakpoint-regressions.py"
COUNT="$SCRIPT_DIR/count-fixable.sh"

TMP_ROOT="${TMPDIR:-/tmp}"
WORK="$(mktemp -d "${TMP_ROOT%/}/check-breakpoint-regressions.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# run <args...> — sets STATUS, OUT, ERR
run() {
  python3 "$CHECK" "$@" >"$WORK/stdout" 2>"$WORK/stderr"
  STATUS=$?
  OUT="$(cat "$WORK/stdout")"
  ERR="$(cat "$WORK/stderr")"
}

exits() {
  if [ "$STATUS" -eq "$1" ]; then ok "exits $1"; else bad "exits $1" "got: $STATUS" "stdout: $OUT" "stderr: $ERR"; fi
}

same() {
  if [ "$OUT" = "$2" ]; then ok "$1"; else bad "$1" "expected:" "$2" "got:" "$OUT"; fi
}

no_output() {
  if [ -z "$OUT" ]; then ok "prints nothing on stdout"; else bad "prints nothing on stdout" "$OUT"; fi
}

# sel <width> <min-width> <broken-words-json> — one found selector's reading
sel() {
  printf '{"found": true, "geometry": {"x": 0, "y": 0, "width": %s, "height": 96}, "computed": {"color": "rgb(0, 0, 0)", "min-width": "%s"}, "holds_text": true, "broken_words": %s}' \
    "$1" "$2" "$3"
}

# measurement <name> <width> <results-json> — a measurement file
measurement() {
  local file="$WORK/$1.json"
  printf '{"target": "http://localhost:3001/drafts/x", "width": %s, "results": %s}\n' "$2" "$3" > "$file"
  echo "$file"
}

echo "check: a broken word (A) and a box narrower than its own min-width (B)"
M="$(measurement squeezed 375 "{
  \".table\": $(sel 327 0px '["WebSurge", "HyperView", "Ultra-", "WebSurge"]'),
  \".table th\": $(sel 109 200px '["WebSurge"]'),
  \".absent\": {\"found\": false}
}")"
run check "$M"
exits 1
same "one line per selector and signal, in selector order" \
"[fixable] at 375px, .table: 4 words broken across lines (WebSurge, HyperView, Ultra-)
[fixable] at 375px, .table th: 1 word broken across lines (WebSurge)
[fixable] at 375px, .table th: 109px wide, narrower than its own min-width 200px"

echo "check: a selector hidden at this width is not read, whatever its box or its words say"
M="$(measurement hidden 375 "{
  \".table\": $(sel 600 0px '[]'),
  \".nav\": $(sel 0 200px '["Broken"]' | jq -c '. + {hidden: true}')
}")"
run check "$M"
exits 0
no_output

echo "check: quiet when no word is broken and every box meets its min-width"
M="$(measurement fits 375 "{
  \".table\": $(sel 600 0px '[]'),
  \".table th\": $(sel 200 200px '[]'),
  \".auto\": $(sel 10 auto '[]'),
  \".pct\": $(sel 10 50% '[]'),
  \".none\": $(sel 10 none '[]')
}")"
run check "$M"
exits 0
no_output

echo "check: half a pixel under min-width is rounding, not a squeeze"
M1="$(measurement rounding 768 "{\".a\": $(sel 199.6 200px '[]')}")"
M2="$(measurement squeeze 768 "{\".a\": $(sel 199.4 200px '[]')}")"
run check "$M1"
exits 0
run check "$M2"
exits 1
same "a fractional width is printed to one decimal" \
"[fixable] at 768px, .a: 199.4px wide, narrower than its own min-width 200px"

echo "check: more than five distinct words names the first five"
M="$(measurement many 375 "{\".t\": $(sel 300 0px '["a1", "b2", "c3", "d4", "e5", "f6", "a1"]')}")"
run check "$M"
exits 1
same "the count is every occurrence; five words, then an ellipsis" \
"[fixable] at 375px, .t: 7 words broken across lines (a1, b2, c3, d4, e5, …)"

echo "check: several measurements, in the order given"
M1="$(measurement wide 1440 "{\".t\": $(sel 400 200px '[]')}")"
M2="$(measurement narrow 375 "{\".t\": $(sel 109 200px '[]')}")"
run check "$M1" "$M2"
exits 1
same "only the narrow width fires" \
"[fixable] at 375px, .t: 109px wide, narrower than its own min-width 200px"

echo "check: its lines are counted by count-fixable.sh as fixable"
M="$(measurement counted 375 "{
  \".table\": $(sel 327 0px '["WebSurge"]'),
  \".table th\": $(sel 109 200px '[]')
}")"
run check "$M"
printf '[content-dependent] .x height: follows its copy\n%s\n' "$OUT" > "$WORK/check-1.txt"
COUNTED="$(bash "$COUNT" "$WORK/check-1.txt")"
if [ "$COUNTED" = "fixable: fixable=2 gaps=0 approx=1" ]; then
  ok "two fixable lines beside a content-dependent one"
else
  bad "two fixable lines beside a content-dependent one" "got: $COUNTED"
fi

echo "check: refusals"
run check
exits 2
no_output
printf 'not json' > "$WORK/bad.json"
run check "$WORK/bad.json"
exits 2
run check "$WORK/absent.json"
exits 2
M="$(measurement nowidth 375 "{\".t\": $(sel 1 0px '[]')}")"
jq 'del(.width)' "$M" > "$WORK/nowidth2.json"
run check "$WORK/nowidth2.json"
exits 2
if [[ "$ERR" == *"width"* ]]; then ok "names the missing width"; else bad "names the missing width" "$ERR"; fi
jq '.results[".t"] |= del(.broken_words)' "$M" > "$WORK/nobroken.json"
run check "$WORK/nobroken.json"
exits 2
if [[ "$ERR" == *"broken_words"* ]]; then ok "names the missing broken_words"; else bad "names the missing broken_words" "$ERR"; fi
jq '.results[".t"].computed |= del(.["min-width"])' "$M" > "$WORK/nominwidth.json"
run check "$WORK/nominwidth.json"
exits 2
if [[ "$ERR" == *"min-width"* ]]; then ok "names the missing min-width"; else bad "names the missing min-width" "$ERR"; fi

echo "selectors: every selector declaring a min-width that can be broken"
cat > "$WORK/block.css" <<'EOF'
/* .commented { min-width: 10px; } */
.t table th, .t table td { min-width: 200px; }
.t { min-width: auto; }
.t p { min-width: 0; }
.t img { MIN-WIDTH: 50% !important; }
@media (width >= 900px) {
  .t table th { min-width: 240px; }
  .t span { min-width: 3em; }
}
.t a { width: 20px; }
EOF
run selectors "$WORK/block.css"
exits 0
same "once each, in source order, keywords and zero left out" \
".t table th
.t table td
.t img
.t span"

echo "selectors: a stylesheet with none"
printf '.t { color: red; }\n' > "$WORK/plain.css"
run selectors "$WORK/plain.css"
exits 0
no_output

echo "selectors: refusals"
run selectors "$WORK/absent.css"
exits 2
run selectors
exits 2
run frobnicate "$WORK/block.css"
exits 2

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
