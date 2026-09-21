#!/usr/bin/env bash
# check-requires.sh — Probe what a provider pack declared it needs present on
# this machine, and report. Reads the manifest's optional `requires:` key
# (see shared/pack-manifest.md): per entry a `tool`, a `probe` given as
# argv, and a `remedy`.
#
# This is the one place in the core that runs something to answer a question
# about the machine, and it is deliberately not the capability gate that runs
# before a route. That gate reads declarations only and never probes, because
# a false negative from a live probe would abort a run permanently, on
# conditions a pack author does not control. Here, a false negative costs a
# wrong line in a report that nothing acts on automatically.
#
# Read-only, in the strong sense: it runs each declared probe and nothing
# else. It never writes, never edits, never creates, and above all never
# installs. `remedy` is printed for a human to act on — it is never passed to
# a shell, because a component that could install its own dependency is a
# component that changes the machine it was asked only to inspect.
#
# The probe runs as argv, exactly as declared, with no shell between. Only
# its exit status is read: zero is present. Its output is discarded rather
# than parsed, and no version is compared — the manifest key cannot express a
# version requirement, so this cannot invent one.
#
# A pack that declares no `requires:` is a pack with no local precondition.
# That is reported as nothing to check, never as a failure.
#
# Usage:
#   check-requires.sh <path-to-pack.yaml>
#
# Exit codes:
#   0 — every declared tool is present, or none is declared; one
#       "ok: <tool>" line per entry, or "ok: no requirements declared"
#   1 — at least one declared tool is missing; one
#       "missing: <tool> — <remedy>" line per missing entry, on stderr,
#       then a count. Present tools still report their own "ok:" line.
#   2 — usage error: no argument, file not found, or a malformed `requires:`
#       block (validate-pack-manifest.sh is what explains the malformation;
#       this script only refuses to guess at it)

set -uo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
  echo "usage: check-requires.sh <path-to-pack.yaml>" >&2
  exit 2
fi

if [[ ! -f "$FILE" ]]; then
  echo "invalid: file not found: $FILE" >&2
  exit 2
fi

malformed() {
  echo "invalid: malformed 'requires:' block — $1" >&2
  exit 2
}

# Read the file the same way the manifest validator does: line at a time,
# blank lines and full-line comments dropped, for portability across
# installed shell versions.
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  LINES+=("$line")
done < "$FILE"
n=${#LINES[@]}

# Find the requires: block. It may sit anywhere among the manifest's keys;
# this script cares only about its own key, and leaves the ordering rules to
# the validator.
start=-1
for ((i = 0; i < n; i++)); do
  [[ "${LINES[i]}" == "requires:" ]] && { start=$i; break; }
done

if (( start < 0 )); then
  echo "ok: no requirements declared"
  exit 0
fi

MISSING=0
CHECKED=0
i=$((start + 1))

while (( i < n )); do
  [[ "${LINES[i]}" =~ ^\ \ -\ tool:\ (.+)$ ]] || break
  tool="${BASH_REMATCH[1]}"
  i=$((i + 1))

  [[ "${LINES[i]:-}" =~ ^\ \ \ \ probe:\ \[(.*)\]$ ]] \
    || malformed "'$tool' has no 'probe:' list"
  probe_raw="${BASH_REMATCH[1]}"
  i=$((i + 1))

  [[ "${LINES[i]:-}" =~ ^\ \ \ \ remedy:\ \"(.*)\"$ ]] \
    || malformed "'$tool' has no 'remedy:'"
  remedy="${BASH_REMATCH[1]}"
  i=$((i + 1))

  # Split the declared argv on commas and trim each argument. A probe is a
  # command and its flags, not a sentence, so this is the whole of the
  # quoting story — and it is why the key is a list rather than a string.
  ARGV=()
  IFS=',' read -ra RAW <<< "$probe_raw"
  for arg in "${RAW[@]:-}"; do
    arg="${arg#"${arg%%[![:space:]]*}"}"
    arg="${arg%"${arg##*[![:space:]]}"}"
    [[ -z "$arg" ]] && continue
    ARGV+=("$arg")
  done
  [[ ${#ARGV[@]} -eq 0 ]] && malformed "'$tool' declares an empty probe"

  CHECKED=$((CHECKED + 1))

  if "${ARGV[@]}" >/dev/null 2>&1; then
    echo "ok: $tool"
  else
    # The remedy is reproduced exactly as the pack declared it. Rewording it
    # here would put this script between a pack author and the person who
    # has to act on it, and only the pack author knows what its tool needs.
    echo "missing: $tool — $remedy" >&2
    MISSING=$((MISSING + 1))
  fi
done

if (( CHECKED == 0 )); then
  malformed "'requires:' declares no entries"
fi

if (( MISSING > 0 )); then
  echo "$MISSING of $CHECKED declared tools are missing; nothing was installed" >&2
  exit 1
fi

exit 0
