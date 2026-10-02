#!/usr/bin/env bash
# resolve-verify-target.test.sh — what verify points a browser at.
#
# Usage:
#   bash resolve-verify-target.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/resolve-verify-target.py"
PACK_YAML="$SCRIPT_DIR/../../../../jira/pack.yaml"
PREVIEW="http://localhost:3000/preview"

PASS=0
FAIL=0

TMP="$(mktemp -d "${TMPDIR:-/tmp}/resolve-verify-target.XXXXXX")" || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# case <label> <expected exit> <expected output substring> <components> <files_named> <spec text>
case_() {
  local label="$1" want_rc="$2" want_out="$3" components="$4" files="$5" spec="$6"
  printf 'item_id: EDS-22\nitem_type: Bug\ncomponents: %s\nfiles_named: %s\n' "$components" "$files" > "$TMP/fact-record.yaml"
  printf '%b' "$spec" > "$TMP/spec.md"
  local out rc
  out="$(python3 "$SCRIPT" "$TMP/fact-record.yaml" "$TMP/spec.md" "$PACK_YAML" "$PREVIEW" 2>&1)"
  rc=$?
  if [ "$rc" = "$want_rc" ] && [[ "$out" == *"$want_out"* ]]; then
    echo "  ok: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected exit $want_rc containing: $want_out"
    echo "    got exit $rc: $out"
    FAIL=$((FAIL + 1))
  fi
}

REPRO='# Long button labels are cut off\n\n## Steps to reproduce\n\n1. Open https://main--aem-eds-ai-workflow-demo--agenticdraft.aem.page/buttons-test\n2. Make the window 375 px wide\n'

case_ "declared components win" 0 "target=blocks names=accordion,cards" \
  "[accordion, cards]" "[styles/styles.css]" "$REPRO"
case_ "block folders in files_named, when no component" 0 "target=blocks names=table" \
  "[]" "[blocks/table/table.css, styles/styles.css]" "$REPRO"
case_ "no block: the URL under the reproduction heading, as a local path" 0 \
  "target=page path=/buttons-test source=https://main--aem-eds-ai-workflow-demo--agenticdraft.aem.page/buttons-test" \
  "[]" "[styles/styles.css]" "$REPRO"
case_ "trailing punctuation is not part of the path" 0 "target=page path=/buttons-test source=" \
  "[]" "[]" '## Steps to reproduce\n\nOpen https://main--x--y.aem.live/buttons-test.\n'
case_ "a local draft URL keeps its drafts path" 0 "target=page path=/drafts/EDS-22 " \
  "[]" "[]" '## Repro\n\nhttp://localhost:3000/drafts/EDS-22\n'
case_ "a query string and fragment are kept off the path" 0 "target=page path=/buttons-test " \
  "[]" "[]" '## Steps\n\nhttps://main--x--y.aem.page/buttons-test?a=1#top\n'
case_ "the first URL under the heading, not one above it" 0 "target=page path=/second " \
  "[]" "[]" 'See https://main--x--y.aem.page/first\n\n## Steps to reproduce\n\nhttps://main--x--y.aem.page/second\n'
case_ "a URL on another host is not a target" 1 "target=none" \
  "[]" "[styles/styles.css]" '## Steps to reproduce\n\nhttps://example.com/buttons-test\n'
case_ "a URL outside any reproduction heading is not a target" 1 "target=none" \
  "[]" "[styles/styles.css]" '## Description\n\nhttps://main--x--y.aem.page/buttons-test\n'
case_ "the reproduction section ends at the next heading" 1 "target=none" \
  "[]" "[]" '## Steps to reproduce\n\nOpen the page.\n\n## Acceptance criteria\n\nhttps://main--x--y.aem.page/a\n'
case_ "nothing at all names a reason" 1 "reason=" "[]" "[]" 'No links here.\n'

if python3 "$SCRIPT" a b 2>/dev/null; then
  echo "  FAIL: a usage error exits non-zero"; FAIL=$((FAIL + 1))
else
  [ "$?" = 2 ] && { echo "  ok: a usage error exits 2"; PASS=$((PASS + 1)); } || { echo "  FAIL: a usage error exits 2"; FAIL=$((FAIL + 1)); }
fi

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
