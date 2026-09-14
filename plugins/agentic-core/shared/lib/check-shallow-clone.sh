#!/usr/bin/env bash
# check-shallow-clone.sh — Deterministic precondition for the auto-fix
# eligibility oracle (see shared/audit-taxonomy.md and
# check-auto-fix-eligibility.sh, the check this precondition protects).
#
# A shallow clone (`git clone --depth N`) returns at most one commit for
# *any* path's history, regardless of how many times that path was really
# touched — the depth cutoff decides what `git log` reports, not the
# path's real history. Run against a shallow clone, the eligibility oracle
# would silently misclassify every already-edited file as untouched since
# import. This check exists so that never happens quietly.
#
# Callers MUST run this once, against the same project root, and confirm
# it exits 0 before calling check-auto-fix-eligibility.sh even once — the
# two checks are kept as separate, ordered scripts deliberately, so a
# caller getting the order wrong (or skipping this one) is a visible
# mistake in whatever invokes them, not something either script could
# paper over by re-checking the other's work.
#
# A positive result here is a PERMANENT abort: it stops before any file is
# checked, and the only remedy is restoring full history.
#
# Usage:
#   check-shallow-clone.sh <project-root>
#
# Exit codes:
#   0 — full clone; "ok: full clone (safe for the eligibility oracle)" on
#       stdout
#   1 — shallow clone; "permanent-abort: <reason>" on stderr, naming
#       `git fetch --unshallow` as the remedy
#   2 — usage error: missing argument, project root not found, or not a
#       git checkout

set -uo pipefail

ROOT="${1:-}"

if [[ -z "$ROOT" ]]; then
  echo "usage: check-shallow-clone.sh <project-root>" >&2
  exit 2
fi

if [[ ! -d "$ROOT" ]]; then
  echo "invalid: project root not found: $ROOT" >&2
  exit 2
fi

GIT_COMMON_DIR="$ROOT/.git"
if [[ ! -d "$GIT_COMMON_DIR" ]]; then
  echo "invalid: not a git checkout (no .git directory): $ROOT" >&2
  exit 2
fi

git_root() {
  git --git-dir="$GIT_COMMON_DIR" --work-tree="$ROOT" "$@"
}

IS_SHALLOW="$(git_root rev-parse --is-shallow-repository 2>/dev/null)" || {
  echo "invalid: could not determine shallow status: $ROOT" >&2
  exit 2
}

if [[ "$IS_SHALLOW" == "true" ]]; then
  echo "permanent-abort: shallow clone detected — the eligibility oracle needs full history to be trustworthy; run 'git fetch --unshallow' in $ROOT and retry." >&2
  exit 1
fi

echo "ok: full clone (safe for the eligibility oracle)"
exit 0
