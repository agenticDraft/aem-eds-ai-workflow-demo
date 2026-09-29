#!/usr/bin/env bash
# check-component-reuse.sh — Deterministic create-vs-extend answer (D10 reuse
# map) for every component/file the work item names. No model involved.
#
# Usage:
#   check-component-reuse.sh <path-to-fact-record.yaml> [project-root] [manifest]
#
# Globs `<project-root>/blocks/` for existing block directories, then checks
# each of the fact record's `components` and `files_named` entries against
# that inventory, then against the pinned upstream block collection (D528):
# `manifest` defaults to the one this pack ships in
# `shared/block-collection/`, written only by refresh-block-collection.sh.
# Read from disk only — this script never touches the network.
#
# Output:
#   existing_blocks=<comma-list, or (none)>
#   upstream_manifest=<pinned commit> | unavailable: <reason>
#   reuse=<name>     # a named entry that matches an existing block
#   upstream=<name>  # no existing block; the collection has it vendored
#   new=<name>       # in neither
#   upstream_unknown=<name>  # no existing block, and the manifest is missing
#                    # or malformed: could not check — never reported as `new`.
#                    # The caller warns and continues as new.
#   decision=no_components_named   # only when both fields are empty
#   exemplar=<name>  # ALWAYS emitted (1-2 lines, or `(none)`): the existing
#                    # units whose conventions a new unit should follow. The
#                    # reuse matches when there are any, else the first two
#                    # non-structural blocks. `plan` has no other source.
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${3:-$SCRIPT_DIR/../../../shared/block-collection/manifest.txt}"

if [[ -z "$FACT" ]]; then
  echo "usage: check-component-reuse.sh <path-to-fact-record.yaml> [project-root] [manifest]" >&2
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

# read_manifest — fills `upstream` and `pin`, or sets `manifest_error`. Every
# line must be a comment, blank, or one of `repo=`, `commit=`, `block=`; each
# listed block must have its vendored files, and the upstream LICENSE must sit
# beside the manifest — a copy without it could not be redistributed.
upstream=()
pin=""
manifest_error=""
read_manifest() {
  local line repo="" dir
  dir="$(dirname "$MANIFEST")"
  [[ -f "$MANIFEST" ]] || { manifest_error="manifest not found"; return; }
  [[ -r "$MANIFEST" ]] || { manifest_error="manifest not readable"; return; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      ''|'#'*) ;;
      repo=?*) repo="${line#repo=}" ;;
      commit=*) pin="${line#commit=}" ;;
      block=*)
        if [[ "${line#block=}" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
          upstream+=("${line#block=}")
        else
          manifest_error="unsafe block name: ${line#block=}"; return
        fi ;;
      *) manifest_error="unreadable line: $line"; return ;;
    esac
  done < "$MANIFEST"
  [[ -n "$repo" ]] || { manifest_error="no repo line"; return; }
  [[ "$pin" =~ ^[0-9a-f]{40}$ ]] || { manifest_error="commit is not a full 40-hex id"; return; }
  [[ ${#upstream[@]} -gt 0 ]] || { manifest_error="no block listed"; return; }
  [[ -s "$dir/LICENSE" ]] || { manifest_error="no upstream LICENSE beside the manifest"; return; }
  local b f found
  for b in "${upstream[@]}"; do
    found=0
    for f in "$dir/blocks/$b"/*; do [[ -f "$f" ]] && found=1; done
    [[ $found -eq 1 ]] || { manifest_error="no vendored files for block $b"; return; }
  done
}
read_manifest
if [[ -n "$manifest_error" ]]; then
  upstream=()
  echo "upstream_manifest=unavailable: $manifest_error"
else
  echo "upstream_manifest=$pin"
fi

in_upstream() {
  local want="$1" u
  for u in "${upstream[@]:-}"; do
    [[ "$u" == "$want" ]] && return 0
  done
  return 1
}

exists_in() {
  local want="$1" e
  for e in "${existing[@]:-}"; do
    [[ "$e" == "$want" ]] && return 0
  done
  return 1
}

named_any=0
reused=()
for name in "${components[@]:-}" "${files_named[@]:-}"; do
  [[ -z "$name" ]] && continue
  named_any=1
  base="$(basename "$name")"
  base="${base%.*}"
  if exists_in "$base"; then
    echo "reuse=$name"
    reused+=("$base")
  elif [[ -n "$manifest_error" ]]; then
    echo "upstream_unknown=$name"
  elif in_upstream "$base"; then
    echo "upstream=$name"
  else
    echo "new=$name"
  fi
done

if [[ $named_any -eq 0 ]]; then
  echo "decision=no_components_named"
fi

# Exemplars are emitted on every path, including no_components_named: `plan`
# reads this artifact as its ONLY source of project conventions, so a run that
# named no component must still be told which existing units to follow.
# STRUCTURAL is excluded because those three are not shaped like ordinary
# blocks — header/footer scope on the semantic element, fragment ships no CSS.
STRUCTURAL="header footer fragment"
is_structural() {
  local e
  for e in $STRUCTURAL; do [[ "$1" == "$e" ]] && return 0; done
  return 1
}

exemplars=()
if [[ ${#reused[@]} -gt 0 ]]; then
  exemplars=("${reused[@]}")
else
  for e in "${existing[@]:-}"; do
    # `${arr[@]:-}` yields one EMPTY STRING for an empty array under bash 3.2,
    # which would otherwise be appended as a real (blank) exemplar.
    [[ -z "$e" ]] && continue
    is_structural "$e" && continue
    exemplars+=("$e")
    [[ ${#exemplars[@]} -eq 2 ]] && break
  done
fi

emitted=0
for e in "${exemplars[@]:-}"; do
  [[ -z "$e" ]] && continue
  echo "exemplar=$e"
  emitted=$((emitted + 1))
done
[[ $emitted -eq 0 ]] && echo "exemplar=(none)"

exit 0
