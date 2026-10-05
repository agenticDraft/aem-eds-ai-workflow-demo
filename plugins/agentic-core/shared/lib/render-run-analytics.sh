#!/usr/bin/env bash
# render-run-analytics.sh — Render a run's analytics.md at a terminal state
# from the transcript path the driver's hook recorded (see shared/analytics.md).
#
# Usage:
#   render-run-analytics.sh <run-context-dir>
#
# Reads <run-context-dir>/transcript-path.txt (written by the driver's
# record-transcript-path hook) and renders <run-context-dir>/analytics.md
# from that transcript with render-analytics.sh. A terminal node must end
# whether or not analytics could be rendered, so every outcome but a usage
# error exits 0 and says what happened on one stdout line:
#
#   written: <run-context-dir>/analytics.md       rendered
#   skipped: no transcript path recorded in <dir> no hook input reached the run
#   skipped: transcript not found: <path>         the recorded file is gone
#   skipped: analytics not rendered (exit <n>)    the renderer refused; its stderr is kept
#
# Exit codes: 0 — one of the lines above was printed; 2 — usage error (no
# directory given, or not a directory).

set -uo pipefail

CONTEXT="${1:-}"

if [[ -z "$CONTEXT" || ! -d "$CONTEXT" ]]; then
  echo "usage: render-run-analytics.sh <run-context-dir>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECORD="$CONTEXT/transcript-path.txt"

TRANSCRIPT=""
[[ -f "$RECORD" ]] && TRANSCRIPT="$(head -n 1 "$RECORD" 2>/dev/null | tr -d '\r')"

if [[ -z "$TRANSCRIPT" ]]; then
  echo "skipped: no transcript path recorded in $CONTEXT"
  exit 0
fi

if [[ ! -f "$TRANSCRIPT" ]]; then
  echo "skipped: transcript not found: $TRANSCRIPT"
  exit 0
fi

if OUT="$(bash "$SCRIPT_DIR/render-analytics.sh" "$TRANSCRIPT" "$CONTEXT/analytics.md" 2>&1)"; then
  printf '%s\n' "$OUT"
  exit 0
fi

STATUS=$?
printf '%s\n' "$OUT" >&2
echo "skipped: analytics not rendered (exit $STATUS)"
exit 0
