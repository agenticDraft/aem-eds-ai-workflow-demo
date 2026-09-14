#!/usr/bin/env bash
# classify-severity.sh — Deterministic severity test for an audit finding
# (see shared/audit-taxonomy.md). No model involved: severity is decided by
# one checkable question — "does an agent read this file as truth?" — never
# by how a finding looks.
#
# The test is a membership check against a list a platform pack declares
# itself: the paths it loads into every stage's own context (a house-style
# document, a project-conventions file, and the like). The core has no
# opinion on which paths those are for any given platform — only the pack
# knows — so this script takes that list as an argument rather than
# hardcoding one.
#
# Usage:
#   classify-severity.sh <file> <path-to-trusted-files-list>
#
# <path-to-trusted-files-list> is a plain text file, one relative path per
# line; blank lines and lines starting with # are ignored. <file> is
# compared to each line by exact string equality after trimming surrounding
# whitespace from both sides — no path normalization beyond that.
#
# Output (stdout), exactly one line:
#   severity: poisoning   — <file> is a member of the trusted-files list
#   severity: cosmetic    — it is not
#
# Exit codes:
#   0 — classified (either outcome above is a legitimate answer, not an
#       error)
#   2 — usage error: missing argument, or the trusted-files list not found

set -uo pipefail

FILE="${1:-}"
LIST="${2:-}"

if [[ -z "$FILE" || -z "$LIST" ]]; then
  echo "usage: classify-severity.sh <file> <path-to-trusted-files-list>" >&2
  exit 2
fi

if [[ ! -f "$LIST" ]]; then
  echo "invalid: file not found: $LIST" >&2
  exit 2
fi

TARGET="${FILE#"${FILE%%[![:space:]]*}"}"
TARGET="${TARGET%"${TARGET##*[![:space:]]}"}"

while IFS= read -r line || [[ -n "$line" ]]; do
  trimmed="${line#"${line%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  [[ -z "$trimmed" ]] && continue
  [[ "$trimmed" =~ ^# ]] && continue
  if [[ "$trimmed" == "$TARGET" ]]; then
    echo "severity: poisoning"
    exit 0
  fi
done < "$LIST"

echo "severity: cosmetic"
exit 0
