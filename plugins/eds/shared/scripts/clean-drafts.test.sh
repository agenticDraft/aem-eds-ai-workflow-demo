#!/usr/bin/env bash
# clean-drafts.test.sh — the draft cleanup, with the scm role's script
# stubbed. The stub answers from a per-case table; a fake `gh` first on PATH
# records any call, and the suite asserts it is never made.
#
# Usage:
#   bash clean-drafts.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEAN="$SCRIPT_DIR/clean-drafts.sh"

PASS=0
PLAIN=".plain.html"
FAIL=0

ok()   { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_file()    { if [ -e "$2" ]; then ok "$1"; else bad "$1" "missing: $2"; fi; }
assert_no_file() { if [ ! -e "$2" ]; then ok "$1"; else bad "$1" "still present: $2"; fi; }
assert_has()     { if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "expected to contain: $2 — got: $3"; fi; }
assert_eq()      { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2 — got: $3"; fi; }
assert_alive()   { if kill -0 "$2" 2>/dev/null; then ok "$1"; else bad "$1" "pid $2 is not running"; fi; }
assert_dead()    { if ! kill -0 "$2" 2>/dev/null; then ok "$1"; else bad "$1" "pid $2 is still running"; fi; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/clean-drafts.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
SERVER_PID=""
trap '[ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null; rm -rf "$WORK"' EXIT

# A fake gh that only records that it was called.
mkdir -p "$WORK/bin"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/gh-calls"\nexit 1\n' "$WORK" > "$WORK/bin/gh"
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

# The stubbed scm pack. Its check_status script answers from $WORK/states:
# one `<branch> <answer>` line per branch. Answers:
#   open|merged|closed|none   — a pass envelope carrying that state
#   fail-merged               — a fail envelope that still carries `merged`
#   unknown                   — a fail envelope with no change_state line
#   invalid                   — an envelope carrying an out-of-contract state
#   badverdict                — merged, in an envelope that does not validate
#   crash                     — no envelope, non-zero exit
PACK="$WORK/scm-pack"
mkdir -p "$PACK/skills/check-status/scripts"
cat > "$PACK/skills/check-status/scripts/check-status.sh" <<STUB
#!/usr/bin/env bash
echo "\$1" >> "$WORK/scm-calls"
answer=\$(awk -v b="\$1" '\$1 == b { print \$2 }' "$WORK/states")
env_pass() { printf '## Result\nverdict: pass\nsummary: Stubbed.\nartifacts: []\nnext_action: none\nchange_state: %s\n' "\$1"; }
case "\$answer" in
  open|merged|closed|none) env_pass "\$answer" ;;
  fail-merged) printf '## Result\nverdict: fail\nsummary: Checks unreadable.\nartifacts: []\nnext_action: none\nchange_state: merged\n' ;;
  invalid) env_pass "abandoned" ;;
  badverdict) printf '## Result\nverdict: done\nsummary: Stubbed.\nartifacts: []\nnext_action: none\nchange_state: merged\n' ;;
  crash) echo "boom" >&2; exit 3 ;;
  *) printf '## Result\nverdict: fail\nsummary: Lookup failed.\nartifacts: []\nnext_action: none\n' ;;
esac
STUB
chmod +x "$PACK/skills/check-status/scripts/check-status.sh"
write_manifest() {
  cat > "$PACK/pack.yaml" <<'EOF'
kind: provider
role: scm
operations:
  create_branch: create-branch
  publish_change: publish-change
  check_status: check-status
unsupported: []
EOF
  if [ "${1:-with}" = "with" ]; then
    printf 'scripts:\n  check_status: "skills/check-status/scripts/check-status.sh"\n' >> "$PACK/pack.yaml"
  fi
}

# fresh <states line>... — a clean project with records for every branch
# named in the states table, drafts EDS-18, EDS-7, EDS-99, columns-demo, an
# image, and a running fake draft server with its pid file.
PROJ="$WORK/project"
fresh() {
  rm -rf "$PROJ" "$WORK/scm-calls" "$WORK/gh-calls"
  mkdir -p "$PROJ/.ai/scm" "$PROJ/.ai/logs" "$PROJ/drafts"
  : > "$WORK/states"
  local line branch
  for line in "$@"; do
    echo "$line" >> "$WORK/states"
    branch="${line%% *}"
    echo '{"number":1,"state":"OPEN"}' > "$PROJ/.ai/scm/publish-change-${branch}.json"
  done
  for d in EDS-18 EDS-7 EDS-99 columns-demo; do
    echo "<div>$d</div>" > "$PROJ/drafts/$d.plain.html"
  done
  echo "png" > "$PROJ/drafts/eds-18-image.png"
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
  sleep 300 &
  SERVER_PID=$!
  disown "$SERVER_PID" 2>/dev/null
  echo "$SERVER_PID" > "$PROJ/.ai/logs/draft-server.pid"
  write_manifest with
}

