#!/usr/bin/env bash
# list-changed-files.sh <project-root> — the change, minimally (publish-criteria.md).
#
# Prints, one per line, sorted and unique: every path that differs between the
# merge base of origin/HEAD and HEAD, plus every untracked path the project's
# ignore rules do not exclude. A path created in this run and never committed
# is part of the change, so the second set is not optional.
#
# Exit codes:
#   0 — listed (possibly nothing)
#   2 — usage or environment error (not a checkout, no origin/HEAD, no merge base)

set -uo pipefail

ROOT="${1:-}"
if [[ -z "$ROOT" || ! -d "$ROOT" ]]; then
  echo "usage: list-changed-files.sh <project-root>" >&2
  exit 2
fi

git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { echo "invalid: not a git checkout: $ROOT" >&2; exit 2; }

BASE_SYMREF="$(git -C "$ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)" || {
  echo "invalid: origin/HEAD is not set — run 'git remote set-head origin -a' on the project root" >&2
  exit 2
}
MERGE_BASE="$(git -C "$ROOT" merge-base "${BASE_SYMREF#refs/remotes/}" HEAD 2>/dev/null)" || {
  echo "invalid: no merge base between ${BASE_SYMREF#refs/remotes/} and HEAD" >&2
  exit 2
}

{
  git -C "$ROOT" diff "$MERGE_BASE" --name-only
  git -C "$ROOT" ls-files --others --exclude-standard
} | sort -u
