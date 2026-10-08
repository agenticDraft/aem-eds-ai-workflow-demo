#!/usr/bin/env bash
# Tests for check-status.sh. Run with:
#   bash plugins/github/skills/check-status/scripts/check-status.test.sh
#
# No framework — exits 0 on success, 1 if any case fails.
#
# Nothing here touches GitHub. `gh` is stubbed: it answers `pr list` from
# `$GH_STUB/list-<branch>.json` and `pr checks <n>` from
# `$GH_STUB/checks-<n>.json`, and fails when the file it needs is absent.
#
# The case that matters is D534's reject rule: a merged or closed change must
# never come back as `none`. The script used to look up only open changes,
# so every merged change read as "no pull request found".

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-status.sh"
VALIDATE="$SCRIPT_DIR/../../../core/lib/validate-result-envelope.sh"

if [[ -z "${TMPDIR:-}" ]]; then
  echo "TMPDIR is empty; refusing to create test directories elsewhere" >&2
  exit 1
fi
WORK="$(mktemp -d "$TMPDIR/check-status.XXXXXX")"
if [[ -z "$WORK" || ! -d "$WORK" ]]; then
  echo "mktemp -d failed" >&2
  exit 1
fi
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

export GH_STUB="$WORK/stub"
mkdir -p "$WORK/bin" "$GH_STUB" "$WORK/project"
cat > "$WORK/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$GH_STUB/calls.log"
case "${1:-} ${2:-}" in
  "auth status") [[ -f "$GH_STUB/no-auth" ]] && exit 1; exit 0 ;;
  "pr list")
    head=""
    while [[ $# -gt 0 ]]; do [[ "$1" == "--head" ]] && head="$2"; shift; done
    f="$GH_STUB/list-${head}.json"
    [[ -f "$f" ]] || { echo "stub: no list fixture for $head" >&2; exit 1; }
    cat "$f" ;;
  "pr checks")
    f="$GH_STUB/checks-${3:-}.json"
    [[ -f "$f" ]] || { echo "stub: no checks for ${3:-}" >&2; exit 1; }
    cat "$f" ;;
  *) exit 1 ;;
esac
GH
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

TWO_CHECKS='[{"name":"build","state":"SUCCESS","bucket":"pass","link":"x"},{"name":"lint","state":"FAILURE","bucket":"fail","link":"y"}]'

# run <branch> — runs the script from the scratch project; sets OUT and ST, and
# writes OUT to $ENV_FILE so the real validator can read it.
ENV_FILE="$WORK/envelope.txt"
run() {
  OUT="$(cd "$WORK/project" && bash "$SCRIPT" "$1" 2>/dev/null)"; ST=$?
  printf '%s\n' "$OUT" > "$ENV_FILE"
}

has()    { [[ "$OUT" == *"$2"* ]] && ok "$1" || bad "$1" "expected to contain: $2" "got:" "$OUT"; }
hasnt()  { [[ "$OUT" != *"$2"* ]] && ok "$1" || bad "$1" "expected NOT to contain: $2" "got:" "$OUT"; }
exit0()  { [[ "$ST" == 0 ]] && ok "$1" || bad "$1" "exit $ST"; }
valid()  { bash "$VALIDATE" "$ENV_FILE" >/dev/null 2>&1 && ok "$1" || bad "$1" "$(bash "$VALIDATE" "$ENV_FILE" 2>&1)"; }

echo "=== check-status.sh tests ==="

echo "[open] an open change reports its state and its checks"
echo '[{"number":11,"state":"OPEN"}]' > "$GH_STUB/list-feature-open.json"
echo "$TWO_CHECKS" > "$GH_STUB/checks-11.json"
run feature-open
exit0 "exit 0"
has "verdict pass" "verdict: pass"
has "change_state open" "change_state: open"
has "checks counted in the summary" "1 pass, 1 fail"
has "metrics carry the per-bucket counts" "metrics: total=2 pass=1 fail=1"
has "checks JSON named as an artifact" "  - .ai/scm/check-status-feature-open.json"
[[ -s "$WORK/project/.ai/scm/check-status-feature-open.json" ]] && ok "checks JSON written" || bad "checks JSON written"
valid "envelope validates"

echo "[merged] a merged change reports merged, never none"
echo '[{"number":12,"state":"MERGED"}]' > "$GH_STUB/list-feature-merged.json"
echo "$TWO_CHECKS" > "$GH_STUB/checks-12.json"
run feature-merged
exit0 "exit 0"
has "change_state merged" "change_state: merged"
hasnt "not reported as none" "change_state: none"
has "checks still reported" "metrics: total=2"
valid "envelope validates"

echo "[closed] a closed change reports closed, never none"
echo '[{"number":13,"state":"CLOSED"}]' > "$GH_STUB/list-feature-closed.json"
echo '[]' > "$GH_STUB/checks-13.json"
run feature-closed
exit0 "exit 0"
has "change_state closed" "change_state: closed"
hasnt "not reported as none" "change_state: none"
has "no checks configured is still a read" "no checks configured"
valid "envelope validates"

echo "[none] a branch with no change reports none, no checks, exit 0"
echo '[]' > "$GH_STUB/list-feature-none.json"
: > "$GH_STUB/calls.log"
run feature-none
exit0 "exit 0"
has "verdict pass — no change is not a failure" "verdict: pass"
has "change_state none" "change_state: none"
has "no artifacts" "artifacts: []"
hasnt "no metrics line" "metrics:"
grep -q "^pr checks" "$GH_STUB/calls.log" && bad "checks are not asked for" "$(cat "$GH_STUB/calls.log")" || ok "checks are not asked for"
[[ ! -e "$WORK/project/.ai/scm/check-status-feature-none.json" ]] && ok "no checks JSON written" || bad "no checks JSON written"
valid "envelope validates"

