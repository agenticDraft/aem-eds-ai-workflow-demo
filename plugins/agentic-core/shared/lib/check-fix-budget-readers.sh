#!/usr/bin/env bash
# check-fix-budget-readers.sh — Deterministic answer to "does every declared
# edit budget have a reader?" A platform pack's stage may declare
# `fix_attempts` only when its skill asks check-fix-budget.sh (see
# shared/pack-manifest.md and shared/fix-loop.md). No model involved and no
# side effects.
#
# A stage reads its budget only if its `skills/<skill>/SKILL.md`, under the
# pack root, invokes check-fix-budget.sh: a line inside a fenced code block
# whose command word is the script, run directly or through `bash`. A mention
# in prose or inline code is not an invocation. A stage that invokes the
# script without declaring `fix_attempts` is allowed — it reads the configured
# default.
#
# Usage:
#   check-fix-budget-readers.sh <pack root>
#
# Exit codes:
#   0 — "valid: every declared fix_attempts has a reader (<n> declared)"
#   1 — one "invalid: stage '<id>' …" line on stderr per stage that declares
#       `fix_attempts` with no reader, or whose skill file does not exist
#   2 — usage error (wrong argument count, pack root or pack.yaml not found)

set -uo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: check-fix-budget-readers.sh <pack root>" >&2
  exit 2
fi

ROOT="${1%/}"
PACK="$ROOT/pack.yaml"

if [[ ! -d "$ROOT" ]]; then
  echo "invalid: pack root not found: $ROOT" >&2
  exit 2
fi
if [[ ! -f "$PACK" ]]; then
  echo "invalid: file not found: $PACK" >&2
  exit 2
fi

# --- one "<id> <skill>" line per stage that declares fix_attempts ------------
# Read inside the top-level `stages:` list only — other lists (artifacts) use
# the same "  - id:" shape. An entry's keys may come in any order, so each entry
# is printed when the next one, or the next top-level key, begins.
DECLARED="$(awk '
  function flush() { if (id != "" && has_budget) print id " " skill; id = ""; skill = ""; has_budget = 0 }
  /^[^ ]/                  { flush(); in_stages = ($0 ~ /^stages:[ ]*$/); next }
  in_stages && /^  - id: / { flush(); id = $0; sub(/^  - id:[ ]*/, "", id); next }
  in_stages && /^    skill:/        { skill = $0; sub(/^    skill:[ ]*/, "", skill); next }
  in_stages && /^    fix_attempts:/ { has_budget = 1; next }
  END { flush() }
' "$PACK")"

# --- does a skill file invoke the script inside a fenced block? --------------
invokes_budget_script() {
  awk '
    /^[ \t]*(```|~~~)/ { in_fence = !in_fence; next }
    in_fence {
      cmd = $1
      if (cmd == "bash") cmd = $2
      sub(/.*\//, "", cmd)
      if (cmd == "check-fix-budget.sh") { found = 1; exit }
    }
    END { exit !found }
  ' "$1"
}

COUNT=0
BAD=0
while read -r STAGE SKILL; do
  [[ -n "$STAGE" ]] || continue
  COUNT=$((COUNT + 1))
  SKILL_FILE="$ROOT/skills/$SKILL/SKILL.md"
  if [[ -z "$SKILL" ]]; then
    echo "invalid: stage '$STAGE' declares 'fix_attempts' and names no skill" >&2
    BAD=$((BAD + 1))
  elif [[ ! -f "$SKILL_FILE" ]]; then
    echo "invalid: stage '$STAGE' declares 'fix_attempts'; its skill file is not found: skills/$SKILL/SKILL.md" >&2
    BAD=$((BAD + 1))
  elif ! invokes_budget_script "$SKILL_FILE"; then
    echo "invalid: stage '$STAGE' declares 'fix_attempts'; skills/$SKILL/SKILL.md never invokes check-fix-budget.sh" >&2
    BAD=$((BAD + 1))
  fi
done <<< "$DECLARED"

(( BAD == 0 )) || exit 1

echo "valid: every declared fix_attempts has a reader ($COUNT declared)"
exit 0
