#!/usr/bin/env bash
# write-design-source-kind.sh — Runs resolve-design-source.py against the same
# artifacts `intake` just wrote and appends its decision to the fact record as
# `design_source_kind` (`fact-record.md`, D100, G503, Phase 10 / Task 2).
#
# This is intake's own second, purely mechanical script call — it does not decide
# anything the fact record didn't already determine; it records verbatim what
# resolve-design-source.py's deterministic classification returns.
#
# Usage:
#   write-design-source-kind.sh <fact-record.yaml> <sanitized-spec.md> <fetched-item.json>
#
# Exit codes:
#   0 — `design_source_kind: <word>` appended to the fact record
#   2 — usage error (missing argument, a file not found, or the resolver's own
#       usage error) — nothing appended

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-design-source.py"

FACT="${1:-}"
SPEC="${2:-}"
ITEM="${3:-}"

if [[ -z "$FACT" || -z "$SPEC" || -z "$ITEM" ]]; then
  echo "usage: write-design-source-kind.sh <fact-record.yaml> <sanitized-spec.md> <fetched-item.json>" >&2
  exit 2
fi
for f in "$FACT" "$SPEC" "$ITEM"; do
  [[ -f "$f" ]] || { echo "invalid: file not found: $f" >&2; exit 2; }
done

OUT="$(python3 "$RESOLVER" "$FACT" "$SPEC" "$ITEM" 2>&1)"
ST=$?
if [[ $ST -ne 0 ]]; then
  echo "invalid: resolve-design-source.py failed: $OUT" >&2
  exit 2
fi

if [[ "$OUT" =~ ^decision=([a-z]+) ]]; then
  DECISION="${BASH_REMATCH[1]}"
else
  echo "invalid: resolve-design-source.py printed no usable decision: $OUT" >&2
  exit 2
fi

printf 'design_source_kind: %s\n' "$DECISION" >> "$FACT"
echo "wrote: design_source_kind=$DECISION"
exit 0
