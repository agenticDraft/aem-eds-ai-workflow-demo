#!/usr/bin/env bash
# check-reference.sh — Deterministic "is this string referenced anywhere"
# check (see shared/audit-taxonomy.md). No model involved: this is the
# mechanical test behind an audit finding like "this asset's own name is
# never mentioned outside its own declaration" — a plain, literal-string
# search, not a judgment call about whether something still matters.
#
# A generic utility, not asset- or file-type-specific: it knows nothing
# about fonts, images or any other asset kind. What counts as "the name to
# search for" and "where to search" is decided by whoever calls this
# script — a platform pack's own knowledge of its own files — never by this
# script itself.
#
# Usage:
#   check-reference.sh <needle> <root-dir> [<exclude-file>]
#
# <needle> is matched as a literal, fixed string (grep -F), not a regular
# expression — a font-family name or a file path can itself contain regex
# metacharacters that must not be interpreted as such. <exclude-file>, when
# given, is skipped entirely, so a declaration is not counted as its own
# use (a font file's own @font-face rule, a path's own manifest entry).
#
# Output:
#   one "referenced: <path>:<line>" line per match found (stdout), if any
#   "not-referenced" (stdout) if none are found
#
# Exit codes:
#   0 — at least one reference found (excluding <exclude-file>)
#   1 — no reference found anywhere under <root-dir>
#   2 — usage error: missing argument, <root-dir> not found

set -uo pipefail

NEEDLE="${1:-}"
ROOT="${2:-}"
EXCLUDE="${3:-}"

if [[ -z "$NEEDLE" || -z "$ROOT" ]]; then
  echo "usage: check-reference.sh <needle> <root-dir> [<exclude-file>]" >&2
  exit 2
fi

if [[ ! -d "$ROOT" ]]; then
  echo "invalid: directory not found: $ROOT" >&2
  exit 2
fi

EXCLUDE_ABS=""
if [[ -n "$EXCLUDE" ]]; then
  if [[ -f "$EXCLUDE" ]]; then
    EXCLUDE_ABS="$(cd "$(dirname "$EXCLUDE")" && pwd)/$(basename "$EXCLUDE")"
  else
    echo "invalid: exclude-file not found: $EXCLUDE" >&2
    exit 2
  fi
fi

FOUND=0
while IFS= read -r -d '' f; do
  ABS_F="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
  [[ -n "$EXCLUDE_ABS" && "$ABS_F" == "$EXCLUDE_ABS" ]] && continue
  while IFS=: read -r lineno _rest; do
    echo "referenced: $f:$lineno"
    FOUND=1
  done < <(grep -Fn -- "$NEEDLE" "$f" 2>/dev/null)
done < <(find "$ROOT" -type f -print0)

if (( FOUND == 1 )); then
  exit 0
else
  echo "not-referenced"
  exit 1
fi
