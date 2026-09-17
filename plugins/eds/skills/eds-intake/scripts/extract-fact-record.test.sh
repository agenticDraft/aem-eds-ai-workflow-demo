#!/usr/bin/env bash
# extract-fact-record.test.sh — Regression coverage for extract-fact-record.py's
# files_named extraction, added alongside the fix that taught it to recognise a
# bare component directory (e.g. "blocks/features-carousel/") the work item's
# text names without a specific file inside it — the shape a plain FILE_RE
# extension match can never catch (see G83, 05-gap-register.md).
#
# Not full coverage of the script's every field; this covers only the
# files_named change, which had zero test coverage before this fix.
#
# Usage:
#   bash extract-fact-record.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/extract-fact-record.py"
# The tracker pack, not eds's own — text_conventions lives there (04-eds-pack-design.md),
# the same pack path eds-intake/SKILL.md itself resolves this script against.
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
  tmp="$(mktemp -d)"
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

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
