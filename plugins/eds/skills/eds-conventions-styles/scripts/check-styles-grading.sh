#!/usr/bin/env bash
# check-styles-grading.sh — Deterministic short-circuit for the `styles`
# subagent (D20, D75). Answers the two cases the contract already fixes
# outright, before any judgment is needed; only the remaining case is a real
# grading question, left to the calling skill's own reasoning.
#
# Usage:
#   check-styles-grading.sh <path-to-design-reference.json> [project-root]
#
# `project-root` defaults to the current directory — the manifest this checks
# for is a project-source file, `<project-root>/styles/design-system.md`
# (D20/D22), never a path under this plugin.
#
# Output: one line.
#   decision=no-values     — the design reference carries has_values: false;
#                             an image source or a source with no variables to
#                             compare. Nothing to grade.
#   decision=no-manifest   — has_values: true, but this project has not
#                             adopted a design system yet (D20's "no manifest"
#                             path). Nothing to grade against.
#   decision=gradeable variables=<n>
#                           — both exist; the calling skill grades each named
#                             variable itself.
#
# Exit codes:
#   0 — decided (every branch above is a decision, not an error)
#   2 — usage error (missing argument, file not found, unreadable JSON)

set -uo pipefail

REF="${1:-}"
ROOT="${2:-.}"

if [[ -z "$REF" ]]; then
  echo "usage: check-styles-grading.sh <path-to-design-reference.json> [project-root]" >&2
  exit 2
fi
[[ -f "$REF" ]] || { echo "invalid: file not found: $REF" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "invalid: jq not available" >&2; exit 2; }

has_values="$(jq -r '.has_values' "$REF" 2>/dev/null)" \
  || { echo "invalid: $REF is not valid JSON" >&2; exit 2; }
[[ "$has_values" == "true" || "$has_values" == "false" ]] \
  || { echo "invalid: $REF has no boolean 'has_values' field" >&2; exit 2; }

if [[ "$has_values" == "false" ]]; then
  echo "decision=no-values"
  exit 0
fi

if [[ ! -f "$ROOT/styles/design-system.md" ]]; then
  echo "decision=no-manifest"
  exit 0
fi

count="$(jq -r '.variables // {} | length' "$REF" 2>/dev/null || echo 0)"
echo "decision=gradeable variables=$count"
exit 0
