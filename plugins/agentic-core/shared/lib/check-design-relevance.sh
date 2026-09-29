#!/usr/bin/env bash
# check-design-relevance.sh — Deterministic check that a design reference is
# about the same thing as the work item it came with (see
# shared/plan-criteria.md, "Design relevance"). No model involved.
#
# Compares two keyword lists:
#   item keywords   — the tokens of the sanitized spec's summary (its first
#                     '# ' heading) and of every entry of the fact record's
#                     `components` list;
#   design keywords — the tokens of the design reference's `node_name` and of
#                     every `data-name` attribute value in the design-context
#                     file its `design_context.code_file` names. Element names
#                     only: text between tags is rendered copy, never read.
#
# A design name is one node name or element name, with any leading
# `Desktop/`, `Mobile/` or `Component/` removed (case-insensitive, repeated),
# identified by its token sequence; two names with the same tokens are one
# name. A name matches when any of its tokens is an item keyword. Fewer than
# 2 matching names is `low`.
#
# Tokenisation, applied the same way to both sides:
#   1. a lower-case letter or digit followed by an upper-case letter is split
#      there (camel case);
#   2. every character that is not an ASCII letter or digit separates tokens
#      (so hyphens, underscores, slashes and spaces all split);
#   3. lower-cased;
#   4. a token shorter than 3 characters is dropped, and so is a token of
#      digits only;
#   5. a token on the stop-word list below is dropped;
#   6. a token of 4 or more characters ending in `s` but not `ss` loses that
#      `s` (a plural is its singular; nothing else is stemmed).
#
# Usage:
#   check-design-relevance.sh <root> <spec> <fact record> <design reference>
#   check-design-relevance.sh --tokens <text>
#   check-design-relevance.sh --stop-words
#
# <spec>, <fact record> and <design reference> are absolute, or relative to
# <root>; a relative `code_file` is relative to <root>.
#
# Output (stdout), first line always the decision:
#   relevance: match (<n> of <m> design names share an item keyword; threshold 2)
#   relevance: low (<n> of <m> design names share an item keyword; threshold 2)
#     followed, for both, by:
#   item keywords: <sorted, comma-separated>
#   design keywords: <sorted, comma-separated>
#   matching names: <sorted, semicolon-separated> | none
#
#   relevance: not run (<what was missing>)
#     when the fact record's design_source and design_mentioned are both
#     false, when no design reference file exists, or when its
#     design_context is null; otherwise naming, separated by '; ', each of
#     a missing node_name, a missing design_context.code_file, a code file
#     that does not exist, and a code file with no data-name values.
#
# Exit codes:
#   0 — a decision was printed: match, low or not run. A low score is a
#       finding for the caller to record, never a failure; not run is no
#       finding.
#   2 — usage error, no decision printed: missing argument, spec or fact
#       record not found, spec with no summary heading, design reference not
#       a JSON object, design_context neither null nor an object, or a
#       node_name or code_file present but not a string. The caller treats
#       it as a check that could not run (gate-contract.md).
#
# Requires: jq.

set -uo pipefail
export LC_ALL=C

STOP_WORDS="and are but component desktop for from has have into its mobile not onto our per should that the their this via was were will with your"
THRESHOLD=2

usage() {
  echo "usage: check-design-relevance.sh <root> <spec> <fact record> <design reference>" >&2
  echo "       check-design-relevance.sh --tokens <text> | --stop-words" >&2
  if [ "$#" -gt 0 ]; then echo "$1" >&2; fi
  exit 2
}

# stdin: any text. stdout: its tokens, one per line, in order.
tokenise() {
  sed -E 's/([a-z0-9])([A-Z])/\1 \2/g' \
    | tr -c 'A-Za-z0-9' '\n' \
    | tr 'A-Z' 'a-z' \
    | awk -v stop="$STOP_WORDS" '
        BEGIN { n = split(stop, s, " "); for (i = 1; i <= n; i++) sw[s[i]] = 1 }
        length($0) < 3 { next }
        /^[0-9]+$/ { next }
        ($0 in sw) { next }
        {
          t = $0
          if (length(t) >= 4 && t ~ /s$/ && t !~ /ss$/) t = substr(t, 1, length(t) - 1)
          print t
        }'
}

# stdin: one name per line. stdout: the same names with leading prefixes removed.
strip_prefixes() {
  awk '{
    while (tolower($0) ~ /^[[:space:]]*(desktop|mobile|component)\//) sub(/^[^\/]*\//, "")
    print
  }'
}

joined() { paste -sd, - | sed 's/,/, /g'; }

case "${1:-}" in
  --tokens)
    [ "$#" -eq 2 ] || usage "--tokens takes exactly one text argument"
    printf '%s\n' "$2" | tokenise
    exit 0
    ;;
  --stop-words)
    [ "$#" -eq 1 ] || usage "--stop-words takes no argument"
    printf '%s\n' $STOP_WORDS
    exit 0
    ;;
esac

[ "$#" -eq 4 ] || usage "expected exactly four arguments"
command -v jq > /dev/null 2>&1 || usage "jq is required and was not found"

ROOT="$1"
[ -d "$ROOT" ] || usage "'$ROOT' is not a directory"

resolve() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$ROOT" "$1" ;; esac; }

