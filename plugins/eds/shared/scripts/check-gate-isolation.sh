#!/usr/bin/env bash
# check-gate-isolation.sh — Deterministic gate isolation check (D537, D121,
# gate-contract.md "Isolation is checked, not assumed"). No model involved.
#
# A gate compares its own working directory with the project_root it was
# given, both resolved to physical paths (`pwd -P`). Equal means the harness
# ran the gate in the checkout under review, not an isolated one. The gate
# records the answer in its report and reviews as usual; its verdict is the
# review's own. That it wrote nothing else is proved by the driver's tree
# guard, not by this check.
#
# Usage:
#   check-gate-isolation.sh isolation <project_root>
#     Compares this process's working directory with <project_root>.
#     Output: `isolation: present` (different) or `isolation: absent` (equal).
#
# Exit codes:
#   0 — answered
#   2 — usage error (unknown mode, or a missing, empty or non-directory
#       project_root)

set -uo pipefail

usage() {
  echo "usage: check-gate-isolation.sh isolation <project_root>" >&2
  if [ "$#" -gt 0 ]; then echo "$1" >&2; fi
  exit 2
}

MODE="${1:-}"
[ "$#" -gt 0 ] && shift

case "$MODE" in
  isolation)
    [ "$#" -eq 1 ] || usage "isolation: expected exactly 1 argument"
    ROOT="$1"
    [ -n "$ROOT" ] || usage "isolation: project_root is empty"
    [ -d "$ROOT" ] || usage "isolation: '$ROOT' is not a directory"
    HERE=$(pwd -P) || usage "isolation: cannot resolve the working directory"
    THERE=$(cd "$ROOT" && pwd -P) || usage "isolation: cannot resolve '$ROOT'"
    if [ "$HERE" = "$THERE" ]; then
      echo "isolation: absent"
    else
      echo "isolation: present"
    fi
    ;;
  *)
    usage "unknown mode '${MODE}'"
    ;;
esac
exit 0
