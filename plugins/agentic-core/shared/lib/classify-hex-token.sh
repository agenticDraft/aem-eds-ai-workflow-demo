#!/usr/bin/env bash
# classify-hex-token.sh — Deterministic classification of a raw hex color
# value against an adopted token set (see shared/design-manifest.md and
# shared/audit-taxonomy.md). No model involved: this is the mechanical test
# behind one of the audit taxonomy's worked examples — a raw hex in a
# stylesheet is `mechanical` when it exactly equals an adopted token, and
# `judgment` when it is close but not equal.
#
# "Close" is a fixed, stated rule, not a feel: every RGB channel of the
# candidate differs from the nearest adopted color token by at most 20 (of
# 255) — near enough to plausibly be a hand-typed or rounded copy of that
# token, far enough that equality is never mistaken for closeness. Alpha
# (an 8-digit hex's last channel) is ignored for comparison, since it is
# opacity, not color identity. A 3- or 4-digit hex is expanded to its
# 6-digit form first (`abc` -> `aabbcc`), the same shorthand CSS itself
# defines.
#
# Only `tokens.values` entries whose value is itself a hex color are
# candidates — a dimension token can never be "close" to a color, and an
# `tokens.unresolvable` entry has no comparable value at all.
#
# Usage:
#   classify-hex-token.sh <hex> <path-to-design-manifest>
#
# Output (stdout), exactly one line:
#   mechanical: exact match — <token name> (<value>)
#   judgment: close match — <token name> (<value>), max channel difference <n>
#   no-match
#
# Exit codes:
#   0 — classified (any of the three outcomes above)
#   1 — the manifest file does not conform to shared/design-manifest.md;
#       "invalid: <reason>" on stderr
#   2 — usage error: missing argument, file not found, or <hex> is not a
#       recognizable hex color literal
#
# Requires: the manifest to already validate against
# lib/validate-design-manifest.sh; this script re-parses it directly rather
# than shelling out, so its own contract violations are reported the same
# way that validator reports them.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HEX_IN="${1:-}"
MANIFEST="${2:-}"

if [[ -z "$HEX_IN" || -z "$MANIFEST" ]]; then
  echo "usage: classify-hex-token.sh <hex> <path-to-design-manifest>" >&2
  exit 2
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "invalid: file not found: $MANIFEST" >&2
  exit 2
fi

# --- normalize the candidate hex --------------------------------------------
SHORT_RE='^#([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])?$'
LONG_RE='^#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})?$'

if [[ "$HEX_IN" =~ $LONG_RE ]]; then
  R_IN="${BASH_REMATCH[1]}"; G_IN="${BASH_REMATCH[2]}"; B_IN="${BASH_REMATCH[3]}"
elif [[ "$HEX_IN" =~ $SHORT_RE ]]; then
  R_IN="${BASH_REMATCH[1]}${BASH_REMATCH[1]}"
  G_IN="${BASH_REMATCH[2]}${BASH_REMATCH[2]}"
  B_IN="${BASH_REMATCH[3]}${BASH_REMATCH[3]}"
else
  echo "usage: '$HEX_IN' is not a recognizable hex color (#rgb, #rgba, #rrggbb or #rrggbbaa)" >&2
  exit 2
fi