run() { (cd "$PROJ" && bash "$CLEAN" "$@" 2>&1); }

echo "=== clean-drafts.sh tests ==="

echo "[usage] no argument"
OUT=$(bash "$CLEAN" 2>&1); ST=$?
assert_eq "exit 2" "2" "$ST"

echo "[merged] a merged record deletes only its own item's draft; an open record keeps its own and the server"
fresh "eds-18 merged" "eds-7 open"
OUT=$(run "$PACK"); ST=$?
assert_eq "exit 0" "0" "$ST"
assert_no_file "merged item's draft deleted" "$PROJ/drafts/EDS-18.plain.html"
assert_file "open item's draft kept" "$PROJ/drafts/EDS-7.plain.html"
assert_file "draft with no record kept" "$PROJ/drafts/EDS-99.plain.html"
assert_file "unit-named draft with no record kept" "$PROJ/drafts/columns-demo.plain.html"
assert_file "non-draft file kept" "$PROJ/drafts/eds-18-image.png"
assert_no_file "merged record moved out" "$PROJ/.ai/scm/publish-change-eds-18.json"
assert_file "merged record in scm-closed" "$PROJ/.ai/logs/scm-closed/publish-change-eds-18.json"
assert_file "open record stays" "$PROJ/.ai/scm/publish-change-eds-7.json"
assert_alive "server kept while a record is open" "$SERVER_PID"
assert_file "pid file kept" "$PROJ/.ai/logs/draft-server.pid"
assert_has "reports the merged record" "record: eds-18 state=merged" "$OUT"
assert_has "names the deleted draft" "deleted=drafts/EDS-18${PLAIN}" "$OUT"
assert_has "reports the server kept" "server: kept" "$OUT"

echo "[closed] a closed record deletes its draft and moves its record"
fresh "eds-7 closed" "eds-18 open"
OUT=$(run "$PACK")
assert_no_file "closed item's draft deleted" "$PROJ/drafts/EDS-7.plain.html"
assert_file "open item's draft kept" "$PROJ/drafts/EDS-18.plain.html"
assert_file "closed record in scm-closed" "$PROJ/.ai/logs/scm-closed/publish-change-eds-7.json"

echo "[every matching draft] every draft whose derived branch equals the record's branch goes"
fresh "eds-18 merged" "eds-7 open"
echo "<div>alt</div>" > "$PROJ/drafts/eds_18.plain.html"
OUT=$(run "$PACK")
assert_no_file "EDS-18 deleted" "$PROJ/drafts/EDS-18.plain.html"
assert_no_file "eds_18 deleted (same derived branch)" "$PROJ/drafts/eds_18.plain.html"

echo "[fail verdict] change_state is read whatever the verdict"
fresh "eds-18 fail-merged" "eds-7 open"
OUT=$(run "$PACK")
assert_no_file "fail envelope carrying merged still deletes" "$PROJ/drafts/EDS-18.plain.html"

echo "[unknown] a lookup with no change_state keeps the draft and counts as open"
fresh "eds-18 unknown"
OUT=$(run "$PACK")
assert_file "draft kept" "$PROJ/drafts/EDS-18.plain.html"
assert_file "record stays" "$PROJ/.ai/scm/publish-change-eds-18.json"
assert_alive "server kept (unknown counts as open)" "$SERVER_PID"
assert_has "reports unknown" "record: eds-18 state=unknown" "$OUT"

echo "[unknown] an envelope that does not validate is unknown"
fresh "eds-18 invalid"
OUT=$(run "$PACK")
assert_file "draft kept" "$PROJ/drafts/EDS-18.plain.html"
assert_alive "server kept" "$SERVER_PID"
assert_has "reports unknown" "record: eds-18 state=unknown" "$OUT"

