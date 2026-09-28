#!/usr/bin/env bash
# check-gate-reporting.test.sh — the pack's own skills conform, and each
# violation the checker names is caught on a copy made to break it.
#
# Usage:
#   bash check-gate-reporting.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-gate-reporting.sh"
SKILLS="$SCRIPT_DIR/../../skills"

PASS=0
FAIL=0

expect() {
  local desc="$1" want_exit="$2" want_text="$3" dir="$4" out rc
  out=$(bash "$CHECK" "$dir" 2>&1); rc=$?
  if [ "$rc" -eq "$want_exit" ] && [[ "$out" == *"$want_text"* ]]; then
    echo "  ok: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected exit=$want_exit containing: $want_text"
    echo "    got exit=$rc: $out"
    FAIL=$((FAIL + 1))
  fi
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-gate-reporting.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# A fresh copy of the two gates plus one ordinary forked stage, per case.
fresh() {
  rm -rf "$WORK/skills"
  mkdir -p "$WORK/skills"
  cp -R "$SKILLS/eds-publish-gate" "$SKILLS/eds-plan-gate" "$SKILLS/eds-lint" "$WORK/skills/"
}

echo "[accept] this pack's own skills"
expect "plugins/eds/skills conforms" 0 "valid: gate reporting" "$SKILLS"
expect "both gates are recognised" 0 "2 gates" "$SKILLS"

echo "[reject] text instructed after the block"
fresh
printf '\nFollow the block with each surviving finding, one short paragraph each.\n' \
  >> "$WORK/skills/eds-publish-gate/SKILL.md"
expect "publish-gate: 'Follow the block with' is caught" 1 "instructs text after the result block" "$WORK/skills"

fresh
printf '\nAfter the `## Result` block, list every warning.\n' >> "$WORK/skills/eds-lint/SKILL.md"
expect "any forked stage, not only a gate" 1 "eds-lint/SKILL.md" "$WORK/skills"

echo "[reject] a Report node that does not write through the emitter"
fresh
awk '/^### / { in_warn = ($0 == "### Report warn") }
     in_warn { gsub(/plan-gate-report\.md/, "other.md") } { print }' \
  "$WORK/skills/eds-plan-gate/SKILL.md" > "$WORK/p" && mv "$WORK/p" "$WORK/skills/eds-plan-gate/SKILL.md"
expect "warn without its report artifact" 1 "'Report warn' does not pass --artifact .ai/run-context/plan-gate-report.md" "$WORK/skills"

fresh
awk '/^### Report pass$/ { skip = 1; next } skip && /^#{2,3} / { skip = 0 } !skip { print }' \
  "$WORK/skills/eds-publish-gate/SKILL.md" > "$WORK/p" && mv "$WORK/p" "$WORK/skills/eds-publish-gate/SKILL.md"
expect "a missing Report node" 1 "no '### Report pass' node" "$WORK/skills"

fresh
awk '{ print } $0 == "- `verdict: fail`" { print "- `artifacts: []`" }' \
  "$WORK/skills/eds-publish-gate/SKILL.md" > "$WORK/p" && mv "$WORK/p" "$WORK/skills/eds-publish-gate/SKILL.md"
expect "artifacts: [] left in a Report node" 1 "'Report fail' still declares artifacts: []" "$WORK/skills"

fresh
for f in "$WORK"/skills/eds-publish-gate/SKILL.md; do
  sed 's/emit-envelope\.sh/write-it-yourself/g' "$f" > "$f.new" && mv "$f.new" "$f"
done
expect "no emitter named" 1 "does not name emit-envelope.sh" "$WORK/skills"

echo "[usage]"
expect "no argument" 2 "usage" ""
expect "not a directory" 2 "is not a directory" "$WORK/absent"

echo ""
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
