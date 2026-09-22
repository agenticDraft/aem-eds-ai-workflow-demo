#!/usr/bin/env bash
# write-design-source-kind.test.sh — Coverage for write-design-source-kind.sh,
# the wrapper eds-intake calls to append design_source_kind to the fact record
# it just wrote, by running the same resolve-design-source.py eds-extract already
# trusts (Phase 10 / Task 2, D100, G503).
#
# Usage:
#   bash write-design-source-kind.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/write-design-source-kind.sh"

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

check_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  ok: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== write-design-source-kind.sh ==="

echo "[usage] no arguments"
OUT="$(bash "$SCRIPT" 2>&1)"; ST=$?
check_exit "no args -> exit 2" 2 "$ST"

echo "[usage] fact record not found"
OUT="$(bash "$SCRIPT" "/does/not/exist.yaml" "/does/not/exist.md" "/does/not/exist.json" 2>&1)"; ST=$?
check_exit "missing file -> exit 2" 2 "$ST"

echo "[append] a url-sourced item"
tmp="$(mktemp -d)"
fact="$tmp/fact-record.yaml"
spec="$tmp/sanitized-spec.md"
item="$tmp/item.json"
printf 'item_id: TEST-1\ndesign_source: true\ndesign_mentioned: true\n' > "$fact"
printf 'See https://www.figma.com/design/ABC/Page?node-id=1-2 for the design.\n' > "$spec"
printf '{"key":"TEST-1","fields":{"attachment":[]}}\n' > "$item"

OUT="$(bash "$SCRIPT" "$fact" "$spec" "$item" 2>&1)"; ST=$?
check_exit "exit 0 on success" 0 "$ST"
FACT_CONTENTS="$(cat "$fact")"
check "design_source_kind: url appended" "design_source_kind: url" "$FACT_CONTENTS"
check "original fields preserved" "item_id: TEST-1" "$FACT_CONTENTS"
rm -rf "$tmp"

echo "[append] an item with neither field set"
tmp="$(mktemp -d)"
fact="$tmp/fact-record.yaml"
spec="$tmp/sanitized-spec.md"
item="$tmp/item.json"
printf 'item_id: TEST-2\ndesign_source: false\ndesign_mentioned: false\n' > "$fact"
printf 'No visual change here.\n' > "$spec"
printf '{"key":"TEST-2","fields":{"attachment":[]}}\n' > "$item"

OUT="$(bash "$SCRIPT" "$fact" "$spec" "$item" 2>&1)"; ST=$?
check_exit "exit 0 on success" 0 "$ST"
check "design_source_kind: decline appended" "design_source_kind: decline" "$(cat "$fact")"
rm -rf "$tmp"

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
