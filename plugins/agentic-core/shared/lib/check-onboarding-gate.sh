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
#   audit_digest_path:     "<relative path>"  # sha256 of each file the audit judged
#
# No key is required. A pack declaring none runs this check as a
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
#   (c) audit_digest_path declared and present, and any file it lists no
#       longer hashes to the recorded value -> warn, never block (G500).
#       The audit's own verdict is only as current as the files it read; a
#       clean findings list says nothing about a file edited afterwards.
#       The core never learns what any listed path means -- it reads the
#       paths out of the digest the pack wrote (D28, D80's shape).
#
# Check (b) runs before (c) on purpose: an open poisoning finding is a
# block and ends the run, so a freshness warning about the same project is
# never reached.
#
# Usage:
#   check-onboarding-gate.sh <path-to-platform-pack.yaml>
#
# Exit codes:
#   0 — "not-gated" (no key declared), or one line per declared key:
#       "onboarding: ok" / "onboarding: warn — <reason>",
#       "audit: ok" / "audit: ok — no audit yet at '<path>'", and
#       "audit-digest: ok" / "audit-digest: ok — no digest yet at '<path>'"
#       / "audit-digest: warn — <path> has changed ..."
#   1 — "invalid: <reason>" on stderr, naming the open poisoning finding and
#       the file it names, or the digest list the gate could not read
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

# Verify a digest list with whichever checker this machine has. Both print
# "<path>: FAILED" for a file whose content moved, which is what check (c)
# parses; they differ only in name and flag spelling.
sha_verify() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "$1"
  else
    shasum -a 256 -c "$1"
  fi
}

ONBOARDING_PATH="$(grep -m1 -E '^onboarding_state_path: "(.*)"$' "$FILE" \
  | sed -E 's/^onboarding_state_path: "(.*)"$/\1/')"
AUDIT_PATH="$(grep -m1 -E '^audit_findings_path: "(.*)"$' "$FILE" \
  | sed -E 's/^audit_findings_path: "(.*)"$/\1/')"

DIGEST_PATH="$(grep -m1 -E '^audit_digest_path: "(.*)"$' "$FILE" \
  | sed -E 's/^audit_digest_path: "(.*)"$/\1/')"

if [[ -z "$ONBOARDING_PATH" && -z "$AUDIT_PATH" && -z "$DIGEST_PATH" ]]; then
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

# --- check (c): audit digest, when declared (G500) ------------------------
if [[ -n "$DIGEST_PATH" ]]; then
  if [[ ! -f "$DIGEST_PATH" ]]; then
    echo "audit-digest: ok — no digest yet at '$DIGEST_PATH'"
  else
    # Shape first, decided here rather than inherited: the two system
    # checkers disagree on a malformed list — GNU sha256sum -c warns and
    # exits 0, shasum -a 256 -c exits 1 — so a gate that trusted the exit
    # code alone would pass or fail by which binary is installed.
    DIGEST_LINE_RE='^[0-9a-f]{64}  .+$'
    DIGEST_LINES=0
    DIGEST_SHAPE_OK=1
    DIGEST_MISSING=""
    while IFS= read -r dline || [[ -n "$dline" ]]; do
      [[ -z "$dline" ]] && continue
      if [[ "$dline" =~ $DIGEST_LINE_RE ]]; then
        DIGEST_LINES=$((DIGEST_LINES + 1))
        # A listed file that has gone is decided here too, not by the
        # checker: shasum reports it as a "FAILED open or read" line, GNU
        # sha256sum only on stderr, so neither text is portable to parse.
        [[ -z "$DIGEST_MISSING" && ! -r "${dline:66}" ]] && DIGEST_MISSING="${dline:66}"
      else
        DIGEST_SHAPE_OK=0
        break
      fi
    done < "$DIGEST_PATH"

    if [[ "$DIGEST_SHAPE_OK" -eq 0 || "$DIGEST_LINES" -eq 0 ]]; then
      fail "the audit digest at '$DIGEST_PATH' is not a digest list — expected one '<sha256>  <path>' line per file the audit judged, and at least one line"
    fi

    if [[ -n "$DIGEST_MISSING" ]]; then
      echo "audit-digest: warn — '$DIGEST_MISSING' is named by the audit digest '$DIGEST_PATH' but is no longer readable, so that audit's verdict cannot be checked against it; re-run this project's own audit, confidence is capped low"
    elif DIGEST_OUT="$(sha_verify "$DIGEST_PATH" 2>&1)"; then
      echo "audit-digest: ok"
    else
      CHANGED="$(printf '%s\n' "$DIGEST_OUT" | grep -m1 ': FAILED' | sed 's/: FAILED.*//')"
      if [[ -n "$CHANGED" ]]; then
        echo "audit-digest: warn — '$CHANGED' has changed since the audit recorded in '$DIGEST_PATH', so that audit's verdict no longer describes it; re-run this project's own audit, confidence is capped low"
      else
        fail "the audit digest at '$DIGEST_PATH' could not be verified — $DIGEST_OUT"
      fi
    fi
  fi
fi

exit 0
