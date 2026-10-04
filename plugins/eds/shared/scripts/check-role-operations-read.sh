#!/usr/bin/env bash
# check-role-operations-read.sh — every stage that calls another pack's role
# operation reads the core's role-operations contract as a numbered step of its
# own, rather than only naming it.
#
# Usage:
#   check-role-operations-read.sh <skills dir>
#
# A SKILL.md under <skills dir> that names role-operations.md must carry a
# numbered list line that tells the stage to Read that file. Prints
# `valid: role-operations read (<n> stages)` and exits 0, or one
# `missing: <skill>` line per stage without the step and
# `invalid: <n> stage(s) name role-operations.md without reading it`, exit 1.
# Exit 2 on a usage error.

set -uo pipefail

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
  echo "usage: check-role-operations-read.sh <skills dir>" >&2
  exit 2
fi

checked=0
missing=0
for f in "$1"/*/SKILL.md; do
  [ -f "$f" ] || continue
  grep -qF 'role-operations.md' "$f" || continue
  checked=$((checked + 1))
  if ! grep -qE '^[[:space:]]*[0-9]+\. Read `[^`]*role-operations\.md`' "$f"; then
    echo "missing: $(basename "$(dirname "$f")")"
    missing=$((missing + 1))
  fi
done

if [ "$missing" -gt 0 ]; then
  echo "invalid: $missing stage(s) name role-operations.md without reading it"
  exit 1
fi
echo "valid: role-operations read ($checked stages)"
