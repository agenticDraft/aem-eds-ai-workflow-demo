#!/usr/bin/env bash
# check-component-reuse.sh — Deterministic create-vs-extend answer (D10 reuse
# map) for every component/file the work item names. No model involved.
#
# Usage:
#   check-component-reuse.sh <path-to-fact-record.yaml> [project-root]
#
# Globs `<project-root>/blocks/` for existing block directories, then checks
# each of the fact record's `components` and `files_named` entries against
# that inventory.
#
# Output:
#   existing_blocks=<comma-list, or (none)>
#   reuse=<name>   # one line per named entry that matches an existing block
#   new=<name>     # one line per named entry with no existing block
#   decision=no_components_named   # only when both fields are empty
#
# Exit codes:
#   0 — decided (every branch above is a decision, not an error)
#   2 — usage error (missing argument, file not found)
#
# Bash 3.2-safe on purpose (macOS ships no newer bash on PATH by default):
# no `mapfile`/`readarray`, and every array is seeded with `=()` before a
# loop appends to it so `set -u` never trips on one that stayed empty.

set -uo pipefail

FACT="${1:-}"
ROOT="${2:-.}"

if [[ -z "$FACT" ]]; then
  echo "usage: check-component-reuse.sh <path-to-fact-record.yaml> [project-root]" >&2
  exit 2
fi
[[ -f "$FACT" ]] || { echo "invalid: file not found: $FACT" >&2; exit 2; }

field() {
  local want="$1" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^${want}:[[:space:]]*\[(.*)\][[:space:]]*$ ]] || continue
    echo "${BASH_REMATCH[1]}"
    return 0
  done < "$FACT"
  return 1
}

# split_list <raw comma-separated body> — prints each trimmed, unquoted entry
# on its own line. No array-by-name trick (no `eval`, no bash-4-only
# nameref) — these entries trace back to a tracker item's own text, and this
# script never treats fetched text as anything but a literal string to
# compare, never as something to evaluate.
split_list() {
  local raw="$1" item
  [[ -z "$raw" ]] && return 0
  IFS=',' read -ra parts <<< "$raw"
  for item in "${parts[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    item="${item%\"}"; item="${item#\"}"
    [[ -n "$item" ]] && echo "$item"
  done
}

components=()
while IFS= read -r line; do
  [[ -n "$line" ]] && components+=("$line")
done < <(split_list "$(field components || true)")

files_named=()
while IFS= read -r line; do
  [[ -n "$line" ]] && files_named+=("$line")
done < <(split_list "$(field files_named || true)")

existing=()
shopt -s nullglob
for d in "$ROOT"/blocks/*/; do
  existing+=("$(basename "$d")")
done
shopt -u nullglob

if [[ ${#existing[@]} -eq 0 ]]; then
  echo "existing_blocks=(none)"
else
  IFS=,; echo "existing_blocks=${existing[*]}"; unset IFS
fi

exists_in() {
  local want="$1" e
  for e in "${existing[@]:-}"; do
    [[ "$e" == "$want" ]] && return 0
  done
  return 1
}

named_any=0
for name in "${components[@]:-}" "${files_named[@]:-}"; do
  [[ -z "$name" ]] && continue
  named_any=1
  base="$(basename "$name")"
  base="${base%.*}"
  if exists_in "$base"; then
    echo "reuse=$name"
  else
    echo "new=$name"
  fi
done

if [[ $named_any -eq 0 ]]; then
  echo "decision=no_components_named"
fi
exit 0