# --- reuse the manifest parser's own token-list reading ---------------------
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  LINES+=("$line")
done < "$MANIFEST"
n=${#LINES[@]}

fail_invalid() {
  echo "invalid: $1" >&2
  exit 1
}

[[ "${LINES[0]:-}" =~ ^version:\ [0-9]+$ ]] || fail_invalid "expected 'version: <int>' on line 1"
[[ "${LINES[1]:-}" == "tokens:" ]] || fail_invalid "expected 'tokens:' on line 2"
[[ "${LINES[2]:-}" == "  provenance: resolved-value-set" ]] \
  || fail_invalid "expected '  provenance: resolved-value-set' on line 3"

cursor=3
TOKEN_NAMES=()
TOKEN_VALUES=()

if [[ "${LINES[cursor]:-}" == "  values: []" ]]; then
  cursor=$((cursor + 1))
elif [[ "${LINES[cursor]:-}" == "  values:" ]]; then
  cursor=$((cursor + 1))
  while [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ -\ name:\ \"(.*)\"$ ]]; do
    name="${BASH_REMATCH[1]}"
    cursor=$((cursor + 1))
    [[ "${LINES[cursor]:-}" =~ ^\ \ \ \ \ \ value:\ \"(.*)\"$ ]] \
      || fail_invalid "'$name' is missing its 'value'"
    TOKEN_NAMES+=("$name")
    TOKEN_VALUES+=("${BASH_REMATCH[1]}")
    cursor=$((cursor + 1))
  done
else
  fail_invalid "expected '  values: []' or '  values:'"
fi
(( cursor <= n )) || fail_invalid "manifest ended before 'unresolvable:'"

# --- compare against every color-shaped adopted token -----------------------
BEST_NAME=""
BEST_VALUE=""
BEST_MAX_DIFF=999
EXACT_NAME=""
EXACT_VALUE=""

# printf's %d accepts a "0x"-prefixed operand case-insensitively, so
# comparing the decimal values sidesteps hex case-folding entirely — no
# bash-version-dependent case-conversion syntax needed.
hex2dec() { printf '%d' "0x$1"; }
abs_diff() { local a=$1 b=$2; (( a > b )) && echo $((a - b)) || echo $((b - a)); }

R_IN_DEC=$(hex2dec "$R_IN"); G_IN_DEC=$(hex2dec "$G_IN"); B_IN_DEC=$(hex2dec "$B_IN")

for i in "${!TOKEN_NAMES[@]}"; do
  tval="${TOKEN_VALUES[$i]}"
  [[ "$tval" =~ $LONG_RE ]] || { [[ "$tval" =~ $SHORT_RE ]] || continue; }

  if [[ "$tval" =~ $LONG_RE ]]; then
    tok_r="${BASH_REMATCH[1]}"; tok_g="${BASH_REMATCH[2]}"; tok_b="${BASH_REMATCH[3]}"
  else
    [[ "$tval" =~ $SHORT_RE ]] || continue
    tok_r="${BASH_REMATCH[1]}${BASH_REMATCH[1]}"
    tok_g="${BASH_REMATCH[2]}${BASH_REMATCH[2]}"
    tok_b="${BASH_REMATCH[3]}${BASH_REMATCH[3]}"
  fi

  tok_r_dec=$(hex2dec "$tok_r"); tok_g_dec=$(hex2dec "$tok_g"); tok_b_dec=$(hex2dec "$tok_b")

  if (( tok_r_dec == R_IN_DEC && tok_g_dec == G_IN_DEC && tok_b_dec == B_IN_DEC )); then
    EXACT_NAME="${TOKEN_NAMES[$i]}"
    EXACT_VALUE="$tval"
    break
  fi

  dr=$(abs_diff "$tok_r_dec" "$R_IN_DEC")
  dg=$(abs_diff "$tok_g_dec" "$G_IN_DEC")
  db=$(abs_diff "$tok_b_dec" "$B_IN_DEC")
  max_diff=$dr
  (( dg > max_diff )) && max_diff=$dg
  (( db > max_diff )) && max_diff=$db

  if (( max_diff < BEST_MAX_DIFF )); then
    BEST_MAX_DIFF=$max_diff
    BEST_NAME="${TOKEN_NAMES[$i]}"
    BEST_VALUE="$tval"
  fi
done

CLOSE_THRESHOLD=20

if [[ -n "$EXACT_NAME" ]]; then
  echo "mechanical: exact match — $EXACT_NAME ($EXACT_VALUE)"
  exit 0
fi

if [[ -n "$BEST_NAME" ]] && (( BEST_MAX_DIFF <= CLOSE_THRESHOLD )); then
  echo "judgment: close match — $BEST_NAME ($BEST_VALUE), max channel difference $BEST_MAX_DIFF"
  exit 0
fi

echo "no-match"
exit 0
