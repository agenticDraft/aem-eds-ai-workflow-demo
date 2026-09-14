#!/usr/bin/env bash
# write-design-manifest.sh — Mechanical writer for a design manifest (see
# shared/design-manifest.md), and the proposed-tokens.css and
# proposed-breakpoints.md files that accompany it. No judgment involved: the
# caller has already retrieved every input frame through the design role's
# fetch_reference operation; this script only classifies and places what
# fetch_reference already resolved.
#
# Classification is mechanical, never a guess: a value matching a hex color
# or a plain numeric/dimensioned pattern becomes a CSS custom property; any
# other value (a composite or structured value a design tool returns as one
# token, e.g. a bundled typography style) is recorded in the manifest's
# tokens.unresolvable list instead, with the reason stated, never dropped
# and never coerced into a guessed CSS value.
#
# The same variable name resolving to two different values across input
# frames is a conflict this script refuses to resolve by picking either one
# — it aborts instead (exit 1), naming both conflicting frames.
#
# Usage:
#   write-design-manifest.sh <output-dir> <artifact.json> [<artifact.json> ...]
#
# Each <artifact.json> is one fetch_reference artifact: an object with
# 'reference' (string), 'geometry.width' (number), and 'variables' (an
# object, name to resolved value, possibly empty).
#
# Writes, always overwriting whatever is already there (this script owns
# the whole of each of the three files, nothing else ever writes into
# them):
#   <output-dir>/design-system.md      — the design manifest
#   <output-dir>/proposed-tokens.css   — one custom property per resolved value
#   <output-dir>/proposed-breakpoints.md — the recorded frame widths, undereived
#
# Exit codes:
#   0 — success; "written: <output-dir>" on stdout
#   1 — contract violation: an artifact missing a required field, or the
#       same variable name resolving to two different values across inputs
#   2 — usage error: too few arguments, an artifact file not found or not
#       valid JSON
#
# Requires: jq.

set -uo pipefail

OUT_DIR="${1:-}"
shift || true
ARTIFACTS=("$@")

if [[ -z "$OUT_DIR" || "${#ARTIFACTS[@]}" -eq 0 ]]; then
  echo "usage: write-design-manifest.sh <output-dir> <artifact.json> [<artifact.json> ...]" >&2
  exit 2
fi

fail_usage() {
  echo "invalid: $1" >&2
  exit 2
}

fail() {
  echo "invalid: $1" >&2
  exit 1
}

for a in "${ARTIFACTS[@]}"; do
  [[ -f "$a" ]] || fail_usage "artifact file not found: $a"
  jq -e . "$a" > /dev/null 2>&1 || fail_usage "not valid JSON: $a"
  jq -e 'has("reference") and has("geometry") and (.geometry | has("width")) and has("variables")' "$a" > /dev/null 2>&1 \
    || fail_usage "$a is missing one of: reference, geometry.width, variables"
done

# --- frames, in input order -------------------------------------------------
FRAMES_JSON=$(jq -s '[.[] | {reference: .reference, width: .geometry.width}]' "${ARTIFACTS[@]}")

