#!/usr/bin/env bash
# delivery-text.test.sh — the "Verified locally" block, the short tracker note
# and the delivery report's evidence section (D535, G535). No framework; exits
# 0 when every case passes, 1 otherwise. EDS-18's real manifest and check
# result are the main fixture (fixtures/delivery-text/).
#
# Usage:
#   bash delivery-text.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEXT="$SCRIPT_DIR/delivery-text.py"
FIX="$SCRIPT_DIR/fixtures/delivery-text"
MANIFEST="$FIX/eds-18-evidence-manifest.json"
CHECKS="$FIX/eds-18-check-status.json"
PR="https://github.com/agenticDraft/aem-eds-ai-workflow-demo/pull/170"

PASS=0
FAIL=0

ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_eq()    { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2 — got: $3"; fi; }
assert_has()   { if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "expected to contain: $2 — got: $3"; fi; }
assert_lacks() { if [[ "$3" != *"$2"* ]]; then ok "$1"; else bad "$1" "expected not to contain: $2"; fi; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/delivery-text.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# config <serve> [preview] — a project config with that serve command
config() {
  printf 'version: 1\n\ncommands:\n  lint: "npm run lint"\n  serve: "%s"\n\npaths:\n  preview: "%s"\n' \
    "$1" "${2:-http://localhost:3000/preview}" > "$WORK/config.yaml"
}
# package <json-scripts-object> — a package.json with those scripts
package() { printf '{"name":"x","scripts":%s}\n' "$1" > "$WORK/package.json"; }

config "npm run up"
package '{"up":"aem up","up:draft":"aem up --html-folder drafts"}'
COMMON=(--config "$WORK/config.yaml" --package "$WORK/package.json")

run() { OUT=$(python3 "$TEXT" "$@" 2>"$WORK/err"); CODE=$?; ERR=$(cat "$WORK/err"); }

echo "[block] EDS-18: target, local-only line naming the branch, restart command"
run block --manifest "$MANIFEST" --branch eds-18 "${COMMON[@]}"
BLOCK="$OUT"
assert_eq "exit 0" "0" "$CODE"
EXPECTED=$'## Verified locally\nTarget: http://localhost:3001/drafts/EDS-18\nLocal only: answers while the draft server runs and branch eds-18 is checked out.\nRestart: npm run up:draft -- --port 3001'
assert_eq "the exact block" "$EXPECTED" "$BLOCK"

echo "[block] no up:draft → commands.serve with --html-folder drafts and the port appended"
package '{"up":"aem up"}'
run block --manifest "$MANIFEST" --branch eds-18 "${COMMON[@]}"
assert_has "npm run command gets --" "Restart: npm run up -- --html-folder drafts --port 3001" "$OUT"
config "aem up --no-open"
run block --manifest "$MANIFEST" --branch eds-18 "${COMMON[@]}"
assert_has "a non-npm command is appended directly" "Restart: aem up --no-open --html-folder drafts --port 3001" "$OUT"
config "npm run up -- --no-open"
run block --manifest "$MANIFEST" --branch eds-18 "${COMMON[@]}"
assert_has "an existing -- is not doubled" "Restart: npm run up -- --no-open --html-folder drafts --port 3001" "$OUT"
config "npm run up" "http://localhost:4500/preview"
package '{"up:draft":"aem up --html-folder drafts"}'
run block --manifest "$MANIFEST" --branch eds-18 "${COMMON[@]}"
assert_has "port is the preview's plus one" "Restart: npm run up:draft -- --port 4501" "$OUT"
config "npm run up" "http://localhost/preview"
run block --manifest "$MANIFEST" --branch eds-18 "${COMMON[@]}"
assert_has "no preview port → 3000 + 1, as start-draft-server.sh" "--port 3001" "$OUT"
config ""
package '{}'
run block --manifest "$MANIFEST" --branch eds-18 "${COMMON[@]}"
assert_has "no serve command and no up:draft" "Restart: no serve command is configured" "$OUT"
rm -f "$WORK/package.json"
config "npm run up"
run block --manifest "$MANIFEST" --branch eds-18 "${COMMON[@]}"
assert_has "no package.json → commands.serve path" "Restart: npm run up -- --html-folder drafts --port 3001" "$OUT"
config "npm run up"
package '{"up":"aem up","up:draft":"aem up --html-folder drafts"}'

echo "[block] no manifest → one line, in both places"
run block --manifest "$WORK/missing.json" --branch eds-18 "${COMMON[@]}"
assert_eq "exit 0" "0" "$CODE"
assert_eq "heading and one line" $'## Verified locally\nNo verification target is on record for this run.' "$OUT"
NOBLOCK="$OUT"
run note --manifest "$WORK/missing.json" --branch eds-18 --item-id EDS-18 --pr-url "$PR" --checks "$CHECKS" "${COMMON[@]}"
assert_has "the note carries the same no-target block" "$NOBLOCK" "$OUT"

echo "[note] EDS-18: about ten lines, fonts under Action needed, the block verbatim"
run note --manifest "$MANIFEST" --branch eds-18 --item-id EDS-18 --pr-url "$PR" --checks "$CHECKS" "${COMMON[@]}"
NOTE="$OUT"
assert_eq "exit 0" "0" "$CODE"
assert_eq "first line" "EDS-18 — ready for review" "$(echo "$NOTE" | head -1)"
assert_has "PR line" "- PR: $PR" "$NOTE"
assert_has "the block, verbatim (same target text as the PR body)" "$BLOCK" "$NOTE"
LINES=$(printf '%s\n' "$NOTE" | grep -c .)
if [ "$LINES" -ge 8 ] && [ "$LINES" -le 14 ]; then ok "about ten non-blank lines ($LINES)"; else bad "about ten non-blank lines" "got $LINES"; fi
ACTION=$(printf '%s\n' "$NOTE" | sed -n '/^Action needed$/,/^$/p')
assert_has "missing fonts under Action needed" "Roboto Mono, DM Sans, Rethink Sans, Reddit Mono not declared" "$ACTION"
assert_has "the failing check under Action needed" "- Check failing: aem-psi-check" "$ACTION"
assert_lacks "a passing check is not an action" "build" "$ACTION"
assert_lacks "no 'judged visually only' line in the note" "judged visually only" "$NOTE"
assert_lacks "no skipped comparison in the note" "no baseline comparison ran" "$NOTE"
assert_eq "last line" "Details: delivery-report.md (attached)" "$(echo "$NOTE" | tail -1)"

echo "[note] nothing to act on → one line"
printf '%s' '{"version":"1.0","item_id":"X-1","target":"http://localhost:3001/drafts/X-1","target_reachable":true,"target_reachable_reason":"HTTP 200","coverage_gaps":["design value a was judged visually only"],"attachments":[]}' > "$WORK/clean.json"
printf '[{"bucket":"pass","name":"build","state":"SUCCESS"},{"bucket":"pending","name":"psi","state":"IN_PROGRESS"}]' > "$WORK/green.json"
run note --manifest "$WORK/clean.json" --branch x-1 --item-id X-1 --pr-url "$PR" --checks "$WORK/green.json" "${COMMON[@]}"
assert_has "Nothing to do before merge" $'Action needed\n- Nothing to do before merge' "$OUT"

echo "[note] checks that cannot be read, and a cancelled check, need a person"
run note --manifest "$WORK/clean.json" --branch x-1 --item-id X-1 --pr-url "$PR" --checks "$WORK/missing-checks.json" "${COMMON[@]}"
assert_has "unreadable checks" "- Automated checks could not be read; see delivery-report.md" "$OUT"
printf '[{"bucket":"cancel","name":"build","state":"CANCELLED"}]' > "$WORK/cancel.json"
run note --manifest "$WORK/clean.json" --branch x-1 --item-id X-1 --pr-url "$PR" --checks "$WORK/cancel.json" "${COMMON[@]}"
assert_has "cancelled check" "- Check cancelled: build" "$OUT"

echo "[note] the placeholder-fixture gap becomes the remedy line"
printf '%s' '{"version":"1.0","item_id":"X-2","target":"http://localhost:3001/drafts/X-2","target_reachable":false,"target_reachable_reason":"loopback address","coverage_gaps":["the rendered target was a generated placeholder fixture (drafts/X-2.plain.html), not authored content"],"attachments":[]}' > "$WORK/fixture.json"
run note --manifest "$WORK/fixture.json" --branch x-2 --item-id X-2 --pr-url "$PR" --checks "$WORK/green.json" --block-name cards "${COMMON[@]}"
assert_has "remedy names the block and the fixture" "- To make this openable, author and publish real \`cards\` content — the only content behind this target right now is the generated placeholder fixture at \`drafts/X-2.plain.html\`." "$OUT"
run note --manifest "$WORK/fixture.json" --branch x-2 --item-id X-2 --pr-url "$PR" --checks "$WORK/green.json" "${COMMON[@]}"
assert_has "no block name → the target block" "author and publish real content for the target block" "$OUT"

echo "[note] a manifest that cannot be read is an action, and the block says no target"
printf '{not json' > "$WORK/broken.json"
run note --manifest "$WORK/broken.json" --branch x-1 --item-id X-1 --pr-url "$PR" --checks "$WORK/green.json" "${COMMON[@]}"
assert_eq "exit 0" "0" "$CODE"
assert_has "no-target block" "No verification target is on record for this run." "$OUT"
assert_has "action line" "- The evidence manifest could not be read" "$OUT"
printf '%s' '{"version":"1.0","item_id":"X-1"}' > "$WORK/partial.json"
run block --manifest "$WORK/partial.json" --branch x-1 "${COMMON[@]}"
assert_has "a manifest missing target → no-target block" "No verification target is on record for this run." "$OUT"

echo "[report] delivery-report.md's evidence section carries every gap verbatim"
run report --manifest "$MANIFEST"
REPORT="$OUT"
assert_eq "exit 0" "0" "$CODE"
assert_has "target" "- target: http://localhost:3001/drafts/EDS-18" "$REPORT"
assert_has "reachability" "- target_reachable: false (loopback address)" "$REPORT"
MISSING=0
while IFS= read -r gap; do
  if ! printf '%s\n' "$REPORT" | grep -qxF -- "- $gap"; then MISSING=$((MISSING + 1)); fi
done < <(jq -r '.coverage_gaps[]' "$MANIFEST")
TOTAL=$(jq '.coverage_gaps | length' "$MANIFEST")
assert_eq "all $TOTAL gaps present, one line each, verbatim" "0" "$MISSING"
assert_eq "no extra gap lines" "$TOTAL" "$(printf '%s\n' "$REPORT" | sed -n '/^### coverage_gaps$/,$p' | grep -c '^- ')"
run report --manifest "$WORK/clean.json"
run report --manifest "$WORK/missing.json"
assert_eq "no manifest → one line" "No evidence manifest is on record for this run." "$OUT"
printf '%s' '{"version":"1.0","item_id":"X","target":"t","target_reachable":true,"target_reachable_reason":"r","coverage_gaps":[],"attachments":[]}' > "$WORK/nogaps.json"
run report --manifest "$WORK/nogaps.json"
assert_has "an empty list is said, not omitted" $'### coverage_gaps\n- none recorded' "$OUT"

echo "[usage]"
run
assert_eq "no mode → exit 2" "2" "$CODE"
run block --manifest "$MANIFEST" "${COMMON[@]}"
assert_eq "block without --branch → exit 2" "2" "$CODE"
run note --manifest "$MANIFEST" --branch eds-18 "${COMMON[@]}"
assert_eq "note without --item-id/--pr-url → exit 2" "2" "$CODE"

echo "[boundary] the core names neither the limit nor the draft server"
CORE="$SCRIPT_DIR/../../../agentic-core"
if grep -rIl -e 'check-branch-length' -e 'draft server' -e 'delivery-text' "$CORE" >/dev/null 2>&1; then
  bad "core names none of them" "$(grep -rIl -e 'check-branch-length' -e 'draft server' -e 'delivery-text' "$CORE" | head -3)"
else
  ok "core names none of them"
fi

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
