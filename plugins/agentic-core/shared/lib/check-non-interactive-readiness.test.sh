#!/usr/bin/env bash
# check-non-interactive-readiness.test.sh — Coverage for
# check-non-interactive-readiness.sh (Phase 10 / Task 2, D100, G503, validator 19).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-non-interactive-readiness.sh"

PASS=0
FAIL=0

check_exit() {
  local desc="$1" expected="$2" actual="$3" out="$4"
  if [[ "$actual" == "$expected" ]]; then
    echo "  ok: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected exit $expected, got $actual)"
    echo "    output: $out"
    FAIL=$((FAIL + 1))
  fi
}

check_contains() {
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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fact_url_autonomous="$tmp/fact-url-autonomous.yaml"
printf 'item_id: TEST-1\ndesign_source_kind: url\n' > "$fact_url_autonomous"

fact_image="$tmp/fact-image.yaml"
printf 'item_id: TEST-2\ndesign_source_kind: image\n' > "$fact_image"

fact_decline="$tmp/fact-decline.yaml"
printf 'item_id: TEST-3\ndesign_source_kind: decline\n' > "$fact_decline"

state_autonomous="$tmp/state-autonomous.json"
printf '{\n  "mode": "autonomous"\n}\n' > "$state_autonomous"

state_interactive="$tmp/state-interactive.json"
printf '{\n  "mode": "interactive"\n}\n' > "$state_interactive"

design_pack_gated="$tmp/figma-pack.yaml"
printf 'kind: provider\nrole: design\noperations:\n  fetch_reference: fetch-reference\nunsupported: []\nrequires_interactive_session: [fetch_reference]\n' > "$design_pack_gated"

design_pack_ungated="$tmp/other-pack.yaml"
printf 'kind: provider\nrole: design\noperations:\n  fetch_reference: fetch-reference\nunsupported: []\n' > "$design_pack_ungated"

echo "=== check-non-interactive-readiness.sh ==="

echo "[usage] too few arguments"
OUT="$(bash "$SCRIPT" "$fact_url_autonomous" "$state_autonomous" 2>&1)"; ST=$?
check_exit "exit 2" 2 "$ST" "$OUT"

echo "[usage] fact record not found"
OUT="$(bash "$SCRIPT" "/does/not/exist.yaml" "$state_autonomous" "$design_pack_gated" 2>&1)"; ST=$?
check_exit "exit 2" 2 "$ST" "$OUT"

echo "[pass] url-sourced, autonomous, but the pack does not require interactive session"
OUT="$(bash "$SCRIPT" "$fact_url_autonomous" "$state_autonomous" "$design_pack_ungated" 2>&1)"; ST=$?
check_exit "exit 0" 0 "$ST" "$OUT"

echo "[fail] url-sourced, autonomous, pack requires interactive session — the refusal case"
OUT="$(bash "$SCRIPT" "$fact_url_autonomous" "$state_autonomous" "$design_pack_gated" 2>&1)"; ST=$?
check_exit "exit 1" 1 "$ST" "$OUT"
check_contains "reason names the item id" "TEST-1" "$OUT"
check_contains "reason names autonomous mode" "autonomous" "$OUT"

echo "[pass] url-sourced, interactive mode — a human can complete OAuth"
OUT="$(bash "$SCRIPT" "$fact_url_autonomous" "$state_interactive" "$design_pack_gated" 2>&1)"; ST=$?
check_exit "exit 0" 0 "$ST" "$OUT"

echo "[pass] image-sourced, autonomous — not a url source at all"
OUT="$(bash "$SCRIPT" "$fact_image" "$state_autonomous" "$design_pack_gated" 2>&1)"; ST=$?
check_exit "exit 0" 0 "$ST" "$OUT"

echo "[pass] decline — no design source involved"
OUT="$(bash "$SCRIPT" "$fact_decline" "$state_autonomous" "$design_pack_gated" 2>&1)"; ST=$?
check_exit "exit 0" 0 "$ST" "$OUT"

echo "[pass] no design pack configured — literal 'none'"
OUT="$(bash "$SCRIPT" "$fact_url_autonomous" "$state_autonomous" "none" 2>&1)"; ST=$?
check_exit "exit 0" 0 "$ST" "$OUT"

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
