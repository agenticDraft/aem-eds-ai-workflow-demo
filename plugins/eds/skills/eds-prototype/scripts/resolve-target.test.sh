#!/usr/bin/env bash
# Tests for resolve-target.py. Run with:
#   bash plugins/eds/skills/eds-prototype/scripts/resolve-target.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Each case writes
# a fact record, and answers through the core's own write-question-answer.sh
# so the file is always in the shape the reader accepts (D526, D527).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE="$SCRIPT_DIR/resolve-target.py"
WRITER="$SCRIPT_DIR/../../../../agentic-core/shared/lib/write-question-answer.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/resolve-target.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
NL=$'\n'

ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# fact <name> <components body> <files_named body> — writes a fact record; echoes its path
fact() {
  local f="$WORK/$1.fact.yaml"
  printf 'item_id: "EDS-1"\nitem_type: Story\nlabels: []\ncomponents: [%s]\nfiles_named: [%s]\n\ndesign_source: true\n' \
    "$2" "$3" > "$f"
  echo "$f"
}

# answer <name> <stage> <question id> <answer> — upserts one answer; echoes the file path
answer() {
  local qa="$WORK/$1.qa.yaml"
  bash "$WRITER" "$qa" "$2" "$3" "Which block?" "$4" > /dev/null || { echo "writer refused" >&2; return 1; }
  echo "$qa"
}

# expect <desc> <exit> <stdout> <fact> <qa>
expect() {
  local desc="$1" want_rc="$2" want_out="$3" out rc
  out="$(python3 "$RESOLVE" "$4" "$5" 2>&1)"; rc=$?
  if [[ "$rc" == "$want_rc" && "$out" == "$want_out" ]]; then
    ok "$desc"
  else
    bad "$desc" "expected exit=$want_rc, got exit=$rc" "expected: $(printf '%q' "$want_out")" "got:      $(printf '%q' "$out")"
  fi
}

NO_QA="$WORK/absent.qa.yaml"

echo "=== resolve-target.py tests ==="

echo "-- zero candidates"
expect "no components, no blocks/ path -> question, no candidate" 4 \
  "source=none" \
  "$(fact zero "" "styles/styles.css, scripts/scripts.js")" "$NO_QA"

echo "-- exactly one candidate"
expect "one component -> resolved from components" 0 \
  "target=table${NL}source=components" \
  "$(fact one-comp "table" "")" "$NO_QA"
expect "no component, one distinct block in files_named -> resolved" 0 \
  "target=table${NL}source=files_named" \
  "$(fact one-file "" "blocks/table/, blocks/table/table.css, blocks/table/table.js, styles/styles.css")" "$NO_QA"
expect "a component outranks files_named naming other blocks (EDS-18 with component table)" 0 \
  "target=table${NL}source=components" \
  "$(fact eds18 "table" "blocks/columns/, blocks/table/, blocks/table/table.css, blocks/table/table.js, styles/styles.css")" "$NO_QA"
expect "one component named twice counts once" 0 \
  "target=hero${NL}source=components" \
  "$(fact dup-comp "hero, hero" "")" "$NO_QA"

echo "-- two or more candidates"
expect "two blocks in files_named -> question listing both (EDS-18 as run)" 4 \
  "source=files_named${NL}candidate=columns${NL}candidate=table" \
  "$(fact two-file "" "blocks/columns/, blocks/table/, blocks/table/table.css, blocks/table/table.js, styles/styles.css")" "$NO_QA"
expect "candidates are listed sorted, never in field order" 4 \
  "source=components${NL}candidate=cards${NL}candidate=hero${NL}candidate=table" \
  "$(fact three-comp "table, hero, cards" "")" "$NO_QA"

echo "-- an answer outranks everything"
QA_ONE="$(answer ans-one prototype target-block "blocks/columns/")"
expect "answer as a blocks/ path outranks components and files_named" 0 \
  "target=columns${NL}source=answer" \
  "$(fact ans-one "table, hero" "blocks/cards/")" "$QA_ONE"
QA_BARE="$(answer ans-bare prototype target-block "table")"
expect "answer as a bare block name resolves" 0 \
  "target=table${NL}source=answer" \
  "$(fact ans-bare "" "blocks/columns/, blocks/table/")" "$QA_BARE"
QA_PROSE="$(answer ans-prose prototype target-block "Build a new blocks/table/ block, never touch the old one")"
expect "answer prose naming one blocks/ path resolves to it" 0 \
  "target=table${NL}source=answer" \
  "$(fact ans-prose "" "blocks/columns/, blocks/table/")" "$QA_PROSE"
QA_NONE="$(answer ans-none prototype target-block "whatever you think is best")"
expect "answer naming no block falls through to the fact record" 0 \
  "target=hero${NL}source=components" \
  "$(fact ans-none "hero" "")" "$QA_NONE"
QA_TWO="$(answer ans-two prototype target-block "blocks/table/ or maybe blocks/columns/")"
expect "answer naming two blocks -> question listing both" 4 \
  "source=answer${NL}candidate=columns${NL}candidate=table" \
  "$(fact ans-two "hero" "")" "$QA_TWO"
QA_OTHER="$(answer ans-other prototype icon-collision "blocks/columns/")"
QA_OTHER="$(answer ans-other cards target-block "blocks/cards/")"
expect "answers under other keys are invisible" 0 \
  "target=hero${NL}source=components" \
  "$(fact ans-other "hero" "")" "$QA_OTHER"

echo "-- refusals"
BROKEN="$WORK/broken.qa.yaml"
printf 'answers:\n  - stage: prototype\n' > "$BROKEN"
out="$(python3 "$RESOLVE" "$(fact broken "hero" "")" "$BROKEN" 2>&1)"; rc=$?
if [[ "$rc" == 1 && "$out" == invalid:* ]]; then ok "malformed answer file -> exit 1 with the reader's reason"
else bad "malformed answer file -> exit 1 with the reader's reason" "exit=$rc" "out=$out"; fi
out="$(python3 "$RESOLVE" "$WORK/missing.fact.yaml" "$NO_QA" 2>&1)"; rc=$?
if [[ "$rc" == 2 && -n "$out" ]]; then ok "missing fact record -> exit 2"
else bad "missing fact record -> exit 2" "exit=$rc" "out=$out"; fi
out="$(python3 "$RESOLVE" 2>&1)"; rc=$?
if [[ "$rc" == 2 ]]; then ok "no arguments -> exit 2"
else bad "no arguments -> exit 2" "exit=$rc"; fi

echo
echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]]
