#!/usr/bin/env bash
# validate-design-manifest.sh — Deterministic conformance check for the
# design manifest contract (see shared/design-manifest.md). No model
# involved: this is the CI floor a design manifest must clear before
# anything reads it.
#
# Checks the fixed shape shared/design-manifest.md defines: three top-level
# keys in order (version, tokens, frames); tokens.provenance fixed to
# 'resolved-value-set'; tokens.values and tokens.unresolvable each either
# the literal '[]' or a list of name/value or name/reason entries; every
# field non-empty; no name repeated within or across values/unresolvable;
# frames non-empty with a positive width per entry.
#
# Usage:
#   validate-design-manifest.sh <path>
#
# Exit codes:
#   0 — conformant; "valid: design manifest (<n> tokens, <m> frames)" on stdout
#   1 — contract violation; "invalid: <reason>" on stderr
#   2 — usage error (no argument, file not found)

set -uo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
  echo "usage: validate-design-manifest.sh <path>" >&2
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

ALL_NAMES=()
name_seen() {
  local name="$1"
  for existing in "${ALL_NAMES[@]:-}"; do
    [[ "$existing" == "$name" ]] && return 0
  done
  return 1
}

# --- version -----------------------------------------------------------
[[ "${LINES[cursor]:-}" =~ ^version:\ ([0-9]+)$ ]] \
  || fail "expected 'version: <int>', got '${LINES[cursor]:-<end of file>}'"
version="${BASH_REMATCH[1]}"
(( version >= 1 )) || fail "version must be >= 1, got '$version'"
cursor=$((cursor + 1))

# --- tokens: -------------------------------------------------------------
[[ "${LINES[cursor]:-}" == "tokens:" ]] \
  || fail "expected 'tokens:', got '${LINES[cursor]:-<end of file>}'"
cursor=$((cursor + 1))

[[ "${LINES[cursor]:-}" == "  provenance: resolved-value-set" ]] \
  || fail "expected '  provenance: resolved-value-set', got '${LINES[cursor]:-<end of file>}'"
cursor=$((cursor + 1))

read_token_list() {
  local key="$1" field2="$2" out_count_var="$3"
  local count=0

  if [[ "${LINES[cursor]:-}" == "  ${key}: []" ]]; then
    cursor=$((cursor + 1))
    printf -v "$out_count_var" '%d' 0
    return 0
  fi

  [[ "${LINES[cursor]:-}" == "  ${key}:" ]] \
    || fail "expected '  ${key}: []' or '  ${key}:', got '${LINES[cursor]:-<end of file>}'"
  cursor=$((cursor + 1))

  while [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ -\ name:\ \"(.*)\"$ ]]; do
    local name="${BASH_REMATCH[1]}"
    [[ -z "$name" ]] && fail "${key} entry has an empty name"
    name_seen "$name" && fail "duplicate token name across values/unresolvable: '$name'"
    ALL_NAMES+=("$name")
    cursor=$((cursor + 1))

    [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ \ \ ${field2}:\ \"(.*)\"$ ]] \
      || fail "'$name' is missing its '${field2}'"
    [[ -z "${BASH_REMATCH[1]}" ]] && fail "'$name' has an empty ${field2}"
    cursor=$((cursor + 1))

    count=$((count + 1))
  done

  (( count == 0 )) && fail "'${key}:' has no entries; use '${key}: []' for an empty list"
  printf -v "$out_count_var" '%d' "$count"
}

read_token_list "values" "value" values_count
read_token_list "unresolvable" "reason" unresolvable_count
token_count=$((values_count + unresolvable_count))

# --- frames: ---------------------------------------------------------------
[[ "${LINES[cursor]:-}" == "frames:" ]] \
  || fail "expected 'frames:', got '${LINES[cursor]:-<end of file>}'"
cursor=$((cursor + 1))

frame_count=0
while [[ "${LINES[cursor]:-}" =~ ^\ \ -\ reference:\ \"(.*)\"$ ]]; do
  reference="${BASH_REMATCH[1]}"
  [[ -z "$reference" ]] && fail "a frame has an empty reference"
  cursor=$((cursor + 1))

  [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ width:\ (.+)$ ]] \
    || fail "frame '$reference' is missing its 'width'"
  width="${BASH_REMATCH[1]}"
  [[ "$width" =~ ^[0-9]+(\.[0-9]+)?$ ]] || fail "frame '$reference' has a non-numeric width: '$width'"
  awk -v w="$width" 'BEGIN { exit !(w > 0) }' || fail "frame '$reference' has a non-positive width: '$width'"
  cursor=$((cursor + 1))

  frame_count=$((frame_count + 1))
done

(( frame_count == 0 )) && fail "'frames:' has no entries; at least one is required"

# --- nothing else may follow ------------------------------------------------
if (( cursor < n )); then
  fail "unexpected content: '${LINES[cursor]}'"
fi

echo "valid: design manifest ($token_count tokens, $frame_count frames)"
exit 0
