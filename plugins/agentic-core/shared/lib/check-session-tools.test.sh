#!/usr/bin/env bash
# Tests for check-session-tools.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-session-tools.test.sh
#
# No framework — exits 0 on success, 1 if any case failed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-session-tools.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/session-tools"

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3" output="$4"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected exit=$expected, got exit=$actual"
    [[ -n "$output" ]] && echo "    output: $output"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected output to contain: $needle"
    echo "    got: $haystack"
  fi
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

echo "=== check-session-tools.sh tests ==="

# --- list: what the driver asks the session for ------------------------------

echo "[list] one pack, one declared tool"
OUT=$(bash "$CHECK" --list "$FIXDIR/one-tool/pack.yaml" 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_eq "one tool line" "tool: mcp__example-server__read_item" "$OUT"

echo "[list] two packs, the same tool once"
OUT=$(bash "$CHECK" --list "$FIXDIR/one-tool/pack.yaml" "$FIXDIR/two-tools/pack.yaml" 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_eq "each name once, in declaration order" \
  "$(printf 'tool: mcp__example-server__read_item\ntool: mcp__example-server__read_image')" "$OUT"

echo "[list] nothing declared"
OUT=$(bash "$CHECK" --list "$FIXDIR/none-declared/pack.yaml" 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_eq "says so" "none declared" "$OUT"

echo "[list] no pack at all"
OUT=$(bash "$CHECK" --list 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_eq "says so" "none declared" "$OUT"

# --- check: names declared against names found ------------------------------

echo "[check] the declared tool is absent from the session"
OUT=$(bash "$CHECK" "$FIXDIR/one-tool/pack.yaml" --found 2>&1); ST=$?
assert_exit "exit 1" 1 $ST "$OUT"
assert_contains "names the tool and quotes the remedy" \
  "missing: mcp__example-server__read_item — enable the example plugin, then restart the session" "$OUT"

echo "[check] the declared tool is present"
OUT=$(bash "$CHECK" "$FIXDIR/one-tool/pack.yaml" --found mcp__example-server__read_item 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_eq "ok line" "ok: mcp__example-server__read_item" "$OUT"

echo "[check] other tools found do not stand in for the declared one"
OUT=$(bash "$CHECK" "$FIXDIR/one-tool/pack.yaml" --found mcp__example-server__read_image mcp__example-server__read_item_v2 2>&1); ST=$?
assert_exit "exit 1" 1 $ST "$OUT"
assert_contains "exact match only" "missing: mcp__example-server__read_item" "$OUT"

echo "[check] one of two present"
OUT=$(bash "$CHECK" "$FIXDIR/two-tools/pack.yaml" --found mcp__example-server__read_item 2>&1); ST=$?
assert_exit "exit 1" 1 $ST "$OUT"
assert_contains "the present one is ok" "ok: mcp__example-server__read_item" "$OUT"
assert_contains "the absent one carries its own remedy" \
  "missing: mcp__example-server__read_image — sign in to the example server" "$OUT"
assert_contains "a count closes the report" "1 of 2 declared session tools are missing" "$OUT"

echo "[check] the requires: block is not read as session tools"
[[ "$OUT" != *"example-tool"* ]]
assert_exit "no line for the requires entry" 0 $? "$OUT"

echo "[check] a pack declaring nothing"
OUT=$(bash "$CHECK" "$FIXDIR/none-declared/pack.yaml" --found 2>&1); ST=$?
assert_exit "exit 0" 0 $ST "$OUT"
assert_eq "says so" "ok: no session tools declared" "$OUT"

echo "[check] two packs; only the one declaring a tool can miss"
OUT=$(bash "$CHECK" "$FIXDIR/none-declared/pack.yaml" "$FIXDIR/one-tool/pack.yaml" --found 2>&1); ST=$?
assert_exit "exit 1" 1 $ST "$OUT"
assert_contains "the declared tool is missing" "missing: mcp__example-server__read_item" "$OUT"

# --- refusals ---------------------------------------------------------------

echo "[usage] no --found and no --list"
OUT=$(bash "$CHECK" "$FIXDIR/one-tool/pack.yaml" 2>&1); ST=$?
assert_exit "exit 2" 2 $ST "$OUT"

echo "[usage] no argument"
OUT=$(bash "$CHECK" 2>&1); ST=$?
assert_exit "exit 2" 2 $ST "$OUT"

echo "[usage] pack file not found"
OUT=$(bash "$CHECK" "$FIXDIR/does-not-exist/pack.yaml" --found 2>&1); ST=$?
assert_exit "exit 2" 2 $ST "$OUT"
assert_contains "names the file" "does-not-exist/pack.yaml" "$OUT"

echo "[malformed] an entry with no remedy is refused, never reported ok"
OUT=$(bash "$CHECK" "$FIXDIR/no-remedy/pack.yaml" --found mcp__example-server__read_item 2>&1); ST=$?
assert_exit "exit 2" 2 $ST "$OUT"
assert_contains "names the block" "malformed 'session_tools:'" "$OUT"

echo "[malformed] the same refusal for --list"
OUT=$(bash "$CHECK" --list "$FIXDIR/no-remedy/pack.yaml" 2>&1); ST=$?
assert_exit "exit 2" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
