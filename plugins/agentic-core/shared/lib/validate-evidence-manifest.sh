#!/usr/bin/env bash
# validate-evidence-manifest.sh — Deterministic conformance check for the
# delivery evidence manifest a platform pack's `evidence_manifest` key may
# name (see shared/evidence-manifest.md). No model involved: this is the CI
# floor a manifest must clear before a delivery stage reads it.
#
# Checks the fixed shape: seven required top-level fields — version,
# item_id, target, target_reachable, target_reachable_reason, coverage_gaps,
# attachments. target_reachable is a JSON boolean. coverage_gaps is an array
# of non-empty strings ('[]' allowed). attachments is an array of objects,
# each carrying a non-empty path, a positive width and a non-empty label
# ('[]' allowed).
#
# Deliberately does not check that an attachment's path exists on disk.
# This validator runs against fixtures with no working tree behind them —
# the same reason 01-core-contracts.md §13 validator 15 never checks a
# declared path resolves in a real project. A path missing by the time a
# delivery stage reads the manifest is that stage's own concern (reported
# and skipped, never silently dropped), not this script's.
#
# Usage:
#   validate-evidence-manifest.sh <path-to-evidence-manifest.json>
#
# Exit codes:
#   0 — conformant; "valid: evidence manifest (<n> attachments, <m> coverage gaps)" on stdout
#   1 — contract violation; "invalid: <reason>" on stderr, naming the field
#   2 — usage error: no argument, file not found, jq missing, or not valid JSON
#
# Requires: jq.

set -uo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
  echo "usage: validate-evidence-manifest.sh <path-to-evidence-manifest.json>" >&2
  exit 2
fi

if [[ ! -f "$FILE" ]]; then
  echo "invalid: file not found: $FILE" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "invalid: jq is required and was not found on PATH" >&2
  exit 2
fi

if ! jq -e . "$FILE" > /dev/null 2>&1; then
  echo "invalid: not valid JSON: $FILE" >&2
  exit 2
fi

fail() {
  echo "invalid: $1" >&2
  exit 1
}

# assert_jq <jq boolean filter> <failure message> — runs the filter against
# $FILE and fails with the given message when it does not evaluate true.
assert_jq() {
  local filter="$1" message="$2"
  jq -e "$filter" "$FILE" > /dev/null 2>&1 || fail "$message"
}

require_nonempty_string() {
  local field="$1"
  assert_jq "has(\"$field\")" "missing required field '$field'"
  assert_jq "(.${field} | type) == \"string\"" "'$field' must be a string"
  assert_jq "(.${field} | length) > 0" "'$field' must not be empty"
}

# --- the four plain-string required fields ---------------------------------

require_nonempty_string version
require_nonempty_string item_id
require_nonempty_string target
require_nonempty_string target_reachable_reason

# --- target_reachable: a JSON boolean, never a string or number ------------

assert_jq 'has("target_reachable")' "missing required field 'target_reachable'"
assert_jq '(.target_reachable | type) == "boolean"' \
  "'target_reachable' must be a boolean (true or false), not a string or number"

# --- coverage_gaps: an array of non-empty strings, [] allowed --------------

assert_jq 'has("coverage_gaps")' "missing required field 'coverage_gaps'"
assert_jq '(.coverage_gaps | type) == "array"' "'coverage_gaps' must be an array"
assert_jq '[.coverage_gaps[] | select((type != "string") or (length == 0))] | length == 0' \
  "every 'coverage_gaps' entry must be a non-empty string"
coverage_gaps_count=$(jq '.coverage_gaps | length' "$FILE")

# --- attachments: an array of {path, width, label}, [] allowed -------------

assert_jq 'has("attachments")' "missing required field 'attachments'"
assert_jq '(.attachments | type) == "array"' "'attachments' must be an array"

attachments_count=$(jq '.attachments | length' "$FILE")

for ((i = 0; i < attachments_count; i++)); do
  assert_jq ".attachments[$i] | type == \"object\"" \
    "attachments[$i] must be an object"
  assert_jq ".attachments[$i] | has(\"path\")" \
    "attachments[$i] is missing its 'path'"
  assert_jq "(.attachments[$i].path | type) == \"string\" and (.attachments[$i].path | length > 0)" \
    "attachments[$i].path must be a non-empty string"
  assert_jq ".attachments[$i] | has(\"width\")" \
    "attachments[$i] is missing its 'width'"
  assert_jq "(.attachments[$i].width | type) == \"number\" and (.attachments[$i].width > 0)" \
    "attachments[$i].width must be a positive number"
  assert_jq ".attachments[$i] | has(\"label\")" \
    "attachments[$i] is missing its 'label'"
  assert_jq "(.attachments[$i].label | type) == \"string\" and (.attachments[$i].label | length > 0)" \
    "attachments[$i].label must be a non-empty string"
done

echo "valid: evidence manifest ($attachments_count attachments, $coverage_gaps_count coverage gaps)"
exit 0