SPEC=$(resolve "$2")
FACTS=$(resolve "$3")
REFERENCE=$(resolve "$4")

[ -f "$SPEC" ] || usage "spec not found: $SPEC"
[ -f "$FACTS" ] || usage "fact record not found: $FACTS"

fact_value() { sed -n "s/^$1:[[:space:]]*//p" "$FACTS" | head -1 | sed 's/[[:space:]]*$//'; }

if [ "$(fact_value design_source)" = "false" ] && [ "$(fact_value design_mentioned)" = "false" ]; then
  echo "relevance: not run (the item has no design reference)"
  exit 0
fi

if [ ! -f "$REFERENCE" ]; then
  echo "relevance: not run (no design reference at $REFERENCE)"
  exit 0
fi

jq -e 'type == "object"' "$REFERENCE" > /dev/null 2>&1 || usage "design reference is not a JSON object: $REFERENCE"

CONTEXT_KIND=$(jq -r 'if .design_context == null then "null"
  elif (.design_context | type) != "object" then "malformed"
  elif .design_context.code_file == null then "absent"
  elif (.design_context.code_file | type) == "string" then "file"
  else "malformed" end' "$REFERENCE")
NODE_KIND=$(jq -r 'if (.node_name == null or .node_name == "") then "absent"
  elif (.node_name | type) == "string" then "name"
  else "malformed" end' "$REFERENCE")

[ "$CONTEXT_KIND" != malformed ] \
  || usage "design_context must be null or an object whose code_file is a path: $REFERENCE"
[ "$NODE_KIND" != malformed ] || usage "node_name must be a string: $REFERENCE"

if [ "$CONTEXT_KIND" = null ]; then
  echo "relevance: not run (the design reference has no design context)"
  exit 0
fi

MISSING=()
[ "$NODE_KIND" = name ] || MISSING+=("no node_name")
CODE_FILE=""
if [ "$CONTEXT_KIND" = absent ]; then
  MISSING+=("no design_context.code_file")
else
  CODE_FILE=$(resolve "$(jq -r '.design_context.code_file' "$REFERENCE")")
  if [ ! -f "$CODE_FILE" ]; then
    MISSING+=("no design-context file at $CODE_FILE")
  elif ! grep -qE "data-name=(\"[^\"]*\"|'[^']*')" "$CODE_FILE"; then
    MISSING+=("no data-name values in $CODE_FILE")
  fi
fi

if [ "${#MISSING[@]}" -gt 0 ]; then
  REASON=$(printf '%s\n' "${MISSING[@]}" | paste -sd';' - | sed 's/;/; /g')
  echo "relevance: not run ($REASON)"
  exit 0
fi

SUMMARY=$(sed -n 's/^# //p' "$SPEC" | head -1)
[ -n "${SUMMARY//[[:space:]]/}" ] || usage "spec has no summary heading (a first '# ' line): $SPEC"

COMPONENTS=$(fact_value components | sed -e 's/^\[//' -e 's/\]$//' | tr ',' '\n' \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")

ITEM_KEYWORDS=$(printf '%s\n%s\n' "$SUMMARY" "$COMPONENTS" | tokenise | sort -u)

NAMES_RAW=$( {
  jq -r 'if (.node_name | type) == "string" then .node_name else empty end' "$REFERENCE"
  grep -oE "data-name=(\"[^\"]*\"|'[^']*')" "$CODE_FILE" | sed -E "s/^data-name=[\"'](.*)[\"']$/\1/"
} | strip_prefixes)

# One line per distinct design name: its tokens, space-separated.
NAMES=$(printf '%s\n' "$NAMES_RAW" | while IFS= read -r name; do
  [ -n "$name" ] || continue
  printf '%s\n' "$name" | tokenise | paste -sd' ' -
done | sed '/^$/d' | sort -u)

DESIGN_KEYWORDS=$(printf '%s\n' "$NAMES" | tr ' ' '\n' | sed '/^$/d' | sort -u)

MATCHING=$(printf '%s\n' "$NAMES" | awk -v item="$(printf '%s ' $ITEM_KEYWORDS)" '
  BEGIN { n = split(item, k, " "); for (i = 1; i <= n; i++) kw[k[i]] = 1 }
  NF == 0 { next }
  { for (i = 1; i <= NF; i++) if ($i in kw) { print; next } }')

TOTAL=$(printf '%s\n' "$NAMES" | sed '/^$/d' | wc -l | tr -d ' ')
COUNT=$(printf '%s\n' "$MATCHING" | sed '/^$/d' | wc -l | tr -d ' ')

if [ "$COUNT" -ge "$THRESHOLD" ]; then DECISION=match; else DECISION=low; fi

echo "relevance: $DECISION ($COUNT of $TOTAL design names share an item keyword; threshold $THRESHOLD)"
echo "item keywords: $(printf '%s\n' "$ITEM_KEYWORDS" | sed '/^$/d' | joined)"
echo "design keywords: $(printf '%s\n' "$DESIGN_KEYWORDS" | sed '/^$/d' | joined)"
if [ "$COUNT" -eq 0 ]; then
  echo "matching names: none"
else
  echo "matching names: $(printf '%s\n' "$MATCHING" | sed '/^$/d' | paste -sd';' - | sed 's/;/; /g')"
fi
exit 0
