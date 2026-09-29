#!/usr/bin/env bash
# check-trigger-identity.sh — Is this comment author allowed to start a run?
# Deterministic: reads trigger.allowed_identities from a project config (see
# shared/project-config.md) and compares it, whole-string, against one
# identity handle. No model involved, no network call.
#
# The handle's format is the tracker pack's business; this script treats it
# as an opaque string and never parses it.
#
# Usage:
#   check-trigger-identity.sh <config-path> <author-id>
#
# Exit codes:
#   0 — allowed; "allowed" on stdout
#   1 — refused; "refused: <reason>" on stderr
#   2 — usage error (wrong argument count, file not found)

set -uo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: check-trigger-identity.sh <config-path> <author-id>" >&2
  exit 2
fi

CONFIG="$1"
AUTHOR="$2"

if [[ ! -f "$CONFIG" ]]; then
  echo "refused: file not found: $CONFIG" >&2
  exit 2
fi

if [[ -z "$AUTHOR" ]]; then
  echo "refused: empty author id" >&2
  exit 1
fi

# Collect the allowed_identities entries: the four-space "- \"...\"" lines
# that directly follow the allowed_identities key under trigger:, stopping at
# the first non-matching line or when we leave the trigger block.
in_trigger=0
in_list=0
allowed=()
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^trigger:$ ]]; then
    in_trigger=1
    continue
  fi
  if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_-]*:$ ]]; then
    # Hit another top-level key, so trigger block ended
    if (( in_trigger )); then
      break
    fi
  fi
  if (( in_trigger )); then
    if [[ "$line" =~ ^\ \ allowed_identities:$ ]]; then
      in_list=1
      continue
    fi
    if (( in_list )); then
      if [[ "$line" =~ ^\ \ \ \ -\ \"(.*)\"$ ]]; then
        allowed+=("${BASH_REMATCH[1]}")
      else
        break
      fi
    fi
  fi
done < "$CONFIG"

if (( ${#allowed[@]} == 0 )); then
  echo "refused: no trigger.allowed_identities in $CONFIG" >&2
  exit 1
fi

for id in "${allowed[@]}"; do
  if [[ "$id" == "$AUTHOR" ]]; then
    echo "allowed"
    exit 0
  fi
done

echo "refused: '$AUTHOR' is not in trigger.allowed_identities" >&2
exit 1
