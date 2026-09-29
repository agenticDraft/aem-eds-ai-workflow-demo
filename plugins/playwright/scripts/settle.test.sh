#!/usr/bin/env bash
# Tests for settle.cjs. Run with:
#   bash plugins/playwright/scripts/settle.test.sh
#
# No framework, and no browser — exits 0 on success, 1 if anything failed.
# Every case drives settle() with a scripted probe and a fake clock, so no
# case waits on real time.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTLE="$SCRIPT_DIR/settle.cjs"

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

# run_case <probe-sequence-json> [fonts-mode] [interval] [timeout]
# Each sequence entry is one probe result: {"value":..., "blockers":[...]}.
# The last entry repeats once the sequence is exhausted; the literal "hang"
# stands for a probe that never resolves. fonts-mode is "ready" (default)
# or "hang". Prints the settle() outcome as one JSON line, plus the number
# of probes taken and the fake time elapsed.
run_case() {
  node -e '
const { settle } = require(process.argv[1]);
const seq = JSON.parse(process.argv[2]);
const fontsMode = process.argv[3];
const interval = Number(process.argv[4]);
const timeout = Number(process.argv[5]);
let t = 0;
let probes = 0;
const never = new Promise(() => {});
const clock = {
  now: () => t,
  sleep: (ms) => { t += ms; return Promise.resolve(); },
  // A deadline timer fires on the next turn, advancing the fake clock to it,
  // unless the raced promise settled first and cancelled it.
  timer: (ms) => {
    let handle;
    const promise = new Promise((resolve) => { handle = setImmediate(() => { t += ms; resolve(); }); });
    return { promise, cancel: () => clearImmediate(handle) };
  },
};
settle({
  probe: () => {
    const entry = seq[Math.min(probes, seq.length - 1)];
    probes += 1;
    return entry === "hang" ? never : Promise.resolve(entry);
  },
  fontsReady: () => (fontsMode === "hang" ? never : Promise.resolve()),
  intervalMs: interval,
  timeoutMs: timeout,
  clock,
}).then((r) => {
  process.stdout.write(JSON.stringify({ ...r, probes, elapsed: t }));
});
' "$SETTLE" "$1" "${2:-ready}" "${3:-250}" "${4:-10000}" 2>&1
}

field() { node -e 'const o = JSON.parse(process.argv[1]); const v = o[process.argv[2]]; process.stdout.write(typeof v === "string" ? v : String(JSON.stringify(v)));' "$1" "$2"; }

echo "=== settle.cjs tests ==="

echo "[defaults] a fixed interval and an upper bound are exported"
assert_eq "interval 250" "250" "$(node -e "process.stdout.write(String(require(process.argv[1]).SETTLE_INTERVAL_MS))" "$SETTLE")"
assert_eq "timeout 10000" "10000" "$(node -e "process.stdout.write(String(require(process.argv[1]).SETTLE_TIMEOUT_MS))" "$SETTLE")"

echo "[require] loading the module runs nothing"
assert_eq "no output on require" "" "$(node -e "require(process.argv[1])" "$SETTLE" 2>&1)"

echo "[stable] two identical consecutive snapshots settle"
OUT=$(run_case '[{"value":{"a":1},"blockers":[]}]')
assert_eq "settled" "true" "$(field "$OUT" settled)"
assert_eq "value is the snapshot" '{"a":1}' "$(field "$OUT" value)"
assert_eq "two probes" "2" "$(field "$OUT" probes)"
assert_eq "one interval elapsed" "250" "$(field "$OUT" elapsed)"

echo "[changing] a changing snapshot settles only once two in a row match"
OUT=$(run_case '[{"value":{"w":0},"blockers":[]},{"value":{"w":1200},"blockers":[]},{"value":{"w":1200},"blockers":[]}]')
assert_eq "settled" "true" "$(field "$OUT" settled)"
assert_eq "the later value" '{"w":1200}' "$(field "$OUT" value)"
assert_eq "three probes" "3" "$(field "$OUT" probes)"

echo "[changing] A B A does not count as settled"
OUT=$(run_case '[{"value":{"w":1},"blockers":[]},{"value":{"w":2},"blockers":[]},{"value":{"w":1},"blockers":[]},{"value":{"w":1},"blockers":[]}]')
assert_eq "four probes" "4" "$(field "$OUT" probes)"
assert_eq "settled" "true" "$(field "$OUT" settled)"