echo "[lookup] every state is asked for, by exact head branch"
: > "$GH_STUB/calls.log"
run feature-merged
grep -q -- "pr list --head feature-merged --state all" "$GH_STUB/calls.log" \
  && ok "pr list --head <branch> --state all" || bad "pr list --head <branch> --state all" "$(cat "$GH_STUB/calls.log")"

echo "[several] an open change wins over earlier closed or merged ones"
echo '[{"number":21,"state":"CLOSED"},{"number":25,"state":"OPEN"},{"number":22,"state":"MERGED"}]' > "$GH_STUB/list-feature-reused.json"
echo "$TWO_CHECKS" > "$GH_STUB/checks-25.json"
: > "$GH_STUB/calls.log"
run feature-reused
has "change_state open" "change_state: open"
grep -q "^pr checks 25 " "$GH_STUB/calls.log" && ok "checks read from the open change" || bad "checks read from the open change" "$(cat "$GH_STUB/calls.log")"

echo "[several] with none open, the newest change's state is reported"
echo '[{"number":31,"state":"MERGED"},{"number":34,"state":"CLOSED"}]' > "$GH_STUB/list-feature-old.json"
echo '[]' > "$GH_STUB/checks-34.json"
: > "$GH_STUB/calls.log"
run feature-old
has "change_state closed (#34 is newer than #31)" "change_state: closed"
grep -q "^pr checks 34 " "$GH_STUB/calls.log" && ok "checks read from #34" || bad "checks read from #34" "$(cat "$GH_STUB/calls.log")"

echo "[unknown] a failed lookup is fail with no state — unknown is never none"
run feature-unlisted
exit0 "exit 0"
has "verdict fail" "verdict: fail"
hasnt "no change_state at all" "change_state:"
valid "envelope validates"

echo "[unknown] an unreadable lookup payload is fail with no state"
echo 'not json' > "$GH_STUB/list-feature-garbage.json"
run feature-garbage
has "verdict fail" "verdict: fail"
hasnt "no change_state at all" "change_state:"

echo "[checks] unreadable checks on an existing change: fail, state still reported"
echo '[{"number":41,"state":"MERGED"}]' > "$GH_STUB/list-feature-nochecks.json"
run feature-nochecks
has "verdict fail" "verdict: fail"
has "change_state merged still reported" "change_state: merged"
valid "envelope validates"

echo "[auth] gh not authenticated: fail, no state"
touch "$GH_STUB/no-auth"
run feature-open
has "verdict fail" "verdict: fail"
hasnt "no change_state at all" "change_state:"
rm -f "$GH_STUB/no-auth"

echo "[envelope] --envelope leaves the same block in the named file, for a caller that must not transcribe it"
ENV_OUT="$WORK/project/.ai/run-context/envelope-check-status.txt"
mkdir -p "$WORK/project/.ai/run-context"
rm -f "$ENV_OUT"
OUT="$(cd "$WORK/project" && bash "$SCRIPT" --envelope .ai/run-context/envelope-check-status.txt feature-merged 2>/dev/null)"; ST=$?
exit0 "exit 0"
[[ -s "$ENV_OUT" ]] && ok "the named file is written" || bad "the named file is written"
[[ "$(cat "$ENV_OUT")" == "$OUT" ]] && ok "the file holds exactly the block printed" || bad "the file holds exactly the block printed" "file: $(cat "$ENV_OUT")" "stdout: $OUT"
has "the file's block carries change_state merged" "change_state: merged"
bash "$VALIDATE" "$ENV_OUT" >/dev/null 2>&1 && ok "the file validates" || bad "the file validates" "$(bash "$VALIDATE" "$ENV_OUT" 2>&1)"
rm -f "$ENV_OUT"
OUT="$(cd "$WORK/project" && bash "$SCRIPT" --envelope .ai/run-context/envelope-check-status.txt feature-none 2>/dev/null)"; ST=$?
has "a none lookup is written too" "change_state: none"
[[ -s "$ENV_OUT" ]] && ok "the none envelope reaches the file" || bad "the none envelope reaches the file"
rm -f "$ENV_OUT"
touch "$GH_STUB/no-auth"
OUT="$(cd "$WORK/project" && bash "$SCRIPT" --envelope .ai/run-context/envelope-check-status.txt feature-open 2>/dev/null)"; ST=$?
rm -f "$GH_STUB/no-auth"
has "a failed lookup is written too, with no state" "verdict: fail"
grep -q 'change_state:' "$ENV_OUT" && bad "no change_state in the failed lookup's file" || ok "no change_state in the failed lookup's file"
(cd "$WORK/project" && bash "$SCRIPT" --envelope >/dev/null 2>&1); ST=$?
[[ "$ST" == 2 ]] && ok "--envelope without a value -> exit 2" || bad "--envelope without a value -> exit 2" "got $ST"

echo "[usage] no branch -> exit 2"
(cd "$WORK/project" && bash "$SCRIPT" >/dev/null 2>&1); ST=$?
[[ "$ST" == 2 ]] && ok "exit 2" || bad "exit 2" "got $ST"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
