#!/usr/bin/env bash
# check-branch-length.sh — Deterministic branch-length check (D539, D129). No
# model involved.
#
# The dev server builds `<branch>--<repo>--<owner>` and refuses to start when
# that exceeds the 63-character DNS label limit (G45), so the longest branch a
# project accepts is 63 minus the length of its own `--<repo>--<owner>`. That
# number is the project's, read from the project config's
# `branch_name.max_length`; this pack holds none. The dev server replaces `/`
# with `-` before measuring, which does not change the length.
#
# Usage:
#   check-branch-length.sh <branch> [--config <path>]
#
#   --config  the project config (default .ai/project-config.yaml)
#
# Output: one line,
#   ok: branch=<name> length=<n> limit=<max>          (exit 0)
#   too-long: branch=<name> length=<n> limit=<max>    (exit 1)
#   not-configured: branch_name.max_length — <why>    (exit 4)
#
# Exit codes:
#   0 — within the limit
#   1 — too long
#   2 — usage error (a missing or empty argument, an unknown option)
#   4 — the config holds no positive `branch_name.max_length`; no default applies

set -uo pipefail

usage() { echo "usage: check-branch-length.sh <branch> [--config <path>]" >&2; exit 2; }

BRANCH="${1:-}"
[[ -n "$BRANCH" ]] || usage
shift
CONFIG=".ai/project-config.yaml"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) [[ $# -ge 2 && -n "$2" ]] || usage; CONFIG="$2"; shift 2 ;;
    *) usage ;;
  esac
done

not_configured() { echo "not-configured: branch_name.max_length — $1"; exit 4; }

[[ -f "$CONFIG" ]] || not_configured "no project config at $CONFIG"

LIMIT=$(awk '
  /^branch_name:[[:space:]]*$/ { inside = 1; next }
  inside && /^[^[:space:]]/ { inside = 0 }
  inside && /^  max_length:/ { sub(/^  max_length:[[:space:]]*/, ""); gsub(/["[:space:]]/, ""); print; exit }
' "$CONFIG")
[[ -n "$LIMIT" ]] || not_configured "not set in $CONFIG"
[[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || not_configured "'$LIMIT' in $CONFIG is not a positive integer"

LENGTH=$(LC_ALL=C; printf '%s' "$BRANCH" | wc -c | tr -d ' ')

if [[ "$LENGTH" -gt "$LIMIT" ]]; then
  echo "too-long: branch=$BRANCH length=$LENGTH limit=$LIMIT"
  exit 1
fi

echo "ok: branch=$BRANCH length=$LENGTH limit=$LIMIT"
exit 0
