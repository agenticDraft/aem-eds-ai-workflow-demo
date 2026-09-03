#!/usr/bin/env bash
# resolve-route.sh — Deterministic route resolution (see shared/project-config.md
# for the routes shape and shared/fact-record.md for the fact record shape). No
# model involved: turns a fact record into an ordered stage list by lookup only,
# in this fixed order:
#   1. an explicitly named route (fact record's explicit_route) — wins outright
#   2. the config's ordered signal table (routes[].when) — first match wins
#   3. the declared default
#
# A route's `when` block matches the fact record when every key present in it
# matches: item_type is a membership check (the fact record's item_type is one
# of the listed types); labels is a subset check (every listed label is present
# on the fact record); design_source is an equality check. A key absent from
# `when` is ignored.
#
# Usage:
#   resolve-route.sh <project-config path> <fact-record path>
#
# Exit codes:
#   0 — resolved; prints "route: <id>", "stages: [...]" and "rule: <what fired>"
#   1 — contract violation (e.g. explicit_route names an id absent from the
#       route table); "invalid: <reason>" on stderr
#   2 — usage error (missing argument, file not found)

set -uo pipefail

CONFIG="${1:-}"
FACT="${2:-}"

if [[ -z "$CONFIG" || -z "$FACT" ]]; then
  echo "usage: resolve-route.sh <project-config path> <fact-record path>" >&2
  exit 2
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "invalid: file not found: $CONFIG" >&2
  exit 2
fi

if [[ ! -f "$FACT" ]]; then
  echo "invalid: file not found: $FACT" >&2
  exit 2
fi

fail() {
  echo "invalid: $1" >&2
  exit 1
}

