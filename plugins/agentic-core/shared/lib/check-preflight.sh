#!/usr/bin/env bash
# check-preflight.sh — Deterministic capability probe (see shared/pre-flight.md,
# core contract §6/§10). No model, no side effects, no live calls: every check
# reads a pack.yaml or the project config — the same files
# validate-pack-manifest.sh and validate-project-config.sh already validate —
# never a runtime health check against a live tool or process.
#
# Three checks, in order:
#   1. every role the project config requires (packs.platform/tracker/scm/
#      browser always, packs.design only when it is not "none") has a
#      role=path argument naming a pack.yaml that validates as the right
#      kind for that role.
#   2. every operation core contract §6 declares for a configured provider
#      role that a stage could need is implemented rather than declared
#      unsupported. Operations that exist only for callers upstream of the
#      route are exempt — no stage reaches them, so their absence cannot make
#      a stage unrunnable.
#   3. the onboarding gate (core contract §6.3, D80), delegated to
#      check-onboarding-gate.sh against the platform pack's manifest — a
#      no-op unless that manifest declares onboarding_state_path and/or
#      audit_findings_path. An absent onboarding-state file only warns; an
#      open poisoning finding at the audit-findings path blocks.
#   4. the serve notice (core contract §6.4, D94), delegated to
#      check-serve-notice.sh against the same manifest and the project
#      config — a no-op unless the platform pack declares a `serve` stage.
#      It never blocks: it says which preview the run will need and what
#      will start it, so a human learns that before intake rather than
#      several stages in. Like every other check here it reads declarations
#      only; nothing polls the preview.
#
# Usage:
#   check-preflight.sh <project-config path> <role>=<path-to-pack.yaml> [...]
#
# role is one of: platform tracker scm design browser
#
# Exit codes:
#   0 — "ready", then one "<role>: ok" line per role checked ("design: none"
#       when config requires no design pack), then check 3's own line(s)
#       ("onboarding: ok|warn — …", "audit: ok — …") when the platform pack
#       declares either onboarding path — omitted entirely when it declares
#       neither — then check 4's own line ("serve: ok|warn — …") when that
#       pack declares a `serve` stage, omitted entirely when it does not.
#   1 — "invalid: <reason>" on stderr, naming the first missing pack, role
#       mismatch, unavailable operation, or open poisoning finding
#   2 — usage error: no config argument, config not found, a malformed
#       role=path pair, an unrecognized role name

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_CONFIG="$SCRIPT_DIR/validate-project-config.sh"
VALIDATE_MANIFEST="$SCRIPT_DIR/validate-pack-manifest.sh"
CHECK_ONBOARDING="$SCRIPT_DIR/check-onboarding-gate.sh"
CHECK_SERVE_NOTICE="$SCRIPT_DIR/check-serve-notice.sh"

usage() {
  echo "usage: check-preflight.sh <project-config path> <role>=<path-to-pack.yaml> [...]" >&2
  exit 2
}

fail() {
  echo "invalid: $1" >&2
  exit 1
}

CONFIG="${1:-}"
[[ -z "$CONFIG" ]] && usage
shift

if [[ ! -f "$CONFIG" ]]; then
  echo "invalid: file not found: $CONFIG" >&2
  exit 2
fi

CONFIG_OUT="$("$VALIDATE_CONFIG" "$CONFIG" 2>&1)"
CONFIG_STATUS=$?
if [[ $CONFIG_STATUS -ne 0 ]]; then
  fail "project config does not validate — ${CONFIG_OUT#invalid: }"
fi

# --- parse role=path arguments --------------------------------------------
# Parallel indexed arrays, matching every other lookup in this codebase's
# scripts (e.g. STAGE_IDS/STAGE_SKILLS in validate-pack-manifest.sh) — kept
# to that same one portable construct rather than a second one only this
# script would use.
ROLE_NAMES=()
ROLE_PATHS=()
for arg in "$@"; do
  if [[ "$arg" =~ ^([a-z]+)=(.+)$ ]]; then
    role="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
  else
    echo "usage: malformed role=path argument: '$arg'" >&2
    exit 2
  fi
  case "$role" in
    platform|tracker|scm|design|browser) ;;
    *) echo "usage: unrecognized role: '$role'" >&2; exit 2 ;;
  esac
  ROLE_NAMES+=("$role")
  ROLE_PATHS+=("$path")
done

# role_path <role> — sets the global MATCH_PATH to the path supplied for
# that role, or "" if none was.
MATCH_PATH=""
role_path() {
  local want="$1" i
  MATCH_PATH=""
  for i in "${!ROLE_NAMES[@]}"; do
    if [[ "${ROLE_NAMES[$i]}" == "$want" ]]; then
      MATCH_PATH="${ROLE_PATHS[$i]}"
      return 0
    fi
  done
  return 1
}

# --- which roles this config requires --------------------------------------
CONFIG_DESIGN="$(grep -m1 -E '^  design: ' "$CONFIG" | sed -E 's/^  design: *//')"