echo "[blocked] a blocked snapshot never counts, even when identical"
OUT=$(run_case '[{"value":{"w":0},"blockers":["x"]},{"value":{"w":0},"blockers":["x"]},{"value":{"w":0},"blockers":[]},{"value":{"w":0},"blockers":[]}]')
assert_eq "settled" "true" "$(field "$OUT" settled)"
assert_eq "four probes" "4" "$(field "$OUT" probes)"

echo "[blocked] a blocker that never clears fails at the bound, naming it"
OUT=$(run_case '[{"value":{"w":0},"blockers":["not visible: .table"]}]' ready 250 1000)
assert_eq "not settled" "false" "$(field "$OUT" settled)"
assert_eq "no value" "undefined" "$(field "$OUT" value)"
assert_eq "reason names the blocker" \
  "the page did not settle within 1000 ms: not visible: .table" "$(field "$OUT" reason)"
assert_eq "stops at the bound" "1000" "$(field "$OUT" elapsed)"

echo "[never stable] a snapshot that keeps changing fails at the bound"
SEQ=$(node -e 'const a=[]; for (let i=0;i<100;i+=1) a.push({value:{w:i},blockers:[]}); process.stdout.write(JSON.stringify(a));')
OUT=$(run_case "$SEQ" ready 250 1000)
assert_eq "not settled" "false" "$(field "$OUT" settled)"
assert_eq "reason says it kept changing" \
  "the page did not settle within 1000 ms: consecutive snapshots 250 ms apart still differ" "$(field "$OUT" reason)"
assert_eq "stops at the bound" "1000" "$(field "$OUT" elapsed)"

echo "[fonts] fonts that never finish loading fail at the bound"
OUT=$(run_case '[{"value":{"a":1},"blockers":[]}]' hang 250 1000)
assert_eq "not settled" "false" "$(field "$OUT" settled)"
assert_eq "reason names fonts" \
  "the page did not settle within 1000 ms: document fonts never finished loading" "$(field "$OUT" reason)"
assert_eq "no probe taken" "0" "$(field "$OUT" probes)"

echo "[hang] a probe that never returns fails at the bound"
OUT=$(run_case '["hang"]' ready 250 1000)
assert_eq "not settled" "false" "$(field "$OUT" settled)"
assert_eq "reason names the snapshot" \
  "the page did not settle within 1000 ms: a snapshot did not return" "$(field "$OUT" reason)"

echo "[bound] the interval never overshoots the bound"
OUT=$(run_case '[{"value":{"w":0},"blockers":["x"]}]' ready 400 1000)
assert_eq "not settled" "false" "$(field "$OUT" settled)"
assert_eq "elapsed stays within the bound" "800" "$(field "$OUT" elapsed)"

echo "[same] deep-equal snapshots with the same key order compare equal"
SAME='const { sameSnapshot } = require(process.argv[1]); process.stdout.write(String(sameSnapshot(JSON.parse(process.argv[2]), JSON.parse(process.argv[3]))));'
assert_eq "same" "true" "$(node -e "$SAME" "$SETTLE" '{"a":{"x":1.5,"y":[1,2]}}' '{"a":{"x":1.5,"y":[1,2]}}')"
assert_eq "one value differs" "false" "$(node -e "$SAME" "$SETTLE" '{"a":{"x":382.8}}' '{"a":{"x":385.2}}')"

echo "[visible] a found element with an empty box or hidden is not visible"
VIS='const { notVisible } = require(process.argv[1]); process.stdout.write(JSON.stringify(notVisible(JSON.parse(process.argv[2]))));'
assert_eq "empty box" '[".a"]' "$(node -e "$VIS" "$SETTLE" '{".a":{"found":true,"width":0,"height":0,"hidden":false}}')"
assert_eq "visibility hidden" '[".a"]' "$(node -e "$VIS" "$SETTLE" '{".a":{"found":true,"width":10,"height":10,"hidden":true}}')"
assert_eq "one axis is enough" '[]' "$(node -e "$VIS" "$SETTLE" '{".a":{"found":true,"width":10,"height":0,"hidden":false}}')"
assert_eq "not found is not a blocker" '[]' "$(node -e "$VIS" "$SETTLE" '{".a":{"found":false}}')"

echo ""
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
