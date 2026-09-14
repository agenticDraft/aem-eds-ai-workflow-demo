#!/usr/bin/env bash
# derive-breakpoints.sh — Mechanical derivation of breakpoint thresholds from
# a list of design frame widths (see shared/breakpoint-thresholds.md). No
# model involved, and no I/O of any kind: this script reads only its own
# arguments and writes only stdout/stderr, so it is testable as pure
# arithmetic with no design provider, no pack and no file on disk involved.
#
# A frame width is a canvas width the design source recorded — a statement
# of what one layout looks like, never itself a switch point. Reading a
# frame width directly as a threshold gives a design its own width as its
# own switch point, so a viewport just past it still renders the narrower
# layout — the defect this script exists to prevent.
#
# Rule: sort the given widths ascending. The smallest is the base and gets
# no threshold. Every adjacent pair's threshold is the geometric mean of the
# two widths, rounded to the nearest 50 — proportional stretch is equal in
# both directions at that point, which the arithmetic mean does not give.
#
# Usage:
#   derive-breakpoints.sh <width> [<width> ...]
#
# Each <width> is a positive number, no unit — this script names no
# platform, no design tool and no unit. Order does not matter; widths are
# sorted before deriving. At least one width is required; a single width
# produces only the base row and no threshold.
#
# Output (stdout), tab-separated fields, one row per line, in ascending
# order:
#   base	<smallest width>
#   threshold	<low>	<high>	<sqrt(low*high) rounded to the nearest integer>	<that value rounded to the nearest 50>
#
# Exit codes:
#   0 — success
#   2 — usage error: no widths given, a width that is not a positive number,
#       or two widths equal to each other (their geometric mean would equal
#       both of them — a threshold equal to a frame width, the exact defect
#       this script exists to prevent, so equal widths are refused rather
#       than silently producing one)
#
# Requires: awk, sort.

set -uo pipefail

if [[ "$#" -lt 1 ]]; then
  echo "usage: derive-breakpoints.sh <width> [<width> ...]" >&2
  exit 2
fi

for w in "$@"; do
  if ! [[ "$w" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "invalid: width must be a positive number, no unit: '$w'" >&2
    exit 2
  fi
  if ! awk -v w="$w" 'BEGIN { exit !(w > 0) }'; then
    echo "invalid: width must be greater than 0: '$w'" >&2
    exit 2
  fi
done

# --- sort ascending ----------------------------------------------------
SORTED=()
while IFS= read -r w; do
  SORTED+=("$w")
done < <(printf '%s\n' "$@" | sort -n)

# --- reject two frames of the same width --------------------------------
for ((i = 1; i < ${#SORTED[@]}; i++)); do
  if awk -v a="${SORTED[$((i - 1))]}" -v b="${SORTED[$i]}" 'BEGIN { exit !(a == b) }'; then
    echo "invalid: two frames share width '${SORTED[$i]}' — their geometric mean would equal both, a threshold equal to a frame width" >&2
    exit 2
  fi
done

# --- base: the smallest width, no threshold -----------------------------
echo -e "base\t${SORTED[0]}"

# --- one threshold per adjacent pair -------------------------------------
for ((i = 1; i < ${#SORTED[@]}; i++)); do
  low="${SORTED[$((i - 1))]}"
  high="${SORTED[$i]}"
  read -r sqrt_int rounded_50 < <(awk -v lo="$low" -v hi="$high" '
    BEGIN {
      s = sqrt(lo * hi)
      si = int(s + 0.5)
      r50 = int((si / 50) + 0.5) * 50
      print si, r50
    }
  ')
  echo -e "threshold\t${low}\t${high}\t${sqrt_int}\t${rounded_50}"
done

exit 0
