#!/usr/bin/env bash
# Tests for write-design-reference.py. Run with:
#   bash plugins/eds/skills/eds-extract/scripts/write-design-reference.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Inputs are built
# in a temporary directory per case. Each case runs the script from its own
# case directory, because the provider JSON names its code file relative to the
# project root.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/write-design-reference.py"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/write-design-reference.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# check <desc> <jq filter that must print true> <json file>
check() {
  local desc="$1" filter="$2" file="$3" got
  got="$(jq -r "$filter" "$file" 2>&1)"
  if [ "$got" = "true" ]; then ok "$desc"; else bad "$desc" "filter: $filter" "got: $got"; fi
}

URL='https://www.figma.com/design/abc123/Mock?node-id=1-185'
STYLES='Text/Link: #000000, Accent/Accent 2: #DFECC6.'

# case_dir <name> — a fresh case directory holding a provider image
case_dir() {
  local dir="$WORK/$1"
  mkdir -p "$dir/.ai/figma" "$dir/.ai/run-context"
  printf 'PNG-BYTES' > "$dir/.ai/figma/abc123-1-185.png"
  echo "$dir"
}

# run_design_tool <case-dir> — runs design_tool mode from inside the case dir
run_design_tool() {
  (cd "$1" && python3 "$WRITER" design_tool "$URL" \
    .ai/figma/abc123-1-185.json .ai/figma/abc123-1-185.png \
    .ai/run-context/design-reference.json .ai/run-context/design-reference.png \
    .ai/run-context/design-context.txt >"$1/stdout" 2>"$1/stderr")
}

echo "design_tool: provider JSON with a code block"
D="$(case_dir code)"
# Unfenced code, a trailing space, a tab, a non-ASCII character and no final
# newline: any rewriting on the way through changes at least one byte.
printf 'export default function Button() {\n  return (\n\t<a className="bg-[#dfecc6] px-[22px] py-[14px] rounded-[1000px]" data-node-id="1:185">Discover More \xe2\x80\x94 </a>\n  );\n}' \
  > "$D/.ai/figma/abc123-1-185.context.txt"
jq -n --arg styles "$STYLES" '{
  reference: "x", file_key: "abc123", node_id: "1-185", node_name: "Button",
  geometry: {x: 0, y: 0, width: 138, height: 48},
  variables: {"Accent/Accent 2": "#DFECC6"},
  design_context: {code_file: ".ai/figma/abc123-1-185.context.txt", styles: $styles}
}' > "$D/.ai/figma/abc123-1-185.json"
if run_design_tool "$D"; then ok "exits 0"; else bad "exits 0" "stderr: $(cat "$D/stderr")"; fi
OUT="$D/.ai/run-context/design-reference.json"
if [ -f "$OUT" ]; then
  check "design_context is an object" '.design_context | type == "object"' "$OUT"
  check "code_file names the run-context copy" \
    '.design_context.code_file == ".ai/run-context/design-context.txt"' "$OUT"
  got="$(jq -r '.design_context.styles' "$OUT")"
  if [ "$got" = "$STYLES" ]; then ok "styles carried verbatim"; else bad "styles carried verbatim" "got: $got"; fi
  check "variables still carried" '.variables == {"Accent/Accent 2": "#DFECC6"}' "$OUT"
  check "geometry still carried" '.geometry.width == 138' "$OUT"
  check "has_values stays true" '.has_values == true' "$OUT"
else
  bad "design-reference.json written" "missing: $OUT"
fi
if cmp -s "$D/.ai/figma/abc123-1-185.context.txt" "$D/.ai/run-context/design-context.txt"; then
  ok "design-context.txt is byte-identical to the provider's code"
else
  bad "design-context.txt is byte-identical to the provider's code" \
    "diff: $(diff "$D/.ai/figma/abc123-1-185.context.txt" "$D/.ai/run-context/design-context.txt" 2>&1 | head -5)"
fi

echo "design_tool: provider JSON with design_context: null"
D="$(case_dir null)"
jq -n '{
  reference: "x", file_key: "abc123", node_id: "1-185", node_name: "Button",
  geometry: {x: 0, y: 0, width: 138, height: 48}, variables: {},
  design_context: null
}' > "$D/.ai/figma/abc123-1-185.json"
if run_design_tool "$D"; then ok "exits 0"; else bad "exits 0" "stderr: $(cat "$D/stderr")"; fi
OUT="$D/.ai/run-context/design-reference.json"
if [ -f "$OUT" ]; then
  check "design_context key present and null" 'has("design_context") and .design_context == null' "$OUT"
  check "variables still carried as {}" '.variables == {}' "$OUT"
else
  bad "design-reference.json written" "missing: $OUT"
fi
if [ -e "$D/.ai/run-context/design-context.txt" ]; then
  bad "writes no design-context.txt" "found one"
else
  ok "writes no design-context.txt"
fi

echo "design_tool: provider JSON names a code file that does not exist"
D="$(case_dir missing)"
jq -n '{geometry: {width: 1}, variables: {},
  design_context: {code_file: ".ai/figma/absent.context.txt", styles: null}}' \
  > "$D/.ai/figma/abc123-1-185.json"
run_design_tool "$D"
status=$?
if [ "$status" -eq 2 ]; then ok "exits 2"; else bad "exits 2" "got: $status"; fi
if [ -e "$D/.ai/run-context/design-reference.json" ]; then
  bad "writes no design-reference.json" "found one"
else
  ok "writes no design-reference.json"
fi

echo "image mode"
D="$(case_dir image)"
(cd "$D" && python3 "$WRITER" image design-reference.png image/png \
  .ai/figma/abc123-1-185.png .ai/run-context/design-reference.json >"$D/stdout" 2>"$D/stderr")
status=$?
if [ "$status" -eq 0 ]; then ok "exits 0"; else bad "exits 0" "stderr: $(cat "$D/stderr")"; fi
OUT="$D/.ai/run-context/design-reference.json"
if [ -f "$OUT" ]; then
  check "design_context key present and null" 'has("design_context") and .design_context == null' "$OUT"
  check "variables null, has_values false" '.variables == null and .has_values == false' "$OUT"
else
  bad "design-reference.json written" "missing: $OUT"
fi
if [ -e "$D/.ai/run-context/design-context.txt" ]; then
  bad "writes no design-context.txt" "found one"
else
  ok "writes no design-context.txt"
fi

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
