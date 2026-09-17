#!/usr/bin/env bash
# check-spec.test.sh — Coverage for check-spec.py: one case per form rule it
# enforces, plus the readiness case a draft can fail without breaking any form
# rule (a visual change with no design reference attached).
#
# Every case is the conforming draft with one thing changed, written inline
# rather than shipped as a fixture file, so a case and the rule it covers stay
# in one place.
#
# Usage:
#   bash check-spec.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/check-spec.py"
# An explicit template, not a bare "mktemp -d": on this platform the bare form
# ignores TMPDIR and picks a per-user directory a sandboxed run may not write to.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-spec.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

# A draft that satisfies every rule.
clean_draft() {
  cat <<'EOF'
---
item_type: Story
summary: Features carousel block
---

## Description

Add a features carousel to blocks/features-carousel/, authored through the
project's standard table-based content model.

## Design reference

https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-167

## Acceptance criteria

AC-1 A block directory blocks/features-carousel/ exists.
AC-2 Every spacing value resolves to an adopted design-system token.

## Out of scope

Any change to another block.
EOF
}

# run_case <label> <expected exit> <expected substring> <draft text>
# The draft arrives as an argument rather than on stdin: a pipeline would run
# this function in a subshell, and the pass/fail counters would never survive it.
run_case() {
  local label="$1" expected_exit="$2" expected="$3" draft_text="$4"
  local draft="$TMP/${label// /-}.md" out actual_exit
  printf '%s\n' "$draft_text" > "$draft"
  out="$(python3 "$CHECKER" "$draft" 2>&1)"
  actual_exit=$?
  if [[ "$actual_exit" == "$expected_exit" && "$out" == *"$expected"* ]]; then
    echo "  ok: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected exit $expected_exit containing: $expected"
    echo "    got exit $actual_exit:"
    echo "$out" | sed 's/^/      /'
    FAIL=$((FAIL + 1))
  fi
}

echo "[accepts a conforming draft]"
run_case "clean story" 0 "valid: write-specs" "$(clean_draft)"

echo "[form violations]"
run_case "criterion with no id" 1 "carries no AC-<n> id" \
  "$(clean_draft | sed 's|^AC-1 A block directory|- A block directory|')"

run_case "ids not sequential" 1 "not sequential from 1" \
  "$(clean_draft | sed 's|^AC-2 |AC-4 |')"

run_case "semicolon in a criterion" 1 "semicolon" \
  "$(clean_draft | sed 's|^AC-2 .*|AC-2 Spacing resolves to a token; colour does too.|')"

run_case "unverifiable wording" 1 "no pass/fail threshold" \
  "$(clean_draft | sed 's|^AC-2 .*|AC-2 The block renders properly.|')"

run_case "two sentences in a criterion" 1 "more than one sentence" \
  "$(clean_draft | sed 's|^AC-2 .*|AC-2 The list renders. The button renders.|')"

run_case "no out-of-scope section" 1 "an out-of-scope section" \
  "$(clean_draft | sed '/^## Out of scope$/,$d')"

run_case "summary is a sentence" 1 "ends in a full stop" \
  "$(clean_draft | sed 's|^summary: .*|summary: Add a features carousel block to the project.|')"

run_case "summary too long" 1 "more than 8" \
  "$(clean_draft | sed 's|^summary: .*|summary: Features carousel block with a numbered list and a button image|')"

run_case "component path without its slash" 1 "no trailing slash" \
  "$(clean_draft | sed 's|blocks/features-carousel/ exists|blocks/features-carousel exists|')"

echo "[readiness, not form]"
run_case "visual change with no design reference" 1 "readiness would fail" \
  "$(clean_draft | sed '/^https:\/\/www.figma.com/d')"

echo "[item type with its own rules]"
run_case "bug with no reproduction steps" 1 "reproduction steps" \
  "$(clean_draft | sed 's|^item_type: Story|item_type: Bug|')"

echo "[review notes do not fail the run]"
run_case "criterion joined with and" 0 "review: AC-2 contains 'and'" \
  "$(clean_draft | sed 's|^AC-2 .*|AC-2 The list and the button render through the global styles.|')"

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