REQUIRED_ROLES=(platform tracker scm browser)
PROVIDER_ROLES=(tracker scm browser)
if [[ "$CONFIG_DESIGN" != "none" ]]; then
  REQUIRED_ROLES+=(design)
  PROVIDER_ROLES+=(design)
fi

# --- check 1: every required pack is installed ------------------------------
for role in "${REQUIRED_ROLES[@]}"; do
  if ! role_path "$role"; then
    fail "no pack installed for role '$role' — project config requires one"
  fi
  if [[ ! -f "$MATCH_PATH" ]]; then
    fail "pack for role '$role' not installed: file not found: $MATCH_PATH"
  fi
done

role_path platform
PLATFORM_PATH="$MATCH_PATH"
PLATFORM_OUT="$("$VALIDATE_MANIFEST" "$PLATFORM_PATH" 2>&1)"
PLATFORM_STATUS=$?
if [[ $PLATFORM_STATUS -ne 0 ]]; then
  fail "pack for role 'platform' does not validate — ${PLATFORM_OUT#invalid: }"
fi
[[ "$PLATFORM_OUT" == "valid: platform" ]] \
  || fail "pack for role 'platform' is not a platform pack: $PLATFORM_PATH"

for role in "${PROVIDER_ROLES[@]}"; do
  role_path "$role"
  path="$MATCH_PATH"
  out="$("$VALIDATE_MANIFEST" "$path" 2>&1)"
  status=$?
  if [[ $status -ne 0 ]]; then
    fail "pack for role '$role' does not validate — ${out#invalid: }"
  fi
  [[ "$out" == "valid: provider" ]] \
    || fail "pack for role '$role' is not a provider pack: $path"

  manifest_role="$(grep -m1 -E '^role: ' "$path" | sed -E 's/^role: *//')"
  [[ "$manifest_role" == "$role" ]] \
    || fail "pack installed for role '$role' declares role '$manifest_role' instead: $path"
done

# --- check 2: every operation a stage could need is implemented ------------
# The contract's rule is that an unsupported operation makes *a stage needing
# it* unrunnable. Not every operation can be needed by one: a few exist for
# callers upstream of the route, which no stage reaches. Blocking a run because
# one of those is unimplemented refuses work the run was never going to do.
#
# There is no declared stage-to-operation map to consult, so the set that no
# stage can need is named here, once. An operation absent from this list is
# assumed reachable, which is the safe direction: a new operation blocks until
# someone states otherwise, rather than being silently exempt.
AUTHORING_ONLY_OPS=(create_item update_item)

for role in "${PROVIDER_ROLES[@]}"; do
  role_path "$role"
  path="$MATCH_PATH"
  unsupported_line="$(grep -m1 -E '^unsupported: \[' "$path")"
  unsupported_content="$(printf '%s' "$unsupported_line" | sed -E 's/^unsupported: \[(.*)\]$/\1/')"
  unsupported_trimmed="${unsupported_content//[[:space:]]/}"

  blocking=""
  IFS=',' read -r -a declared <<< "$unsupported_trimmed"
  for op in "${declared[@]:-}"; do
    [[ -z "$op" ]] && continue
    reachable=1
    for exempt in "${AUTHORING_ONLY_OPS[@]}"; do
      [[ "$op" == "$exempt" ]] && reachable=0
    done
    if [[ "$reachable" -eq 1 ]]; then
      [[ -n "$blocking" ]] && blocking+=","
      blocking+="$op"
    fi
  done

  if [[ -n "$blocking" ]]; then
    fail "role '$role' cannot perform operation(s) '$blocking' — declared unsupported by $path"
  fi
done

# --- check 3: onboarding gate, when the platform pack declares it (D80) ----
GATE_OUT="$("$CHECK_ONBOARDING" "$PLATFORM_PATH" 2>&1)"
GATE_STATUS=$?
if [[ $GATE_STATUS -eq 1 ]]; then
  fail "${GATE_OUT#invalid: }"
elif [[ $GATE_STATUS -ne 0 ]]; then
  fail "onboarding gate could not run — ${GATE_OUT}"
fi

# --- check 4: the serve notice, when the platform pack declares that stage -
# This check has no failing verdict — it reports, it never blocks. A
# non-zero exit is therefore not a verdict about the project but a fault in
# a check whose two inputs this script has already validated, and it is
# reported as one.
SERVE_OUT="$("$CHECK_SERVE_NOTICE" "$CONFIG" "$PLATFORM_PATH" 2>&1)"
SERVE_STATUS=$?
if [[ $SERVE_STATUS -ne 0 ]]; then
  fail "serve notice could not run — ${SERVE_OUT}"
fi

# --- ready -------------------------------------------------------------
echo "ready"
echo "platform: ok"
echo "tracker: ok"
echo "scm: ok"
if [[ "$CONFIG_DESIGN" == "none" ]]; then
  echo "design: none"
else
  echo "design: ok"
fi
echo "browser: ok"
if [[ "$GATE_OUT" != "not-gated" ]]; then
  echo "$GATE_OUT"
fi
if [[ "$SERVE_OUT" != "not-declared" ]]; then
  echo "$SERVE_OUT"
fi
exit 0
