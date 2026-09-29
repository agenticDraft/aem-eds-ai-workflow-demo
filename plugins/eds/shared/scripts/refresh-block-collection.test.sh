#!/usr/bin/env bash
# Tests for refresh-block-collection.sh. Run with:
#   bash plugins/eds/shared/scripts/refresh-block-collection.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. The upstream is
# a local git repository built here, so the suite needs no network; the real
# refresh against the public collection is run by hand (D528).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFRESH="$SCRIPT_DIR/refresh-block-collection.sh"
CHECK="$SCRIPT_DIR/../../skills/eds-conventions-component-reuse/scripts/check-component-reuse.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/refresh-collection.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

g() { git -C "$UP" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }

# The upstream: commit one has accordion + table and a LICENSE; commit two adds
# tabs and drops accordion. A NOTICE exists only in commit two.
UP="$WORK/upstream"
mkdir -p "$UP/blocks/accordion" "$UP/blocks/table"
git init -q "$UP"
printf 'Apache License\nVersion 2.0, January 2004\n' > "$UP/LICENSE"
echo ".accordion {}" > "$UP/blocks/accordion/accordion.css"
echo "export default function decorate() {}" > "$UP/blocks/accordion/accordion.js"
echo ".table {}" > "$UP/blocks/table/table.css"
echo "export default function decorate(block) { return block; }" > "$UP/blocks/table/table.js"
echo "not a block" > "$UP/README.md"
g add -A && g commit -qm one
FIRST="$(g rev-parse HEAD)"
g rm -rq blocks/accordion
mkdir -p "$UP/blocks/tabs"; echo ".tabs {}" > "$UP/blocks/tabs/tabs.css"
echo "Notice text" > "$UP/NOTICE"
g add -A && g commit -qm two
SECOND="$(g rev-parse HEAD)"

refresh() { OUT="$(bash "$REFRESH" "$@" 2>&1)"; RC=$?; }

echo "=== refresh-block-collection.sh tests ==="

echo "-- writes manifest, vendored files and license at the pin"
DEST="$WORK/collection"
refresh "${FIRST:0:12}" "$UP" "$DEST"
if [[ "$RC" == 0 ]]; then ok "exit 0"; else bad "exit 0" "got exit=$RC" "$OUT"; fi
if grep -qxF "commit=$FIRST" "$DEST/manifest.txt" 2>/dev/null; then
  ok "short pin recorded as the full commit"
else
  bad "short pin recorded as the full commit" "$(cat "$DEST/manifest.txt" 2>&1)"
fi
if grep -qxF "repo=$UP" "$DEST/manifest.txt" 2>/dev/null; then ok "repo recorded"; else bad "repo recorded"; fi
if [[ "$(sed -n 's/^block=//p' "$DEST/manifest.txt" 2>/dev/null | tr '\n' ' ')" == "accordion table " ]]; then
  ok "blocks at that commit, sorted"
else
  bad "blocks at that commit, sorted" "$(cat "$DEST/manifest.txt" 2>&1)"
fi
if cmp -s "$UP/LICENSE" "$DEST/LICENSE"; then ok "license vendored byte-identical"; else bad "license vendored byte-identical"; fi
if git -C "$UP" show "$FIRST:blocks/table/table.js" | cmp -s - "$DEST/blocks/table/table.js" \
    && git -C "$UP" show "$FIRST:blocks/accordion/accordion.css" | cmp -s - "$DEST/blocks/accordion/accordion.css"; then
  ok "block files vendored byte-identical"
else
  bad "block files vendored byte-identical" "$(ls -R "$DEST" 2>&1)"
fi
if [[ ! -e "$DEST/NOTICE" && ! -e "$DEST/README.md" ]]; then
  ok "nothing but license, notices and blocks"
else
  bad "nothing but license, notices and blocks" "$(ls "$DEST")"
fi

echo "-- the reuse check accepts what it wrote"
FACT="$WORK/fact.yaml"
printf 'item_id: "EDS-1"\nitem_type: Story\nlabels: []\ncomponents: [table]\nfiles_named: []\n' > "$FACT"
mkdir -p "$WORK/project/blocks"
CK="$(bash "$CHECK" "$FACT" "$WORK/project" "$DEST/manifest.txt" 2>&1)"
if grep -qxF "upstream=table" <<< "$CK"; then ok "upstream=table from the refreshed manifest"; else bad "upstream=table from the refreshed manifest" "$CK"; fi

echo "-- a new pin replaces the old one whole"
refresh "$SECOND" "$UP" "$DEST"
if [[ "$RC" == 0 && ! -e "$DEST/blocks/accordion" && -f "$DEST/blocks/tabs/tabs.css" ]]; then
  ok "dropped block gone, added block present"
else
  bad "dropped block gone, added block present" "exit=$RC" "$(ls -R "$DEST" 2>&1)"
fi
if cmp -s "$UP/NOTICE" "$DEST/NOTICE"; then ok "an upstream NOTICE is vendored"; else bad "an upstream NOTICE is vendored"; fi
if grep -qxF "commit=$SECOND" "$DEST/manifest.txt"; then ok "pin moved"; else bad "pin moved"; fi

echo "-- a failed refresh leaves the old pin untouched"
BEFORE="$(cd "$DEST" && find . -type f -exec cksum {} + | sort)"
refresh "0000000000000000000000000000000000000000" "$UP" "$DEST"
if [[ "$RC" != 0 && "$(cd "$DEST" && find . -type f -exec cksum {} + | sort)" == "$BEFORE" ]]; then
  ok "unknown commit -> non-zero, destination unchanged"
else
  bad "unknown commit -> non-zero, destination unchanged" "exit=$RC" "$OUT"
fi
g rm -q LICENSE && g commit -qm three
refresh "$(g rev-parse HEAD)" "$UP" "$DEST"
if [[ "$RC" != 0 && "$(cd "$DEST" && find . -type f -exec cksum {} + | sort)" == "$BEFORE" ]]; then
  ok "upstream without LICENSE -> non-zero, destination unchanged"
else
  bad "upstream without LICENSE -> non-zero, destination unchanged" "exit=$RC" "$OUT"
fi

echo "-- usage"
refresh
if [[ "$RC" == 2 ]]; then ok "no argument -> exit 2"; else bad "no argument -> exit 2" "got exit=$RC"; fi

echo
echo "passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]]
