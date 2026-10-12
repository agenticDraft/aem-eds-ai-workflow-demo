#!/usr/bin/env bash
# check-session-tools.sh — Decide whether every session tool the given packs
# declare is present, from two lists: the names the packs declare under
# `session_tools:` (see shared/pack-manifest.md) and the names the caller
# found in the session's own tool registry.
#
# No model involved and no probe. This script cannot see the session; the
# component that drives a route asks the registry and passes what it found.
# What this script owns is the comparison, so whether a run may go on is a
# script's answer, never a reading of a tool listing.
#
# Two modes:
#   --list <pack.yaml>…              print the names to ask the registry for,
#                                    one "tool: <name>" line each, each name
#                                    once, in declaration order; "none
#                                    declared" when there is nothing to ask
#   <pack.yaml>… --found [<name>…]   compare; exact names only
#
# Usage:
#   check-session-tools.sh --list [<path-to-pack.yaml> …]
#   check-session-tools.sh <path-to-pack.yaml> [<path> …] --found [<name> …]
#
# Exit codes:
#   0 — nothing missing: one "ok: <tool>" line per declared tool, or
#       "ok: no session tools declared"; for --list, always 0 on a readable
#       declaration
#   1 — at least one declared tool was not found: "missing: <tool> —
#       <remedy>" on stderr per missing tool, then a count; present tools
#       still report their own "ok:" line
#   2 — usage error: no mode, a pack file not found, or a malformed
#       `session_tools:` block (validate-pack-manifest.sh explains the
#       malformation; this script only refuses to guess at it)

set -uo pipefail

usage() {
  echo "usage: check-session-tools.sh --list [<pack.yaml> …]" >&2
  echo "       check-session-tools.sh <pack.yaml> [<pack.yaml> …] --found [<tool name> …]" >&2
  exit 2
}

MODE=""
PACKS=()
FOUND=()

if [[ "${1:-}" == "--list" ]]; then
  MODE="list"
  shift
  PACKS=("$@")
else
  while (( $# > 0 )); do
    if [[ "$1" == "--found" ]]; then
      MODE="check"
      shift
      FOUND=("$@")
      break
    fi
    PACKS+=("$1")
    shift
  done
  [[ "$MODE" == "check" ]] || usage
  (( ${#PACKS[@]} > 0 )) || usage
fi

for pack in "${PACKS[@]:-}"; do
  [[ -z "$pack" ]] && continue
  [[ -f "$pack" ]] || { echo "invalid: file not found: $pack" >&2; exit 2; }
done

# Declared entries across every pack, each name once: the first declaration's
# remedy is the one reported.
NAMES=()
REMEDIES=()

malformed() {
  echo "invalid: malformed 'session_tools:' block in $1 — $2" >&2
  exit 2
}

read_pack() {
  local file="$1" line start=-1 i n tool remedy seen known
  local lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    lines+=("$line")
  done < "$file"
  n=${#lines[@]}

  for ((i = 0; i < n; i++)); do
    [[ "${lines[i]}" == "session_tools:" ]] && { start=$i; break; }
  done
  (( start < 0 )) && return 0

  i=$((start + 1))
  local count=0
  while (( i < n )); do
    [[ "${lines[i]}" =~ ^\ \ -\ tool:\ ([A-Za-z0-9_-]+)$ ]] || break
    tool="${BASH_REMATCH[1]}"
    i=$((i + 1))
    [[ "${lines[i]:-}" =~ ^\ \ \ \ remedy:\ \"(.*)\"$ ]] \
      || malformed "$file" "'$tool' has no 'remedy:'"
    remedy="${BASH_REMATCH[1]}"
    [[ -n "${remedy//[[:space:]]/}" ]] || malformed "$file" "'$tool' has an empty 'remedy:'"
    i=$((i + 1))
    count=$((count + 1))

    known=0
    for seen in "${NAMES[@]:-}"; do
      [[ "$seen" == "$tool" ]] && known=1
    done
    if (( ! known )); then
      NAMES+=("$tool")
      REMEDIES+=("$remedy")
    fi
  done
  (( count > 0 )) || malformed "$file" "it declares no entries"
}

for pack in "${PACKS[@]:-}"; do
  [[ -z "$pack" ]] && continue
  read_pack "$pack"
done

if [[ "$MODE" == "list" ]]; then
  if (( ${#NAMES[@]} == 0 )); then
    echo "none declared"
  else
    for name in "${NAMES[@]}"; do
      echo "tool: $name"
    done
  fi
  exit 0
fi

if (( ${#NAMES[@]} == 0 )); then
  echo "ok: no session tools declared"
  exit 0
fi

MISSING=0
for i in "${!NAMES[@]}"; do
  name="${NAMES[$i]}"
  present=0
  for found in "${FOUND[@]:-}"; do
    [[ "$found" == "$name" ]] && present=1
  done
  if (( present )); then
    echo "ok: $name"
  else
    # Quoted exactly as the pack declared it; only the pack knows its fix.
    echo "missing: $name — ${REMEDIES[$i]}" >&2
    MISSING=$((MISSING + 1))
  fi
done

if (( MISSING > 0 )); then
  echo "$MISSING of ${#NAMES[@]} declared session tools are missing" >&2
  exit 1
fi

exit 0
