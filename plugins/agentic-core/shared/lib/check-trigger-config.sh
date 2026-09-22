#!/usr/bin/env bash
# check-trigger-config.sh — Does a tracker-side trigger definition still
# carry the token the project config declares? Deterministic: reads
# trigger.token from the config and looks for that literal string in the
# definition file. No model involved, no network call.
#
# The definition's format is the tracker pack's business. This script never
# parses it and holds no path into any pack: the caller supplies both paths,
# which is what keeps this core free of any product name.
#
# Usage:
#   check-trigger-config.sh <config-path> <rule-path>
#
# Exit codes:
#   0 — the definition carries the configured token; "agrees" on stdout
#   1 — it does not; "invalid: <reason>" on stderr
#   2 — usage error (wrong argument count, file not found)

set -uo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: check-trigger-config.sh <config-path> <rule-path>" >&2
  exit 2
fi

CONFIG="$1"
RULE="$2"

for f in "$CONFIG" "$RULE"; do
  if [[ ! -f "$f" ]]; then
    echo "invalid: file not found: $f" >&2
    exit 2
  fi
done

TOKEN=""
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^\ \ token:\ \"(.*)\"$ ]]; then
    TOKEN="${BASH_REMATCH[1]}"
    break
  fi
done < "$CONFIG"

if [[ -z "$TOKEN" ]]; then
  echo "invalid: no trigger.token in $CONFIG" >&2
  exit 1
fi

if grep -qF -- "$TOKEN" "$RULE"; then
  echo "agrees"
  exit 0
fi

echo "invalid: $RULE does not carry the configured token '$TOKEN'" >&2
exit 1
