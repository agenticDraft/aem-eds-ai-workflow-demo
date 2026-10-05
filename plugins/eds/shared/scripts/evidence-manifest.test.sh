#!/usr/bin/env bash
# Tests for evidence-manifest.py. Run with:
#   bash plugins/eds/shared/scripts/evidence-manifest.test.sh
#
# No framework, no browser — exits 0 when every case passes, 1 otherwise.
# The EDS-24 run's real comparison outputs and verify-design manifest are the
# main fixtures (fixtures/evidence-manifest/); synthetic cases cover the rules
# one at a time.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EM="$SCRIPT_DIR/evidence-manifest.py"
FIX="$SCRIPT_DIR/fixtures/evidence-manifest"
VALIDATE="$SCRIPT_DIR/../../../agentic-core/shared/lib/validate-evidence-manifest.sh"

TMP_ROOT="${TMPDIR:-/tmp}"
WORK="$(mktemp -d "${TMP_ROOT%/}/evidence-manifest.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
TAB="$(printf '\t')"

ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# run <args...> — sets STATUS, OUT, ERR
run() {
  python3 "$EM" "$@" >"$WORK/stdout" 2>"$WORK/stderr"
  STATUS=$?
  OUT="$(cat "$WORK/stdout")"
  ERR="$(cat "$WORK/stderr")"
}
exits() { if [ "$STATUS" -eq "$1" ]; then ok "exits $1"; else bad "exits $1" "got: $STATUS" "stdout: $OUT" "stderr: $ERR"; fi; }
same()  { if [ "$OUT" = "$2" ]; then ok "$1"; else bad "$1" "expected:" "$2" "got:" "$OUT"; fi; }
has_line() { if printf '%s\n' "$OUT" | grep -qxF -- "$2"; then ok "$1"; else bad "$1" "want: $2" "got:" "$OUT"; fi; }
no_line_matching() { if printf '%s\n' "$OUT" | grep -qE -- "$2"; then bad "$1" "found: $(printf '%s\n' "$OUT" | grep -E -- "$2")"; else ok "$1"; fi; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: $2" "got: $3"; fi; }

# ---------------------------------------------------------------- gaps ----

echo "gaps: the check file — content-asset and content-dependent entries become gaps, fixable lines do not"
printf '%s\n' \
  '[fixable] at 375px, .table: 42 words broken across lines (WebSurge, HyperView)' \
  '[content-asset gap] 1440 vs the reference: text geometry, with DM Sans not declared' \
  '[content-dependent] .t th height: expected 96px, measured box 400x96px' \
  '[content-dependent] .t th height: expected 96px, measured box 400x96px' \
  '[content-dependent] .t th height: expected 96px, measured box 400x96px' \
  '[content-asset gap] 375 vs Mobile (2:2): the hero photo is a placeholder' > "$WORK/check.txt"
run gaps --check "$WORK/check.txt"
exits 0
same "one gap per distinct entry, in order, identical entries collapsed with a count" \
"content-asset gap: 1440 vs the reference: text geometry, with DM Sans not declared
content-dependent, not graded: .t th height: expected 96px, measured box 400x96px (×3)
content-asset gap: 375 vs Mobile (2:2): the hero photo is a placeholder"

echo "gaps: variables output — an unmeasured line names its variable, selector and property; repeats collapse"
{
  for _ in 1 2 3; do printf 'unmeasured\tDividers/Divider 1\t.t td\tborder-color\t#E9E9E9: not in measure'"'"'s property set\n'; done
  printf 'match\tAccent/Accent 4\t.t td p\tcolor\t#000000\n'
  printf 'mismatch\tText/Headline\t.t th p\tcolor\texpected #000000, measured rgb(19, 19, 19)\n'
  printf 'unmeasured\t-\t.t td p\tfont-family\t'"'"'Roboto Mono'"'"', monospace: no variable matches this line\n'
  printf 'unmeasured\tDividers/Divider 1\t.t th:first-child\tborder-color\t#E9E9E9: not in measure'"'"'s property set\n'
  printf 'unmeasured\tAccent/Accent 1\t-\t-\t#485C11: no design-values line carries its token\n'
} > "$WORK/variables.txt"
run gaps --variables "$WORK/variables.txt"
exits 0
same "variables gaps" \
"design variable 'Dividers/Divider 1' (border-color on .t td) was judged visually only, not confirmed numerically: #E9E9E9: not in measure's property set (×3)
design value for font-family on .t td p matches no design variable, so it was judged visually only: 'Roboto Mono', monospace: no variable matches this line
design variable 'Dividers/Divider 1' (border-color on .t th:first-child) was judged visually only, not confirmed numerically: #E9E9E9: not in measure's property set
design variable 'Accent/Accent 1' was judged visually only, not confirmed numerically: #485C11: no design-values line carries its token"

echo "gaps: compare output — an unmeasured line names its nodes, grouped; approx lines are content-dependent with their nodes"
{
  printf 'unmeasured\t1:196\t-\tborder-width\t1px: not in measure'"'"'s property set\n'
  printf 'unmeasured\t1:197\t-\tborder-width\t1px: not in measure'"'"'s property set\n'
  printf 'match\t1:217\t.t td\tpadding-left\t30px\n'
  printf 'unmeasured\t1:198\t.t th p\tline-height\t1.2: not comparable to the computed value\n'
  printf 'unmeasured\t1:196\t-\tborder-width\t1px: not in measure'"'"'s property set\n'
  printf 'approx\t1:197\t.t th\theight\texpected 96px, measured box 400x96px\n'
  printf 'approx\t1:206\t.t th\theight\texpected 96px, measured box 400x96px\n'
  printf 'approx\t7:7\t-\twidth\t50px: no selector recorded for this node\n'
} > "$WORK/compare.txt"
run gaps --compare "$WORK/compare.txt"
exits 0
same "compare gaps" \
"design value 'border-width 1px' on nodes 1:196, 1:197 was judged visually only: not in measure's property set
design value 'line-height 1.2' on node 1:198 was judged visually only: not comparable to the computed value
content-dependent, not graded: .t th height: expected 96px, measured box 400x96px (nodes 1:197, 1:206)
content-dependent, not graded: width 50px on node 7:7: no selector recorded for this node"

echo "gaps: the three inputs together, check file first, then variables, then compare; nothing twice"
printf 'unmeasured\t1:196\t-\tborder-width\t1px: not in measure'"'"'s property set\n' > "$WORK/compare-b.txt"
run gaps --check "$WORK/check.txt" --variables "$WORK/variables.txt" --compare "$WORK/compare-b.txt"
exits 0
eq "line count" "8" "$(printf '%s\n' "$OUT" | grep -c .)"
eq "first line is the check file's" "content-asset gap: 1440 vs the reference: text geometry, with DM Sans not declared" "$(printf '%s\n' "$OUT" | head -1)"
eq "last line is the compare file's" "design value 'border-width 1px' on node 1:196 was judged visually only: not in measure's property set" "$(printf '%s\n' "$OUT" | tail -1)"

echo "gaps: an empty input prints nothing; an absent file or a malformed line is a usage error"
: > "$WORK/empty.txt"
run gaps --check "$WORK/empty.txt" --variables "$WORK/empty.txt" --compare "$WORK/empty.txt"
exits 0
same "nothing" ""
run gaps --check "$WORK/absent.txt"
exits 2
printf 'unmeasured\tonly-two\n' > "$WORK/short.txt"
run gaps --variables "$WORK/short.txt"
exits 2
if [[ "$ERR" == *"short.txt"* ]]; then ok "names the malformed file"; else bad "names the malformed file" "$ERR"; fi
run gaps
exits 2

echo "gaps: the EDS-24 run's real outputs — no line twice, 27 Dividers/Divider 1 lines become 5, 3 th-height lines become 1"
run gaps --check "$FIX/eds-24-check-2.txt" --variables "$FIX/eds-24-variables-2.txt" --compare "$FIX/eds-24-compare-2.txt"
exits 0
eq "no duplicate line" "$(printf '%s\n' "$OUT" | grep -c .)" "$(printf '%s\n' "$OUT" | grep . | sort -u | wc -l | tr -d ' ')"
eq "one Dividers/Divider 1 line per carrier selector" "5" "$(printf '%s\n' "$OUT" | grep -c "design variable 'Dividers/Divider 1'")"
has_line "the td carrier line carries its count" \
  "design variable 'Dividers/Divider 1' (border-color on .table.comparison table td) was judged visually only, not confirmed numerically: #E9E9E9: not in measure's property set (×18)"
has_line "the th height line names its three nodes" \
  "content-dependent, not graded: .table.comparison table th height: expected 96px, measured box 400x96px (nodes 1:197, 1:206, 1:215)"
has_line "the content-asset gap is carried verbatim" \
  "content-asset gap: 1440 vs the reference: text geometry of the three headings and every data cell (glyph shapes, where text sits in its box), with Roboto Mono, DM Sans, Rethink Sans, Reddit Mono not declared"
no_line_matching "no line names a bare '-' variable" "design variable '-'"

# --------------------------------------------------------------- merge ----

# attachments <file> <json-array> ; gapsfile <file> <lines...>
attachments() { printf '%s' "$2" > "$1"; }
gapsfile() { local f="$1"; shift; : > "$f"; for l in "$@"; do printf '%s\n' "$l" >> "$f"; done; }

echo "merge: an absent manifest is created with the given fields, gaps and attachments, and validates"
M="$WORK/absent/evidence-manifest.json"
mkdir -p "$WORK/absent"
gapsfile "$WORK/g1.txt" "gap a" "gap b"
attachments "$WORK/a1.json" '[{"path":"shots/375.png","width":375,"label":"mobile width"}]'
run merge "$M" --item-id EDS-24 --target http://localhost:3001/drafts/EDS-24 --target-reachable false \
  --reason "loopback address" --gaps "$WORK/g1.txt" --attachments "$WORK/a1.json"
exits 0
same "reports what it wrote" "written: $M gaps=2 (+2 new, 0 duplicate dropped) attachments=1 (+1 new, 0 duplicate dropped)"
eq "version" '"1.0"' "$(jq -c .version "$M")"
eq "item_id" '"EDS-24"' "$(jq -c .item_id "$M")"
eq "target_reachable is a boolean" 'false' "$(jq -c .target_reachable "$M")"
eq "reason" '"loopback address"' "$(jq -c .target_reachable_reason "$M")"
eq "gaps in order" '["gap a","gap b"]' "$(jq -c .coverage_gaps "$M")"
eq "attachments" '[{"path":"shots/375.png","width":375,"label":"mobile width"}]' "$(jq -c .attachments "$M")"
eq "validator accepts it" "valid: evidence manifest (1 attachments, 2 coverage gaps)" "$(bash "$VALIDATE" "$M" 2>&1)"

echo "merge: an existing manifest is merged — union, first occurrence kept, order kept, later writer's fields win"
gapsfile "$WORK/g2.txt" "gap b" "gap c" "gap a" "gap d"
attachments "$WORK/a2.json" '[{"path":"shots/375.png","width":375,"label":"design comparison at 375"},{"path":"shots/1440.png","width":1440,"label":"desktop width"}]'
run merge "$M" --item-id EDS-24 --target http://localhost:3000/drafts/EDS-24 --target-reachable true \
  --reason "loaded through the browser role, HTTP 200" --gaps "$WORK/g2.txt" --attachments "$WORK/a2.json"
exits 0
same "reports the union" "written: $M gaps=4 (+2 new, 2 duplicate dropped) attachments=2 (+1 new, 1 duplicate dropped)"
eq "gaps: existing first, new appended once each" '["gap a","gap b","gap c","gap d"]' "$(jq -c .coverage_gaps "$M")"
eq "attachments: same path kept once, the first label wins" \
  '[{"path":"shots/375.png","width":375,"label":"mobile width"},{"path":"shots/1440.png","width":1440,"label":"desktop width"}]' \
  "$(jq -c .attachments "$M")"
eq "the later writer's target wins" '"http://localhost:3000/drafts/EDS-24"' "$(jq -c .target "$M")"
eq "the later writer's reachability wins" 'true' "$(jq -c .target_reachable "$M")"
eq "exactly the seven keys" '["attachments","coverage_gaps","item_id","target","target_reachable","target_reachable_reason","version"]' "$(jq -c 'keys' "$M")"
eq "validator accepts it" "valid: evidence manifest (2 attachments, 4 coverage gaps)" "$(bash "$VALIDATE" "$M" 2>&1)"

echo "merge: a gaps file with blank lines and an empty attachments list"
printf 'gap x\n\n  \ngap x\n' > "$WORK/g3.txt"
attachments "$WORK/a3.json" '[]'
M3="$WORK/three.json"
run merge "$M3" --item-id X --target http://h/ --target-reachable false --reason r --gaps "$WORK/g3.txt" --attachments "$WORK/a3.json"
exits 0
eq "blank lines ignored, repeat dropped" '["gap x"]' "$(jq -c .coverage_gaps "$M3")"
eq "empty attachments is the literal []" '[]' "$(jq -c .attachments "$M3")"
: > "$WORK/g4.txt"
M4="$WORK/four.json"
run merge "$M4" --item-id X --target http://h/ --target-reachable false --reason r --gaps "$WORK/g4.txt" --attachments "$WORK/a3.json"
exits 0
eq "an empty gaps file is the literal []" '[]' "$(jq -c .coverage_gaps "$M4")"

echo "merge: an existing manifest that already repeats a gap comes out unique"
M5="$WORK/five.json"
printf '{"version":"1.0","item_id":"X","target":"t","target_reachable":false,"target_reachable_reason":"r","coverage_gaps":["p","q","p"],"attachments":[]}' > "$M5"
run merge "$M5" --item-id X --target t --target-reachable false --reason r --gaps "$WORK/g4.txt" --attachments "$WORK/a3.json"
exits 0
eq "the existing repeat is dropped too" '["p","q"]' "$(jq -c .coverage_gaps "$M5")"
same "the dropped existing repeat is counted" "written: $M5 gaps=2 (+0 new, 1 duplicate dropped) attachments=0 (+0 new, 0 duplicate dropped)"

echo "merge: refusals exit 2 and write nothing"
M6="$WORK/six.json"
run merge "$M6" --item-id X --target t --target-reachable maybe --reason r --gaps "$WORK/g4.txt" --attachments "$WORK/a3.json"
exits 2
[ ! -e "$M6" ] && ok "nothing written on a bad --target-reachable" || bad "nothing written on a bad --target-reachable"
attachments "$WORK/bad-a.json" '[{"path":"x.png","label":"no width"}]'
run merge "$M6" --item-id X --target t --target-reachable false --reason r --gaps "$WORK/g4.txt" --attachments "$WORK/bad-a.json"
exits 2
if [[ "$ERR" == *"width"* ]]; then ok "names the missing attachment field"; else bad "names the missing attachment field" "$ERR"; fi
run merge "$M6" --item-id X --target t --target-reachable false --reason r --gaps "$WORK/absent.txt" --attachments "$WORK/a3.json"
exits 2
printf 'not json' > "$WORK/broken.json"
run merge "$WORK/broken.json" --item-id X --target t --target-reachable false --reason r --gaps "$WORK/g4.txt" --attachments "$WORK/a3.json"
exits 2
eq "a broken existing manifest is left alone" "not json" "$(cat "$WORK/broken.json")"
run merge "$M6" --item-id X --target t --target-reachable false --reason r --gaps "$WORK/g4.txt"
exits 2
run merge "$M6" --item-id "" --target t --target-reachable false --reason r --gaps "$WORK/g4.txt" --attachments "$WORK/a3.json"
exits 2
run frobnicate
exits 2

echo "merge: the EDS-24 run — verify-design's manifest (214 gaps, 184 unique) plus verify's three"
M7="$WORK/eds-24.json"
cp "$FIX/eds-24-verify-design-manifest.json" "$M7"
attachments "$WORK/a7.json" '[{"path":".ai/playwright/capture-localhost-3001-drafts-EDS-24-375-4.png","width":375,"label":"mobile width"},{"path":".ai/playwright/capture-localhost-3001-drafts-EDS-24-768-4.png","width":768,"label":"tablet width"},{"path":".ai/playwright/capture-localhost-3001-drafts-EDS-24-1440-6.png","width":1440,"label":"desktop width"}]'
run merge "$M7" --item-id EDS-24 --target http://localhost:3001/drafts/EDS-24 --target-reachable false \
  --reason "loopback address — condition 1 of the reachability rule, decided with no network call" \
  --gaps "$FIX/eds-24-verify-gaps.txt" --attachments "$WORK/a7.json"
exits 0
eq "every gap once" "true" "$(jq '.coverage_gaps | length == (unique | length)' "$M7")"
eq "184 unique from verify-design plus 3 from verify" "187" "$(jq '.coverage_gaps | length' "$M7")"
eq "verify-design's first gap stays first" "$(jq -r '.coverage_gaps[0]' "$FIX/eds-24-verify-design-manifest.json")" "$(jq -r '.coverage_gaps[0]' "$M7")"
eq "verify's three come last, in order" "$(cat "$FIX/eds-24-verify-gaps.txt")" "$(jq -r '.coverage_gaps[184:][]' "$M7")"
eq "attachments 6 + 3" "9" "$(jq '.attachments | length' "$M7")"
eq "validator accepts it" "valid: evidence manifest (9 attachments, 187 coverage gaps)" "$(bash "$VALIDATE" "$M7" 2>&1)"

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