# --- union every variable, detect same-name/different-value conflicts ------
GROUPED_JSON=$(jq -s '
  [ .[] as $a | ($a.variables // {}) | to_entries[] | {name: .key, value: (.value | tostring), ref: $a.reference} ] as $triples
  | ($triples | group_by(.name) | map({name: .[0].name, values: (map(.value) | unique), refs: (map(.ref) | unique)})) as $grouped
  | {
      conflicts: ($grouped | map(select(.values | length > 1))),
      tokens: ($grouped | map(select(.values | length == 1) | {name, value: .values[0]}) | sort_by(.name))
    }
' "${ARTIFACTS[@]}")

CONFLICTS=$(jq -r '.conflicts | length' <<< "$GROUPED_JSON")
if (( CONFLICTS > 0 )); then
  CONFLICT_DESC=$(jq -r '.conflicts | map("'"'"'" + .name + "'"'"' resolved to " + (.values | join(" and ")) + " across " + (.refs | join(", "))) | join("; ")' <<< "$GROUPED_JSON")
  fail "conflicting variable resolution, refusing to pick one: $CONFLICT_DESC"
fi

# --- classify each token: CSS-representable value, or unresolvable ---------
COLOR_RE='^#[0-9A-Fa-f]{3}$|^#[0-9A-Fa-f]{4}$|^#[0-9A-Fa-f]{6}$|^#[0-9A-Fa-f]{8}$'
DIMENSION_RE='^-?[0-9]+(\.[0-9]+)?(px|rem|em|%)?$'

VALUE_NAMES=()
VALUE_VALUES=()
UNRESOLVABLE_NAMES=()
UNRESOLVABLE_REASONS=()

while IFS=$'\t' read -r name value; do
  [[ -z "$name" ]] && continue
  if [[ "$value" =~ $COLOR_RE || "$value" =~ $DIMENSION_RE ]]; then
    VALUE_NAMES+=("$name")
    VALUE_VALUES+=("$value")
  else
    UNRESOLVABLE_NAMES+=("$name")
    UNRESOLVABLE_REASONS+=("value is not a recognized color or dimension: provider returned a composite type")
  fi
done < <(jq -r '.tokens[] | [.name, .value] | @tsv' <<< "$GROUPED_JSON")

mkdir -p "$OUT_DIR"

# --- design-system.md --------------------------------------------------
MANIFEST_PATH="$OUT_DIR/design-system.md"
{
  echo "version: 1"
  echo "tokens:"
  echo "  provenance: resolved-value-set"
  if [[ "${#VALUE_NAMES[@]}" -eq 0 ]]; then
    echo "  values: []"
  else
    echo "  values:"
    for i in "${!VALUE_NAMES[@]}"; do
      echo "    - name: \"${VALUE_NAMES[$i]}\""
      echo "      value: \"${VALUE_VALUES[$i]}\""
    done
  fi
  if [[ "${#UNRESOLVABLE_NAMES[@]}" -eq 0 ]]; then
    echo "  unresolvable: []"
  else
    echo "  unresolvable:"
    for i in "${!UNRESOLVABLE_NAMES[@]}"; do
      echo "    - name: \"${UNRESOLVABLE_NAMES[$i]}\""
      echo "      reason: \"${UNRESOLVABLE_REASONS[$i]}\""
    done
  fi
  echo "frames:"
  jq -r '.[] | "  - reference: \"" + .reference + "\"\n    width: " + (.width | tostring)' <<< "$FRAMES_JSON"
} > "$MANIFEST_PATH"

# --- proposed-tokens.css --------------------------------------------------
slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

CSS_PATH="$OUT_DIR/proposed-tokens.css"
{
  echo "/* Generated from the design source's own resolved values."
  echo " * Nothing here was carried over from an existing stylesheet."
  echo " * See design-system.md for the variable this property came from,"
  echo " * and for values the design source could not resolve to a plain"
  echo " * color or dimension (tokens.unresolvable)."
  echo " */"
  echo ":root {"
  for i in "${!VALUE_NAMES[@]}"; do
    echo "  --$(slug "${VALUE_NAMES[$i]}"): ${VALUE_VALUES[$i]};"
  done
  echo "}"
} > "$CSS_PATH"

# --- proposed-breakpoints.md --------------------------------------------
BREAKPOINTS_PATH="$OUT_DIR/proposed-breakpoints.md"
{
  echo "# Proposed breakpoints"
  echo
  echo "Frame widths recorded from the design source. Thresholds have not been derived from"
  echo "these yet — that derivation is a separate step, not part of this extraction."
  echo
  jq -r '.[] | "- `" + .reference + "` — width " + (.width | tostring)' <<< "$FRAMES_JSON"
} > "$BREAKPOINTS_PATH"

echo "written: $OUT_DIR"
exit 0
