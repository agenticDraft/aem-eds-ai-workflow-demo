#!/usr/bin/env bash
# Tests for resolve-design-source.py. Run with:
#   bash plugins/eds/skills/eds-extract/scripts/resolve-design-source.test.sh
#
# No framework — exits 0 on success, 1 on first failure. Inputs are built in a
# temporary directory per case rather than checked in, because every one of
# them is three files whose only interesting content is one or two fields.
#
# The attachment cases are a matrix: seven image sets, each run twice — once
# with a design URL in the sanitized text and once without. The two halves
# answer different questions. Without a URL the image set decides the whole
# outcome; with one, the URL is the design source and the image set only
# decides whether a fallback is named.
#
# Two invariants are asserted on EVERY decision case, not just the new ones:
# exactly one `decision=` line on stdout, and exit 0. Callers depend on both.

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

# --- the seven image sets -----------------------------------------------------

# One attachment carrying the reserved name, among several that do not.
RESERVED_AMONG='[{"filename":"capture-a.png","content":"https://tracker.example/attach/1","mimeType":"image/png"},{"filename":"design-reference.png","content":"https://tracker.example/attach/2","mimeType":"image/png"},{"filename":"capture-b.png","content":"https://tracker.example/attach/3","mimeType":"image/png"}]'
# The reserved name and nothing else.
RESERVED_ALONE='[{"filename":"design-reference.png","content":"https://tracker.example/attach/2","mimeType":"image/png"}]'
# The reserved name spelled with different case, and the .jpg spelling.
RESERVED_CASE='[{"filename":"Design-Reference.JPG","content":"https://tracker.example/attach/4","mimeType":"image/jpeg"}]'
# Several images, none of them carrying the reserved name.
UNMARKED_MANY='[{"filename":"capture-a.png","content":"https://tracker.example/attach/1","mimeType":"image/png"},{"filename":"capture-b.png","content":"https://tracker.example/attach/3","mimeType":"image/png"},{"filename":"capture-c.png","content":"https://tracker.example/attach/5","mimeType":"image/png"}]'
# Exactly one image, not carrying the reserved name.
UNMARKED_ONE='[{"filename":"capture-a.png","content":"https://tracker.example/attach/1","mimeType":"image/png"}]'
# Two attachments both carrying a reserved name.
RESERVED_TWO='[{"filename":"design-reference.png","content":"https://tracker.example/attach/2","mimeType":"image/png"},{"filename":"design-reference.jpg","content":"https://tracker.example/attach/6","mimeType":"image/jpeg"}]'
# No images at all.
NO_IMAGES='[]'

# Not part of the matrix: attachments that are not images, and a name that only
# looks reserved.
NON_IMAGE='[{"filename":"design-reference.pdf","content":"https://tracker.example/attach/9","mimeType":"application/pdf"}]'
NEAR_MISS='[{"filename":"design-reference-2.png","content":"https://tracker.example/attach/8","mimeType":"image/png"},{"filename":"my-design-reference.png","content":"https://tracker.example/attach/10","mimeType":"image/png"}]'

DESIGN_URL='See https://www.figma.com/design/abc123/Mock?node-id=1-1043 for the target.'
URL='https://www.figma.com/design/abc123/Mock?node-id=1-1043'
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

echo "[no URL] the image set decides the whole outcome"

assert_decision "reserved name among several images -> that one image" \
  "$(fixture n-among true "$NO_URL" "$RESERVED_AMONG")" \
  "decision=image filename=design-reference.png content_url=https://tracker.example/attach/2 mime=image/png"

assert_decision "reserved name alone -> that image" \
  "$(fixture n-alone true "$NO_URL" "$RESERVED_ALONE")" \
  "decision=image filename=design-reference.png content_url=https://tracker.example/attach/2 mime=image/png"

assert_decision "reserved name in different case -> still that image" \
  "$(fixture n-case true "$NO_URL" "$RESERVED_CASE")" \
  "decision=image filename=Design-Reference.JPG content_url=https://tracker.example/attach/4 mime=image/jpeg"

assert_decision "several images, none reserved -> ambiguous over all of them" \
  "$(fixture n-many true "$NO_URL" "$UNMARKED_MANY")" \
  "decision=ambiguous count=3 filenames=capture-a.png,capture-b.png,capture-c.png"

assert_decision "exactly one image, not reserved -> ambiguous, never assumed" \
  "$(fixture n-one true "$NO_URL" "$UNMARKED_ONE")" \
  "decision=ambiguous count=1 filenames=capture-a.png"

assert_decision "two reserved names at once -> ambiguous over all images" \
  "$(fixture n-two true "$NO_URL" "$RESERVED_TWO")" \
  "decision=ambiguous count=2 filenames=design-reference.png,design-reference.jpg"

assert_decision "no images -> missing" \
  "$(fixture n-zero true "$NO_URL" "$NO_IMAGES")" \
  "decision=missing"

echo "[design URL] the URL is the source; the image set only names a fallback"

assert_decision "reserved name among several images -> url + that fallback" \
  "$(fixture u-among true "$DESIGN_URL" "$RESERVED_AMONG")" \
  "decision=url reference=$URL fallback_image=design-reference.png fallback_url=https://tracker.example/attach/2 fallback_mime=image/png"

assert_decision "reserved name alone -> url + that fallback" \
  "$(fixture u-alone true "$DESIGN_URL" "$RESERVED_ALONE")" \
  "decision=url reference=$URL fallback_image=design-reference.png fallback_url=https://tracker.example/attach/2 fallback_mime=image/png"

assert_decision "reserved name in different case -> url + that fallback" \
  "$(fixture u-case true "$DESIGN_URL" "$RESERVED_CASE")" \
  "decision=url reference=$URL fallback_image=Design-Reference.JPG fallback_url=https://tracker.example/attach/4 fallback_mime=image/jpeg"

assert_decision "several images, none reserved -> url alone, no fallback" \
  "$(fixture u-many true "$DESIGN_URL" "$UNMARKED_MANY")" \
  "decision=url reference=$URL"

assert_decision "exactly one image, not reserved -> url alone, no fallback" \
  "$(fixture u-one true "$DESIGN_URL" "$UNMARKED_ONE")" \
  "decision=url reference=$URL"

assert_decision "two reserved names at once -> url alone, no fallback" \
  "$(fixture u-two true "$DESIGN_URL" "$RESERVED_TWO")" \
  "decision=url reference=$URL"

assert_decision "no images -> url alone" \
  "$(fixture u-zero true "$DESIGN_URL" "$NO_IMAGES")" \
  "decision=url reference=$URL"

echo "[reserved name] what does and does not count as one"

assert_decision "a name that merely contains the reserved stem does not count" \
  "$(fixture near-miss true "$NO_URL" "$NEAR_MISS")" \
  "decision=ambiguous count=2 filenames=design-reference-2.png,my-design-reference.png"

assert_decision "the reserved name on a non-image attachment does not count" \
  "$(fixture non-image true "$NO_URL" "$NON_IMAGE")" \
  "decision=missing"

assert_decision "the reserved name on a non-image attachment names no fallback either" \
  "$(fixture non-image-url true "$DESIGN_URL" "$NON_IMAGE")" \
  "decision=url reference=$URL"

echo "[unchanged] decisions this task does not touch"

assert_decision "decline — neither design_source nor design_mentioned" \
  "$(fixture decline false "$NO_URL" "$RESERVED_ALONE")" \
  "decision=decline"

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
