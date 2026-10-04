#!/usr/bin/env bash
# Tests that every operation skill in this pack runs its browser script with
# the command sandbox off. Run with:
#   bash plugins/playwright/scripts/skill-grants.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise.
#
# The browser process does not launch inside the default command sandbox: the
# launch fails before any page is loaded, and the operation returns `fail`
# with a summary that is not about the target. The grant therefore belongs to
# the operation, which knows its script launches a browser, not to each
# caller. This suite reads each skill's run step and refuses one that leaves
# the grant out.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/../skills"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

for op in render capture measure interact; do
  file="$SKILLS_DIR/$op/SKILL.md"
  if [[ ! -f "$file" ]]; then
    bad "$op: SKILL.md exists" "missing: $file"
    continue
  fi
  # the run step: the numbered line that names the operation's own script, plus
  # its continuation lines up to the next numbered step
  step="$(awk -v s="scripts/$op.cjs" '
    /^[0-9]+\. / { if (on) exit; on = index($0, s) > 0 }
    on { print }
  ' "$file")"
  if [[ -z "$step" ]]; then
    bad "$op: a numbered step runs scripts/$op.cjs"
    continue
  fi
  ok "$op: a numbered step runs scripts/$op.cjs"
  if [[ "$step" == *'`dangerouslyDisableSandbox: true`'* ]]; then
    ok "$op: that step runs the script with the sandbox off"
  else
    bad "$op: that step runs the script with the sandbox off" "step: $(echo "$step" | head -3)"
  fi
done

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
