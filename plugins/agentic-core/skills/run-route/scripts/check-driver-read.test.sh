#!/usr/bin/env bash
# Tests for check-driver-read.sh. Run with:
#   bash plugins/agentic-core/skills/run-route/scripts/check-driver-read.test.sh
#
# Each case drives the checker the way the hook does: a tool-input JSON object
# on stdin, with CLAUDE_PROJECT_DIR pointed at a scratch directory so the log
# these tests assert on never lands in a real run's log, and CLAUDE_PLUGIN_ROOT
# pointed at a scratch plugin root — loaded by path inside the project, or
# cache-shaped outside it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/check-driver-read.sh"

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3" output="$4"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected exit=$expected, got exit=$actual"
    [[ -n "$output" ]] && echo "    output: $output"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected output to contain: $needle"
    echo "    got: $haystack"
  fi
}

# Create the scratch directory inside TMPDIR explicitly. Letting mktemp pick its
# own default can land outside a sandboxed run's writable set, and an empty WORK
# would silently send this suite's log writes into the real project.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-driver-read.XXXXXX")"
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
  echo "FAIL: could not create a scratch directory under ${TMPDIR:-/tmp}" >&2
  exit 1
fi
trap 'rm -rf "$WORK"' EXIT
LOG="$WORK/.ai/logs/run-route-reads.log"

# Two plugin roots: one loaded by path from inside the project, one shaped like
# an installed copy, outside it.
SRC_ROOT="$WORK/plugins/agentic-core"
CACHE_ROOT="$WORK/home/.claude/plugins/cache/a-market/agentic-core/1.4.0"
for r in "$SRC_ROOT" "$CACHE_ROOT"; do
  mkdir -p "$r/shared/lib" "$r/skills/run-route"
  : > "$r/shared/result-envelope.md"
done
ROOT="$SRC_ROOT"

# Drive the checker as the hook does, with ROOT as the plugin root.
run_check() {
  local path="$1"
  printf '{"tool_input":{"file_path":%s}}' "$(printf '%s' "$path" | jq -R .)" \
    | CLAUDE_PROJECT_DIR="$WORK" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$CHECKER" 2>&1
}

# A run is live while the orchestration marker exists; every case up to
# [no run] below is judged inside one.
FLAG="$WORK/.ai/run-context/orchestrating.flag"
mkdir -p "$(dirname "$FLAG")" && : > "$FLAG"

echo "[allow] the driver's own bookkeeping"
for p in .ai/project-config.yaml .ai/run-state.json .ai/progress.md .ai/route-progress.txt; do
  OUT=$(run_check "$p"); ST=$?
  assert_exit "$p proceeds" 0 $ST "$OUT"
done

echo "[allow] the shared contracts"
for p in plugins/agentic-core/shared/result-envelope.md \
         plugins/agentic-core/shared/run-state.md \
         plugins/agentic-core/shared/question-protocol.md; do
  OUT=$(run_check "$p"); ST=$?
  assert_exit "$p proceeds" 0 $ST "$OUT"
done

echo "[allow] an absolute path judges the same as a relative one"
OUT=$(run_check "$WORK/.ai/run-state.json"); ST=$?
assert_exit "absolute bookkeeping path proceeds" 0 $ST "$OUT"
OUT=$(run_check "$SRC_ROOT/shared/result-envelope.md"); ST=$?
assert_exit "absolute contract path proceeds" 0 $ST "$OUT"

echo "[deny] a path an envelope lists under artifacts:"
OUT=$(run_check ".ai/run-context/fact-record.yaml"); ST=$?
assert_exit "fact-record.yaml is blocked" 2 $ST ""
assert_contains "the reason names the denied path" "Denied: .ai/run-context/fact-record.yaml" "$OUT"
assert_contains "the reason names what is allowed" "$SRC_ROOT/shared/*.md" "$OUT"
assert_contains "the reason says where the read belongs" "isolated subagent" "$OUT"

echo "[deny] the whole run-context boundary, not just the one observed file"
OUT=$(run_check ".ai/run-context/sanitized-spec.md"); ST=$?
assert_exit "sanitized-spec.md is blocked" 2 $ST ""

echo "[deny] a script under the contract directory's lib/"
OUT=$(run_check "plugins/agentic-core/shared/lib/validate-result-envelope.sh"); ST=$?
assert_exit "a lib/ script is blocked" 2 $ST ""

echo "[deny] a .md nested below the contract directory is not a contract"
OUT=$(run_check "plugins/agentic-core/shared/lib/notes.md"); ST=$?
assert_exit "a nested .md is blocked" 2 $ST ""

echo "[deny] stage instructions, and the driver's own body"
OUT=$(run_check "plugins/a-pack/skills/a-stage/SKILL.md"); ST=$?
assert_exit "a stage's SKILL.md is blocked" 2 $ST ""
OUT=$(run_check "plugins/agentic-core/skills/run-route/SKILL.md"); ST=$?
assert_exit "the driver's own SKILL.md is blocked" 2 $ST ""

echo "[deny] a source file"
OUT=$(run_check "blocks/cards/cards.js"); ST=$?
assert_exit "a source file is blocked" 2 $ST ""

echo "[deny] an extension the old denylist never covered"
OUT=$(run_check "scripts/data.json"); ST=$?
assert_exit "a .json file is blocked" 2 $ST ""

echo "[edge] a path containing a space"
OUT=$(run_check "drafts/my draft.plain.html"); ST=$?
assert_exit "a spaced path is blocked, not split" 2 $ST ""
assert_contains "the reason keeps the path intact" "Denied: drafts/my draft.plain.html" "$OUT"

