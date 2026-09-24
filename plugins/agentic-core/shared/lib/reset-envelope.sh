#!/usr/bin/env bash
# Run: bash plugins/agentic-core/shared/lib/reset-envelope.sh .ai/run-context/envelope-<stage id>.txt
#
# reset-envelope.sh <envelope-file>
#
# Empties a stage's envelope file before that stage is invoked, creating it if
# it does not exist. This is what lets the caller read "the file is non-empty"
# as "this stage wrote its own envelope" rather than as "a file with this name
# was already here" — the same stage id in an earlier run produces the same
# filename, so without this the two are indistinguishable.
#
# Exit codes: 0 — the file exists and is empty; 2 — usage, or the path could
# not be made empty.

set -uo pipefail

usage() {
  echo "usage: reset-envelope.sh <envelope-file>" >&2
  if [ "$#" -gt 0 ]; then echo "$1" >&2; fi
  exit 2
}

[ "$#" -eq 1 ] || usage "expected exactly 1 argument"
FILE="$1"

DIR="$(dirname "$FILE")"
[ -d "$DIR" ] || usage "'$DIR' is not a directory"

: > "$FILE" || usage "could not empty '$FILE'"
[ -f "$FILE" ] && [ ! -s "$FILE" ] || usage "'$FILE' is not an empty file after reset"

echo "reset: '$FILE' is empty; a non-empty file after the stage returns is the stage's own envelope"
exit 0
