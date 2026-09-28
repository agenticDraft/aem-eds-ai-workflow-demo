#!/usr/bin/env bash
# Run: bash plugins/eds/shared/scripts/check-gate-reporting.sh plugins/eds/skills
#
# check-gate-reporting.sh <skills dir>
#
# Deterministic. Fails when a stage skill's own text would put anything after
# its result block, or when a gate skill does not write its findings report and
# its envelope the way the gate contract requires. Two checks:
#
#   1. Every `context: fork` skill: no line instructs text after the block
#      ("Follow the block with …", "After the block, …").
#   2. Every skill running as the gate reviewer agent, `eds-<gate id>`: each
#      of its `### Report pass`, `### Report warn` and `### Report fail` nodes
#      exists, names the emitter (`emit-envelope.sh`), names its envelope file
#      (`envelope-<gate id>.txt`), passes `--artifact
#      .ai/run-context/<gate id>-report.md`, and carries no `artifacts: []`.
#
# Exit codes: 0 — every skill conforms; 1 — at least one violation, each named
# on stderr; 2 — usage.

set -uo pipefail

usage() {
  echo "usage: check-gate-reporting.sh <skills dir>" >&2
  if [ "$#" -gt 0 ]; then echo "$1" >&2; fi
  exit 2
}

[ "$#" -eq 1 ] || usage "expected exactly 1 argument"
DIR="$1"
[ -d "$DIR" ] || usage "'$DIR' is not a directory"

VIOLATIONS=0
FORKS=0
GATES=0

violation() {
  echo "invalid: $1" >&2
  VIOLATIONS=$((VIOLATIONS + 1))
}

# Prints the body of one `### <heading>` section: every line after the heading
# up to the next `#`/`##`/`###` heading outside a fenced block.
section() {
  awk -v want="### $2" '
    /^```/ { if (on) print; fence = !fence; next }
    !fence && /^#{1,3} / { if (on) exit; if ($0 == want) { on = 1; next } }
    on { print }
  ' "$1"
}

for skill in "$DIR"/*/SKILL.md; do
  [ -f "$skill" ] || continue
  head_block=$(awk 'NR == 1 && /^---$/ { on = 1; next } on && /^---$/ { exit } on { print }' "$skill")
  printf '%s\n' "$head_block" | grep -q '^context: fork$' || continue
  FORKS=$((FORKS + 1))

  hits=$(grep -niE 'follow the (`## Result` )?block with|after the (`## Result` )?block,? (write|list|add|follow|append)' "$skill")
  if [ -n "$hits" ]; then
    while IFS= read -r hit; do
      violation "$skill:${hit%%:*}: instructs text after the result block"
    done <<< "$hits"
  fi

  printf '%s\n' "$head_block" | grep -qE '^agent: [^ ]*:?[^ ]*gate-reviewer$' || continue
  GATES=$((GATES + 1))
  name=$(basename "$(dirname "$skill")")
  gate="${name#*-}"

  for verdict in pass warn fail; do
    body=$(section "$skill" "Report $verdict")
    if [ -z "$body" ]; then
      violation "$skill: no '### Report $verdict' node"
      continue
    fi
    printf '%s\n' "$body" | grep -q 'emit-envelope\.sh' \
      || violation "$skill: 'Report $verdict' does not name emit-envelope.sh"
    printf '%s\n' "$body" | grep -qF "envelope-$gate.txt" \
      || violation "$skill: 'Report $verdict' does not name envelope-$gate.txt"
    printf '%s\n' "$body" | grep -qF -- "--artifact .ai/run-context/$gate-report.md" \
      || violation "$skill: 'Report $verdict' does not pass --artifact .ai/run-context/$gate-report.md"
    if printf '%s\n' "$body" | grep -qF 'artifacts: []'; then
      violation "$skill: 'Report $verdict' still declares artifacts: []"
    fi
  done
done

if [ "$VIOLATIONS" -gt 0 ]; then
  exit 1
fi
echo "valid: gate reporting ($FORKS forked skills, $GATES gates)"
exit 0
