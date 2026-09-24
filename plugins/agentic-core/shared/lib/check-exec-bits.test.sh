#!/usr/bin/env bash
# Tests for check-exec-bits.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-exec-bits.test.sh
#
# No framework — exits 0 on success, 1 if any case fails.
#
# The rule under test: a script a skill invokes as a plain command must be
# executable, because the caller has no way to recover when it is not. A script
# invoked through an interpreter does not need the bit and is not required to
# have one — the checker must tell those two apart, or it becomes noise nobody
# reads.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-exec-bits.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-exec-bits.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# fixture <name> <invocation line> <script-is-executable yes|no> -- echoes the plugins dir
fixture() {
  local name="$1" line="$2" exec_bit="$3"
  local root="$WORK/$name"
  mkdir -p "$root/mypack/skills/mystage" "$root/mypack/shared/lib" "$root/otherpack/shared/lib"
  printf '#!/usr/bin/env bash\ntrue\n' > "$root/mypack/shared/lib/thing.sh"
  printf '#!/usr/bin/env bash\ntrue\n' > "$root/otherpack/shared/lib/sibling.sh"
  [ "$exec_bit" = yes ] && chmod +x "$root/mypack/shared/lib/thing.sh" "$root/otherpack/shared/lib/sibling.sh"
  printf -- '---\ndescription: x\n---\n\n# mystage\n\nRun:\n\n```\n%s\n```\n' "$line" \
    > "$root/mypack/skills/mystage/SKILL.md"
  echo "$root"
}

run_check() { OUT="$(bash "$CHECK" "$1" 2>&1)"; ST=$?; }

echo "=== check-exec-bits.sh tests ==="

echo "[catches] a plain invocation of a script without the bit"
run_check "$(fixture plain-noexec '${CLAUDE_PLUGIN_ROOT}/shared/lib/thing.sh .ai/x.txt' no)"
[[ "$ST" == 1 && "$OUT" == *"thing.sh"* ]] && ok "plain invocation, no exec bit -> invalid, names the script" \
  || bad "plain invocation, no exec bit -> invalid, names the script" "exit $ST" "$OUT"
[[ "$OUT" == *"mystage"* ]] && ok "the failure names the skill that invokes it" \
  || bad "the failure names the skill that invokes it" "$OUT"

echo "[allows] the same script once it is executable"
run_check "$(fixture plain-exec '${CLAUDE_PLUGIN_ROOT}/shared/lib/thing.sh .ai/x.txt' yes)"
[[ "$ST" == 0 ]] && ok "plain invocation, exec bit present -> valid" || bad "plain invocation, exec bit present -> valid" "exit $ST" "$OUT"

echo "[ignores] an invocation through an interpreter, which needs no bit"
run_check "$(fixture via-bash 'bash ${CLAUDE_PLUGIN_ROOT}/shared/lib/thing.sh .ai/x.txt' no)"
[[ "$ST" == 0 ]] && ok "'bash <script>' with no exec bit -> valid, not a finding" || bad "'bash <script>' with no exec bit -> valid, not a finding" "exit $ST" "$OUT"

echo "[resolves] a sibling pack's path through ../"
run_check "$(fixture sibling '${CLAUDE_PLUGIN_ROOT}/../otherpack/shared/lib/sibling.sh' no)"
[[ "$ST" == 1 && "$OUT" == *"sibling.sh"* ]] && ok "'../<pack>/' resolves to the sibling pack and is checked" \
  || bad "'../<pack>/' resolves to the sibling pack and is checked" "exit $ST" "$OUT"

echo "[quiet] a path that resolves to nothing is not reported"
run_check "$(fixture missing '${CLAUDE_PLUGIN_ROOT}/shared/lib/not-here.sh' no)"
[[ "$ST" == 0 ]] && ok "a script that does not exist is not a missing exec bit" || bad "a script that does not exist is not a missing exec bit" "exit $ST" "$OUT"

echo "[errors]"
bash "$CHECK" >/dev/null 2>&1; ST=$?
[[ "$ST" == 2 ]] && ok "no argument -> exit 2" || bad "no argument -> exit 2" "got $ST"
bash "$CHECK" "$WORK/nope" >/dev/null 2>&1; ST=$?
[[ "$ST" == 2 ]] && ok "a directory that does not exist -> exit 2" || bad "a directory that does not exist -> exit 2" "got $ST"

echo "[shipped] this repository's own plugins pass"
REAL="$SCRIPT_DIR/../../.."
run_check "$REAL"
[[ "$ST" == 0 ]] && ok "plugins/ passes ($OUT)" || bad "plugins/ passes" "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
