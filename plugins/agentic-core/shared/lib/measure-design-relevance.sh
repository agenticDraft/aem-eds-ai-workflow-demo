#!/usr/bin/env bash
# measure-design-relevance.sh — Re-runs check-design-relevance.sh over archived
# run contexts, so its threshold can be re-measured from saved runs rather than
# from pairs assembled by hand. No model involved. It never changes the checker,
# its threshold or any stage; it only reads.
#
# A run context is any directory, up to three levels under <archive>, that holds
# sanitized-spec.md. It qualifies when it also holds fact-record.yaml and a
# design-reference.json whose node_name is a string; otherwise it is listed as
# skipped with the reason. Each qualifying context is one true pair: its own
# spec against its own design. Each line of <cross pairs> (`<spec context> TAB
# <design context>`, paths relative to <archive>) is one cross pair: a spec
# against another run's design, a link that should not match.
#
# The design reference's code_file names a path inside the run it was written
# in. For each pair the file of that name in the design's archived context is
# placed at that relative path under a fresh temporary root, and the checker
# runs against that root.
#
# Usage:
#   measure-design-relevance.sh <archive> [<cross pairs>]
#
# Output (stdout), paths relative to <archive>, in context order:
#   pair TAB true|cross TAB <spec context> TAB <design context> TAB <n> TAB <m>
#   not-run TAB true|cross TAB <spec context> TAB <design context> TAB <reason>
#   skipped TAB <context> TAB <reason>
#   summary: true=<t> cross=<c> not_run=<r> skipped=<s>
#   threshold 1: true warned=<x> of <t>; cross passed=<y> of <c>
#   threshold 2: true warned=<x> of <t>; cross passed=<y> of <c>
# where <n> of <m> is the checker's count of design names sharing an item
# keyword. At threshold k, a pair with n < k warns and one with n >= k passes.
#
# Exit codes:
#   0 — the measurement was printed, including for an empty archive
#   2 — usage error: missing or unreadable archive or cross pairs file, a cross
#       line without a tab, a cross pair naming a context that does not
#       qualify, or a checker exit 2 (the pair is named on stderr)
#
# Requires: jq.

set -uo pipefail
export LC_ALL=C

CHECKER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-design-relevance.sh"

usage() {
  echo "usage: measure-design-relevance.sh <archive> [<cross pairs>]" >&2
  if [ "$#" -gt 0 ]; then echo "$1" >&2; fi
  exit 2
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage "expected one or two arguments"
ARCHIVE="${1%/}"
CROSS="${2:-}"
[ -d "$ARCHIVE" ] || usage "archive not found: $ARCHIVE"
[ -z "$CROSS" ] || [ -f "$CROSS" ] || usage "cross pairs file not found: $CROSS"
command -v jq > /dev/null 2>&1 || usage "jq is required and was not found"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/measure-design-relevance.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# stdout: the reason a context does not qualify, or nothing when it does.
disqualified() {
  local dir="$ARCHIVE/$1"
  [ -f "$dir/fact-record.yaml" ] || { echo "no fact-record.yaml"; return; }
  [ -f "$dir/design-reference.json" ] || { echo "no design-reference.json"; return; }
  jq -e '(.node_name | type) == "string"' "$dir/design-reference.json" > /dev/null 2>&1 \
    || echo "no node_name in the design reference"
}

QUALIFIED=()
while IFS= read -r spec; do
  ctx="${spec#"$ARCHIVE"/}"
  ctx="${ctx%/sanitized-spec.md}"
  reason="$(disqualified "$ctx")"
  if [ -n "$reason" ]; then
    printf 'skipped\t%s\t%s\n' "$ctx" "$reason" >> "$WORK/skipped"
  else
    QUALIFIED+=("$ctx")
  fi
done < <(find "$ARCHIVE" -mindepth 2 -maxdepth 4 -name sanitized-spec.md | sort)

qualifies() {
  local q
  for q in "${QUALIFIED[@]+"${QUALIFIED[@]}"}"; do [ "$q" = "$1" ] && return 0; done
  return 1
}

PAIRS=()
for q in "${QUALIFIED[@]+"${QUALIFIED[@]}"}"; do PAIRS+=("true$(printf '\t')$q$(printf '\t')$q"); done
if [ -n "$CROSS" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    case "$line" in *$'\t'*) ;; *) usage "cross line has no tab: $line" ;; esac
    a="${line%%$'\t'*}"
    b="${line#*$'\t'}"
    qualifies "$a" || usage "cross pair names a context that does not qualify: $a"
    qualifies "$b" || usage "cross pair names a context that does not qualify: $b"
    PAIRS+=("cross$(printf '\t')$a$(printf '\t')$b")
  done < "$CROSS"
