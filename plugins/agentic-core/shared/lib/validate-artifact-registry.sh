#!/usr/bin/env bash
# validate-artifact-registry.sh — Deterministic conformance check for the
# core artifact registry (see shared/artifact-registry.md). No model
# involved: this is the CI floor a registry entry must clear before it
# counts as a real, core-owned artifact rather than a line of prose.
#
# Checks the fixed shape shared/artifact-registry.md defines: a bare list
# of entries, each `id`, `version`, `produced_by`, `required_content`,
# `validation`, in that order. `produced_by` must name one of the core's
# own fixed producers — the two reserved stages, the two gate stages, or
# the runner itself. An open, pack-declared stage id is never a valid
# producer here: a core-owned artifact's producer is core vocabulary, the
# same separation pack-manifest.md draws between a pack's own artifacts
# (checked against that pack's own `stages:` map) and this registry's.
#
# Usage:
#   validate-artifact-registry.sh <path-to-registry-file>
#
# Exit codes:
#   0 — conformant; "valid: artifact registry (<n> entries)" on stdout
#   1 — contract violation; "invalid: <reason>" on stderr
#   2 — usage error (no argument, file not found)

set -uo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
  echo "usage: validate-artifact-registry.sh <path-to-registry-file>" >&2
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

PRODUCERS=(intake deliver plan-gate publish-gate runner)
producer_known() {
  local id="$1"
  for existing in "${PRODUCERS[@]}"; do
    [[ "$existing" == "$id" ]] && return 0
  done
  return 1
}

# Read the file into an indexed array one line at a time, stripping blank
# lines and full-line comments, for maximum portability across shell
# versions.
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  LINES+=("$line")
done < "$FILE"
n=${#LINES[@]}
cursor=0

IDS=()
count=0
while [[ "${LINES[cursor]:-}" =~ ^-\ id:\ (.+)$ ]]; do
  id="${BASH_REMATCH[1]}"
  cursor=$((cursor + 1))

  for existing in "${IDS[@]:-}"; do
    [[ "$existing" == "$id" ]] && fail "duplicate artifact id: '$id'"
  done
  IDS+=("$id")

  [[ "${LINES[cursor]:-}" =~ ^\ \ version:\ (.+)$ ]] \
    || fail "'$id' is missing its 'version'"
  cursor=$((cursor + 1))

  [[ "${LINES[cursor]:-}" =~ ^\ \ produced_by:\ (.+)$ ]] \
    || fail "'$id' has no producer"
  producer="${BASH_REMATCH[1]}"
  cursor=$((cursor + 1))
  producer_known "$producer" \
    || fail "'$id' names a producer that does not exist: '$producer'"

  [[ "${LINES[cursor]:-}" =~ ^\ \ required_content:\ (.+)$ ]] \
    || fail "'$id' is missing its 'required_content'"
  cursor=$((cursor + 1))

  [[ "${LINES[cursor]:-}" =~ ^\ \ validation:\ (.+)$ ]] \
    || fail "'$id' is missing its 'validation'"
  cursor=$((cursor + 1))

  count=$((count + 1))
done

if (( cursor < n )); then
  fail "unexpected content: '${LINES[cursor]}'"
fi

if (( count == 0 )); then
  fail "registry has no entries"
fi

echo "valid: artifact registry ($count entries)"
exit 0
