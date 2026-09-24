#!/usr/bin/env bash
# Tests for instructions-stamp.sh. Run with:
#   bash plugins/agentic-core/shared/lib/instructions-stamp.test.sh
#
# No framework — exits 0 on success, 1 if any case fails.
#
# The property under test is that the stamp tracks the file's content and
# nothing else. A caller holding an older copy of the same file carries an
# older stamp, so comparing what this prints against what the caller carries
# is what tells the two apart. Every case below exists to make sure that
# comparison cannot come out equal when the content differs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$SCRIPT_DIR/instructions-stamp.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/instructions-stamp.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

N=0
mkfile() {
  N=$((N + 1))
  local f="$WORK/f-$N.md"
  printf '%s\n' "$1" > "$f"
  echo "$f"
}

BODY='---
description: a driver
---

# driver

Do the first thing.

## Node

Do the second thing.'

echo "=== instructions-stamp.sh tests ==="

echo "[write] a file with no stamp gets one"
F="$(mkfile "$BODY")"
bash "$STAMP" --write "$F" >/dev/null 2>&1; S=$?
LINES="$(grep -c 'instructions-stamp:' "$F")"
[[ "$S" == 0 && "$LINES" == 1 ]] && ok "a stamp line is added, exactly one" || bad "a stamp line is added, exactly one" "exit $S, $LINES stamp lines"

echo "[verify] a stamped file verifies and prints its stamp"
OUT="$(bash "$STAMP" "$F" 2>&1)"; S=$?
[[ "$S" == 0 && "$OUT" == stamp:* ]] && ok "verifies, prints 'stamp: <value>'" || bad "verifies, prints 'stamp: <value>'" "exit $S" "out: $OUT"
STAMP_A="$OUT"

echo "[idempotent] writing twice changes nothing"
BEFORE="$(cat "$F")"
bash "$STAMP" --write "$F" >/dev/null 2>&1
[[ "$(cat "$F")" == "$BEFORE" ]] && ok "a second --write is a no-op" || bad "a second --write is a no-op"

echo "[detects] content changed without regenerating the stamp"
printf 'A step somebody added later.\n' >> "$F"
OUT="$(bash "$STAMP" "$F" 2>&1)"; S=$?
[[ "$S" == 1 ]] && ok "edited content, stale stamp -> exit 1" || bad "edited content, stale stamp -> exit 1" "exit $S" "out: $OUT"
[[ "$OUT" == *"--write"* ]] && ok "the failure names how to regenerate it" || bad "the failure names how to regenerate it" "out: $OUT"

echo "[changes] a different file body yields a different stamp"
bash "$STAMP" --write "$F" >/dev/null 2>&1
STAMP_B="$(bash "$STAMP" "$F" 2>&1)"
[[ "$STAMP_A" != "$STAMP_B" ]] && ok "the stamp changed when the body changed" || bad "the stamp changed when the body changed" "both: $STAMP_A"

echo "[stable] the same body yields the same stamp in a different file"
G="$(mkfile "$BODY")"
bash "$STAMP" --write "$G" >/dev/null 2>&1
H="$(mkfile "$BODY")"
bash "$STAMP" --write "$H" >/dev/null 2>&1
[[ "$(bash "$STAMP" "$G")" == "$(bash "$STAMP" "$H")" ]] && ok "identical bodies stamp identically" || bad "identical bodies stamp identically"

echo "[excludes itself] the stamp does not cover the stamp line"
# Two files identical but for their stamp values must still verify, because
# the value is computed over the content with that line removed.
I="$(mkfile "$BODY")"
bash "$STAMP" --write "$I" >/dev/null 2>&1
sed -i.bak 's/instructions-stamp: .*/instructions-stamp: deadbeefdead -->/' "$I" && rm -f "$I.bak"
OUT="$(bash "$STAMP" "$I" 2>&1)"; S=$?
[[ "$S" == 1 ]] && ok "a tampered stamp value is caught" || bad "a tampered stamp value is caught" "exit $S" "out: $OUT"

echo "[errors]"
OUT="$(bash "$STAMP" "$WORK/nope.md" 2>&1)"; S=$?
[[ "$S" == 2 ]] && ok "missing file -> exit 2" || bad "missing file -> exit 2" "exit $S"
bash "$STAMP" >/dev/null 2>&1; S=$?
[[ "$S" == 2 ]] && ok "no argument -> exit 2" || bad "no argument -> exit 2" "exit $S"
J="$(mkfile "$BODY")"
OUT="$(bash "$STAMP" "$J" 2>&1)"; S=$?
[[ "$S" == 1 && "$OUT" == *"--write"* ]] && ok "no stamp line at all -> exit 1, names --write" || bad "no stamp line at all -> exit 1, names --write" "exit $S" "out: $OUT"

echo "[shipped] the driver's own instructions carry a current stamp"
# This is the regression guard, not a unit case: editing run-route/SKILL.md
# without regenerating its stamp makes every run refuse to start, and this is
# where that is caught instead -- before the edit is merged.
DRIVER="$SCRIPT_DIR/../../skills/run-route/SKILL.md"
if [[ -f "$DRIVER" ]]; then
  OUT="$(bash "$STAMP" "$DRIVER" 2>&1)"; S=$?
  [[ "$S" == 0 ]] && ok "run-route/SKILL.md verifies (${OUT})" \
    || bad "run-route/SKILL.md verifies" "$OUT" "regenerate with: bash ${STAMP##*/} --write <that file>"
else
  bad "run-route/SKILL.md verifies" "not found at $DRIVER"
fi

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
