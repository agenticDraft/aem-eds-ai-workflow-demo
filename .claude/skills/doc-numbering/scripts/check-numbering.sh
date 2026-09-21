#!/usr/bin/env bash
# check-numbering.sh — Report duplicate identifiers across a set of numbered
# record documents: gap headings (`### G<n> — …`) and decision headings
# (`## D<n> — …`).
#
# Why this exists: a register that several sessions append to has no
# allocation mechanism. Two authors can each read the same "next free"
# number minutes apart and both write it, and nothing notices — the file
# stays valid markdown, the duplicate sits in the middle of thousands of
# lines, and every later reference to that number becomes ambiguous.
#
# This is a detector, not a lock. It does not reserve a number or edit
# anything; it tells you, after you have written, whether what you wrote
# collided. Run it immediately after appending an entry — that is when a
# collision is one renumber away from fixed, rather than a week of
# references later.
#
# What to read is an argument rather than a fixed path: what this checks is
# a convention about numbered headings, not a particular project's files.
#
# **Name the files that own numbers, not the directory that contains them.**
# A register owns its identifiers; a spec or a completion note that discusses
# one restates the heading, and pointing this at a whole directory reports
# every such mention as a collision. Those false positives are worse than no
# check at all, because a report nobody trusts is a report nobody reads. A
# directory argument is accepted for the case where every file in it is an
# owner, and it is the wrong default.
#
# Usage:
#   check-numbering.sh <file-or-directory> [<file-or-directory> …]
#
# Exit codes:
#   0 — no duplicates; "valid: numbering (<n> identifiers across <m> files)"
#   1 — at least one duplicate; one block per duplicated identifier on
#       stderr naming every file:line that claims it, then a count
#   2 — usage error: no argument, or a path that does not exist

set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: check-numbering.sh <file-or-directory> [<file-or-directory> …]" >&2
  exit 2
fi

for target in "$@"; do
  [[ -e "$target" ]] || { echo "invalid: no such file or directory: $target" >&2; exit 2; }
done

# Collect "<id>\t<file>:<line>" for every numbered heading, then look for an
# id claimed more than once. Both heading shapes are matched at their own
# depth, because a gap and a decision are numbered independently — G12 and
# D12 are not a collision.
ENTRIES="$(
  for target in "$@"; do
    if [[ -d "$target" ]]; then
      find "$target" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort
    else
      printf '%s\n' "$target"
    fi
  done | while IFS= read -r file; do
    grep -nE '^(## D|### G)[0-9]+' "$file" 2>/dev/null | while IFS=: read -r lineno text; do
      id="$(printf '%s' "$text" | sed -E 's/^#+ ([DG][0-9]+).*/\1/')"
      printf '%s\t%s:%s\n' "$id" "$file" "$lineno"
    done
  done
)"

if [[ -z "$ENTRIES" ]]; then
  echo "valid: numbering (0 identifiers across 0 files)"
  exit 0
fi

TOTAL="$(printf '%s\n' "$ENTRIES" | wc -l | tr -d ' ')"
FILES="$(printf '%s\n' "$ENTRIES" | cut -f2 | cut -d: -f1 | sort -u | wc -l | tr -d ' ')"

DUPES="$(printf '%s\n' "$ENTRIES" | cut -f1 | sort | uniq -d)"

if [[ -z "$DUPES" ]]; then
  echo "valid: numbering ($TOTAL identifiers across $FILES files)"
  exit 0
fi

COUNT=0
while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  COUNT=$((COUNT + 1))
  echo "invalid: '$id' is claimed more than once:" >&2
  printf '%s\n' "$ENTRIES" | awk -F'\t' -v want="$id" '$1 == want { print "  " $2 }' >&2
done <<< "$DUPES"

echo "$COUNT duplicated identifier(s); renumber the later one and update every reference to it" >&2
exit 1
