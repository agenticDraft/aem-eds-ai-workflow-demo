#!/usr/bin/env bash
# Tests for check-direct-script-calls.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-direct-script-calls.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Each case writes
# a small transcript in the shape the runtime writes for a subagent: one JSON
# object per line, tool calls under message.content[].

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-direct-script-calls.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-direct-script-calls.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# tool_use <name> <json input> — one transcript line holding one tool call
tool_use() {
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"%s","input":%s}]}}\n' "$1" "$2"
}
bash_call() { tool_use Bash "$(jq -cn --arg c "$1" '{command: $c}')"; }
skill_call() { tool_use Skill "$(jq -cn --arg s "$1" '{skill: $s, args: "target: http://localhost:3001/x"}')"; }

run() {  # run <own pack> <files...> — sets OUT, STATUS
  OUT="$(bash "$CHECK" "$@" 2>&1)"; STATUS=$?
}
has()    { grep -qF -- "$2" <<<"$OUT" && ok "$1" || bad "$1" "$OUT"; }
hasnot() { grep -qF -- "$2" <<<"$OUT" && bad "$1" "$OUT" || ok "$1"; }

echo "# a stage that runs other packs' operation scripts itself"
T="$WORK/direct.jsonl"
{
  printf '{"type":"user","message":{"role":"user","content":"start"}}\n'
  bash_call 'cat .ai/run-context/fact-record.yaml'
  skill_call browserpack:render
  bash_call 'node plugins/browserpack/skills/render/scripts/render.cjs http://localhost:3001/x; echo "exit=$?"'
  bash_call 'P=plugins/browserpack/skills; node $P/capture/scripts/capture.cjs http://localhost:3001/x 1440; node $P/measure/scripts/measure.cjs http://localhost:3001/x ".t"'
  bash_call $'for f in a b; do bash plugins/trackerpack/skills/attach-file/scripts/attach-file.sh KEY "$f"\ndone'
  bash_call 'python3 plugins/platformpack/skills/stage-x/scripts/own.py; bash plugins/agentic-core/shared/lib/emit-envelope.sh out.txt --verdict warn'
  bash_call 'bash plugins/platformpack/shared/scripts/helper.sh'
  bash_call 'bash plugins/agentic-core/shared/lib/check-reachability.sh "http://localhost:3001/x" "plugins/browserpack/skills/render/scripts/render.cjs"'
  bash_call 'grep -n require plugins/browserpack/skills/capture/scripts/capture.cjs | head'
  bash_call 'bash plugins/trackerpack/skills/attach-file/scripts/attach-file.sh KEY c'
} > "$T"
run platformpack "$T"
[[ "$STATUS" -eq 1 ]] && ok "exits 1" || bad "exits 1" "got $STATUS" "$OUT"
has "capture behind a variable prefix is named, with the command's start" \
  "direct	browserpack/capture	direct.jsonl	P=plugins/browserpack/skills; node \$P/capture"
has "measure from the same command is named too" "direct	browserpack/measure	direct.jsonl	"
[[ "$(grep -c "^direct	trackerpack/attach-file	" <<<"$OUT")" -eq 2 ]] \
  && ok "the tracker script is named once per command that ran it, a multi-line one included" \
  || bad "the tracker script is named once per command that ran it, a multi-line one included" "$OUT"
hasnot "the render script run right after its skill was invoked is the operation's own" "browserpack/render"
hasnot "the stage's own pack is never reported" "platformpack/"
hasnot "the core's shared library is never reported" "agentic-core"
hasnot "a pack's shared scripts are never reported" "shared/scripts"
hasnot "a script path given as an argument is never reported" "check-reachability"
has "summary counts every direct call" "invalid: 4 provider script(s) run directly"

echo "# the most recent skill invocation licenses only its own script"
L="$WORK/licence.jsonl"
{
  skill_call browserpack:render
  bash_call 'node plugins/browserpack/skills/render/scripts/render.cjs http://localhost:3001/x'
  bash_call 'node plugins/browserpack/skills/render/scripts/render.cjs http://localhost:3001/x'
  bash_call 'node plugins/browserpack/skills/capture/scripts/capture.cjs http://localhost:3001/x 1440'
  skill_call browserpack:capture
  bash_call 'node plugins/browserpack/skills/capture/scripts/capture.cjs http://localhost:3001/x 375'
  bash_call 'node plugins/browserpack/skills/render/scripts/render.cjs http://localhost:3001/x'
} > "$L"
run platformpack "$L"
[[ "$STATUS" -eq 1 ]] && ok "exits 1" || bad "exits 1" "got $STATUS" "$OUT"
[[ "$(grep -c "^direct	browserpack/capture	" <<<"$OUT")" -eq 1 ]] && ok "capture before its skill was invoked is direct, once" || bad "capture before its skill was invoked is direct, once" "$OUT"
[[ "$(grep -c "^direct	browserpack/render	" <<<"$OUT")" -eq 1 ]] && ok "render after another operation's skill is direct; the retry right after its own skill is not" || bad "render after another operation's skill is direct; the retry right after its own skill is not" "$OUT"
has "summary" "invalid: 2 provider script(s) run directly"

echo "# a stage that only invokes operations"
C="$WORK/clean.jsonl"
{
  skill_call browserpack:render
  bash_call 'node plugins/browserpack/skills/render/scripts/render.cjs http://localhost:3001/x'
  skill_call browserpack:measure
  bash_call 'node plugins/browserpack/skills/measure/scripts/measure.cjs http://localhost:3001/x ".t"'
  bash_call 'python3 plugins/platformpack/skills/stage-x/scripts/own.py .ai/run-context/x.json'
  bash_call 'bash plugins/agentic-core/shared/lib/emit-envelope.sh out.txt --verdict pass'
} > "$C"
run platformpack "$C"
[[ "$STATUS" -eq 0 ]] && ok "exits 0" || bad "exits 0" "got $STATUS" "$OUT"
has "summary counts the commands read" "ok: no provider script run directly (4 commands read)"

echo "# several transcripts in one call"
run platformpack "$C" "$T"
[[ "$STATUS" -eq 1 ]] && ok "one direct transcript among several exits 1" || bad "one direct transcript among several exits 1" "got $STATUS"
has "each line names its transcript" "	direct.jsonl	"

echo "# an installed copy: scripts under cache/<marketplace>/<pack>/<version>/skills/"
K="$WORK/cache.jsonl"
CACHE='/home/u/.claude/plugins/cache/a-market'
{
  bash_call "node $CACHE/browserpack/1.2.0/skills/capture/scripts/capture.cjs http://localhost:3001/x 1440"
  bash_call "P=$CACHE/trackerpack/0.3.1/skills; bash \$P/attach-file/scripts/attach-file.sh KEY a"
  skill_call browserpack:render
  bash_call "node $CACHE/browserpack/1.2.0/skills/render/scripts/render.cjs http://localhost:3001/x"
  bash_call "python3 $CACHE/platformpack/2.0.0/skills/stage-x/scripts/own.py"
  bash_call "bash $CACHE/agentic-core/1.0.0/shared/lib/emit-envelope.sh out.txt --verdict pass"
  bash_call "bash $CACHE/browserpack/1.2.0/shared/scripts/helper.sh"
} > "$K"
run platformpack "$K"
[[ "$STATUS" -eq 1 ]] && ok "exits 1" || bad "exits 1" "got $STATUS" "$OUT"
has "a direct call through a cache path is named by its pack, not its version" "direct	browserpack/capture	cache.jsonl	"
has "a cache path behind a variable prefix is resolved" "direct	trackerpack/attach-file	cache.jsonl	"
hasnot "the operation's own script, right after its skill, is not reported" "browserpack/render"
hasnot "the stage's own pack is never reported from the cache either" "platformpack/"
hasnot "the core's library in the cache is never reported" "agentic-core"
hasnot "a pack's shared scripts in the cache are never reported" "shared/scripts"
awk -F'\t' '$1 == "direct" && $2 ~ /^[0-9]/' <<<"$OUT" | grep -q . \
  && bad "the version is never taken for the pack" "$OUT" \
  || ok "the version is never taken for the pack"
has "summary" "invalid: 2 provider script(s) run directly"

echo "# usage errors"
run platformpack
[[ "$STATUS" -eq 2 ]] && ok "no transcript → exit 2" || bad "no transcript → exit 2" "got $STATUS"
run platformpack "$WORK/missing.jsonl"
[[ "$STATUS" -eq 2 ]] && ok "a missing transcript → exit 2" || bad "a missing transcript → exit 2" "got $STATUS"
printf 'not json\n' > "$WORK/bad.jsonl"
run platformpack "$WORK/bad.jsonl"
[[ "$STATUS" -eq 2 ]] && ok "a line that is not JSON → exit 2" || bad "a line that is not JSON → exit 2" "got $STATUS" "$OUT"

echo "# the contract states the one-call, one-script rule the checker enforces"
CONTRACT="$SCRIPT_DIR/../role-operations.md"
grep -qF 'One invocation runs one script, alone in its own command' "$CONTRACT" \
  && ok "one invocation, one script, its own command" \
  || bad "one invocation, one script, its own command" "not in $CONTRACT"
grep -qF 'every call, on every check, is a new invocation' "$CONTRACT" \
  && ok "every call is a new invocation" \
  || bad "every call is a new invocation" "not in $CONTRACT"

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
