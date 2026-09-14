#!/usr/bin/env bash
# check-onboarding-gate.sh — Pre-flight's third check (see shared/pre-flight.md,
# shared/pack-manifest.md §"onboarding_state_path"/"audit_findings_path",
# core contract §6.3, D80, closing G63). No model, no side effects, no live
# calls: reads the platform pack's own manifest for two optional declared
# paths and tests each for existence against the project's own working
# tree — never a running process, never the network.
#
# A platform pack may declare, in its manifest:
#   onboarding_state_path: "<relative path>"  # presence marks onboarding complete
#   audit_findings_path:   "<relative path>"  # findings, shared/audit-taxonomy.md's shape
#
# Neither key is required. A pack declaring neither runs this check as a
# no-op. Each declared path is resolved relative to the current working
# directory — the project root, by the same convention every other
# project-relative path in this system already uses (run from the project
# root, the same way check-preflight.sh's own caller does).
#
# Two checks, deliberately different (D80):
#   (a) onboarding_state_path declared but absent -> warn, never block. The
#       project has not completed onboarding; every design value a later
#       stage reads is a guess.
#   (b) audit_findings_path declared and present, and it carries an open
#       "severity: poisoning" finding -> block. Declared but absent (no
#       audit has run yet), or present with no poisoning finding -> pass. A
#       "cosmetic" finding never blocks.
#
# Usage:
#   check-onboarding-gate.sh <path-to-platform-pack.yaml>
#
# Exit codes:
#   0 — "not-gated" (neither key declared), or one line per declared key:
#       "onboarding: ok" / "onboarding: warn — <reason>", and
#       "audit: ok" / "audit: ok — no audit yet at '<path>'"
#   1 — "invalid: <reason>" on stderr, naming the open poisoning finding and
#       the file it names
#   2 — usage error (no argument, file not found)

set -uo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
  echo "usage: check-onboarding-gate.sh <path-to-platform-pack.yaml>" >&2
  exit 2
fi

if [[ ! -f "$FILE" ]]; then
  echo "invalid: file not found: $FILE" >&2
  exit 2
fi

fail() {
  echo "invalid: $1" >&2
  exit 1
}

ONBOARDING_PATH="$(grep -m1 -E '^onboarding_state_path: "(.*)"$' "$FILE" \
  | sed -E 's/^onboarding_state_path: "(.*)"$/\1/')"
AUDIT_PATH="$(grep -m1 -E '^audit_findings_path: "(.*)"$' "$FILE" \
  | sed -E 's/^audit_findings_path: "(.*)"$/\1/')"

if [[ -z "$ONBOARDING_PATH" && -z "$AUDIT_PATH" ]]; then
  echo "not-gated"
  exit 0
fi

# --- check (a): onboarding-state path -----------------------------------
if [[ -n "$ONBOARDING_PATH" ]]; then
  if [[ -f "$ONBOARDING_PATH" ]]; then
    echo "onboarding: ok"
  else
    echo "onboarding: warn — no onboarding-state file at '$ONBOARDING_PATH'; this project has not completed design-system onboarding, so confidence is capped low"
  fi
fi

# --- check (b): audit-findings path --------------------------------------
if [[ -n "$AUDIT_PATH" ]]; then
  if [[ ! -f "$AUDIT_PATH" ]]; then
    echo "audit: ok — no audit yet at '$AUDIT_PATH'"
  else
    # Findings are a flat list, shared/audit-taxonomy.md's shape: each entry
    # begins "- id: ..." at column 0; every other field of that entry is
    # indented under it. A block boundary is the next "- id:" line (or end
    # of file) — walking this way never mistakes a "diff:" block's own
    # content for a field, since diff content is indented further still and
    # never starts a line at column 0.
    LINES=()
    while IFS= read -r line || [[ -n "$line" ]]; do
      LINES+=("$line")
    done < "$AUDIT_PATH"
    n=${#LINES[@]}

    CUR_ID="" CUR_FILE="" CUR_FINDING="" CUR_SEVERITY=""
    POISON_ID="" POISON_FILE="" POISON_FINDING=""

    flush() {
      if [[ "$CUR_SEVERITY" == "poisoning" && -z "$POISON_ID" ]]; then
        POISON_ID="$CUR_ID"
        POISON_FILE="$CUR_FILE"
        POISON_FINDING="$CUR_FINDING"
      fi
    }

    for ((i = 0; i < n; i++)); do
      line="${LINES[$i]}"
      if [[ "$line" =~ ^-\ id:\ \"(.*)\"$ ]]; then
        flush
        CUR_ID="${BASH_REMATCH[1]}"
        CUR_FILE=""
        CUR_FINDING=""
        CUR_SEVERITY=""
        continue
      fi
      [[ "$line" =~ ^\ \ severity:\ (poisoning|cosmetic)$ ]] && CUR_SEVERITY="${BASH_REMATCH[1]}"
      [[ "$line" =~ ^\ \ file:\ \"(.*)\"$ ]] && CUR_FILE="${BASH_REMATCH[1]}"
      [[ "$line" =~ ^\ \ finding:\ \"(.*)\"$ ]] && CUR_FINDING="${BASH_REMATCH[1]}"
    done
    flush

    if [[ -n "$POISON_ID" ]]; then
      fail "an open poisoning finding at '$AUDIT_PATH' ($POISON_ID: $POISON_FINDING — file: $POISON_FILE) must be resolved through this project's own onboarding-completion flow before this run can proceed"
    fi
    echo "audit: ok"
  fi
fi

exit 0
