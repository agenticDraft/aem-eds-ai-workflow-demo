#!/usr/bin/env bash
# write-proposed-breakpoints.sh — Rewrites proposed-breakpoints.md with the
# real derivation, from the frame widths already recorded in this project's
# design manifest (design-manifest.md, core contract §6.2). Calls the design
# role for nothing: every width this script derives from is already on disk
# from this skill's own earlier "Write the design manifest" step.
#
# The geometric-mean arithmetic itself is not this script's job — that is
# ../../../../agentic-core/shared/lib/derive-breakpoints.sh (D21,
# breakpoint-thresholds.md), pure arithmetic with no file or manifest
# knowledge at all. This script only reads the manifest's frames, feeds
# their widths to that core script in the shape it expects, and formats the
# result as markdown that shows the arithmetic, not only the outcome.
#
# Usage:
#   write-proposed-breakpoints.sh <design-system.md> <output.md>
#
# Exit codes:
#   0 — success; "written: <output.md>" on stdout
#   2 — usage error: missing argument, manifest not found, manifest has no
#       frames, or the core deriver itself rejected the widths (for example
#       two frames sharing a width) — its own stderr message is forwarded
#       verbatim, never reworded

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVER="$SCRIPT_DIR/../../../../agentic-core/shared/lib/derive-breakpoints.sh"

MANIFEST="${1:-}"
OUTPUT="${2:-}"

if [[ -z "$MANIFEST" || -z "$OUTPUT" ]]; then
  echo "usage: write-proposed-breakpoints.sh <design-system.md> <output.md>" >&2
  exit 2
fi
[[ -f "$MANIFEST" ]] || { echo "invalid: manifest not found: $MANIFEST" >&2; exit 2; }
[[ -f "$DERIVER" ]] || { echo "invalid: core deriver not found: $DERIVER" >&2; exit 2; }

# --- read every frame's reference and width, in manifest order -------------
FRAMES_TSV=$(awk '
  /^frames:$/ { in_frames = 1; next }
  in_frames && /^  - reference: / {
    ref = $0
    sub(/^  - reference: "/, "", ref)
    sub(/"$/, "", ref)
    next
  }
  in_frames && /^    width: / {
    width = $0
    sub(/^    width: /, "", width)
    print ref "\t" width
  }
' "$MANIFEST")

if [[ -z "$FRAMES_TSV" ]]; then
  echo "invalid: no frames found in $MANIFEST" >&2
  exit 2
fi

WIDTHS=()
while IFS=$'\t' read -r ref width; do
  [[ -z "$width" ]] && continue
  WIDTHS+=("$width")
done <<< "$FRAMES_TSV"

# --- derive: pure arithmetic, this project's manifest never enters it ------
DERIVED=$(bash "$DERIVER" "${WIDTHS[@]}" 2>&1)
DERIVE_STATUS=$?
if [[ "$DERIVE_STATUS" -ne 0 ]]; then
  echo "invalid: $DERIVED" >&2
  exit 2
fi

# --- format: frames for traceability, thresholds with the arithmetic shown -
{
  echo "# Proposed breakpoints"
  echo
  echo "Derived from the design frame widths already recorded in \`design-system.md\` —"
  echo "no design values were retrieved to produce this file. Thresholds are the geometric"
  echo "mean of adjacent frame widths, rounded to the nearest 50 (D21); the smallest frame"
  echo "is the base and gets no threshold."
  echo
  echo "## Frames"
  echo
  while IFS=$'\t' read -r ref width; do
    [[ -z "$width" ]] && continue
    echo "- \`$ref\` — width $width"
  done <<< "$FRAMES_TSV"
  echo
  echo "## Derived thresholds"
  echo
  while IFS=$'\t' read -r kind a b sqrt_int rounded; do
    [[ -z "$kind" ]] && continue
    if [[ "$kind" == "base" ]]; then
      echo "- base: ${a} (no threshold)"
    else
      echo "- \`√(${a}×${b}) ≈ ${sqrt_int} → ${rounded}\`"
    fi
  done <<< "$DERIVED"
} > "$OUTPUT"

echo "written: $OUTPUT"
exit 0
