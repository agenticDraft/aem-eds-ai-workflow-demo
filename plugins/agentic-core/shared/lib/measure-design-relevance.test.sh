#!/usr/bin/env bash
# Tests for measure-design-relevance.sh. Run with:
#   bash plugins/agentic-core/shared/lib/measure-design-relevance.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. The fixture
# archive holds two qualifying run contexts (run-table: 3 of 4 names match;
# run-pricing: 1 of 3), one without a node_name (run-old), and a cross-pairs
# file pairing each qualifying spec with the other's design.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEASURE="$SCRIPT_DIR/measure-design-relevance.sh"
ARCHIVE="$SCRIPT_DIR/../fixtures/design-relevance-archive"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/measure-design-relevance.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
TAB="$(printf '\t')"

ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

run() { bash "$MEASURE" "$@" >"$WORK/out" 2>"$WORK/err"; STATUS=$?; }
exit_is() { if [ "$STATUS" -eq "$2" ]; then ok "$1"; else bad "$1" "want exit $2, got $STATUS" "stderr: $(cat "$WORK/err")"; fi; }
has_line() { if grep -qxF -- "$2" "$WORK/out"; then ok "$1"; else bad "$1" "want: $2" "got:" "$(cat "$WORK/out")"; fi; }
err_has() { if grep -qF -- "$2" "$WORK/err"; then ok "$1"; else bad "$1" "want in stderr: $2" "stderr: $(cat "$WORK/err")"; fi; }

echo "archive with cross pairs"
run "$ARCHIVE" "$ARCHIVE/cross-pairs.tsv"
exit_is "exits 0" 0
has_line "true pair run-table: 3 of 4" "pair${TAB}true${TAB}run-table${TAB}run-table${TAB}3${TAB}4"
has_line "true pair run-pricing: 1 of 3" "pair${TAB}true${TAB}run-pricing${TAB}run-pricing${TAB}1${TAB}3"
has_line "cross pair table spec, pricing design: 0 of 3" "pair${TAB}cross${TAB}run-table${TAB}run-pricing${TAB}0${TAB}3"
has_line "cross pair pricing spec, table design: 0 of 4" "pair${TAB}cross${TAB}run-pricing${TAB}run-table${TAB}0${TAB}4"
has_line "run-old skipped for its missing node_name" "skipped${TAB}run-old${TAB}no node_name in the design reference"
has_line "summary counts" "summary: true=2 cross=2 not_run=0 skipped=1"
has_line "threshold 1: no true pair warned, no cross pair passed" "threshold 1: true warned=0 of 2; cross passed=0 of 2"
has_line "threshold 2: the 1-name true pair warns" "threshold 2: true warned=1 of 2; cross passed=0 of 2"

echo "archive without cross pairs"
run "$ARCHIVE"
exit_is "exits 0" 0
has_line "summary counts true pairs only" "summary: true=2 cross=0 not_run=0 skipped=1"
has_line "threshold 1 with no cross pairs" "threshold 1: true warned=0 of 2; cross passed=0 of 0"

echo "a real archive shape: the context one directory down"
mkdir -p "$WORK/nested/run-2026/run-context"
cp "$ARCHIVE/run-table/"* "$WORK/nested/run-2026/run-context/"
run "$WORK/nested"
exit_is "exits 0" 0
has_line "nested context found and named by its path" "pair${TAB}true${TAB}run-2026/run-context${TAB}run-2026/run-context${TAB}3${TAB}4"

echo "an empty archive"
mkdir -p "$WORK/empty"
run "$WORK/empty"
exit_is "exits 0" 0
has_line "zero counts" "summary: true=0 cross=0 not_run=0 skipped=0"

echo "usage errors"
run
exit_is "no argument exits 2" 2
run "$WORK/does-not-exist"
exit_is "a missing archive exits 2" 2
printf 'run-table\n' > "$WORK/bad-cross.tsv"
run "$ARCHIVE" "$WORK/bad-cross.tsv"
exit_is "a cross line without a tab exits 2" 2
err_has "the bad cross line is named" "run-table"
printf 'run-table\trun-old\n' > "$WORK/bad-cross.tsv"
run "$ARCHIVE" "$WORK/bad-cross.tsv"
exit_is "a cross pair naming a context that does not qualify exits 2" 2
err_has "the non-qualifying context is named" "run-old"

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
