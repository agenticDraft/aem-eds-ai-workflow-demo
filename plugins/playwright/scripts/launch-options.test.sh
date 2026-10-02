#!/usr/bin/env bash
# Tests for launch-options.cjs. Run with:
#   bash plugins/playwright/scripts/launch-options.test.sh
#
# No browser — exits 0 on success, 1 if anything failed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/launch-options.cjs"
PACK="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    got:      $actual"
  fi
}

# options_for <env-json> — prints launchOptions(env) as one JSON line
options_for() {
  node -e '
const { launchOptions } = require(process.argv[1]);
process.stdout.write(JSON.stringify(launchOptions(JSON.parse(process.argv[2]))));
' "$HELPER" "$1" 2>&1
}

echo "[no proxy] headless only"
assert_eq "no proxy variable" '{"headless":true}' "$(options_for '{}')"
assert_eq "an empty proxy variable" '{"headless":true}' "$(options_for '{"HTTP_PROXY":""}')"

echo "[proxy] the environment's proxy is passed, with its credentials"
assert_eq "upper-case variable, with credentials" \
  '{"headless":true,"proxy":{"server":"http://localhost:3128","username":"srt.abc=","password":"tok"}}' \
  "$(options_for '{"HTTP_PROXY":"http://srt.abc%3D:tok@localhost:3128"}')"
assert_eq "lower-case variable, no credentials" \
  '{"headless":true,"proxy":{"server":"http://localhost:3128"}}' \
  "$(options_for '{"http_proxy":"http://localhost:3128"}')"
assert_eq "an unparseable proxy is ignored" '{"headless":true}' "$(options_for '{"HTTP_PROXY":"not a url"}')"

echo "[operations] every operation launches through the helper"
for op in render capture measure interact; do
  f="$PACK/skills/$op/scripts/$op.cjs"
  assert_eq "$op uses launchOptions" "1" "$(grep -c 'chromium.launch(launchOptions(process.env))' "$f")"
  assert_eq "$op has no literal launch options" "0" "$(grep -c 'chromium.launch({' "$f")"
done

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
