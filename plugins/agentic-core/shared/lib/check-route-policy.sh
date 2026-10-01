#!/usr/bin/env bash
# check-route-policy.sh — Is the route policy usable, and what does it say?
# Deterministic: reads one fixed-shape file, no model, no network. See
# shared/route-policy.md for the shape and what each value means.
#
# Fail-closed by construction: there are no defaults. A missing file, an
# unknown version, an unknown or repeated key, a missing value, a number that
# is not positive, an empty forbidden list or an empty approvers list is
# "invalid", and a caller that gets anything but exit 0 starts nothing.
#
# On success it prints the policy normalized, one value per line, so callers
# never parse the file themselves:
#   version=1
#   forbidden=<rule>                  (one line per rule, in file order)
#   limits.runs_per_identity_per_day=<n>
#   limits.runs_per_day=<n>
#   budget.max_usd_per_run=<n>
#   caps.max_turns=<n>
#   caps.timeout_minutes=<n>
#   break_glass.word=<word>
#   break_glass.approver=<identity>   (one line per approver)
#
# Usage:
#   check-route-policy.sh <policy-path>
#
# Exit codes:
#   0 — valid; the normalized policy on stdout
#   1 — invalid or missing; "invalid: <reason>" on stderr
#   2 — usage error (wrong argument count)

set -uo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: check-route-policy.sh <policy-path>" >&2
  exit 2
fi

POLICY="$1"

invalid() {
  echo "invalid: $1" >&2
  exit 1
}

[[ -f "$POLICY" ]] || invalid "policy file not found: $POLICY"
[[ -r "$POLICY" ]] || invalid "policy file not readable: $POLICY"

INT_RE='^[1-9][0-9]*$'
NUM_RE='^([0-9]+(\.[0-9]+)?)$'
RULE_RE='^[A-Za-z][A-Za-z0-9_]*(\(.+\))?$'
IDENT_RE='^[A-Za-z0-9:_-]+$'
WORD_RE='^[a-z][a-z0-9-]*$'

VERSION=""
FORBIDDEN=()
APPROVERS=()
SEEN=" "     # second-level keys already given, space-separated

section=""   # top-level key currently open
list=""      # list currently open under a section ("forbidden" or "approvers")
n=0

