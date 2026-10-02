#!/usr/bin/env bash
# check-stage-envelopes.test.sh — the pack's own stages conform, and each
# violation the checker names is caught on a copy made to break it.
#
# Usage:
#   bash check-stage-envelopes.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-stage-envelopes.sh"
PACK="$SCRIPT_DIR/../../pack.yaml"
SKILLS="$SCRIPT_DIR/../../skills"

PASS=0
FAIL=0

expect() {
  local desc="$1" want_exit="$2" want_text="$3" pack="$4" dir="$5" out rc
  out=$(bash "$CHECK" "$pack" "$dir" 2>&1); rc=$?
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

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-stage-envelopes.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# A one-stage pack over a fresh copy of eds-lint and eds-deliver, per case.
fresh() {
  rm -rf "$WORK/skills"
  mkdir -p "$WORK/skills"
  cp -R "$SKILLS/eds-lint" "$SKILLS/eds-deliver" "$WORK/skills/"
  printf 'kind: platform\nstages:\n  - id: lint\n    skill: eds-lint\n  - id: deliver\n    skill: eds-deliver\nartifacts:\n  - id: x\n' \
    > "$WORK/pack.yaml"
}

echo "[accept] this pack's own stages"
expect "every eds stage conforms" 0 "valid: stage envelopes (15 stages" "$PACK" "$SKILLS"

echo "[accept] a working node named 'Report back to …' is not a verdict node"
fresh
expect "deliver's 'Report back to the tracker' is ignored" 0 "valid: stage envelopes (2 stages" "$WORK/pack.yaml" "$WORK/skills"

echo "[reject] a Report node that tells the stage to emit the block itself"
fresh
python3 - "$WORK/skills/eds-lint/SKILL.md" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
head, sep, tail = s.partition("### Report pass\n")
tail = re.sub(r"Write the envelope with the emitter.*?Values to pass:",
              "Emit the `## Result` block as plain `key: value` lines. Fields:", tail, count=1, flags=re.S)
open(p, "w").write(head + sep + tail)
PY
expect "names the emitter it lost" 1 "'Report pass' does not name emit-envelope.sh" "$WORK/pack.yaml" "$WORK/skills"
expect "names the envelope file it lost" 1 "'Report pass' does not name envelope-lint.txt" "$WORK/pack.yaml" "$WORK/skills"

echo "[reject] a Report node that writes another stage's envelope"
fresh
sed -i.bak 's/envelope-lint\.txt/envelope-plan.txt/' "$WORK/skills/eds-lint/SKILL.md"
expect "the wrong file is caught" 1 "does not name envelope-lint.txt" "$WORK/pack.yaml" "$WORK/skills"

echo "[reject] a stage whose skill is missing, or has no verdict node"
fresh
rm -rf "$WORK/skills/eds-deliver"
expect "a missing skill is named" 1 "deliver: no " "$WORK/pack.yaml" "$WORK/skills"
fresh
sed -i.bak 's/^### Report /### Done /' "$WORK/skills/eds-lint/SKILL.md"
expect "a skill with no verdict node is named" 1 "no '### Report' node" "$WORK/pack.yaml" "$WORK/skills"

echo "[usage]"
expect "no arguments" 2 "usage:" "" ""
expect "a pack with no stages" 2 "has no stages" "$SKILLS/eds-lint/SKILL.md" "$SKILLS"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ]