echo "[cache] the contracts of a plugin root outside the project"
ROOT="$CACHE_ROOT"
OUT=$(run_check "$CACHE_ROOT/shared/result-envelope.md"); ST=$?
assert_exit "a contract under a cache-shaped root proceeds" 0 $ST "$OUT"
OUT=$(run_check "$CACHE_ROOT/shared/never-written.md"); ST=$?
assert_exit "a contract the root does not hold yet proceeds too" 0 $ST "$OUT"
OUT=$(run_check "plugins/agentic-core/shared/result-envelope.md"); ST=$?
assert_exit "the source tree's copy is not the loaded root's contract" 2 $ST ""
assert_contains "the reason names the loaded root's contracts" "$CACHE_ROOT/shared/*.md" "$OUT"
OUT=$(run_check "$CACHE_ROOT/shared/lib/validate-result-envelope.sh"); ST=$?
assert_exit "a lib/ script under the cache root is blocked" 2 $ST ""
OUT=$(run_check "$CACHE_ROOT/shared/lib/notes.md"); ST=$?
assert_exit "a nested .md under the cache root is blocked" 2 $ST ""
OUT=$(run_check "$CACHE_ROOT/skills/run-route/SKILL.md"); ST=$?
assert_exit "the driver's own SKILL.md under the cache root is blocked" 2 $ST ""
OUT=$(run_check "$CACHE_ROOT/shared/../skills/run-route/SKILL.md"); ST=$?
assert_exit "a .. out of the contract directory is blocked" 2 $ST ""

echo "[canonical] one directory spelled two ways judges the same"
ln -s "$CACHE_ROOT" "$WORK/linked-root"
ROOT="$WORK/linked-root"
OUT=$(run_check "$CACHE_ROOT/shared/result-envelope.md"); ST=$?
assert_exit "root through a link, read by its real path" 0 $ST "$OUT"
ROOT="$CACHE_ROOT"
OUT=$(run_check "$WORK/linked-root/shared/result-envelope.md"); ST=$?
assert_exit "root by its real path, read through a link" 0 $ST "$OUT"
ROOT="$SRC_ROOT"

echo "[unset] no plugin root means no contract directory"
OUT=$(printf '{"tool_input":{"file_path":"plugins/agentic-core/shared/result-envelope.md"}}' \
  | CLAUDE_PROJECT_DIR="$WORK" bash -c 'unset CLAUDE_PLUGIN_ROOT; bash "$0"' "$CHECKER" 2>&1); ST=$?
assert_exit "a contract read is blocked" 2 $ST ""
assert_contains "the reason says the plugin root is not set" "plugin root is not set" "$OUT"
OUT=$(printf '{"tool_input":{"file_path":".ai/run-state.json"}}' \
  | CLAUDE_PROJECT_DIR="$WORK" bash -c 'unset CLAUDE_PLUGIN_ROOT; bash "$0"' "$CHECKER" 2>&1); ST=$?
assert_exit "bookkeeping still proceeds" 0 $ST "$OUT"

echo "[edge] no path at all"
OUT=$(printf '{"tool_input":{}}' | CLAUDE_PROJECT_DIR="$WORK" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$CHECKER" 2>&1); ST=$?
assert_exit "an empty path proceeds silently" 0 $ST "$OUT"
assert_exit "an empty path says nothing" 0 "${#OUT}" ""

echo "[log] every decision is recorded"
assert_contains "an allowed read is logged" "ALLOW .ai/run-state.json" "$(cat "$LOG")"
assert_contains "a denied read is logged" "DENY .ai/run-context/fact-record.yaml" "$(cat "$LOG")"
LINES_BEFORE=$(wc -l < "$LOG")
printf '{"tool_input":{}}' | CLAUDE_PROJECT_DIR="$WORK" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$CHECKER" >/dev/null 2>&1
assert_exit "an empty path adds no log line" "$LINES_BEFORE" "$(wc -l < "$LOG")" ""

echo "[no run] with no orchestration marker the hook judges nothing"
rm -f "$FLAG"
OUT=$(run_check "blocks/cards/cards.js"); ST=$?
assert_exit "a source file proceeds when no run is live" 0 $ST "$OUT"
assert_exit "and says nothing" 0 "${#OUT}" ""
OUT=$(run_check "notes/plan.md"); ST=$?
assert_exit "a document outside the allowlist proceeds when no run is live" 0 $ST "$OUT"
assert_contains "the read is logged as outside a run, not as ALLOW" "NORUN blocks/cards/cards.js" "$(cat "$LOG")"
if grep -q "ALLOW blocks/cards/cards.js" "$LOG"; then
  FAIL=$((FAIL + 1)); echo "  FAIL: a read outside a run is never logged as ALLOW"
else
  PASS=$((PASS + 1)); echo "  ok: a read outside a run is never logged as ALLOW"
fi

echo "[no run] a missing run-context directory is no run either"
rm -rf "$WORK/.ai/run-context"
OUT=$(run_check ".ai/run-context/fact-record.yaml"); ST=$?
assert_exit "proceeds" 0 $ST "$OUT"

echo "[live again] a new marker restores the allowlist"
mkdir -p "$(dirname "$FLAG")" && : > "$FLAG"
OUT=$(run_check "blocks/cards/cards.js"); ST=$?
assert_exit "a source file is blocked again" 2 $ST ""

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
