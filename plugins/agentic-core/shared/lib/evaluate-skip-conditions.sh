#!/usr/bin/env bash
# evaluate-skip-conditions.sh — Deterministic evaluation of a platform pack's
# declared per-stage skip conditions (the optional `skip_when_missing:` key,
# see shared/pack-manifest.md). No model involved.
#
# A platform pack may declare, for a stage, one path whose absence means that
# stage has nothing to do on this run. This script reads that map and reports
# which stages are skipped right now. It decides nothing else: annotating a
# route-progress file, shrinking a counter, or persisting a progress row is
# the caller's job — shared/progress-output.md is explicit that computing the
# skip state and printing a progress line are separate concerns, and that
# print-progress-line.sh never decides a skip itself.
#
# Re-runnable at any point in a run, and meant to be: a precondition path an
# earlier stage writes mid-run flips a later stage from skipped back to not
# skipped, which is exactly why shared/progress-output.md forbids caching a
# <total> across a skip decision.
#
# Usage:
#   evaluate-skip-conditions.sh <path-to-pack.yaml> [project-root]
#
# project-root defaults to the current directory. Every declared path is
# relative to it, never to the pack root — these paths name a run's own
# working files, which live with the project, not with the pack.
#
# Output:
#   one "skipped: <stage id>" line per skipped stage, in manifest order;
#   no output at all when nothing is skipped.
#
# Exit codes:
#   0 — evaluated (with or without any skipped stage)
#   2 — usage error (missing argument, manifest not found, project root is
#       not a directory)

set -uo pipefail

FILE="${1:-}"
PROJECT_ROOT="${2:-.}"

if [[ -z "$FILE" ]]; then
  echo "usage: evaluate-skip-conditions.sh <path-to-pack.yaml> [project-root]" >&2
  exit 2
fi

if [[ ! -f "$FILE" ]]; then
  echo "invalid: file not found: $FILE" >&2
  exit 2
fi

if [[ ! -d "$PROJECT_ROOT" ]]; then
  echo "invalid: project root is not a directory: $PROJECT_ROOT" >&2
  exit 2
fi

# Flat line scan, not a real YAML parser — the same lightweight-parse
# convention run-stage.sh and validate-pack-manifest.sh already use for a
# manifest's own `stages:` map. Only this script's own key is read; every
# other key is skipped over, so an unrelated block cannot be mistaken for a
# condition entry.
in_block=0

while IFS= read -r line || [[ -n "$line" ]]; do
  # A top-level key (column 0, not a list item) closes the block.
  if [[ "$line" =~ ^[A-Za-z0-9_-]+: ]]; then
    if [[ "$line" =~ ^skip_when_missing:[[:space:]]*$ ]]; then
      in_block=1
    else
      in_block=0
    fi
    continue
  fi

  (( in_block )) || continue

  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue

  if [[ "$line" =~ ^\ \ ([A-Za-z0-9_-]+):\ *(.+)$ ]]; then
    stage="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
    # Trim trailing whitespace, then one layer of surrounding double quotes.
    path="${path%"${path##*[![:space:]]}"}"
    path="${path%\"}"
    path="${path#\"}"
    [[ -z "$path" ]] && continue
    if [[ ! -e "$PROJECT_ROOT/$path" ]]; then
      echo "skipped: $stage"
    fi
  else
    # Anything else at this indent level ends the block rather than being
    # silently tolerated as a condition.
    in_block=0
  fi
done < "$FILE"

exit 0
