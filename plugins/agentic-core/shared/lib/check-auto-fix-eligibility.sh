#!/usr/bin/env bash
# check-auto-fix-eligibility.sh — Deterministic auto-fix eligibility oracle
# (see shared/audit-taxonomy.md). No model involved: a file is eligible
# for a silent auto-fix only if it is provably untouched since the
# boilerplate import. `git log --oneline -- <path>` is the oracle,
# answered offline with git as the source of truth: exactly one commit
# (the import itself) means untouched.
#
# A file with more than one commit has been edited since the import, so a
# human decision already lives in it — it demotes from `mechanical` to
# `judgment` rather than being silently rewritten. `audit-taxonomy.md`'s
# `mechanical` class requires a fix applicable "with no human input at
# all"; an already-edited file no longer meets that bar, whatever the edit
# was. A file with zero commits has no import commit to be untouched
# since, so it cannot be *proven* untouched either — treated the same as
# demoted, conservatively, rather than guessed eligible.
#
# Callers MUST run check-shallow-clone.sh against the same project root
# and confirm it exits 0 before calling this script even once. A shallow
# clone makes `git log` return at most one commit for every path
# regardless of real history, which would silently misclassify an
# already-edited file as eligible. This script trusts a full clone and
# does not re-verify it — see check-shallow-clone.sh for why the two
# checks stay separate rather than one script re-checking the other.
#
# Usage:
#   check-auto-fix-eligibility.sh <project-root> <path> [<path> ...]
#
# <path> is relative to <project-root>, matching how a finding's own
# `file` field (audit-taxonomy.md) is recorded.
#
# Output (stdout), one line per path, in argument order:
#   eligible: <path>
#   demoted: <path> (<n> commits)
#
# Exit codes:
#   0 — every path is eligible
#   1 — at least one path is demoted; every line is still printed
#   2 — usage error: missing argument, project root not found, or not a
#       git checkout

set -uo pipefail

ROOT="${1:-}"

if [[ -z "$ROOT" ]]; then
  echo "usage: check-auto-fix-eligibility.sh <project-root> <path> [<path> ...]" >&2
  exit 2
fi
shift

if [[ ! -d "$ROOT" ]]; then
  echo "invalid: project root not found: $ROOT" >&2
  exit 2
fi

GIT_COMMON_DIR="$ROOT/.git"
if [[ ! -d "$GIT_COMMON_DIR" ]]; then
  echo "invalid: not a git checkout (no .git directory): $ROOT" >&2
  exit 2
fi

if [[ $# -eq 0 ]]; then
  echo "usage: check-auto-fix-eligibility.sh <project-root> <path> [<path> ...]" >&2
  exit 2
fi

git_root() {
  git --git-dir="$GIT_COMMON_DIR" --work-tree="$ROOT" "$@"
}

ANY_DEMOTED=0

for path in "$@"; do
  count="$(git_root log --oneline -- "$path" | wc -l | tr -d ' ')"
  if [[ "$count" -eq 1 ]]; then
    echo "eligible: $path"
  else
    echo "demoted: $path ($count commits)"
    ANY_DEMOTED=1
  fi
done

exit "$ANY_DEMOTED"
