#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/check-branch-name.sh <branch>
#
# check-branch-name.sh <branch> [--config <path>] [--project-dir <dir>]
#
# Checks a branch name against the rule the configured platform pack declares
# under `branch_name:` in its manifest (see shared/pack-manifest.md). Names no
# platform and no limit: the pack owns both. Deterministic, no model involved.
#
#   --config       the project config (default .ai/project-config.yaml)
#   --project-dir  passed to resolve-plugin-root.sh, which finds the platform
#                  pack; a caller in a linked worktree passes the main checkout
#
# Characters are checked before length.
#
# Output: one line,
#   ok: branch=<name> length=<n>                     (exit 0)
#   too-long: branch=<name> length=<n> limit=<max>   (exit 1)
#   bad-chars: branch=<name> pattern=<pattern>       (exit 3)
#   ok: no constraint declared                       (exit 0) — no config, no
#       platform pack named, or the resolved pack declares no `branch_name:`
#   not-resolved: platform=<name> — <reason>         (exit 4) — the named pack
#       could not be resolved, or holds no pack.yaml; never "no constraint"
#
# Exit codes: 0 — acceptable; 1 — too long; 2 — usage error; 3 — characters;
# 4 — the platform pack's rule cannot be read.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "usage: check-branch-name.sh <branch> [--config <path>] [--project-dir <dir>]" >&2
  exit 2
}

BRANCH="${1:-}"
[[ -n "$BRANCH" ]] || usage
shift
CONFIG=".ai/project-config.yaml"
RESOLVE_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)      [[ $# -ge 2 ]] || usage; CONFIG="$2"; shift 2 ;;
    --project-dir) [[ $# -ge 2 ]] || usage; RESOLVE_ARGS=(--project-dir "$2"); shift 2 ;;
    *) usage ;;
  esac
done

unconstrained() { echo "ok: no constraint declared"; exit 0; }

[[ -f "$CONFIG" ]] || unconstrained

# `platform:` directly under the top-level `packs:` block.
PLATFORM=$(awk '
  /^packs:[[:space:]]*$/ { inside = 1; next }
  inside && /^[^[:space:]]/ { inside = 0 }
  inside && /^  platform:/ { sub(/^  platform:[[:space:]]*/, ""); gsub(/["[:space:]]/, ""); print; exit }
' "$CONFIG")
[[ -n "$PLATFORM" ]] || unconstrained

not_resolved() { echo "not-resolved: platform=$PLATFORM — $1"; exit 4; }

# The resolver prints the root alone on success and one line on stderr otherwise.
ROOT=$(bash "$SCRIPT_DIR/resolve-plugin-root.sh" "$PLATFORM" ${RESOLVE_ARGS[@]+"${RESOLVE_ARGS[@]}"} 2>&1) \
  || not_resolved "${ROOT:-resolve-plugin-root.sh exited non-zero}"

MANIFEST="$ROOT/pack.yaml"
[[ -f "$MANIFEST" ]] || not_resolved "no pack.yaml at $ROOT"

MAX_LENGTH=""
PATTERN=""
inside=0
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == "branch_name:" ]]; then inside=1; continue; fi
  (( inside )) || continue
  if [[ "$line" =~ ^\ \ max_length:\ ([0-9]+)$ ]]; then
    MAX_LENGTH="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^\ \ pattern:\ \"(.+)\"$ ]]; then
    PATTERN="${BASH_REMATCH[1]}"
  else
    break
  fi
done < "$MANIFEST"

[[ -n "$MAX_LENGTH$PATTERN" ]] || unconstrained

if [[ -n "$PATTERN" ]] && ! printf '%s\n' "$BRANCH" | grep -Eq -- "$PATTERN"; then
  echo "bad-chars: branch=$BRANCH pattern=$PATTERN"
  exit 3
fi

LENGTH=$(LC_ALL=C; printf '%s' "$BRANCH" | wc -c | tr -d ' ')

if [[ -n "$MAX_LENGTH" && "$LENGTH" -gt "$MAX_LENGTH" ]]; then
  echo "too-long: branch=$BRANCH length=$LENGTH limit=$MAX_LENGTH"
  exit 1
fi

echo "ok: branch=$BRANCH length=$LENGTH"
exit 0