# Strips a trailing comment after a value. Quoted values are matched whole
# first, so a '#' inside quotes is never taken for a comment.
value_of() {
  local raw="$1"
  if [[ "$raw" =~ ^\"([^\"]*)\"[[:space:]]*(#.*)?$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  elif [[ "$raw" =~ ^([^\"#[:space:]][^#]*[^#[:space:]]|[^\"#[:space:]])[[:space:]]*(#.*)?$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    return 1
  fi
}

# Second-level values live in plain variables named after the key
# (limits.runs_per_day -> V_limits__runs_per_day); no associative arrays.
var_of() { printf 'V_%s' "${1//./__}"; }
has() { [[ "$SEEN" == *" $1 "* ]]; }
get() { local v; v="$(var_of "$1")"; printf '%s' "${!v}"; }
set_scalar() {
  local key="$1" val="$2"
  has "$key" && invalid "line $n: '$key' given twice"
  SEEN+="$key "
  printf -v "$(var_of "$key")" '%s' "$val"
}

seen_top=" "

while IFS= read -r line || [[ -n "$line" ]]; do
  n=$((n + 1))
  line="${line%$'\r'}"
  [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue

  # Top-level key.
  if [[ "$line" =~ ^([a-z_]+):[[:space:]]*(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
    [[ "$seen_top" != *" $key "* ]] || invalid "line $n: '$key' given twice"
    seen_top+="$key "
    list=""
    case "$key" in
      version)
        val="$(value_of "$rest")" || invalid "line $n: version has no value"
        VERSION="$val"; section="" ;;
      forbidden)
        [[ "$rest" =~ ^(#.*)?$ ]] || invalid "line $n: forbidden must be a list"
        section="forbidden"; list="forbidden" ;;
      limits|budget|caps|break_glass)
        [[ "$rest" =~ ^(#.*)?$ ]] || invalid "line $n: $key must be a block"
        section="$key" ;;
      *) invalid "line $n: unknown key '$key'" ;;
    esac
    continue
  fi

  # A list item, under forbidden or break_glass.approvers.
  if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.*)$ ]]; then
    [[ -n "$list" ]] || invalid "line $n: a list item outside a list"
    val="$(value_of "${BASH_REMATCH[1]}")" || invalid "line $n: unreadable list item"
    if [[ "$list" == "forbidden" ]]; then
      [[ "$val" =~ $RULE_RE ]] || invalid "line $n: forbidden rule '$val' is not <Tool> or <Tool>(<pattern>)"
      FORBIDDEN+=("$val")
    else
      [[ "$val" =~ $IDENT_RE ]] || invalid "line $n: approver '$val' is not an identity handle"
      APPROVERS+=("$val")
    fi
    continue
  fi

  # A second-level key.
  if [[ "$line" =~ ^[[:space:]]+([a-z_]+):[[:space:]]*(.*)$ ]]; then
    sub="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
    [[ -n "$section" && "$section" != "forbidden" ]] || invalid "line $n: '$sub' is not under a block"
    full="$section.$sub"
    if [[ "$full" == "break_glass.approvers" ]]; then
      [[ "$rest" =~ ^(#.*)?$ ]] || invalid "line $n: approvers must be a list"
      has "$full" && invalid "line $n: '$full' given twice"
      SEEN+="$full "
      list="approvers"
      continue
    fi
    list=""
    case "$full" in
      limits.runs_per_identity_per_day|limits.runs_per_day|budget.max_usd_per_run|caps.max_turns|caps.timeout_minutes|break_glass.word) ;;
      *) invalid "line $n: unknown key '$full'" ;;
    esac
    val="$(value_of "$rest")" || invalid "line $n: '$full' has no value"
    set_scalar "$full" "$val"
    continue
  fi

  invalid "line $n: not understood: $line"
done < "$POLICY"

[[ -n "$VERSION" ]] || invalid "version is missing"
[[ "$VERSION" == "1" ]] || invalid "unknown version '$VERSION'; this checker reads version 1"

need() {
  has "$1" || invalid "'$1' is missing"
}

for k in limits.runs_per_identity_per_day limits.runs_per_day caps.max_turns; do
  need "$k"
  v="$(get "$k")"
  [[ "$v" =~ $INT_RE ]] || invalid "'$k' must be a positive whole number, got '$v'"
done
for k in budget.max_usd_per_run caps.timeout_minutes; do
  need "$k"
  v="$(get "$k")"
  [[ "$v" =~ $NUM_RE ]] || invalid "'$k' must be a positive number, got '$v'"
  [[ "$v" =~ [1-9] ]] || invalid "'$k' must be greater than zero, got '$v'"
done
need break_glass.word
v="$(get break_glass.word)"
[[ "$v" =~ $WORD_RE ]] || invalid "'break_glass.word' must be one lower-case word, got '$v'"
need break_glass.approvers

(( ${#FORBIDDEN[@]} > 0 )) || invalid "forbidden is empty or missing; an empty list is refused, not read as 'nothing is forbidden'"
(( ${#APPROVERS[@]} > 0 )) || invalid "break_glass.approvers is empty"

echo "version=1"
for r in "${FORBIDDEN[@]}"; do echo "forbidden=$r"; done
for k in limits.runs_per_identity_per_day limits.runs_per_day budget.max_usd_per_run caps.max_turns caps.timeout_minutes break_glass.word; do
  echo "$k=$(get "$k")"
done
for a in "${APPROVERS[@]}"; do echo "break_glass.approver=$a"; done
exit 0
