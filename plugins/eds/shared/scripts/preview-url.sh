#!/usr/bin/env bash
# preview-url.sh — Deterministic PR preview-URL decision (G31). No model
# involved.
#
# The `aem-psi-check` bot measures the branch preview named in the pull request
# body. Only a change to a served path has anything to measure, and the preview
# host `<branch>--aem-eds-ai-workflow-demo--agenticdraft` is one DNS label, at
# most 63 characters. The repository and owner are fixed here; the suite
# asserts they still match this repository's origin.
#
# Served paths are the site structure `AGENTS.project.md` lists, minus what
# `.hlxignore` excludes (`*.md`):
#   blocks/ styles/ scripts/ fonts/ icons/ tools/ head.html 404.html favicon.ico
#
# Usage:
#   preview-url.sh --branch <branch> --base <ref>
#
# Reads the changed paths in the current directory, per publish-criteria.md:
# `git diff --name-only <merge-base of base and HEAD>` against the working tree
# (committed and uncommitted alike), unioned with
# `git ls-files --others --exclude-standard` (untracked, non-ignored).
#
# Output:
#   stdout — the text to append to the PR body: the URL block for `served`,
#            nothing otherwise
#   stderr — one line:
#     pr-type: served label_length=<n> limit=63
#     pr-type: automation-only
#     pr-type: branch-too-long label_length=<n> limit=63
#     pr-type: branch-unsupported branch=<name> allowed=a-z0-9-
#
# A host label holds only a-z, 0-9 and `-`. How the preview host rewrites any
# other character in a branch name is not documented, so such a branch gets no
# URL rather than a guessed one. `/` becomes `-` and upper case is lowered.
#
# Exit codes:
#   0 — decided (any of the three types)
#   2 — usage error
#   3 — the diff could not be read

set -uo pipefail

LIMIT=63
HOST_SUFFIX="--aem-eds-ai-workflow-demo--agenticdraft"
DOMAIN="aem.page"

BRANCH=""
BASE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --base)   BASE="${2:-}"; shift 2 ;;
    *) echo "usage: preview-url.sh --branch <branch> --base <ref>" >&2; exit 2 ;;
  esac
done

if [[ -z "$BRANCH" || -z "$BASE" ]]; then
  echo "usage: preview-url.sh --branch <branch> --base <ref>" >&2
  exit 2
fi

if ! MERGE_BASE=$(git merge-base "$BASE" HEAD 2>&1); then
  echo "error: no merge base for $BASE and HEAD: $MERGE_BASE" >&2
  exit 3
fi
if ! TRACKED=$(git diff --name-only "$MERGE_BASE" -- 2>&1); then
  echo "error: cannot diff $MERGE_BASE: $TRACKED" >&2
  exit 3
fi
if ! UNTRACKED=$(git ls-files --others --exclude-standard 2>&1); then
  echo "error: cannot list untracked files: $UNTRACKED" >&2
  exit 3
fi
CHANGED="$TRACKED"$'\n'"$UNTRACKED"

is_served() {
  case "$1" in
    *.md) return 1 ;;
    blocks/*|styles/*|scripts/*|fonts/*|icons/*|tools/*) return 0 ;;
    head.html|404.html|favicon.ico) return 0 ;;
    *) return 1 ;;
  esac
}

SERVED=0
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if is_served "$path"; then SERVED=1; break; fi
done <<< "$CHANGED"

if [[ "$SERVED" -eq 0 ]]; then
  echo "pr-type: automation-only" >&2
  exit 0
fi

HOST_BRANCH="$(printf '%s' "$BRANCH" | tr '/' '-' | tr '[:upper:]' '[:lower:]')"
if [[ ! "$HOST_BRANCH" =~ ^[a-z0-9-]+$ ]]; then
  echo "pr-type: branch-unsupported branch=$BRANCH allowed=a-z0-9-" >&2
  exit 0
fi

LABEL="$HOST_BRANCH$HOST_SUFFIX"
LENGTH=$(LC_ALL=C; printf '%s' "$LABEL" | wc -c | tr -d ' ')

if [[ "$LENGTH" -gt "$LIMIT" ]]; then
  echo "pr-type: branch-too-long label_length=$LENGTH limit=$LIMIT" >&2
  exit 0
fi

echo "pr-type: served label_length=$LENGTH limit=$LIMIT" >&2
printf 'URL for testing:\n\n- https://%s.%s/\n' "$LABEL" "$DOMAIN"
exit 0
