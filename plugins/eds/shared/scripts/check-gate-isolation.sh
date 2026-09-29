#!/usr/bin/env bash
# check-gate-isolation.sh — Deterministic gate isolation check and verdict cap
# (D537, gate-contract.md "Isolation is checked, not assumed"). No model
# involved.
#
# A gate compares its own working directory with the project_root it was
# given, both resolved to physical paths (`pwd -P`). Equal means the harness
# ran the gate in the checkout under review, not an isolated one. The gate
# still reviews; its verdict is capped at `warn`.
#
# Usage:
#   check-gate-isolation.sh isolation <project_root>
#     Compares this process's working directory with <project_root>.
#     Output: `isolation: present` (different) or `isolation: absent` (equal).
#   check-gate-isolation.sh cap <present|absent> <pass|warn|fail>
#     Output: the verdict to emit. absent + pass → warn; everything else is
#     returned unchanged. A gate is never failed for being unisolated.
#
# Exit codes:
#   0 — answered
#   2 — usage error (unknown mode, a missing, empty or non-directory
#       project_root, an unknown isolation value or verdict)

set -uo pipefail

usage() {
  echo "usage: check-gate-isolation.sh isolation <project_root>" >&2
  echo "       check-gate-isolation.sh cap <present|absent> <pass|warn|fail>" >&2
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
  cap)
    [ "$#" -eq 2 ] || usage "cap: expected exactly 2 arguments"
    case "$1" in present|absent) ;; *) usage "cap: isolation must be present or absent, got '$1'" ;; esac
    case "$2" in pass|warn|fail) ;; *) usage "cap: verdict must be pass, warn or fail, got '$2'" ;; esac
    if [ "$1" = "absent" ] && [ "$2" = "pass" ]; then
      echo "warn"
    else
      echo "$2"
    fi
    ;;
  *)
    usage "unknown mode '${MODE}'"
    ;;
esac
exit 0
