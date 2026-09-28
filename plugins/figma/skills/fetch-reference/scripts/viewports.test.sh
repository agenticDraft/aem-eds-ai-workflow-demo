#!/usr/bin/env bash
# Tests for viewports.py. Run with:
#   bash plugins/figma/skills/fetch-reference/scripts/viewports.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Classification
# tables come from classify-node.py run on the fixtures, or are written inline
# for shapes no fixture has. Each case runs from its own directory, because the
# paths the script prints and checks are relative to the project root.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIEWPORTS="$SCRIPT_DIR/viewports.py"
CLASSIFY="$SCRIPT_DIR/classify-node.py"
FX="$SCRIPT_DIR/fixtures"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/viewports.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
TAB="$(printf '\t')"

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# case_dir <name> — a fresh project root with .ai/figma
case_dir() {
  local dir="$WORK/$1"
  mkdir -p "$dir/.ai/figma"
  echo "$dir"
}

# run <dir> <args...> — runs the script from <dir>; sets STATUS, OUT, ERR
run() {
  local dir="$1"; shift
  (cd "$dir" && python3 "$VIEWPORTS" "$@" >"$dir/stdout" 2>"$dir/stderr")
  STATUS=$?
  OUT="$(cat "$dir/stdout")"
  ERR="$(cat "$dir/stderr")"
}

exits() {
  if [ "$STATUS" -eq "$1" ]; then ok "exits $1"; else bad "exits $1" "got: $STATUS" "stdout: $OUT" "stderr: $ERR"; fi
}

no_output() {
  if [ -z "$OUT" ]; then ok "prints nothing on stdout"; else bad "prints nothing on stdout" "$OUT"; fi
}

# check <desc> <jq filter that must print true> — against the last stdout
check() {
  local got
  got="$(printf '%s' "$OUT" | jq -r "$2" 2>&1)"
  if [ "$got" = "true" ]; then ok "$1"; else bad "$1" "filter: $2" "got: $got"; fi
}

# classified <dir> <fixture> — classification table of a fixture, in <dir>
classified() {
  python3 "$CLASSIFY" "$FX/$2" > "$1/classification.tsv"
}

# images <dir> <node-id>... — a reference image per node
images() {
  local dir="$1"; shift
  for id in "$@"; do printf 'PNG-%s' "$id" > "$dir/.ai/figma/KEY-$id.png"; done
}

# contexts <dir> <node-id>... — a design-context file per node
contexts() {
  local dir="$1"; shift
  for id in "$@"; do printf 'code for %s' "$id" > "$dir/.ai/figma/KEY-$id.context.txt"; done
}