# --- read the config file into an indexed array -----------------------------
CONFIG_LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  CONFIG_LINES+=("$line")
done < "$CONFIG"
n=${#CONFIG_LINES[@]}

# Find the 'routes:' top-level key, then walk its entries. The config is
# assumed to already conform to shared/project-config.md's shape — this
# resolver reads the routes table, it does not re-validate the whole file.
cursor=0
while (( cursor < n )) && [[ "${CONFIG_LINES[cursor]}" != "routes:" ]]; do
  cursor=$((cursor + 1))
done
(( cursor >= n )) && fail "no 'routes:' key found in $CONFIG"
cursor=$((cursor + 1))

ROUTE_IDS=()
ROUTE_ITEM_TYPES=()   # comma-joined list, or "" when absent
ROUTE_LABELS=()        # comma-joined list, or "" when absent
ROUTE_DESIGN_SOURCE=() # "true" | "false" | "" when absent
ROUTE_STAGES=()

while [[ "${CONFIG_LINES[cursor]:-}" =~ ^\ \ -\ id:\ (.+)$ ]]; do
  route_id="${BASH_REMATCH[1]}"
  cursor=$((cursor + 1))

  item_type="" labels="" design_source=""
  if [[ "${CONFIG_LINES[cursor]:-}" == "    when:" ]]; then
    cursor=$((cursor + 1))
    if [[ "${CONFIG_LINES[cursor]:-}" =~ ^\ \ \ \ \ \ item_type:\ \[(.*)\]$ ]]; then
      item_type="${BASH_REMATCH[1]}"
      cursor=$((cursor + 1))
    fi
    if [[ "${CONFIG_LINES[cursor]:-}" =~ ^\ \ \ \ \ \ labels:\ \[(.*)\]$ ]]; then
      labels="${BASH_REMATCH[1]}"
      cursor=$((cursor + 1))
    fi
    if [[ "${CONFIG_LINES[cursor]:-}" =~ ^\ \ \ \ \ \ design_source:\ (true|false)$ ]]; then
      design_source="${BASH_REMATCH[1]}"
      cursor=$((cursor + 1))
    fi
  fi

  if [[ "${CONFIG_LINES[cursor]:-}" =~ ^\ \ \ \ stages:\ \[(.+)\]$ ]]; then
    stages="${BASH_REMATCH[1]}"
    cursor=$((cursor + 1))
  else
    fail "route '$route_id' is missing its 'stages:' list"
  fi

  ROUTE_IDS+=("$route_id")
  ROUTE_ITEM_TYPES+=("$item_type")
  ROUTE_LABELS+=("$labels")
  ROUTE_DESIGN_SOURCE+=("$design_source")
  ROUTE_STAGES+=("$stages")
done

[[ ${#ROUTE_IDS[@]} -eq 0 ]] && fail "route table has no routes in $CONFIG"

if [[ "${CONFIG_LINES[cursor]:-}" =~ ^\ \ default:\ (.+)$ ]]; then
  default_route="${BASH_REMATCH[1]}"
else
  fail "route table has no default in $CONFIG"
fi

stages_for() {
  local want="$1" i
  for i in "${!ROUTE_IDS[@]}"; do
    [[ "${ROUTE_IDS[$i]}" == "$want" ]] && { echo "${ROUTE_STAGES[$i]}"; return 0; }
  done
  return 1
}

# --- read the fact record: a flat "key: value" file, keys optional ---------
fact_get() {
  local key="$1" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^${key}:\ (.*)$ ]]; then
      echo "${BASH_REMATCH[1]}"
      return 0
    fi
  done < "$FACT"
  return 1
}

fact_item_type="$(fact_get item_type || true)"
fact_labels_raw="$(fact_get labels || true)"
fact_labels="${fact_labels_raw#\[}"
fact_labels="${fact_labels%\]}"
fact_design_source="$(fact_get design_source || true)"
fact_explicit_route="$(fact_get explicit_route || true)"

# comma_contains <list> <item> — true if <item> appears as a whole element of
# a comma-joined, optionally space-padded list. An empty list contains
# nothing — checked explicitly because iterating a zero-element array under
# `set -u` raises "unbound variable" on some bash versions.
comma_contains() {
  local list="$1" item="$2" IFS=','
  [[ -z "$list" ]] && return 1
  local -a parts
  read -ra parts <<< "$list"
  local p
  for p in "${parts[@]}"; do
    p="${p## }"; p="${p%% }"
    [[ "$p" == "$item" ]] && return 0
  done
  return 1
}

# --- 1. explicit intent wins, unconditionally -------------------------------
if [[ -n "$fact_explicit_route" && "$fact_explicit_route" != "null" ]]; then
  resolved_stages="$(stages_for "$fact_explicit_route")" \
    || fail "explicit_route '$fact_explicit_route' not found in route table"
  resolved_id="$fact_explicit_route"
  rule="explicit_route: $fact_explicit_route"
else
  # --- 2. the ordered signal table, first match wins ------------------------
  resolved_id=""
  for i in "${!ROUTE_IDS[@]}"; do
    match=1

    if [[ -n "${ROUTE_ITEM_TYPES[$i]}" ]]; then
      comma_contains "${ROUTE_ITEM_TYPES[$i]}" "$fact_item_type" || match=0
    fi

    if [[ "$match" -eq 1 && -n "${ROUTE_LABELS[$i]}" ]]; then
      IFS=',' read -ra required <<< "${ROUTE_LABELS[$i]}"
      for r in "${required[@]}"; do
        r="${r## }"; r="${r%% }"
        comma_contains "$fact_labels" "$r" || { match=0; break; }
      done
    fi

    if [[ "$match" -eq 1 && -n "${ROUTE_DESIGN_SOURCE[$i]}" ]]; then
      [[ "${ROUTE_DESIGN_SOURCE[$i]}" == "$fact_design_source" ]] || match=0
    fi

    if [[ "$match" -eq 1 ]]; then
      resolved_id="${ROUTE_IDS[$i]}"
      resolved_stages="${ROUTE_STAGES[$i]}"
      rule="signal_table: ${ROUTE_IDS[$i]}"
      break
    fi
  done

  # --- 3. the declared default ----------------------------------------------
  if [[ -z "$resolved_id" ]]; then
    resolved_stages="$(stages_for "$default_route")" \
      || fail "default route '$default_route' not found in route table"
    resolved_id="$default_route"
    rule="default: $default_route"
  fi
fi

echo "route: $resolved_id"
echo "stages: [$resolved_stages]"
echo "rule: $rule"
exit 0
