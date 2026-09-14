#!/usr/bin/env bash
# validate-findings.sh — Deterministic conformance check for an audit
# findings list (see shared/audit-taxonomy.md). No model involved: this is
# the CI floor a findings file must clear before anything reads it as real.
#
# Checks the fixed shape shared/audit-taxonomy.md defines: a bare list of
# entries, each `id`, `class`, `severity`, `file`, `finding`, `diff`, in
# that order, plus `recommendation`/`default` (class: judgment only) or
# `question` (class: needs-the-human only). No blank line is permitted
# outside a `diff:` block scalar's own content, so a stray blank line
# between fields is a contract violation rather than silently ignored.
#
# Usage:
#   validate-findings.sh <path>
#
# Exit codes:
#   0 — conformant; "valid: findings (<n> entries)" on stdout
#   1 — contract violation; "invalid: <reason>" on stderr
#   2 — usage error (no argument, file not found)

set -uo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
  echo "usage: validate-findings.sh <path>" >&2
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

# Read every raw line, preserving blank ones — a `diff:` block scalar may
# legitimately contain a blank line, so blank-line handling here is
# contextual rather than a blanket strip like the simpler flat contracts use.
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  LINES+=("$line")
done < "$FILE"
n=${#LINES[@]}
cursor=0

# Trailing blank lines at end of file are never significant.
while (( n > 0 )) && [[ -z "${LINES[n-1]//[[:space:]]/}" ]]; do
  n=$((n - 1))
done

# An audit that produced no findings is a normal result, not a contract
# violation — written as the literal '[]', the same convention
# design-manifest.md uses for an empty values/unresolvable list, never an
# omitted or blank file.
if (( n == 1 )) && [[ "${LINES[0]}" == "[]" ]]; then
  echo "valid: findings (0 entries)"
  exit 0
fi

IDS=()
count=0

while (( cursor < n )); do
  [[ "${LINES[cursor]:-}" =~ ^-\ id:\ \"(.*)\"$ ]] \
    || fail "expected '- id: \"<string>\"', got '${LINES[cursor]:-<end of file>}'"
  id="${BASH_REMATCH[1]}"
  [[ -z "$id" ]] && fail "an entry has an empty id"
  for existing in "${IDS[@]:-}"; do
    [[ "$existing" == "$id" ]] && fail "duplicate finding id: '$id'"
  done
  IDS+=("$id")
  cursor=$((cursor + 1))

  [[ "${LINES[cursor]:-}" =~ ^\ \ class:\ (mechanical|needs-the-human|judgment|report-only)$ ]] \
    || fail "'$id' has a missing or unknown 'class': '${LINES[cursor]:-<end of file>}'"
  class="${BASH_REMATCH[1]}"
  cursor=$((cursor + 1))

  [[ "${LINES[cursor]:-}" =~ ^\ \ severity:\ (poisoning|cosmetic)$ ]] \
    || fail "'$id' has a missing or unknown 'severity': '${LINES[cursor]:-<end of file>}'"
  cursor=$((cursor + 1))

  [[ "${LINES[cursor]:-}" =~ ^\ \ file:\ \"(.*)\"$ ]] \
    || fail "'$id' is missing its 'file'"
  [[ -z "${BASH_REMATCH[1]}" ]] && fail "'$id' has an empty 'file'"
  cursor=$((cursor + 1))

  [[ "${LINES[cursor]:-}" =~ ^\ \ finding:\ \"(.*)\"$ ]] \
    || fail "'$id' is missing its 'finding'"
  [[ -z "${BASH_REMATCH[1]}" ]] && fail "'$id' has an empty 'finding'"
  cursor=$((cursor + 1))

  [[ "${LINES[cursor]:-}" == "  diff: |" ]] \
    || fail "'$id' is missing its 'diff: |' block"
  cursor=$((cursor + 1))

  diff_lines=0
  while (( cursor < n )) \
        && { [[ "${LINES[cursor]}" =~ ^\ \ \ \ .* ]] || [[ -z "${LINES[cursor]//[[:space:]]/}" ]]; }; do
    [[ -n "${LINES[cursor]//[[:space:]]/}" ]] && diff_lines=$((diff_lines + 1))
    cursor=$((cursor + 1))
  done
  (( diff_lines == 0 )) && fail "'$id' has an empty 'diff' block"

  has_recommendation=0
  has_default=0
  has_question=0

  if [[ "${LINES[cursor]:-}" =~ ^\ \ recommendation:\ \"(.*)\"$ ]]; then
    [[ -z "${BASH_REMATCH[1]}" ]] && fail "'$id' has an empty 'recommendation'"
    has_recommendation=1
    cursor=$((cursor + 1))
    if [[ "${LINES[cursor]:-}" =~ ^\ \ default:\ \"(.*)\"$ ]]; then
      [[ -z "${BASH_REMATCH[1]}" ]] && fail "'$id' has an empty 'default'"
      has_default=1
      cursor=$((cursor + 1))
    fi
  fi

  if [[ "${LINES[cursor]:-}" =~ ^\ \ question:\ \"(.*)\"$ ]]; then
    [[ -z "${BASH_REMATCH[1]}" ]] && fail "'$id' has an empty 'question'"
    has_question=1
    cursor=$((cursor + 1))
  fi

  if [[ "$class" == "judgment" ]]; then
    (( has_recommendation == 1 && has_default == 1 )) \
      || fail "'$id' is class 'judgment' but is missing 'recommendation' and/or 'default'"
    (( has_question == 1 )) \
      && fail "'$id' is class 'judgment' but carries a 'question', which only 'needs-the-human' may"
  elif [[ "$class" == "needs-the-human" ]]; then
    (( has_question == 1 )) \
      || fail "'$id' is class 'needs-the-human' but is missing 'question'"
    (( has_recommendation == 1 || has_default == 1 )) \
      && fail "'$id' is class 'needs-the-human' but carries 'recommendation'/'default', which only 'judgment' may"
  else
    (( has_recommendation == 1 || has_default == 1 || has_question == 1 )) \
      && fail "'$id' is class '$class' but carries a field only 'judgment' or 'needs-the-human' may"
  fi

  count=$((count + 1))
done

(( count == 0 )) && fail "no entries found"

echo "valid: findings ($count entries)"
exit 0
