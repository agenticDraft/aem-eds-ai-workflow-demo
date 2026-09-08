#!/usr/bin/env bash
# validate-project-config.sh — Deterministic conformance check for the
# project config contract (see shared/project-config.md). No model
# involved: this is the CI floor a config file must clear before anything
# reads it.
#
# Checks the fixed shape shared/project-config.md defines: the five
# top-level keys, in order, and nothing else; packs, commands, paths and
# limits as flat sub-mappings with fixed keys.
#
# Usage:
#   validate-project-config.sh <path>
#
# Exit codes:
#   0 — conformant; "valid" on stdout
#   1 — contract violation; "invalid: <reason>" on stderr
#   2 — usage error (no argument, file not found)

set -uo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
  echo "usage: validate-project-config.sh <path>" >&2
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

# require_line <regex> <description> — advances cursor and sets the global
# MATCH to the first capture group on match; fails closed otherwise. Never
# called through command substitution: a $(...) subshell would swallow both
# the cursor advance and a fail() exit, so every caller reads $MATCH after
# a plain (uncaptured) call instead.
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

# top_level_key — sets the global TOPKEY to the key name at the cursor
# (without consuming it), or "" if the line isn't a top-level "key:" line.
TOPKEY=""
top_level_key() {
  local line="${LINES[cursor]:-}"
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_-]*): ]]; then
    TOPKEY="${BASH_REMATCH[1]}"
  else
    TOPKEY=""
  fi
}

# --- top-level key set, in order ------------------------------------------
EXPECTED_TOP_LEVEL=(version packs commands paths limits)

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

# --- version ----------------------------------------------------------
require_line '^version: ([0-9]+)$' "'version: <int>'"
version="$MATCH"
if (( version < 1 )); then
  fail "version must be >= 1, got '$version'"
fi

# --- packs ---------------------------------------------------------------
require_line '^packs:$' "'packs:'"
for subkey in platform tracker scm; do
  require_line "^  ${subkey}: (.+)\$" "'${subkey}:' under packs"
  [[ -z "$MATCH" ]] && fail "packs.${subkey} is empty"
done
require_line '^  design: (.+)$' "'design:' under packs"
[[ -z "$MATCH" ]] && fail "packs.design is empty"
require_line '^  browser: (.+)$' "'browser:' under packs"
[[ -z "$MATCH" ]] && fail "packs.browser is empty"

# --- commands --------------------------------------------------------------
require_line '^commands:$' "'commands:'"
for subkey in lint test build serve; do
  require_line "^  ${subkey}: \"(.*)\"\$" "'${subkey}: \"<command>\"' under commands"
done

# --- paths -----------------------------------------------------------------
require_line '^paths:$' "'paths:'"
for subkey in spec_dir preview; do
  require_line "^  ${subkey}: \"(.*)\"\$" "'${subkey}: \"<value>\"' under paths"
  [[ -z "$MATCH" ]] && fail "paths.${subkey} is empty"
done

# --- limits ------------------------------------------------------------
require_line '^limits:$' "'limits:'"
for subkey in questions_per_run fix_attempts_default; do
  require_line "^  ${subkey}: ([0-9]+)\$" "'${subkey}: <int>' under limits"
  (( MATCH < 0 )) && fail "limits.${subkey} must be >= 0"
done

# --- nothing else may follow --------------------------------------------
if (( cursor < n )); then
  top_level_key
  if [[ -n "$TOPKEY" ]]; then
    fail "unknown top-level key: '$TOPKEY'"
  fi
  fail "unexpected content after 'limits:': '${LINES[cursor]}'"
fi

echo "valid"
exit 0
