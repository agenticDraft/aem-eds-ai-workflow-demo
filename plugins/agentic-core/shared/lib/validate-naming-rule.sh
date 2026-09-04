#!/usr/bin/env bash
# validate-naming-rule.sh — Deterministic conformance check for core contract
# §13 validator 8: no file under the core names a product, platform or tool
# (see shared/naming-rule.md). No model involved: this is the CI floor that
# makes the naming rule executable rather than remembered.
#
# Scans every file under <core-root>, except three paths that necessarily
# carry the banned words as literal data rather than core vocabulary — the
# denylist file itself, this validator's own test suite, and this
# validator's own fixtures — for each term in naming-denylist.txt, matched
# case-sensitively as a whole word or phrase. No exceptions: every term is
# forbidden everywhere else under the core, including this project's own
# borrowed-material source — a third-party plugin's name gets no carve-out
# for appearing "just" in an attribution (see shared/naming-rule.md,
# "No exceptions").
#
# Usage:
#   validate-naming-rule.sh <path-to-core-root>
#
# Exit codes:
#   0 — no hit; "valid: naming rule (<n> files scanned, <m> terms checked)"
#   1 — at least one hit; one "invalid: '<term>' — <path>:<line>: <content>"
#       per hit on stderr, then a count
#   2 — usage error: missing argument, directory not found, denylist missing or empty

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DENYLIST_FILE="$SCRIPT_DIR/naming-denylist.txt"
SELF_TEST_FILE="$SCRIPT_DIR/validate-naming-rule.test.sh"
OWN_FIXTURES_DIR=""
[[ -d "$SCRIPT_DIR/../fixtures/naming-rule" ]] \
  && OWN_FIXTURES_DIR="$(cd "$SCRIPT_DIR/../fixtures/naming-rule" && pwd)"

ROOT="${1:-}"
if [[ -z "$ROOT" ]]; then
  echo "usage: validate-naming-rule.sh <path-to-core-root>" >&2
  exit 2
fi
if [[ ! -d "$ROOT" ]]; then
  echo "invalid: directory not found: $ROOT" >&2
  exit 2
fi
if [[ ! -f "$DENYLIST_FILE" ]]; then
  echo "invalid: denylist not found: $DENYLIST_FILE" >&2
  exit 2
fi

ROOT="$(cd "$ROOT" && pwd)"

# Own-fixtures exclusion (below) only makes sense when <core-root> is a tree
# that merely *contains* this validator's fixtures as test data — not when
# <core-root> is that fixtures tree itself, or a fixture inside it, which is
# exactly how this validator's own test suite proves it can fail.
if [[ -n "$OWN_FIXTURES_DIR" && ( "$ROOT" == "$OWN_FIXTURES_DIR" || "$ROOT" == "$OWN_FIXTURES_DIR"/* ) ]]; then
  OWN_FIXTURES_DIR=""
fi

# --- paths excluded from the scan itself -------------------------------------
# Not exceptions to a rule violation — these paths carry the denylist's own
# literal terms as data, the same way a fixture carries an embedded directive
# as data (shared/external-content-safety.md) rather than as core vocabulary.
is_excluded_path() {
  local file="$1"
  [[ "$file" == "$DENYLIST_FILE" ]] && return 0
  [[ "$file" == "$SELF_TEST_FILE" ]] && return 0
  [[ -n "$OWN_FIXTURES_DIR" && "$file" == "$OWN_FIXTURES_DIR"/* ]] && return 0
  return 1
}

# --- read denylist terms -----------------------------------------------------
TERMS=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  TERMS+=("$line")
done < "$DENYLIST_FILE"

if [[ ${#TERMS[@]} -eq 0 ]]; then
  echo "invalid: denylist is empty: $DENYLIST_FILE" >&2
  exit 2
fi

FILES_SCANNED=$(find "$ROOT" -type f -not -path '*/.git/*' | wc -l | tr -d '[:space:]')
VIOLATIONS=0

for term in "${TERMS[@]}"; do
  # Escape ERE metacharacters, then wrap in word boundaries so a short term
  # cannot match inside an unrelated longer word.
  escaped="$(printf '%s' "$term" | sed -E 's/[][\.^$*+?(){}|\\]/\\&/g')"
  pattern="\\b${escaped}\\b"
  while IFS=: read -r file lineno content; do
    [[ -z "$file" ]] && continue
    is_excluded_path "$file" && continue
    VIOLATIONS=$((VIOLATIONS + 1))
    echo "invalid: '$term' — ${file#"$ROOT"/}:$lineno:$content" >&2
  done < <(grep -rnE --exclude-dir=.git -- "$pattern" "$ROOT" 2>/dev/null)
done

if [[ "$VIOLATIONS" -gt 0 ]]; then
  echo "invalid: $VIOLATIONS naming-rule violation(s) found" >&2
  exit 1
fi

echo "valid: naming rule ($FILES_SCANNED files scanned, ${#TERMS[@]} terms checked)"
exit 0