echo "plan: a section of Desktop, Tablet and Mobile names each variant, widest first"
D="$(case_dir plan)"
classified "$D" section-variants.xml
run "$D" plan classification.tsv KEY
exits 0
if [ "$OUT" = "1-118${TAB}1280${TAB}.ai/figma/KEY-1-118.png${TAB}.ai/figma/KEY-1-118.context.txt${TAB}Desktop
1-274${TAB}800${TAB}.ai/figma/KEY-1-274.png${TAB}.ai/figma/KEY-1-274.context.txt${TAB}Tablet
1-430${TAB}375${TAB}.ai/figma/KEY-1-430.png${TAB}.ai/figma/KEY-1-430.context.txt${TAB}Mobile" ]; then
  ok "one line per variant: node id, width, image, context, name"
else
  bad "one line per variant: node id, width, image, context, name" "$OUT"
fi
n="$(printf '%s\n' "$OUT" | cut -f3,4 | tr '\t' '\n' | sort -u | wc -l | tr -d ' ')"
if [ "$n" -eq 6 ]; then ok "every image and context path is distinct"; else bad "every image and context path is distinct" "distinct: $n"; fi

echo "plan: variants listed narrowest first are printed widest first"
D="$(case_dir order)"
cat > "$D/classification.tsv" <<EOF
class${TAB}variants
node${TAB}frame${TAB}5:1${TAB}2000${TAB}Hero
child${TAB}5:3${TAB}375${TAB}variant${TAB}name:pattern=mobile${TAB}Hero - Mobile
child${TAB}5:2${TAB}1440${TAB}variant${TAB}name:pattern=desktop${TAB}Hero - Desktop
child${TAB}5:4${TAB}767.5${TAB}variant${TAB}name:width=768${TAB}Hero 768
EOF
run "$D" plan classification.tsv KEY
exits 0
if [ "$(printf '%s\n' "$OUT" | cut -f1,2 | tr '\t\n' ' |')" = "5-2 1440|5-4 767.5|5-3 375|" ]; then
  ok "sorted by width, widest first; a fractional width kept"
else
  bad "sorted by width, widest first; a fractional width kept" "$OUT"
fi
if printf '%s\n' "$OUT" | grep -q "${TAB}Hero - Mobile$"; then ok "a name with spaces kept whole"; else bad "a name with spaces kept whole" "$OUT"; fi

echo "plan: a node the classifier did not call variants is refused"
for fixture in instance.xml page.xml frame-styles.xml; do
  D="$(case_dir "refuse-$fixture")"
  classified "$D" "$fixture"
  run "$D" plan classification.tsv KEY
  exits 2
  no_output
done

echo "plan: a variants table whose rows are not all variants is refused"
D="$(case_dir mixed)"
cat > "$D/classification.tsv" <<EOF
class${TAB}variants
node${TAB}frame${TAB}5:1${TAB}2000${TAB}Hero
child${TAB}5:2${TAB}1440${TAB}variant${TAB}name:keyword=desktop${TAB}Desktop
child${TAB}5:3${TAB}375${TAB}-${TAB}none${TAB}Mobile
EOF
run "$D" plan classification.tsv KEY
exits 2
no_output

echo "plan: fewer than two variants is refused"
D="$(case_dir one)"
cat > "$D/classification.tsv" <<EOF
class${TAB}variants
node${TAB}frame${TAB}5:1${TAB}2000${TAB}Hero
child${TAB}5:2${TAB}1440${TAB}variant${TAB}name:keyword=desktop${TAB}Desktop
EOF
run "$D" plan classification.tsv KEY
exits 2

echo "plan: a variant with no numeric width is refused"
D="$(case_dir nowidth)"
cat > "$D/classification.tsv" <<EOF
class${TAB}variants
node${TAB}frame${TAB}5:1${TAB}2000${TAB}Hero
child${TAB}5:2${TAB}${TAB}variant${TAB}name:keyword=desktop${TAB}Desktop
child${TAB}5:3${TAB}375${TAB}variant${TAB}name:keyword=mobile${TAB}Mobile
EOF
run "$D" plan classification.tsv KEY
exits 2

echo "plan: a missing table, or a usage error"
D="$(case_dir usage)"
run "$D" plan absent.tsv KEY
exits 2
run "$D" plan
exits 2
run "$D" frobnicate classification.tsv KEY
exits 2

echo "list: every variant with code — the viewports array, widest first"
D="$(case_dir list)"
classified "$D" section-variants.xml
images "$D" 1-118 1-274 1-430
contexts "$D" 1-118 1-274 1-430
run "$D" list classification.tsv KEY 1-430=code 1-118=code 1-274=code
exits 0
check "a JSON array of three" 'type == "array" and length == 3'
check "each entry has exactly name, node_id, width, image, context" \
  'all(.[]; (keys == ["context","image","name","node_id","width"]))'
check "widest first" '[.[].width] == [1280, 800, 375]'
check "widths are numbers" 'all(.[]; .width | type == "number")'
check "names and node ids from the classifier" \
  '[.[] | .name + "=" + .node_id] == ["Desktop=1-118", "Tablet=1-274", "Mobile=1-430"]'
check "each image is the variant's own file" \
  '[.[].image] == [".ai/figma/KEY-1-118.png", ".ai/figma/KEY-1-274.png", ".ai/figma/KEY-1-430.png"]'
check "each context is the variant's own file" \
  '[.[].context] == [".ai/figma/KEY-1-118.context.txt", ".ai/figma/KEY-1-274.context.txt", ".ai/figma/KEY-1-430.context.txt"]'

echo "list: a structure-only variant has context null"
D="$(case_dir structure)"
classified "$D" section-variants.xml
images "$D" 1-118 1-274 1-430
contexts "$D" 1-118 1-430
run "$D" list classification.tsv KEY 1-118=code 1-274=structure_only 1-430=code
exits 0
check "the structure-only variant's context is null" '.[1].node_id == "1-274" and .[1].context == null'
check "the others keep their context file" '.[0].context != null and .[2].context != null'

echo "list: structure_only wins over a context file left on disk"
D="$(case_dir stale)"
classified "$D" section-variants.xml
images "$D" 1-118 1-274 1-430
contexts "$D" 1-118 1-274 1-430
run "$D" list classification.tsv KEY 1-118=code 1-274=structure_only 1-430=code
exits 0
check "context null although a file exists" '.[1].context == null'

echo "list: a variant whose image is missing is refused"
D="$(case_dir noimage)"
classified "$D" section-variants.xml
images "$D" 1-118 1-430
contexts "$D" 1-118 1-274 1-430
run "$D" list classification.tsv KEY 1-118=code 1-274=code 1-430=code
exits 2
no_output

echo "list: code claimed, but the context file is missing, is refused"
D="$(case_dir nocontext)"
classified "$D" section-variants.xml
images "$D" 1-118 1-274 1-430
contexts "$D" 1-118 1-430
run "$D" list classification.tsv KEY 1-118=code 1-274=code 1-430=code
exits 2
no_output

echo "list: every variant needs exactly one outcome, and only detected variants have one"
D="$(case_dir outcomes)"
classified "$D" section-variants.xml
images "$D" 1-118 1-274 1-430 9-9
contexts "$D" 1-118 1-274 1-430 9-9
run "$D" list classification.tsv KEY 1-118=code 1-274=code
exits 2
run "$D" list classification.tsv KEY 1-118=code 1-274=code 1-430=code 9-9=code
exits 2
run "$D" list classification.tsv KEY 1-118=code 1-274=code 1-430=code 1-430=code
exits 2
run "$D" list classification.tsv KEY 1-118=code 1-274=code 1-430=maybe
exits 2

echo "list: a node the classifier did not call variants is refused"
D="$(case_dir listsingle)"
classified "$D" instance.xml
images "$D" 1-185
contexts "$D" 1-185
run "$D" list classification.tsv KEY 1-185=code
exits 2
no_output

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
