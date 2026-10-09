#!/usr/bin/env bash
# preview-url.sh — Deterministic PR preview-URL decision (G31). No model
# involved.
#
# The `aem-psi-check` bot measures the branch preview named in the pull request
# body. Only a change to a served path has anything to measure, and the preview
# host `<branch><suffix>` is one DNS label, at most 63 characters. The suffix,
# `--<repo>--<owner>` in lower case, is the project's own value, read from the
# project config's `platform.preview_host_suffix`; this pack holds none.
#
# Served paths are the site structure `AGENTS.project.md` lists, minus what
# `.hlxignore` excludes (`*.md`):
#   blocks/ styles/ scripts/ fonts/ icons/ tools/ head.html 404.html favicon.ico
#
# Usage:
#   preview-url.sh --branch <branch> --base <ref> [--config <path>]
#
#   --config  the project config (default .ai/project-config.yaml); read only
#             when a served path changed
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
#     pr-type: not-configured key=platform.preview_host_suffix reason=<why>
#
# A host label holds only a-z, 0-9 and `-`. How the preview host rewrites any
# other character in a branch name is not documented, so such a branch gets no
# URL rather than a guessed one. `/` becomes `-` and upper case is lowered.
#
# Exit codes:
#   0 — decided (served, automation-only, branch-too-long, branch-unsupported)
#   2 — usage error
#   3 — the diff could not be read
#   4 — a served path changed and the config holds no usable suffix; no URL is
#       guessed

set -uo pipefail

LIMIT=63
DOMAIN="aem.page"

usage() { echo "usage: preview-url.sh --branch <branch> --base <ref> [--config <path>]" >&2; exit 2; }

BRANCH=""
BASE=""
CONFIG=".ai/project-config.yaml"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --base)   BASE="${2:-}"; shift 2 ;;
    --config) [[ $# -ge 2 && -n "$2" ]] || usage; CONFIG="$2"; shift 2 ;;
    *) usage ;;
  esac
done

if [[ -z "$BRANCH" || -z "$BASE" ]]; then
  usage
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

not_configured() {
  echo "pr-type: not-configured key=platform.preview_host_suffix reason=$1" >&2
  exit 4
}
[[ -f "$CONFIG" ]] || not_configured "no project config at $CONFIG"
HOST_SUFFIX=$(awk '
  /^platform:[[:space:]]*$/ { inside = 1; next }
  inside && /^[^[:space:]]/ { inside = 0 }
  inside && /^  preview_host_suffix:/ { sub(/^  preview_host_suffix:[[:space:]]*/, ""); gsub(/["[:space:]]/, ""); print; exit }
' "$CONFIG")
[[ -n "$HOST_SUFFIX" ]] || not_configured "not set in $CONFIG"
[[ "$HOST_SUFFIX" =~ ^--[a-z0-9-]+$ ]] \
  || not_configured "'$HOST_SUFFIX' in $CONFIG is not --<repo>--<owner> in a-z, 0-9 and -"

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
