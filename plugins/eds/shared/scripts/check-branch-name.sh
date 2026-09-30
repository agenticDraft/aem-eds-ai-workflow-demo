#!/usr/bin/env bash
# check-branch-name.sh — Deterministic check for a branch name this project
# creates (D539, G31). No model involved.
#
# A branch's preview host `<branch>--<repo>--<owner>` is one DNS label, so the
# name must be short enough (check-branch-length.sh owns the limit) and hold
# only characters a label can carry. Only lower-case a-z, 0-9, `-` and `/` are
# allowed (`/` becomes `-` in the host). A name that fails either gets no
# preview URL from preview-url.sh, and its pull request fails `aem-psi-check`.
#
# Usage:
#   check-branch-name.sh <branch>
#
# Output: one line,
#   ok: branch=<name> length=<n> limit=23                 (exit 0)
#   too-long: branch=<name> length=<n> limit=23           (exit 1)
#   bad-chars: branch=<name> allowed=a-z0-9-/             (exit 3)
#
# Exit codes:
#   0 — valid
#   1 — too long
#   2 — usage error (a missing or empty argument)
#   3 — a character outside a-z0-9-/ (checked before length)

set -uo pipefail

BRANCH="${1:-}"

if [[ -z "$BRANCH" ]]; then
  echo "usage: check-branch-name.sh <branch>" >&2
  exit 2
fi

if [[ ! "$BRANCH" =~ ^[a-z0-9/-]+$ ]]; then
  echo "bad-chars: branch=$BRANCH allowed=a-z0-9-/"
  exit 3
fi

bash "$(dirname "${BASH_SOURCE[0]}")/check-branch-length.sh" "$BRANCH"
