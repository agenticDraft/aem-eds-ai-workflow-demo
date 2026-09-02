#!/usr/bin/env bash
# validate-result-envelope.sh — Deterministic conformance check for the result
# envelope contract (shared/result-envelope.md, adapted from
# 01-core-contracts.md §3). No model involved, per §13's "deterministic
# validators" principle: this is the CI floor a stage adapter's ## Result
# block must clear before anything reads it as a verdict.
#
# Checks, each a real failure mode named in the contract's Anti-patterns
# section:
#   * verdict is exactly one of pass | warn | fail | question
#   * summary is a single line (nothing between it and the artifacts field)
#   * artifacts is present, even as an empty list
#   * nothing follows the block (it must be the last thing emitted)
#   * question / options / blocker are present only with verdict: question,
#     and verdict: question always carries a blocker
#
# Usage:
#   validate-result-envelope.sh <path>
#
# Exit codes:
#   0 — conformant; "verdict: <literal>" on stdout
#   1 — contract violation; "invalid: <reason>" on stderr
#   2 — usage error (no argument, file not found)

set -uo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
  echo "usage: validate-result-envelope.sh <path>" >&2
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

# A list under a field (artifacts:, options:) is zero or more "  - <text>"
# lines. Consumes them from $cursor onward, in place.
consume_list_items() {
  while [[ "${LINES[cursor]:-}" =~ ^\ \ -\ .+$ ]]; do
    cursor=$((cursor + 1))
  done
}

# Portable line read (not `mapfile`, a bash-4+ builtin some default system
# shells predate). The `|| [[ -n "$line" ]]` clause keeps a final line that
# has no trailing newline.
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  LINES+=("$line")
done < "$FILE"
n=${#LINES[@]}

# The block must be the LAST "## Result" heading in the file — find it by
# scanning to the end rather than stopping at the first match.
result_idx=-1
for ((k = 0; k < n; k++)); do
  if [[ "${LINES[k]}" == "## Result" ]]; then
    result_idx=$k
  fi
done
if (( result_idx == -1 )); then
  fail "no '## Result' heading found"
fi
cursor=$((result_idx + 1))

# --- verdict ---------------------------------------------------------------
line="${LINES[cursor]:-}"
if [[ "$line" =~ ^verdict:\ (.+)$ ]]; then
  verdict="${BASH_REMATCH[1]}"
else
  fail "missing or malformed 'verdict:' line"
fi
case "$verdict" in
  pass|warn|fail|question) ;;
  *) fail "unknown verdict '$verdict' (must be pass, warn, fail or question)" ;;
esac
cursor=$((cursor + 1))

# --- summary -----------------------------------------------------------
line="${LINES[cursor]:-}"
if [[ "$line" =~ ^summary:\ (.*)$ ]]; then
  summary="${BASH_REMATCH[1]}"
else
  fail "missing or malformed 'summary:' line"
fi
if [[ -z "$summary" ]]; then
  fail "summary is empty"
fi
if (( ${#summary} > 200 )); then
  fail "summary exceeds 200 characters"
fi
cursor=$((cursor + 1))

# What follows summary decides two distinct failure modes: if it's a known
# field other than artifacts, the artifacts list was skipped entirely; if
# it's not a recognised field at all, the summary text itself spilled onto
# a second line.
next="${LINES[cursor]:-}"
if [[ "$next" == "artifacts:" || "$next" == "artifacts: []" ]]; then
  : # well-formed, handled below
elif [[ "$next" =~ ^(next_action|question|options|blocker|metrics):.*$ ]]; then
  fail "missing 'artifacts:' list"
else
  fail "summary spans multiple lines"
fi

# --- artifacts ---------------------------------------------------------
if [[ "$next" == "artifacts: []" ]]; then
  cursor=$((cursor + 1))
else
  cursor=$((cursor + 1)) # consumed 'artifacts:'
  consume_list_items
fi

# --- next_action ---------------------------------------------------------
line="${LINES[cursor]:-}"
if [[ "$line" =~ ^next_action:\ .+$ ]]; then
  cursor=$((cursor + 1))
else
  fail "missing or malformed 'next_action:' line"
fi

# --- verdict: question's own fields -------------------------------------
if [[ "$verdict" == "question" ]]; then
  line="${LINES[cursor]:-}"
  if [[ "$line" =~ ^question:\ .+$ ]]; then
    cursor=$((cursor + 1))
  else
    fail "verdict: question requires a 'question:' field"
  fi

  if [[ "${LINES[cursor]:-}" == "options:" ]]; then
    cursor=$((cursor + 1))
    consume_list_items
  fi

  line="${LINES[cursor]:-}"
  if [[ "$line" =~ ^blocker:\ .+$ ]]; then
    cursor=$((cursor + 1))
  else
    fail "verdict: question requires a 'blocker:' field"
  fi
else
  # Anti-pattern: question / blocker / options present with a non-question
  # verdict.
  if [[ "${LINES[cursor]:-}" =~ ^(question|options|blocker):.*$ ]]; then
    fail "'${BASH_REMATCH[1]}:' is only valid with verdict: question"
  fi
fi

# --- metrics: optional, any verdict -------------------------------------
if [[ "${LINES[cursor]:-}" =~ ^metrics:\ .+$ ]]; then
  cursor=$((cursor + 1))
fi

# --- nothing else may follow --------------------------------------------
while (( cursor < n )); do
  remainder="${LINES[cursor]}"
  if [[ -n "${remainder//[[:space:]]/}" ]]; then
    fail "text after the block"
  fi
  cursor=$((cursor + 1))
done

echo "verdict: $verdict"
exit 0