fi

T_TOTAL=0; C_TOTAL=0; NOT_RUN=0
T_WARN1=0; T_WARN2=0; C_PASS1=0; C_PASS2=0
i=0
for pair in "${PAIRS[@]+"${PAIRS[@]}"}"; do
  IFS=$'\t' read -r kind a b <<< "$pair"
  i=$((i + 1))
  root="$WORK/root-$i"
  mkdir -p "$root"
  code="$(jq -r '.design_context.code_file // empty' "$ARCHIVE/$b/design-reference.json")"
  if [ -n "$code" ] && [ "${code#/}" = "$code" ] && [ -f "$ARCHIVE/$b/$(basename "$code")" ]; then
    mkdir -p "$root/$(dirname "$code")"
    cp "$ARCHIVE/$b/$(basename "$code")" "$root/$code"
  fi
  out="$(bash "$CHECKER" "$root" "$ARCHIVE/$a/sanitized-spec.md" "$ARCHIVE/$a/fact-record.yaml" \
    "$ARCHIVE/$b/design-reference.json" 2> "$WORK/checker-err")"
  if [ "$?" -ne 0 ]; then
    usage "the checker could not run on $kind pair $a / $b: $(cat "$WORK/checker-err")"
  fi
  first="$(printf '%s\n' "$out" | head -1)"
  case "$first" in
    "relevance: not run ("*)
      reason="${first#relevance: not run (}"
      printf 'not-run\t%s\t%s\t%s\t%s\n' "$kind" "$a" "$b" "${reason%)}"
      NOT_RUN=$((NOT_RUN + 1))
      continue
      ;;
  esac
  n="$(printf '%s\n' "$first" | sed -nE 's/^relevance: (match|low) \(([0-9]+) of ([0-9]+) .*/\2/p')"
  m="$(printf '%s\n' "$first" | sed -nE 's/^relevance: (match|low) \(([0-9]+) of ([0-9]+) .*/\3/p')"
  [ -n "$n" ] || usage "unreadable checker decision on $kind pair $a / $b: $first"
  printf 'pair\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$a" "$b" "$n" "$m"
  if [ "$kind" = true ]; then
    T_TOTAL=$((T_TOTAL + 1))
    [ "$n" -lt 1 ] && T_WARN1=$((T_WARN1 + 1))
    [ "$n" -lt 2 ] && T_WARN2=$((T_WARN2 + 1))
  else
    C_TOTAL=$((C_TOTAL + 1))
    [ "$n" -ge 1 ] && C_PASS1=$((C_PASS1 + 1))
    [ "$n" -ge 2 ] && C_PASS2=$((C_PASS2 + 1))
  fi
done

SKIPPED=0
if [ -f "$WORK/skipped" ]; then
  cat "$WORK/skipped"
  SKIPPED="$(wc -l < "$WORK/skipped" | tr -d ' ')"
fi
echo "summary: true=$T_TOTAL cross=$C_TOTAL not_run=$NOT_RUN skipped=$SKIPPED"
echo "threshold 1: true warned=$T_WARN1 of $T_TOTAL; cross passed=$C_PASS1 of $C_TOTAL"
echo "threshold 2: true warned=$T_WARN2 of $T_TOTAL; cross passed=$C_PASS2 of $C_TOTAL"
exit 0
