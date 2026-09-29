#!/usr/bin/env bash
# Tests for check-component-reuse.sh. Run with:
#   bash plugins/eds/skills/eds-conventions-component-reuse/scripts/check-component-reuse.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Each case builds
# a project root, a fact record and (where the case needs one) an upstream
# block manifest in a temp dir (D528). The last cases read the manifest the
# pack ships, offline.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-component-reuse.sh"
SHIPPED="$SCRIPT_DIR/../../../shared/block-collection/manifest.txt"
PIN="69d7d5083900"
SHA="69d7d50839009376687f105cf1e323e05f4ecad2"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/component-reuse.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# root <name> <block>... — a project root with those blocks; echoes its path
root() {
  local r="$WORK/$1.root" b; shift
  mkdir -p "$r/blocks"
  for b in "$@"; do mkdir -p "$r/blocks/$b"; echo "/* $b */" > "$r/blocks/$b/$b.css"; done
  echo "$r"
}

# fact <name> <components body> <files_named body> — echoes its path
fact() {
  local f="$WORK/$1.fact.yaml"
  printf 'item_id: "EDS-1"\nitem_type: Story\nlabels: []\ncomponents: [%s]\nfiles_named: [%s]\n' "$2" "$3" > "$f"
  echo "$f"
}

# manifest <name> <block>... — a valid manifest dir with vendored files; echoes the manifest path
manifest() {
  local d="$WORK/$1.collection" b; shift
  mkdir -p "$d/blocks"
  printf 'Apache License\nVersion 2.0, January 2004\n' > "$d/LICENSE"
  {
    echo "# written by refresh-block-collection.sh"
    echo "repo=https://example.invalid/collection.git"
    echo "commit=$SHA"
    for b in "$@"; do echo "block=$b"; done
  } > "$d/manifest.txt"
  for b in "$@"; do mkdir -p "$d/blocks/$b"; echo "export default function decorate() {}" > "$d/blocks/$b/$b.js"; done
  echo "$d/manifest.txt"
}

run() { OUT="$(bash "$CHECK" "$@" 2>&1)"; RC=$?; }

has()    { grep -qxF "$1" <<< "$OUT"; }
has_re() { grep -qE "$1" <<< "$OUT"; }

# expect_line <desc> <line> — the output holds that exact line, exit 0
expect_line() {
  if [[ "$RC" == 0 ]] && has "$2"; then ok "$1"; else bad "$1" "want exit 0 and line: $2" "got exit=$RC:" "$OUT"; fi
}
expect_no_re() {
  if ! has_re "$2"; then ok "$1"; else bad "$1" "want no line matching: $2" "got:" "$OUT"; fi
}

echo "=== check-component-reuse.sh tests ==="

R="$(root proj cards columns)"
M="$(manifest col table cards accordion)"

echo "-- blocks/ first, then the collection, then new"
run "$(fact order "cards, table, widget" "")" "$R" "$M"
expect_line "in blocks/ (and in the collection) -> reuse" "reuse=cards"
expect_line "absent from blocks/, in the collection -> upstream" "upstream=table"
expect_line "absent from both -> new" "new=widget"
expect_line "the manifest's pin is reported" "upstream_manifest=$SHA"
expect_no_re "a reused name is never also upstream" '^upstream=cards$'

echo "-- files_named entries resolve to their block name"
run "$(fact paths "" "blocks/table/, blocks/table/table.css, styles/styles.css")" "$R" "$M"
expect_line "directory path -> upstream" "upstream=blocks/table/"
expect_line "file path -> upstream" "upstream=blocks/table/table.css"
expect_line "non-block path -> new" "new=styles/styles.css"

echo "-- missing manifest"
run "$(fact missing "cards, table, widget" "")" "$R" "$WORK/nowhere/manifest.txt"
expect_line "reuse is unaffected" "reuse=cards"
expect_line "absent from blocks/ -> upstream_unknown" "upstream_unknown=table"
expect_line "every unmatched name is upstream_unknown" "upstream_unknown=widget"
expect_no_re "never new alone" '^new='
expect_line "the manifest is reported unavailable" "upstream_manifest=unavailable: manifest not found"

