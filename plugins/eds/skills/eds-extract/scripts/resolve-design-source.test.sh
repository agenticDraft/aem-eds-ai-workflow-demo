#!/usr/bin/env bash
# Tests for resolve-design-source.py. Run with:
#   bash plugins/eds/skills/eds-extract/scripts/resolve-design-source.test.sh
#
# No framework — exits 0 on success, 1 on first failure. Inputs are built in a
# temporary directory per case rather than checked in, because every one of
# them is three files whose only interesting content is one or two fields.
#
# Two invariants are asserted on EVERY decision case, not just the new one:
# exactly one `decision=` line on stdout, and exit 0. Callers depend on both,
# and the change that added the fallback fields is exactly the kind that can
# break them by appending a second line.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-design-source.py"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/resolve-design-source.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; }

# fixture <name> <design_source> <spec-text> <attachment-json-array>
# Writes the three input files for one case and echoes the case directory.
fixture() {
  local name="$1" design_source="$2" spec="$3" attachments="$4"
  local dir="$WORK/$name"
  mkdir -p "$dir"
  printf 'item_key: TEST-1\ndesign_source: %s\ndesign_mentioned: %s\n' \
    "$design_source" "$design_source" > "$dir/fact-record.yaml"
  printf '%s\n' "$spec" > "$dir/sanitized-spec.md"
  printf '{"fields":{"attachment":%s}}\n' "$attachments" > "$dir/fetched-item.json"
  echo "$dir"
}

ONE_IMAGE='[{"filename":"ref.png","content":"https://tracker.example/attach/1","mimeType":"image/png"}]'
TWO_IMAGES='[{"filename":"a.png","content":"https://tracker.example/attach/1","mimeType":"image/png"},{"filename":"b.png","content":"https://tracker.example/attach/2","mimeType":"image/jpeg"}]'
NO_IMAGES='[]'
NON_IMAGE='[{"filename":"spec.pdf","content":"https://tracker.example/attach/9","mimeType":"application/pdf"}]'
DESIGN_URL='See https://www.figma.com/design/abc123/Mock?node-id=1-1043 for the target.'
NO_URL='Make the button green.'

# run <case-dir> -- echoes stdout, sets RUN_STATUS and RUN_LINES
run() {
  RUN_OUT="$(python3 "$RESOLVER" "$1/fact-record.yaml" "$1/sanitized-spec.md" "$1/fetched-item.json" 2>/dev/null)"
  RUN_STATUS=$?
  RUN_LINES="$(printf '%s' "$RUN_OUT" | grep -c '^decision=')"
}

# assert_decision <desc> <case-dir> <expected full stdout line>
assert_decision() {
  local desc="$1" dir="$2" expected="$3"
  run "$dir"
  if [[ "$RUN_STATUS" != 0 ]]; then
    bad "$desc" "expected exit 0, got $RUN_STATUS" "output: $RUN_OUT"; return
  fi
  if [[ "$RUN_LINES" != 1 ]]; then
    bad "$desc" "expected exactly one decision= line, got $RUN_LINES" "output: $RUN_OUT"; return
  fi
  if [[ "$RUN_OUT" != "$expected" ]]; then
    bad "$desc" "expected: $expected" "got:      $RUN_OUT"; return
  fi
  ok "$desc"
}

echo "=== resolve-design-source.py tests ==="

echo "[url] the decision this task changes"
assert_decision "url + exactly one image attachment appends the three fallback fields" \
  "$(fixture url-one true "$DESIGN_URL" "$ONE_IMAGE")" \
  "decision=url reference=https://www.figma.com/design/abc123/Mock?node-id=1-1043 fallback_image=ref.png fallback_url=https://tracker.example/attach/1 fallback_mime=image/png"

assert_decision "url + no attachments leaves the line unchanged" \
  "$(fixture url-none true "$DESIGN_URL" "$NO_IMAGES")" \
  "decision=url reference=https://www.figma.com/design/abc123/Mock?node-id=1-1043"

assert_decision "url + several image attachments leaves the line unchanged, never a guess" \
  "$(fixture url-many true "$DESIGN_URL" "$TWO_IMAGES")" \
  "decision=url reference=https://www.figma.com/design/abc123/Mock?node-id=1-1043"

assert_decision "url + a non-image attachment leaves the line unchanged" \
  "$(fixture url-pdf true "$DESIGN_URL" "$NON_IMAGE")" \
  "decision=url reference=https://www.figma.com/design/abc123/Mock?node-id=1-1043"

echo "[unchanged] every decision that existed before this task"
assert_decision "decline — neither design_source nor design_mentioned" \
  "$(fixture decline false "$NO_URL" "$ONE_IMAGE")" \
  "decision=decline"

assert_decision "image — one attachment, no design URL" \
  "$(fixture image true "$NO_URL" "$ONE_IMAGE")" \
  "decision=image filename=ref.png content_url=https://tracker.example/attach/1 mime=image/png"

assert_decision "ambiguous — several attachments, no design URL" \
  "$(fixture ambiguous true "$NO_URL" "$TWO_IMAGES")" \
  "decision=ambiguous count=2 filenames=a.png,b.png"

assert_decision "missing — design wanted, no URL and no image" \
  "$(fixture missing true "$NO_URL" "$NO_IMAGES")" \
  "decision=missing"

assert_decision "missing — a non-image attachment is not a design source" \
  "$(fixture missing-pdf true "$NO_URL" "$NON_IMAGE")" \
  "decision=missing"

echo "[robustness] a malformed fetched item is not a crash"
assert_decision "unparseable fetched-item.json falls through to the no-attachment path" \
  "$(dir="$(fixture broken true "$NO_URL" "$NO_IMAGES")"; printf 'not json at all' > "$dir/fetched-item.json"; echo "$dir")" \
  "decision=missing"

echo "[usage] the two non-zero exits"
python3 "$RESOLVER" only-one-arg >/dev/null 2>&1
[[ $? == 2 ]] && ok "wrong argument count -> exit 2" || bad "wrong argument count -> exit 2" "got exit $?"

python3 "$RESOLVER" "$WORK/nope.yaml" "$WORK/nope.md" "$WORK/nope.json" >/dev/null 2>&1
[[ $? == 2 ]] && ok "missing fact record -> exit 2" || bad "missing fact record -> exit 2" "got exit $?"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
