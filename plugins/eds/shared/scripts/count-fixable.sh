#!/usr/bin/env bash
# count-fixable.sh — Deterministic count of the mismatches a block edit could
# still close (D536). No model involved.
#
# eds-verify-design writes each check's mismatch list to
# .ai/run-context/verify-design-check-<n>.txt, one line per mismatch, each
# starting with its tag: `[fixable]`, `[content-asset gap]` or
# `[content-dependent]`. This script counts the lines that are neither a
# `[content-asset gap]` nor a `[content-dependent]`: a `[fixable]` line and an
# untagged line both count, so a line the stage failed to tag keeps the fix
# loop going rather than ending it. A `[content-dependent]` line is a value
# that depends on the design's content (D540): it is listed and counted apart,
# and never makes an edit due. A tag counts only at the start of the line,
# after optional whitespace. Blank lines are not mismatches. CR is ignored.
#
# Usage:
#   count-fixable.sh <check file>
#
# Output: one line,
#   nothing-fixable: fixable=0 gaps=<g> approx=<a>     (exit 0)
#   fixable: fixable=<n> gaps=<g> approx=<a>           (exit 1)
#
# Exit codes:
#   0 — no fixable mismatch
#   1 — at least one fixable mismatch
#   2 — usage error (a missing argument, or a file that cannot be read)

set -uo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
  echo "usage: count-fixable.sh <check file>" >&2
  exit 2
fi

if [[ ! -f "$FILE" || ! -r "$FILE" ]]; then
  echo "count-fixable.sh: cannot read $FILE" >&2
  exit 2
fi

read -r FIXABLE GAPS APPROX < <(awk '
  { sub(/\r$/, "") }
  /^[[:space:]]*$/ { next }
  /^[[:space:]]*\[content-asset gap\]/ { gaps++; next }
  /^[[:space:]]*\[content-dependent\]/ { approx++; next }
  { fixable++ }
  END { printf "%d %d %d\n", fixable, gaps, approx }
' "$FILE")

if [[ "$FIXABLE" -eq 0 ]]; then
  echo "nothing-fixable: fixable=0 gaps=$GAPS approx=$APPROX"
  exit 0
fi

echo "fixable: fixable=$FIXABLE gaps=$GAPS approx=$APPROX"
exit 1
