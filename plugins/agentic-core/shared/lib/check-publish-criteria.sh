#!/usr/bin/env bash
# check-publish-criteria.sh — Deterministic half of the publish gate (see
# shared/publish-criteria.md, shared/gate-contract.md). No model involved:
# this is the mechanical check that runs before any reviewing model sees
# the change, per the gate contract's fixed order.
#
# Checks two of the publish gate's four criteria — the two that are
# structural rather than judgment:
#   1. Is there a change to review at all (the working tree differs from
#      where this branch started)?
#   2. Does the change avoid every path the project's own .gitignore marks
#      as never-tracked (a forced add of a secret or a run-scratch file)?
# The other two criteria — does the change implement what the plan
# proposed and nothing else, is it free of anything that must not reach
# publication as-is — are judgment, not structure, and are the reviewing
# model's job once this check passes; see publish-criteria.md.
#
# Takes a project root, never a diff or a file list, because "the actual
# change" is resolved through git itself: the base is wherever
# origin/HEAD points, the review side is the working tree of the project
# root as it stands right now — committed and uncommitted alike. Every
# git invocation below uses --git-dir/--work-tree rather than `cd`, so
# this script never changes its own working directory even when the
# project root sits outside it (see publish-criteria.md's "Resolution
# rules").
#
# Usage:
#   check-publish-criteria.sh <project-root>
#
# Exit codes:
#   0 — both structural criteria hold; "valid: publish (<n> files
#       changed)" on stdout
#   1 — a criterion fails; "invalid: <reason>" on stderr, naming why
#       there is nothing to review or which path is never-tracked
#   2 — usage error (no argument, path not found, not a git checkout,
#       origin/HEAD unresolvable, detached HEAD)

set -uo pipefail

ROOT="${1:-}"

if [[ -z "$ROOT" ]]; then
  echo "usage: check-publish-criteria.sh <project-root>" >&2
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

BASE_SYMREF="$(git_root symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)" || {
  echo "invalid: origin/HEAD is not set — run 'git remote set-head origin -a' on the project root" >&2
  exit 2
}
BASE_REF="${BASE_SYMREF#refs/remotes/}"

REVIEW_REF="$(git_root rev-parse --abbrev-ref HEAD 2>/dev/null)" || {
  echo "invalid: could not resolve the project root's current branch" >&2
  exit 2
}
if [[ "$REVIEW_REF" == "HEAD" ]]; then
  echo "invalid: project root is in detached HEAD state — no branch to publish" >&2
  exit 2
fi

MERGE_BASE="$(git_root merge-base "$BASE_REF" HEAD 2>/dev/null)" || {
  echo "invalid: no merge base between '$BASE_REF' and '$REVIEW_REF'" >&2
  exit 2
}

# --name-only against the merge base, not against HEAD alone, so this
# reflects everything the branch introduces — committed and uncommitted —
# not only what has been committed so far. Unioned with `ls-files
# --others --exclude-standard`: `git diff` only ever reports changes to
# already-tracked paths, so a brand-new file `implement` wrote but nothing
# has `git add`ed yet is otherwise invisible to this check even though it
# is very much part of the change under review.
CHANGED_FILES=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  CHANGED_FILES+=("$line")
done < <(git_root diff --name-only "$MERGE_BASE" -- 2>/dev/null)

UNTRACKED_FILES=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  UNTRACKED_FILES+=("$line")
done < <(git_root ls-files --others --exclude-standard 2>/dev/null)

ALL_FILES=("${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}" "${UNTRACKED_FILES[@]+"${UNTRACKED_FILES[@]}"}")

if (( ${#ALL_FILES[@]} == 0 )); then
  echo "invalid: no change to review — working tree matches '$BASE_REF' at the merge base" >&2
  exit 1
fi

# Only CHANGED_FILES needs the .gitignore check, not UNTRACKED_FILES:
# `ls-files --others --exclude-standard` only ever lists paths .gitignore
# does *not* match, by construction, so an untracked file already cannot
# appear in that list unless it was force-added — which moves it from
# UNTRACKED_FILES into CHANGED_FILES (it is now in the index) instead.
#
# --no-index is load-bearing: check-ignore's default index-aware mode
# never reports an already-tracked path as ignored, which is exactly the
# case this check exists to catch — a secret or run-scratch file that
# reached the diff only because something force-added it past .gitignore.
for f in "${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}"; do
  if git_root check-ignore -q --no-index -- "$f"; then
    echo "invalid: '$f' matches a pattern in .gitignore — never publish a path the project marked never-tracked" >&2
    exit 1
  fi
done

echo "valid: publish (${#ALL_FILES[@]} files changed)"
exit 0
