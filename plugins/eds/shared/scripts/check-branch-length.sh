#!/usr/bin/env bash
# check-branch-length.sh — Deterministic branch-length check (D539). No model
# involved.
#
# The dev server builds `<branch>--<repo>--<owner>` and refuses to start when
# that exceeds the 63-character DNS label limit (G45). For this project the
# suffix `--aem-eds-ai-workflow-demo--agenticDraft` is 40 characters, so a
# branch may be at most 23. The limit is fixed here; the suite asserts it still
# matches this repository's origin. The dev server replaces `/` with `-`
# before measuring, which does not change the length.
#
# Usage:
#   check-branch-length.sh <branch>
#
# Output: one line,
#   ok: branch=<name> length=<n> limit=23          (exit 0)
#   too-long: branch=<name> length=<n> limit=23    (exit 1)
#
# Exit codes:
#   0 — within the limit
#   1 — too long
#   2 — usage error (a missing or empty argument)

set -uo pipefail

LIMIT=23
BRANCH="${1:-}"

if [[ -z "$BRANCH" ]]; then
  echo "usage: check-branch-length.sh <branch>" >&2
  exit 2
fi

LENGTH=$(LC_ALL=C; printf '%s' "$BRANCH" | wc -c | tr -d ' ')

if [[ "$LENGTH" -gt "$LIMIT" ]]; then
  echo "too-long: branch=$BRANCH length=$LENGTH limit=$LIMIT"
  exit 1
fi

echo "ok: branch=$BRANCH length=$LENGTH limit=$LIMIT"
exit 0
