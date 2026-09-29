#!/usr/bin/env bash
# validate-result-envelope.sh — Deterministic conformance check for the
# result envelope contract (see shared/result-envelope.md). No model
# involved: this is the CI floor a stage adapter's ## Result block must
# clear before anything reads it as a verdict.
#
# Checks, each a real failure mode named in the contract's Anti-patterns
# section:
#   * verdict is exactly one of pass | warn | fail | question
#   * summary is a single line (nothing between it and the artifacts field)
#   * artifacts is present, even as an empty list
#   * nothing follows the block (it must be the last thing emitted)
#   * question / options / blocker are present only with verdict: question,
#     and verdict: question always carries a blocker
#   * error_class, when present, is exactly one of TRANSIENT | VALIDATION |
#     PERMANENT, and appears only with verdict: fail or verdict: question
#   * question_id, when present, is a lowercase id of at most 40 characters and
#     appears only with verdict: question (D527 — the key its answer is stored under)
#   * change_state, when present, is exactly one of open | merged | closed |
#     none (D534)
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

# Read the file into an indexed array one line at a time, for maximum
# portability across shell versions. The `|| [[ -n "$line" ]]` clause keeps
# a final line that has no trailing newline.
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

# What follows summary decides three distinct failure modes: if it's
# artifacts written as an inline scalar instead of a list, name that
# specifically; if it's a known field other than artifacts, the artifacts
# list was skipped entirely; if it's not a recognised field at all, the
# summary text itself spilled onto a second line.
next="${LINES[cursor]:-}"
if [[ "$next" == "artifacts:" || "$next" == "artifacts: []" ]]; then
  : # well-formed, handled below
elif [[ "$next" =~ ^artifacts:\ .+$ ]]; then
  fail "'artifacts:' must be a list, even for a single path — write it as 'artifacts:' followed by '  - <path>' on the next line, not an inline value"
elif [[ "$next" =~ ^(next_action|question|question_id|options|blocker|error_class|change_state|metrics):.*$ ]]; then
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

# --- error_class: optional, verdict fail or question only ----------------
# The class is what the caller branches on (see shared/error-handling.md), so
# an unrecognised literal is rejected the same way an unrecognised verdict is:
# a caller must never branch on a value no contract defines. Presence is not
# required here — a stage that omits it degrades to "no class known", which
# every caller already has to handle, whereas requiring it would invalidate
# every fail envelope written before the field existed.
if [[ "$verdict" == "fail" || "$verdict" == "question" ]]; then
  if [[ "${LINES[cursor]:-}" =~ ^error_class:\ (.+)$ ]]; then
    error_class="${BASH_REMATCH[1]}"
    case "$error_class" in
      TRANSIENT|VALIDATION|PERMANENT) ;;
      *) fail "unknown error_class '$error_class' (must be TRANSIENT, VALIDATION or PERMANENT)" ;;
    esac
    cursor=$((cursor + 1))
  fi
elif [[ "${LINES[cursor]:-}" =~ ^error_class: ]]; then
  fail "'error_class:' is only valid with verdict: fail or verdict: question"
fi

# --- verdict: question's own fields -------------------------------------
if [[ "$verdict" == "question" ]]; then
  line="${LINES[cursor]:-}"
  if [[ "$line" =~ ^question:\ .+$ ]]; then
    cursor=$((cursor + 1))
  else
    fail "verdict: question requires a 'question:' field"
  fi

  # Optional: absent, the answer is keyed "default". A key that is not a plain
  # lowercase id could not be written into or matched in the answer file.
  if [[ "${LINES[cursor]:-}" =~ ^question_id:\ ?(.*)$ ]]; then
    question_id="${BASH_REMATCH[1]}"
    if [[ ! "$question_id" =~ ^[a-z][a-z0-9-]*$ ]] || (( ${#question_id} > 40 )); then
      fail "question_id '$question_id' is not a lowercase id (letters, digits and hyphens, starting with a letter, at most 40 characters)"
    fi
    cursor=$((cursor + 1))
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
  if [[ "${LINES[cursor]:-}" =~ ^(question|question_id|options|blocker):.*$ ]]; then
    fail "'${BASH_REMATCH[1]}:' is only valid with verdict: question"
  fi
fi

# --- change_state: optional, any verdict (D534) --------------------------
# The state of the change a scm operation looked up. A caller branches on it
# (a merged or closed change's leftovers are cleaned up), so an unrecognised
# literal is rejected the same way an unrecognised verdict is.
if [[ "${LINES[cursor]:-}" =~ ^change_state:\ ?(.*)$ ]]; then
  change_state="${BASH_REMATCH[1]}"
  case "$change_state" in
    open|merged|closed|none) ;;
    *) fail "unknown change_state '$change_state' (must be open, merged, closed or none)" ;;
  esac
  cursor=$((cursor + 1))
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
