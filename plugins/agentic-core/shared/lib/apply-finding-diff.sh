#!/usr/bin/env bash
# apply-finding-diff.sh — Applies one audit-taxonomy.md finding's own `diff`
# to the file it names. No judgment involved: the diff already carries the
# exact line(s) removed and the exact line(s) added
# (audit-taxonomy.md's own required shape); this script only performs the
# textual replacement, exactly once, and refuses rather than guess when the
# target no longer matches.
#
# Names no platform: it knows only "a file, and the lines to remove and
# lines to add in it," never why a given finding exists.
#
# Usage:
#   apply-finding-diff.sh <target-file> <diff-file>
#
# <diff-file> holds the finding's own `diff` block content verbatim: zero or
# more lines starting with `-` (removed, must each match one line in
# <target-file> exactly, ignoring the leading `-`) followed by zero or more
# lines starting with `+` (added, in their place, ignoring the leading `+`).
# Every `-` line must appear before every `+` line, matching how
# audit-taxonomy.md's own worked examples are written. A diff with only `+`
# lines and no `-` lines is invalid here — a finding's diff always replaces
# something audit-taxonomy.md's own field rules say must already be present
# to find; a file with nothing to remove is not this script's concern.
#
# Exit codes:
#   0 — success; "applied: <target-file>" on stdout
#   1 — contract violation: a `-` line not found verbatim in the target
#       (the file no longer matches what the diff expects), or a
#       malformed diff (a `+` line before a `-` line, or no `-` line at all)
#   2 — usage error: wrong argument count, file not found

set -uo pipefail

TARGET="${1:-}"
DIFF_FILE="${2:-}"
if [[ -z "$TARGET" || -z "$DIFF_FILE" ]]; then
  echo "usage: apply-finding-diff.sh <target-file> <diff-file>" >&2
  exit 2
fi
if [[ ! -f "$TARGET" ]]; then
  echo "target file not found: $TARGET" >&2
  exit 2
fi
if [[ ! -f "$DIFF_FILE" ]]; then
  echo "diff file not found: $DIFF_FILE" >&2
  exit 2
fi

fail() {
  echo "invalid: $1" >&2
  exit 1
}

REMOVE_LINES=()
ADD_LINES=()
seen_add=0
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" ]] && continue
  case "$line" in
    -*)
      if [[ $seen_add -eq 1 ]]; then
        fail "a '-' line appears after a '+' line — malformed diff"
      fi
      REMOVE_LINES+=("${line#-}")
      ;;
    +*)
      seen_add=1
      ADD_LINES+=("${line#+}")
      ;;
    *)
      fail "diff line does not start with '-' or '+': '$line'"
      ;;
  esac
done < "$DIFF_FILE"

if [[ ${#REMOVE_LINES[@]} -eq 0 ]]; then
  fail "diff has no '-' line to match against the target"
fi

for removed in "${REMOVE_LINES[@]}"; do
  if ! grep -qxF -- "$removed" "$TARGET"; then
    fail "line not found verbatim in $TARGET: '$removed'"
  fi
done

TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/apply-finding-diff.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

applied=0
while IFS= read -r line || [[ -n "$line" ]]; do
  matched=0
  if [[ $applied -eq 0 ]]; then
    for removed in "${REMOVE_LINES[@]}"; do
      if [[ "$line" == "$removed" ]]; then
        matched=1
        break
      fi
    done
  fi
  if [[ $matched -eq 1 ]]; then
    last_remove="${REMOVE_LINES[${#REMOVE_LINES[@]}-1]}"
    if [[ "$line" == "$last_remove" ]]; then
      for added in "${ADD_LINES[@]}"; do
        printf '%s\n' "$added"
      done
      applied=1
    fi
    continue
  fi
  printf '%s\n' "$line"
done < "$TARGET" > "$TMP_FILE"

mv "$TMP_FILE" "$TARGET"
trap - EXIT

echo "applied: $TARGET"
exit 0
