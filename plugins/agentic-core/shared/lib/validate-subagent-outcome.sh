#!/usr/bin/env bash
# validate-subagent-outcome.sh — Deterministic conformance check for the
# subagent outcome contract (see shared/subagent-outcome.md). No model
# involved: this is the CI floor a dispatched subagent's ## Outcome block
# must clear before the adapter that dispatched it reads it as a status.
#
# Checks, each a real failure mode named in the contract's Anti-patterns
# section:
#   * status is exactly one of success | warning | failure — never a
#     result-envelope verdict literal (pass, warn, fail, question)
#   * summary is a single line (nothing between it and the artifacts field)
#   * artifacts is present, even as an empty list
#   * nothing follows the block (it must be the last thing emitted)
#   * blocker is present only with status: failure, and status: failure
#     always carries a blocker
#
# Usage:
#   validate-subagent-outcome.sh <path>
#
# Exit codes:
#   0 — conformant; "status: <literal>" on stdout
#   1 — contract violation; "invalid: <reason>" on stderr
#   2 — usage error (no argument, file not found)

set -uo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
  echo "usage: validate-subagent-outcome.sh <path>" >&2
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

# A list under a field (artifacts:) is zero or more "  - <text>" lines.
# Consumes them from $cursor onward, in place.
consume_list_items() {
  while [[ "${LINES[cursor]:-}" =~ ^\ \ -\ .+$ ]]; do
    cursor=$((cursor + 1))
  done
}

# Read the file into an indexed array one line at a time, for maximum
# portability across shell versions. The `|| [[ -n "$line" ]]` clause keeps
# a final line that has no trailing newline.
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  LINES+=("$line")
done < "$FILE"
n=${#LINES[@]}

# The block must be the LAST "## Outcome" heading in the file — find it by
# scanning to the end rather than stopping at the first match.
outcome_idx=-1
for ((k = 0; k < n; k++)); do
  if [[ "${LINES[k]}" == "## Outcome" ]]; then
    outcome_idx=$k
  fi
done
if (( outcome_idx == -1 )); then
  fail "no '## Outcome' heading found"
fi
cursor=$((outcome_idx + 1))

# --- status ------------------------------------------------------------
line="${LINES[cursor]:-}"
if [[ "$line" =~ ^status:\ (.+)$ ]]; then
  status="${BASH_REMATCH[1]}"
else
  fail "missing or malformed 'status:' line"
fi
case "$status" in
  success|warning|failure) ;;
  pass|warn|fail|question)
    fail "'$status' is a result-envelope verdict, not a subagent-outcome status (must be success, warning or failure)" ;;
  *) fail "unknown status '$status' (must be success, warning or failure)" ;;
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
elif [[ "$next" =~ ^(next_action|blocker):.*$ ]]; then
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

# --- blocker: required with status: failure, forbidden otherwise -------
if [[ "$status" == "failure" ]]; then
  line="${LINES[cursor]:-}"
  if [[ "$line" =~ ^blocker:\ .+$ ]]; then
    cursor=$((cursor + 1))
  else
    fail "status: failure requires a 'blocker:' field"
  fi
else
  if [[ "${LINES[cursor]:-}" =~ ^blocker:.*$ ]]; then
    fail "'blocker:' is only valid with status: failure"
  fi
fi

# --- nothing else may follow --------------------------------------------
while (( cursor < n )); do
  remainder="${LINES[cursor]}"
  if [[ -n "${remainder//[[:space:]]/}" ]]; then
    fail "text after the block"
  fi
  cursor=$((cursor + 1))
done

echo "status: $status"
exit 0
