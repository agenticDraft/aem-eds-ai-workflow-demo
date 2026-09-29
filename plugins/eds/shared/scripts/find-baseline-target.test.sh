#!/usr/bin/env bash
# Tests for find-baseline-target.py. Run with:
#   bash plugins/eds/shared/scripts/find-baseline-target.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Each case builds
# a git checkout in a temporary directory, because the search reads the files
# git lists for that checkout.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIND="$SCRIPT_DIR/find-baseline-target.py"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/find-baseline-target.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PREVIEW="http://localhost:3000/some/page"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# checkout <name> [gitignore] — an empty git checkout, optionally with a .gitignore
checkout() {
  local dir="$WORK/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  [[ -z "${2:-}" ]] || printf '%s\n' "$2" > "$dir/.gitignore"
  echo "$dir"
}

# page <checkout> <relative-path> <content>
page() {
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" > "$1/$2"
}

# run_find <checkout> <block> — sets STATUS; stdout/stderr land in the checkout's parent
run_find() {
  python3 "$FIND" "$2" "$PREVIEW" "$1" >"$1.stdout" 2>"$1.stderr"
  STATUS=$?
}

out_is() {
  local got
  got="$(cat "$2.stdout")"
  if [[ "$got" == "$3" ]]; then ok "$1"; else bad "$1" "want: $(printf '%q' "$3")" "got:  $(printf '%q' "$got")"; fi
}

status_is() {
  if [[ "$STATUS" == "$2" ]]; then ok "$1"; else bad "$1" "want exit $2, got $STATUS" "stderr: $(cat "$3.stderr")"; fi
}

TABLE='<div><div class="table"><div><div>A</div></div></div></div>'
TAB=$'\t'

echo "a hit only in drafts/ gives no target URL (D532)"
D="$(checkout drafts-only 'drafts/')"
page "$D" drafts/ITEM-1.plain.html "$TABLE"
run_find "$D" table
out_is "drafts/ITEM-1.plain.html is the only hit → nothing printed" "$D" ""
status_is "exit 1 when nothing is found" 1 "$D"

D="$(checkout drafts-not-ignored)"
page "$D" drafts/ITEM-1.plain.html "$TABLE"
run_find "$D" table
out_is "drafts/ skipped even when the project does not gitignore it" "$D" ""
status_is "exit 1 when drafts/ is not ignored and is the only hit" 1 "$D"

echo "a hit outside drafts/ wins over one inside"
D="$(checkout both 'drafts/')"
page "$D" drafts/ITEM-1.plain.html "$TABLE"
page "$D" pricing.plain.html "$TABLE"
run_find "$D" table
out_is "only the page outside drafts/ is the target" "$D" "pricing.plain.html${TAB}http://localhost:3000/pricing"
status_is "exit 0 when a page is found" 0 "$D"

D="$(checkout both-unignored)"
page "$D" drafts/a.plain.html "$TABLE"
page "$D" zz/b.plain.html "$TABLE"
run_find "$D" table
out_is "drafts/ sorts first but is still skipped" "$D" "zz/b.plain.html${TAB}http://localhost:3000/zz/b"

echo "no hit anywhere gives no target URL"
D="$(checkout none)"
page "$D" 404.html '<html><body><main><div class="cards"></div></main></body></html>'
page "$D" head.html '<meta name="viewport" content="width=device-width">'
run_find "$D" table
out_is "no page names the block → nothing printed" "$D" ""
status_is "exit 1 when no page names the block" 1 "$D"

echo "what counts as a hit"
D="$(checkout variant)"
page "$D" docs/page.plain.html '<div class="table striped"><div></div></div>'
run_find "$D" table
out_is "a variant class list whose first token is the block is a hit" "$D" "docs/page.plain.html${TAB}http://localhost:3000/docs/page"

D="$(checkout not-first)"
page "$D" page.plain.html '<div class="button table"></div><div class="tables"></div>'
run_find "$D" table
out_is "the block as a later token, or a longer name, is not a hit" "$D" ""

D="$(checkout rendered)"
page "$D" a/index.html "<div class='table block' data-block-name='table'></div>"
run_find "$D" table
out_is "a rendered instance hits; index maps to its folder URL" "$D" "a/index.html${TAB}http://localhost:3000/a/"

D="$(checkout order)"
page "$D" b.plain.html "$TABLE"
page "$D" a.plain.html "$TABLE"
run_find "$D" table
out_is "the first hit in path order is the target" "$D" "a.plain.html${TAB}http://localhost:3000/a"

D="$(checkout ignored $'content/\nnode_modules/')"
page "$D" content/page.plain.html "$TABLE"
page "$D" node_modules/x/page.html "$TABLE"
run_find "$D" table
out_is "gitignored pages are never read" "$D" ""

D="$(checkout tracked)"
page "$D" page.plain.html "$TABLE"
git -C "$D" add page.plain.html
run_find "$D" table
out_is "a tracked page is a hit" "$D" "page.plain.html${TAB}http://localhost:3000/page"

echo "usage errors"
D="$(checkout usage)"
python3 "$FIND" table >"$D.stdout" 2>"$D.stderr"; STATUS=$?
status_is "exit 2 with a missing argument" 2 "$D"
python3 "$FIND" 'Table' "$PREVIEW" "$D" >"$D.stdout" 2>"$D.stderr"; STATUS=$?
status_is "exit 2 for a block name that is not a folder name" 2 "$D"
python3 "$FIND" table "localhost:3000" "$D" >"$D.stdout" 2>"$D.stderr"; STATUS=$?
status_is "exit 2 for a preview URL with no scheme" 2 "$D"
mkdir -p "$WORK/not-git"
python3 "$FIND" table "$PREVIEW" "$WORK/not-git" >"$WORK/not-git.stdout" 2>"$WORK/not-git.stderr"; STATUS=$?
status_is "exit 2 outside a git checkout" 2 "$WORK/not-git"

echo
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