echo "[unknown] merged inside an envelope that does not validate is unknown"
fresh "eds-18 badverdict"
OUT=$(run "$PACK")
assert_file "draft kept" "$PROJ/drafts/EDS-18.plain.html"
assert_has "reports unknown" "record: eds-18 state=unknown" "$OUT"

echo "[unknown] a script that exits non-zero is unknown"
fresh "eds-18 crash"
OUT=$(run "$PACK")
assert_file "draft kept" "$PROJ/drafts/EDS-18.plain.html"
assert_alive "server kept" "$SERVER_PID"

echo "[unknown] a pack with no scripts.check_status is unknown for every record"
fresh "eds-18 merged" "eds-7 merged"
write_manifest without
OUT=$(run "$PACK")
assert_file "EDS-18 kept" "$PROJ/drafts/EDS-18.plain.html"
assert_file "EDS-7 kept" "$PROJ/drafts/EDS-7.plain.html"
assert_file "record stays" "$PROJ/.ai/scm/publish-change-eds-18.json"
assert_alive "server kept" "$SERVER_PID"
assert_has "says why" "no scripts.check_status" "$OUT"
assert_no_file "the stub was never run" "$WORK/scm-calls"

echo "[unknown] no scm pack at all is unknown for every record"
fresh "eds-18 merged"
OUT=$(run none)
assert_file "draft kept" "$PROJ/drafts/EDS-18.plain.html"
assert_alive "server kept" "$SERVER_PID"

echo "[none] no change for the branch: draft and record kept, not open"
fresh "eds-18 none"
OUT=$(run "$PACK")
assert_file "draft kept" "$PROJ/drafts/EDS-18.plain.html"
assert_file "record stays" "$PROJ/.ai/scm/publish-change-eds-18.json"
assert_dead "server stopped (none is not open)" "$SERVER_PID"

echo "[stop] no record still open stops the server by its pid file"
fresh "eds-18 merged" "eds-7 closed"
OUT=$(run "$PACK")
assert_dead "server stopped" "$SERVER_PID"
assert_no_file "pid file removed" "$PROJ/.ai/logs/draft-server.pid"
assert_has "reports the stop" "server: stopped: pid=" "$OUT"
assert_file "draft with no record untouched" "$PROJ/drafts/EDS-99.plain.html"

echo "[stop] no records at all stops the server"
fresh
OUT=$(run "$PACK")
assert_dead "server stopped" "$SERVER_PID"
assert_file "every draft untouched" "$PROJ/drafts/EDS-18.plain.html"

echo "[stop] no pid file is nothing to stop"
fresh
rm -f "$PROJ/.ai/logs/draft-server.pid"
OUT=$(run "$PACK"); ST=$?
assert_eq "exit 0" "0" "$ST"
assert_has "nothing to stop" "server: nothing-to-stop" "$OUT"

echo "[collision] a record already in scm-closed is not overwritten"
fresh "eds-18 merged"
mkdir -p "$PROJ/.ai/logs/scm-closed"
echo "older" > "$PROJ/.ai/logs/scm-closed/publish-change-eds-18.json"
OUT=$(run "$PACK")
assert_eq "older record kept" "older" "$(cat "$PROJ/.ai/logs/scm-closed/publish-change-eds-18.json")"
assert_file "new record beside it" "$PROJ/.ai/logs/scm-closed/publish-change-eds-18-2.json"

echo "[no drafts dir] a project with no drafts/ still cleans up records"
fresh "eds-18 merged"
rm -rf "$PROJ/drafts"
OUT=$(run "$PACK"); ST=$?
assert_eq "exit 0" "0" "$ST"
assert_file "record moved" "$PROJ/.ai/logs/scm-closed/publish-change-eds-18.json"

echo "[summary] the last line counts each outcome"
fresh "eds-18 merged" "eds-7 open" "old-x unknown" "old-y none"
OUT=$(run "$PACK")
assert_has "summary line" "cleanup: records=4 merged_or_closed=1 open=1 unknown=1 none=1 drafts_deleted=1 server=kept" "$(echo "$OUT" | tail -1)"

echo "[boundary] the provider tool is never called by the cleanup"
assert_no_file "fake gh never called in any case" "$WORK/gh-calls"
if [ ! -f "$CLEAN" ] || grep -Eq '(^|[^a-z_-])gh[[:space:]]' "$CLEAN"; then
  bad "clean-drafts.sh names no provider command" "found a gh invocation"
else
  ok "clean-drafts.sh names no provider command"
fi

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
