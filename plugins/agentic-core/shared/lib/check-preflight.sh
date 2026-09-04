#!/usr/bin/env bash
# check-preflight.sh — Deterministic capability probe (see shared/pre-flight.md,
# core contract §6/§10). No model, no side effects, no live calls: every check
# reads a pack.yaml or the project config — the same files
# validate-pack-manifest.sh and validate-project-config.sh already validate —
# never a runtime health check against a live tool or process.
#
# Two checks, in order:
#   1. every role the project config requires (packs.platform/tracker/scm/
#      browser always, packs.design only when it is not "none") has a
#      role=path argument naming a pack.yaml that validates as the right
#      kind for that role.
#   2. every declared role operation is available: every stage id named in
#      any configured route resolves in the platform pack's stages map (the
#      route a work item will actually take is not known this early — this
#      runs before intake, which is what resolves it — so every route in
#      config is checked, not only the one that eventually fires), and every
#      operation core contract §6 declares for a configured provider role is
#      implemented rather than declared unsupported.
#
# Usage:
#   check-preflight.sh <project-config path> <role>=<path-to-pack.yaml> [...]
#
# role is one of: platform tracker scm design browser
#
# Exit codes:
#   0 — "ready", then one "<role>: ok" line per role checked ("design: none"
#       when config requires no design pack)
#   1 — "invalid: <reason>" on stderr, naming the first missing pack, role
#       mismatch, unresolvable stage or unavailable operation
#   2 — usage error: no config argument, config not found, a malformed
#       role=path pair, an unrecognized role name

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_CONFIG="$SCRIPT_DIR/validate-project-config.sh"
VALIDATE_MANIFEST="$SCRIPT_DIR/validate-pack-manifest.sh"

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

# --- check 2a: every route's stages resolve in the platform manifest --------
extract_platform_stages() {
  awk '
    /^stages:$/ { grabbing=1; next }
    grabbing && /^[A-Za-z_]/ { exit }
    grabbing && /^  [A-Za-z0-9_-]+:/ {
      line=$0
      sub(/^  /, "", line)
      sub(/:.*/, "", line)
      print line
    }
  ' "$1"
}

PLATFORM_STAGES=()
while IFS= read -r stage_id; do
  [[ -n "$stage_id" ]] && PLATFORM_STAGES+=("$stage_id")
done < <(extract_platform_stages "$PLATFORM_PATH")

stage_known() {
  local id="$1"
  for existing in "${PLATFORM_STAGES[@]}"; do
    [[ "$existing" == "$id" ]] && return 0
  done
  return 1
}

extract_route_stage_refs() {
  awk '
    /^  - id: / { route=$0; sub(/^  - id: /, "", route); next }
    /^    stages: \[/ {
      line=$0
      sub(/^    stages: \[/, "", line)
      sub(/\]$/, "", line)
      n = split(line, ids, ",")
      for (i = 1; i <= n; i++) {
        s = ids[i]
        gsub(/^[ \t]+|[ \t]+$/, "", s)
        if (s != "") print route " " s
      }
    }
  ' "$1"
}

while IFS=' ' read -r route_id stage_id; do
  [[ -z "$stage_id" ]] && continue
  stage_known "$stage_id" \
    || fail "route '$route_id' uses stage '$stage_id' with no entry in the platform pack's stages map"
done < <(extract_route_stage_refs "$CONFIG")

# --- check 2b: every configured role's operations are all implemented ------
for role in "${PROVIDER_ROLES[@]}"; do
  role_path "$role"
  path="$MATCH_PATH"
  unsupported_line="$(grep -m1 -E '^unsupported: \[' "$path")"
  unsupported_content="$(printf '%s' "$unsupported_line" | sed -E 's/^unsupported: \[(.*)\]$/\1/')"
  unsupported_trimmed="${unsupported_content//[[:space:]]/}"
  if [[ -n "$unsupported_trimmed" ]]; then
    fail "role '$role' cannot perform operation(s) '$unsupported_trimmed' — declared unsupported by $path"
  fi
done

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
exit 0
