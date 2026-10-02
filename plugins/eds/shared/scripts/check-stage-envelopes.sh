#!/usr/bin/env bash
# Run: bash plugins/eds/shared/scripts/check-stage-envelopes.sh plugins/eds/pack.yaml plugins/eds/skills
#
# check-stage-envelopes.sh <pack.yaml> <skills dir>
#
# Deterministic. Fails when a route stage would leave its envelope for the
# driver to copy. For every `- id: <stage id>` / `skill: <skill>` pair in the
# manifest's `stages:` list, `<skills dir>/<skill>/SKILL.md` must exist and have
# at least one `### Report <verdict>` node (pass, warn, fail, question or skip),
# and every one of those nodes must name the emitter (`emit-envelope.sh`) and
# the stage's own envelope file (`envelope-<stage id>.txt`).
#
# Exit codes: 0 — every stage conforms; 1 — at least one violation, each named
# on stderr; 2 — usage.

set -uo pipefail

usage() {
  echo "usage: check-stage-envelopes.sh <pack.yaml> <skills dir>" >&2
  if [ "$#" -gt 0 ]; then echo "$1" >&2; fi
  exit 2
}

[ "$#" -eq 2 ] || usage "expected exactly 2 arguments"
PACK="$1"
DIR="$2"
[ -f "$PACK" ] || usage "'$PACK' is not a file"
[ -d "$DIR" ] || usage "'$DIR' is not a directory"

VIOLATIONS=0
STAGES=0
NODES=0

violation() {
  echo "invalid: $1" >&2
  VIOLATIONS=$((VIOLATIONS + 1))
}

# "<stage id> <skill>" per entry of the top-level `stages:` list.
pairs=$(awk '
  /^[^ #]/ { in_stages = ($0 ~ /^stages:/); next }
  in_stages && /^  - id: / { id = $3; next }
  in_stages && /^    skill: / && id != "" { print id, $2; id = "" }
' "$PACK")
[ -n "$pairs" ] || usage "'$PACK' has no stages: list with id/skill pairs"

# Prints each `### Report <verdict>` node of a file as "<heading>\t<body on one
# line>", a body ending at the next `#`/`##`/`###` heading outside a fence.
report_nodes() {
  awk '
    /^```/ { if (on) body = body " " $0; fence = !fence; next }
    !fence && /^#{1,3} / {
      if (on) print head "\t" body
      on = ($0 ~ /^### Report (pass|warn|fail|question|skip)$/); head = $0; body = ""; next
    }
    on { body = body " " $0 }
    END { if (on) print head "\t" body }
  ' "$1"
}

while read -r stage skill; do
  STAGES=$((STAGES + 1))
  file="$DIR/$skill/SKILL.md"
  if [ ! -f "$file" ]; then
    violation "$stage: no $file"
    continue
  fi
  nodes=$(report_nodes "$file")
  if [ -z "$nodes" ]; then
    violation "$file: no '### Report' node"
    continue
  fi
  while IFS=$'\t' read -r head body; do
    NODES=$((NODES + 1))
    case "$body" in *emit-envelope.sh*) ;; *) violation "$file: '${head#\#\#\# }' does not name emit-envelope.sh" ;; esac
    case "$body" in *"envelope-$stage.txt"*) ;; *) violation "$file: '${head#\#\#\# }' does not name envelope-$stage.txt" ;; esac
  done <<< "$nodes"
done <<< "$pairs"

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "invalid: $VIOLATIONS stage envelope violation(s)" >&2
  exit 1
fi
echo "valid: stage envelopes ($STAGES stages, $NODES report nodes)"
exit 0
