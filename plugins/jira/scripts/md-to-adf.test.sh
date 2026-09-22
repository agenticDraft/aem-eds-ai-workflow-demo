#!/usr/bin/env bash
# Tests for md-to-adf.py. Run with:
#   bash plugins/jira/scripts/md-to-adf.test.sh
#
# No framework — exits 0 on success, 1 if anything failed.
#
# These assert on what a detector reads, not on the document that was built.
# A document can be well formed, render correctly and still have lost the one
# property everything downstream depends on: a criterion id starting a line.
# So the round trip is the subject of almost every case here, and the criterion
# count is asserted with the same pattern the authoring checker uses.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONVERTER="$SCRIPT_DIR/md-to-adf.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/md-to-adf-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3" output="$4"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected exit=$expected, got exit=$actual"
    [[ -n "$output" ]] && echo "    output: $output"
  fi
}

assert_equal() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    got:      $actual"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected output to contain: $needle"
    echo "    got: $haystack"
  fi
}

# Flatten a converted document and print it, using the converter's own inverse.
flatten() {
  python3 -c '
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("conv", sys.argv[1])
conv = importlib.util.module_from_spec(spec); spec.loader.exec_module(conv)
sys.stdout.write(conv.to_text(json.load(open(sys.argv[2]))).strip("\n"))
' "$CONVERTER" "$1"
}

# Count criteria the way the authoring checker counts them: its own pattern,
# applied to each stripped line.
count_criteria() {
  python3 -c '
import re, sys
AC = re.compile(r"^AC-(\d+)\b[.)\s]*(.*)$")
text = open(sys.argv[1], encoding="utf-8").read()
print(sum(1 for line in text.split("\n") if AC.match(line.strip())))
' "$1"
}

echo "=== md-to-adf.py tests ==="

# --- usage ------------------------------------------------------------------
OUT="$(python3 "$CONVERTER" 2>&1)"; assert_exit "no arguments -> usage error" 2 $? "$OUT"
OUT="$(python3 "$CONVERTER" "$WORK/absent.md" 2>&1)"
assert_exit "unreadable file -> usage error" 2 $? "$OUT"
printf '\n  \n' > "$WORK/blank.md"
OUT="$(python3 "$CONVERTER" "$WORK/blank.md" 2>&1)"
assert_exit "empty body -> usage error" 2 $? "$OUT"
printf '# x\n' > "$WORK/ok.md"
OUT="$(python3 "$CONVERTER" "$WORK/ok.md" --out 2>&1)"
assert_exit "--out with no path -> usage error" 2 $? "$OUT"

# --- a realistic description -------------------------------------------------
echo "[round trip] a description with headings, wrapped criteria and a bullet list"
cat > "$WORK/body.md" <<'EOF'
## Description

Add a thing at some/path/ so that a second thing becomes possible. This
paragraph wraps across two lines on purpose.

## Acceptance criteria

AC-1 The thing exists.
AC-2 The thing renders, and it does so at every width the project defines,
     which is the part that wraps onto a continuation line.
AC-3 Nothing else changes.

## Out of scope

- The first excluded thing
- The second excluded thing
EOF

python3 "$CONVERTER" "$WORK/body.md" --out "$WORK/body.json"
assert_exit "converts" 0 $? ""
flatten "$WORK/body.json" > "$WORK/body.rt"
assert_equal "flattens back to the input, byte for byte" \
  "$(cat "$WORK/body.md")" "$(cat "$WORK/body.rt")"
assert_equal "criterion count survives" \
  "$(count_criteria "$WORK/body.md")" "$(count_criteria "$WORK/body.rt")"
assert_equal "and that count is 3" "3" "$(count_criteria "$WORK/body.rt")"

echo "[structure] the document is built from real nodes, not one blob"
TYPES="$(python3 -c '
import json, sys
print(",".join(n["type"] for n in json.load(open(sys.argv[1]))["content"]))' "$WORK/body.json")"
assert_equal "node types" \
  "heading,paragraph,heading,paragraph,heading,bulletList" "$TYPES"

echo "[continuation] a wrapped criterion keeps its leading spaces"
assert_contains "the continuation line is preserved verbatim" \
  "     which is the part that wraps onto a continuation line." "$(cat "$WORK/body.rt")"

echo "[continuation] the id line is not joined to the line below it"
JOINED="$(grep -c '^AC-2 The thing renders, and it does so at every width the project defines,$' "$WORK/body.rt")"
assert_equal "AC-2 still ends where the author ended it" "1" "$JOINED"

# --- heading levels ----------------------------------------------------------
echo "[headings] every level survives"
printf '# one\n\n## two\n\n###### six\n' > "$WORK/h.md"
python3 "$CONVERTER" "$WORK/h.md" --out "$WORK/h.json"
flatten "$WORK/h.json" > "$WORK/h.rt"
assert_equal "levels round trip" "$(cat "$WORK/h.md")" "$(cat "$WORK/h.rt")"
LEVELS="$(python3 -c '
import json, sys
print(",".join(str(n["attrs"]["level"]) for n in json.load(open(sys.argv[1]))["content"]))' "$WORK/h.json")"
assert_equal "levels recorded" "1,2,6" "$LEVELS"

# --- things that are not headings --------------------------------------------
echo "[not a heading] a block whose first line looks like one but has more lines"
printf '## still prose\nbecause a heading is one line\n' > "$WORK/n.md"
python3 "$CONVERTER" "$WORK/n.md" --out "$WORK/n.json"
TYPE="$(python3 -c '
import json, sys
print(json.load(open(sys.argv[1]))["content"][0]["type"])' "$WORK/n.json")"
assert_equal "treated as a paragraph" "paragraph" "$TYPE"
flatten "$WORK/n.json" > "$WORK/n.rt"
assert_equal "and still round trips" "$(cat "$WORK/n.md")" "$(cat "$WORK/n.rt")"

# --- the refusal -------------------------------------------------------------
# The guarantee is worth nothing unless a conversion that loses a line is
# actually refused, so this drives the check with a deliberately lossy build.
echo "[refusal] a conversion that drops a line is refused, not emitted"
cat > "$WORK/lossy.py" <<'EOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("conv", sys.argv[1])
conv = importlib.util.module_from_spec(spec); spec.loader.exec_module(conv)

def lossy(block):
    lines = block.split("\n")
    return {"type": "paragraph",
            "content": [{"type": "text", "text": " ".join(lines)}]}

conv.block_to_node = lossy
sys.argv = [sys.argv[0], sys.argv[2]]
sys.exit(conv.main(sys.argv[1:]))
EOF
OUT="$(python3 "$WORK/lossy.py" "$CONVERTER" "$WORK/body.md" 2>&1)"; ST=$?
assert_exit "a reflowing conversion exits 1" 1 $ST "$OUT"
assert_contains "it names the line it changed" "conversion changed line" "$OUT"
assert_contains "it says it will not emit" "refusing to emit" "$OUT"
assert_equal "and nothing was written to stdout" "" "$(python3 "$WORK/lossy.py" "$CONVERTER" "$WORK/body.md" 2>/dev/null)"

if [[ "$FAIL" -eq 0 ]]; then
  echo "=== $PASS passed, 0 failed ==="
  exit 0
fi
echo "=== $PASS passed, $FAIL failed ==="
exit 1