# malformed <desc> <reason substring> — mutate $MM first, then call
malformed() {
  run "$(fact "mal$RANDOM" "table" "")" "$R" "$MM"
  if [[ "$RC" == 0 ]] && has "upstream_unknown=table" && ! has_re '^(new|upstream)=' \
      && has_re "^upstream_manifest=unavailable: .*$2"; then
    ok "$1"
  else
    bad "$1" "want exit 0, upstream_unknown=table, reason ~ $2" "got exit=$RC:" "$OUT"
  fi
}

echo "-- malformed manifest"
MM="$(manifest bad-commit table)"; sed -i.bak "s/^commit=.*/commit=69d7d5083900/" "$MM"
malformed "short commit" "commit"
MM="$(manifest no-commit table)"; sed -i.bak "/^commit=/d" "$MM"
malformed "no commit line" "commit"
MM="$(manifest no-repo table)"; sed -i.bak "/^repo=/d" "$MM"
malformed "no repo line" "repo"
MM="$(manifest no-blocks table)"; sed -i.bak "/^block=/d" "$MM"
malformed "no block lines" "no block"
MM="$(manifest bad-name table)"; echo "block=../escape" >> "$MM"
malformed "unsafe block name" "block name"
MM="$(manifest garbage table)"; echo "this is not a key" >> "$MM"
malformed "unreadable line" "line"
MM="$(manifest no-files table)"; rm -rf "$(dirname "$MM")/blocks/table"
malformed "listed block with no vendored files" "vendored"
MM="$(manifest no-license table)"; rm -f "$(dirname "$MM")/LICENSE"
malformed "no upstream license beside it" "LICENSE"
MM="$(manifest empty table)"; : > "$MM"
malformed "empty manifest" "repo"

echo "-- earlier outcomes unchanged"
run "$(fact none "" "")" "$R" "$M"
expect_line "nothing named -> no_components_named" "decision=no_components_named"
expect_line "exemplars still emitted" "exemplar=cards"
run "$(fact exemplar "table" "")" "$R" "$M"
expect_line "an upstream-only item takes project exemplars" "exemplar=cards"

echo "-- usage"
run
if [[ "$RC" == 2 ]]; then ok "no argument -> exit 2"; else bad "no argument -> exit 2" "got exit=$RC"; fi

echo "-- the shipped manifest (offline)"
if [[ -f "$SHIPPED" ]] && grep -qE "^commit=${PIN}[0-9a-f]{28}$" "$SHIPPED"; then
  ok "pinned at $PIN"
else
  bad "pinned at $PIN" "manifest: $SHIPPED" "$(grep '^commit=' "$SHIPPED" 2>&1)"
fi
LIC="$(dirname "$SHIPPED")/LICENSE"
if grep -q "Apache License" "$LIC" 2>/dev/null && grep -q "Version 2.0" "$LIC"; then
  ok "upstream Apache-2.0 license vendored beside it"
else
  bad "upstream Apache-2.0 license vendored beside it" "missing or not Apache-2.0: $LIC"
fi
all_vendored=1
while IFS= read -r b; do
  f="$(dirname "$SHIPPED")/blocks/$b"
  [[ -s "$f/$b.js" || -s "$f/$b.css" ]] || { all_vendored=0; echo "    no files for $b"; }
done < <(sed -n 's/^block=//p' "$SHIPPED" 2>/dev/null)
if [[ $all_vendored == 1 ]] && grep -q '^block=' "$SHIPPED" 2>/dev/null; then
  ok "every listed block has its vendored files"
else
  bad "every listed block has its vendored files"
fi

echo "-- EDS-18 against the shipped manifest"
EDS="$(root eds18 button cards columns edge-delivery-banner features-carousel footer fragment header hero widget zoran-block)"
run "$(fact eds18 "table" "blocks/columns/, blocks/table/, blocks/table/table.css, blocks/table/table.js, styles/styles.css")" \
  "$EDS" "$SHIPPED"
expect_line "EDS-18 component -> upstream=table" "upstream=table"
expect_line "EDS-18 columns stays reuse" "reuse=blocks/columns/"
run "$(fact eds18-default "table" "")" "$EDS"
expect_line "the shipped manifest is the default" "upstream=table"

echo "-- no network at run time"
if grep -nE '\b(curl|wget|gh|git|nc|python3?)\b' "$CHECK" | grep -vE '^[0-9]+:[[:space:]]*#' > "$WORK/net.txt"; then
  bad "the script calls no network tool" "$(cat "$WORK/net.txt")"
else
  ok "the script calls no network tool"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]]
