#!/usr/bin/env bash
# validate-contracts.sh — Deterministic conformance check for shared/skill-authoring.md:
# a branching skill's DOT digraph (## Flow) node labels must correspond, in both
# directions, to the ### headings under its ## Node Details. No model involved.
#
# A SKILL.md with neither a ## Flow digraph nor a ## Node Details section passes
# trivially — that is a linear skill, which skill-authoring.md exempts from the
# digraph requirement entirely. This checker only ever compares the two sections
# against each other; it never judges whether a skill *should* branch.
#
# Usage:
#   validate-contracts.sh <path-to-SKILL.md>      — check exactly that file
#   validate-contracts.sh <path-to-directory>      — check every SKILL.md found under it
#
# Exit codes:
#   0 — every file checked has matching node <-> heading correspondence (including
#       trivially); "valid: skill-authoring (<n> SKILL.md files scanned, <b> branching)"
#   1 — at least one mismatch; one "invalid: '<label>' — <path>: <reason>" per
#       mismatch on stderr, then a count
#   2 — usage error: missing argument, or path not found

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_TEST_FILE="$SCRIPT_DIR/validate-contracts.test.sh"
OWN_FIXTURES_DIR=""
[[ -d "$SCRIPT_DIR/../fixtures/skill-authoring" ]] \
  && OWN_FIXTURES_DIR="$(cd "$SCRIPT_DIR/../fixtures/skill-authoring" && pwd)"

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "usage: validate-contracts.sh <path-to-SKILL.md-or-directory>" >&2
  exit 2
fi
if [[ ! -e "$TARGET" ]]; then
  echo "invalid: path not found: $TARGET" >&2
  exit 2
fi

# --- extraction ---------------------------------------------------------------

# Every quoted node label declared in the ## Flow section's fenced ```dot block,
# identified by its trailing "[shape=" — an edge line's quoted strings (the
# endpoints, or a "[label=...]" condition) never carry "[shape=", so this alone
# separates node declarations from edges without needing to parse the digraph.
extract_flow_nodes() {
  local file="$1"
  awk '/^## Flow$/{f=1; next} /^## /{if (f) exit} f' "$file" \
    | awk '/^```dot/{f=1; next} /^```/{if (f) exit} f' \
    | grep -E '\[shape=' \
    | grep -oE '"[^"]+"' \
    | sed 's/"//g' \
    | sort -u
}

# Every "### heading" text under ## Node Details.
extract_node_headings() {
  local file="$1"
  awk '/^## Node Details$/{f=1; next} /^## /{if (f) exit} f' "$file" \
    | grep -E '^### ' \
    | sed -E 's/^### //' \
    | sort -u
}

# --- per-file check -------------------------------------------------------------
# Prints one "invalid: ..." line per mismatch, in both directions. Returns via
# global VIOLATIONS / FILES_SCANNED / FILES_BRANCHING rather than a return code,
# since a single check may find more than one mismatch.

VIOLATIONS=0
FILES_SCANNED=0
FILES_BRANCHING=0

check_one_file() {
  local file="$1" relpath="$2"
  local nodes_f headings_f
  nodes_f="$(mktemp "${TMPDIR:-/tmp}/validate-contracts-nodes.XXXXXX")"
  headings_f="$(mktemp "${TMPDIR:-/tmp}/validate-contracts-headings.XXXXXX")"
  extract_flow_nodes "$file" > "$nodes_f"
  extract_node_headings "$file" > "$headings_f"

  FILES_SCANNED=$((FILES_SCANNED + 1))
  if [[ -s "$nodes_f" || -s "$headings_f" ]]; then
    FILES_BRANCHING=$((FILES_BRANCHING + 1))
  fi

  while IFS= read -r label; do
    [[ -z "$label" ]] && continue
    VIOLATIONS=$((VIOLATIONS + 1))
    echo "invalid: '$label' — $relpath: digraph node has no matching '### heading' in ## Node Details" >&2
  done < <(comm -23 "$nodes_f" "$headings_f")

  while IFS= read -r label; do
    [[ -z "$label" ]] && continue
    VIOLATIONS=$((VIOLATIONS + 1))
    echo "invalid: '$label' — $relpath: '### heading' in ## Node Details has no matching digraph node" >&2
  done < <(comm -13 "$nodes_f" "$headings_f")

  rm -f "$nodes_f" "$headings_f"
}

# --- drive ------------------------------------------------------------------

if [[ -f "$TARGET" ]]; then
  # Single-file mode checks exactly the file given, even if it happens to sit
  # under this validator's own fixtures — that override is how the test suite
  # points the checker directly at a violation fixture to prove it fails.
  check_one_file "$TARGET" "$TARGET"
elif [[ -d "$TARGET" ]]; then
  ROOT="$(cd "$TARGET" && pwd)"
  EXCLUDE_FIXTURES="$OWN_FIXTURES_DIR"
  if [[ -n "$EXCLUDE_FIXTURES" && ( "$ROOT" == "$EXCLUDE_FIXTURES" || "$ROOT" == "$EXCLUDE_FIXTURES"/* ) ]]; then
    EXCLUDE_FIXTURES=""
  fi
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if [[ -n "$EXCLUDE_FIXTURES" && "$file" == "$EXCLUDE_FIXTURES"/* ]]; then
      continue
    fi
    check_one_file "$file" "${file#"$ROOT"/}"
  done < <(find "$ROOT" -type f -name 'SKILL.md' -not -path '*/.git/*' | sort)
else
  echo "invalid: not a file or directory: $TARGET" >&2
  exit 2
fi

if [[ "$VIOLATIONS" -gt 0 ]]; then
  echo "invalid: $VIOLATIONS skill-authoring violation(s) found" >&2
  exit 1
fi

echo "valid: skill-authoring ($FILES_SCANNED SKILL.md files scanned, $FILES_BRANCHING branching)"
exit 0
