#!/usr/bin/env bash
# resolve-design-source.test.sh — Coverage for resolve-design-source.py's five
# decisions (decline, url, image, ambiguous, missing), added when the script moved
# here from eds-extract/scripts/ so eds-intake could call it too (Phase 10 / Task 2,
# D100). Zero test coverage existed before this move.
#
# Usage:
#   bash resolve-design-source.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/resolve-design-source.py"

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

# run_case <label> <fact-record contents> <spec text> <attachment mime,filename pairs...>
run_case() {
  local fact_body="$1" spec_text="$2"
  shift 2
  local tmp fact_record spec item_json
  tmp="$(mktemp -d)"
  fact_record="$tmp/fact-record.yaml"
  spec="$tmp/sanitized-spec.md"
  item_json="$tmp/item.json"

  printf '%s\n' "$fact_body" > "$fact_record"
  printf '%s\n' "$spec_text" > "$spec"

  python3 -c "
import json, sys
pairs = sys.argv[3:]
attachments = []
for i in range(0, len(pairs), 2):
    mime, filename = pairs[i], pairs[i + 1]
    attachments.append({'mimeType': mime, 'filename': filename, 'content': f'https://example.test/{filename}'})
item = {'key': 'TEST-1', 'fields': {'attachment': attachments}}
with open(sys.argv[1], 'w') as f:
    json.dump(item, f)
" "$item_json" "ignored" "$@"

  local out
  out="$(python3 "$SCRIPT" "$fact_record" "$spec" "$item_json" 2>&1)"
  echo "$out"
  rm -rf "$tmp"
}

echo "=== resolve-design-source.py decision tests ==="

OUT="$(run_case "design_source: false
design_mentioned: false" "No visual change requested.")"
check "decline when neither field is set" "decision=decline" "$OUT"

OUT="$(run_case "design_source: true
design_mentioned: true" "See https://www.figma.com/design/ABC123/Page?node-id=1-2 for the reference.")"
check "url wins when a figma.com link is in the spec text" "decision=url reference=https://www.figma.com/design/ABC123/Page?node-id=1-2" "$OUT"

OUT="$(run_case "design_source: true
design_mentioned: true" "Matches the attached mockup." "image/png" "mock.png")"
check "single image attachment" "decision=image filename=mock.png" "$OUT"

OUT="$(run_case "design_source: true
design_mentioned: true" "See the attachments." "image/png" "a.png" "image/png" "b.png")"
check "two image attachments is ambiguous" "decision=ambiguous count=2" "$OUT"

OUT="$(run_case "design_source: true
design_mentioned: true" "Needs a visual change but nothing is attached.")"
check "no url and no image attachment is missing" "decision=missing" "$OUT"

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
