#!/usr/bin/env bash
# extract-fact-record.test.sh — Regression coverage for extract-fact-record.py's
# files_named extraction, added alongside the fix that taught it to recognise a
# bare component directory (e.g. "blocks/features-carousel/") the work item's
# text names without a specific file inside it — the shape a plain FILE_RE
# extension match can never catch (see G83).
#
# Not full coverage of the script's every field; this covers only the
# files_named change, which had zero test coverage before this fix.
#
# Usage:
#   bash extract-fact-record.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/extract-fact-record.py"
# The tracker pack, not eds's own — text_conventions lives there, the same pack path
# eds-intake/SKILL.md itself resolves this script against.
PACK_YAML="$SCRIPT_DIR/../../../../jira/pack.yaml"

PASS=0
FAIL=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    echo "  ok: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected to contain: $expected"
    echo "    got: $actual"
    FAIL=$((FAIL + 1))
  fi
}

run_case() {
  local label="$1" description_text="$2"
  echo "[$label]"
  local tmp fact_record spec item_json
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/extract-fact-record.XXXXXX")" || { echo "cannot create a temp dir" >&2; exit 2; }
  [ -n "$tmp" ] && [ -d "$tmp" ] || { echo "cannot create a temp dir" >&2; exit 2; }
  fact_record="$tmp/fact-record.yaml"
  spec="$tmp/sanitized-spec.md"
  item_json="$tmp/item.json"

  python3 -c "
import json, sys
desc_text = sys.argv[1]
doc = {
    'type': 'doc',
    'content': [
        {'type': 'paragraph', 'content': [{'type': 'text', 'text': desc_text}]}
    ],
}
item = {
    'key': 'TEST-1',
    'fields': {
        'issuetype': {'name': 'Story'},
        'summary': 'Test item',
        'description': doc,
        'labels': [],
        'components': [],
        'attachment': [],
    },
}
with open(sys.argv[2], 'w') as f:
    json.dump(item, f)
" "$description_text" "$item_json"

  python3 "$SCRIPT" "$item_json" "$PACK_YAML" "$fact_record" "$spec" >/dev/null 2>&1
  FILES_NAMED="$(grep '^files_named:' "$fact_record" 2>/dev/null || echo "MISSING")"
  echo "$FILES_NAMED"
  rm -rf "$tmp"
}

echo "=== extract-fact-record.py files_named tests ==="

OUT="$(run_case "a bare block directory with no file inside it" \
  "A new block exists under blocks/features-carousel/, authored via the standard content model.")"
check "blocks/features-carousel/ captured" "blocks/features-carousel/" "$OUT"

OUT="$(run_case "a real file path (pre-existing behavior, unchanged)" \
  "See blocks/columns/columns.js for the existing pattern.")"
check "blocks/columns/columns.js still captured" "blocks/columns/columns.js" "$OUT"

OUT="$(run_case "prose mentioning 'blocks' with no path at all" \
  "Add support for reusable blocks across the site.")"
check "no spurious blocks/ match" "files_named: []" "$OUT"

# --- reproduction_content_ok, before_state_* --------------------------------
# These read the checkout, so each case runs inside a throwaway project: its
# own config (the preview host), its own drafts/, its own pages.
PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/extract-fact-record-project.XXXXXX")" || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$PROJECT" ] && [ -d "$PROJECT" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$PROJECT"' EXIT
git init -q "$PROJECT"
mkdir -p "$PROJECT/.ai" "$PROJECT/drafts"
printf 'drafts/\n' > "$PROJECT/.gitignore"
printf 'paths:\n  preview: "http://localhost:3000/preview"\n' > "$PROJECT/.ai/project-config.yaml"
printf '<div><div class="table"><div><div>a</div></div></div></div>\n' > "$PROJECT/drafts/ITEM-1.plain.html"
printf '<div><div class="table"><div><div>a</div></div></div></div>\n' > "$PROJECT/drafts/ITEM-9.plain.html"

# field_case <label> <key> <components csv> <description> — prints the three new fields
field_case() {
  local label="$1" key="$2" components="$3" description_text="$4"
  echo "[$label]" >&2
  python3 -c "
import json, sys
item = {
    'key': sys.argv[1],
    'fields': {
        'issuetype': {'name': 'Bug'},
        'summary': 'Test item',
        'description': {'type': 'doc', 'content': [
            {'type': 'paragraph', 'content': [{'type': 'text', 'text': sys.argv[3]}]}]},
        'labels': [],
        'components': [{'name': c} for c in sys.argv[2].split(',') if c],
        'attachment': [],
    },
}
json.dump(item, open(sys.argv[4], 'w'))
" "$key" "$components" "$description_text" "$PROJECT/item.json"
  (cd "$PROJECT" && python3 "$SCRIPT" item.json "$PACK_YAML" fact-record.yaml spec.md >/dev/null 2>&1)
  grep -E '^(reproduction_content_ok|before_state_mentioned|before_state_available):' "$PROJECT/fact-record.yaml" | tr '\n' ' '
}

echo "=== reproduction_content_ok / before_state_* tests ==="

OUT="$(field_case "the item's own draft, present" ITEM-1 table "Open http://localhost:3001/drafts/ITEM-1")"
check "own draft present -> ok" "reproduction_content_ok: true" "$OUT"

OUT="$(field_case "the item's own draft, missing" ITEM-2 table "Open http://localhost:3001/drafts/ITEM-2")"
check "own draft missing -> not ok" "reproduction_content_ok: false" "$OUT"

OUT="$(field_case "another item's draft, present on disk" ITEM-2 table "Open http://localhost:3001/drafts/ITEM-9")"
check "another item's draft -> not ok" "reproduction_content_ok: false" "$OUT"

OUT="$(field_case "a remote URL and a proxied local page" ITEM-2 table "See https://example.test/page and http://localhost:3000/about")"
check "no draft URL -> ok, nothing probed" "reproduction_content_ok: true" "$OUT"

OUT="$(field_case "a before-state phrase, component only in drafts/" ITEM-1 table "AC-2 The data rows render the same as before the change.")"
check "phrase matched" "before_state_mentioned: true" "$OUT"
check "drafts/ is never a before-state" "before_state_available: false" "$OUT"

printf '<div class="table"></div>\n' > "$PROJECT/index.html"
OUT="$(field_case "the component has a page outside drafts/" ITEM-1 table "AC-2 The data rows render the same as before the change.")"
check "page outside drafts/ -> available" "before_state_available: true" "$OUT"

OUT="$(field_case "no component named" ITEM-1 "" "Nothing to compare.")"
check "no phrase -> not mentioned" "before_state_mentioned: false" "$OUT"
check "no component -> not available" "before_state_available: false" "$OUT"

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
