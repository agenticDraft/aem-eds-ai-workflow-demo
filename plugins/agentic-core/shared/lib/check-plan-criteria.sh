#!/usr/bin/env bash
# check-plan-criteria.sh — Deterministic half of the plan gate (see
# shared/plan-criteria.md, shared/gate-contract.md). No model involved:
# this is the mechanical check that runs before any reviewing model sees
# the plan, per the gate contract's fixed order.
#
# Checks two of the plan gate's four criteria — the two that are
# structural rather than judgment:
#   1. Every requirement maps to at least one stage (its id appears in
#      some stage's `satisfies` list).
#   2. No stage appeared that no requirement asked for (every stage's
#      `satisfies` list names at least one requirement that exists).
# The other two criteria — does the dependency order hold, is the
# verification defined — are judgment, not structure, and are the
# reviewing model's job once this check passes; see plan-criteria.md.
#
# Usage:
#   check-plan-criteria.sh <path-to-plan-file>
#
# Exit codes:
#   0 — both structural criteria hold; "valid: plan (<n> requirements,
#       <m> stages)" on stdout
#   1 — a criterion fails; "invalid: <reason>" on stderr, naming the
#       unmapped requirement or the unrequested stage
#   2 — usage error (no argument, file not found)

set -uo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
  echo "usage: check-plan-criteria.sh <path-to-plan-file>" >&2
  exit 2
fi

if [[ ! -f "$FILE" ]]; then
  echo "invalid: file not found: $FILE" >&2
  exit 2
fi

fail() {
  echo "invalid: $1" >&2
  exit 1
}

# Read the file into an indexed array one line at a time, stripping blank
# lines and full-line comments, for maximum portability across shell
# versions — the same read loop validate-artifact-registry.sh uses.
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  LINES+=("$line")
done < "$FILE"
n=${#LINES[@]}
cursor=0

[[ "${LINES[cursor]:-}" == "requirements:" ]] || fail "expected 'requirements:', found: '${LINES[cursor]:-<end of file>}'"
cursor=$((cursor + 1))

REQUIREMENTS=()
while [[ "${LINES[cursor]:-}" =~ ^\ \ -\ (.+)$ ]]; do
  req="${BASH_REMATCH[1]}"
  for existing in "${REQUIREMENTS[@]:-}"; do
    [[ "$existing" == "$req" ]] && fail "duplicate requirement id: '$req'"
  done
  REQUIREMENTS+=("$req")
  cursor=$((cursor + 1))
done

(( ${#REQUIREMENTS[@]} == 0 )) && fail "no requirements listed"

requirement_known() {
  local id="$1"
  for existing in "${REQUIREMENTS[@]}"; do
    [[ "$existing" == "$id" ]] && return 0
  done
  return 1
}

[[ "${LINES[cursor]:-}" == "stages:" ]] || fail "expected 'stages:', found: '${LINES[cursor]:-<end of file>}'"
cursor=$((cursor + 1))

STAGE_IDS=()
COVERED=()
while [[ "${LINES[cursor]:-}" =~ ^\ \ -\ id:\ (.+)$ ]]; do
  stage_id="${BASH_REMATCH[1]}"
  STAGE_IDS+=("$stage_id")
  cursor=$((cursor + 1))

  [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ satisfies:\ \[(.*)\]$ ]] \
    || fail "'$stage_id' is missing its 'satisfies' list"
  satisfies_content="${BASH_REMATCH[1]}"
  cursor=$((cursor + 1))

  requested=0
  IFS=',' read -ra raw_ids <<< "$satisfies_content"
  for raw_id in "${raw_ids[@]:-}"; do
    id="${raw_id#"${raw_id%%[![:space:]]*}"}"
    id="${id%"${id##*[![:space:]]}"}"
    [[ -z "$id" ]] && continue
    if requirement_known "$id"; then
      requested=1
      COVERED+=("$id")
    fi
  done

  (( requested == 0 )) && fail "stage '$stage_id' satisfies no requirement — unrequested"
done

if (( cursor < n )); then
  fail "unexpected content: '${LINES[cursor]}'"
fi

(( ${#STAGE_IDS[@]} == 0 )) && fail "no stages listed"

for req in "${REQUIREMENTS[@]}"; do
  mapped=0
  for covered in "${COVERED[@]:-}"; do
    [[ "$covered" == "$req" ]] && { mapped=1; break; }
  done
  (( mapped == 0 )) && fail "requirement '$req' maps to no stage"
done

echo "valid: plan (${#REQUIREMENTS[@]} requirements, ${#STAGE_IDS[@]} stages)"
exit 0
