#!/usr/bin/env bash
# validate-convention-record.sh — Deterministic conformance check for the
# convention record contract (see shared/convention-record.md). No model
# involved: this is the CI floor a convention record must clear before
# anything reads it.
#
# Checks the fixed shape shared/convention-record.md defines: the six
# top-level keys, in order, and nothing else; version an integer >= 1; the
# five answer fields each a non-empty quoted string.
#
# Usage:
#   validate-convention-record.sh <path>
#
# Exit codes:
#   0 — conformant; "valid" on stdout
#   1 — contract violation; "invalid: <reason>" on stderr
#   2 — usage error (no argument, file not found)

set -uo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
  echo "usage: validate-convention-record.sh <path>" >&2
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

# Read the file into an indexed array one line at a time, stripping blank
# lines and full-line comments, for maximum portability across shell
# versions.
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  LINES+=("$line")
done < "$FILE"
n=${#LINES[@]}
cursor=0

MATCH=""
require_line() {
  local regex="$1" desc="$2"
  local line="${LINES[cursor]:-}"
  if [[ "$line" =~ $regex ]]; then
    cursor=$((cursor + 1))
    MATCH="${BASH_REMATCH[1]:-}"
  else
    fail "expected $desc, got '${line:-<end of file>}'"
  fi
}

top_level_key() {
  local line="${LINES[cursor]:-}"
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_-]*): ]]; then
    TOPKEY="${BASH_REMATCH[1]}"
  else
    TOPKEY=""
  fi
}

# --- top-level key set, in order ------------------------------------------
EXPECTED_TOP_LEVEL=(version pack_name unit_of_work_location definition_of_done stage_conventions verification_gate)

TOPKEY=""
top_level_key
found=0
for k in "${EXPECTED_TOP_LEVEL[@]}"; do
  [[ "$k" == "$TOPKEY" ]] && found=1
done
if [[ -z "$TOPKEY" ]]; then
  fail "expected 'version:', got '${LINES[cursor]:-<end of file>}'"
elif [[ "$found" -eq 0 ]]; then
  fail "unknown top-level key: '$TOPKEY'"
elif [[ "$TOPKEY" != "version" ]]; then
  fail "top-level keys out of order: expected 'version:' first, got '$TOPKEY:'"
fi

# --- version ---------------------------------------------------------------
require_line '^version: ([0-9]+)$' "'version: <int>'"
version="$MATCH"
if (( version < 1 )); then
  fail "version must be >= 1, got '$version'"
fi

# --- the five answer fields -------------------------------------------------
for subkey in pack_name unit_of_work_location definition_of_done stage_conventions verification_gate; do
  require_line "^${subkey}: \"(.*)\"\$" "'${subkey}: \"<value>\"'"
  [[ -z "$MATCH" ]] && fail "${subkey} is empty"
done

# --- nothing else may follow ------------------------------------------------
if (( cursor < n )); then
  top_level_key
  if [[ -n "$TOPKEY" ]]; then
    fail "unknown top-level key: '$TOPKEY'"
  fi
  fail "unexpected content after 'verification_gate:': '${LINES[cursor]}'"
fi

echo "valid"
exit 0
