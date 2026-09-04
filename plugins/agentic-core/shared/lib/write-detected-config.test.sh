#!/usr/bin/env bash
# Tests for write-detected-config.sh. Run with:
#   bash plugins/agentic-core/shared/lib/write-detected-config.test.sh
#
# No framework — exits 0 on success, 1 on first failure. Mirrors the harness
# in validate-project-config.test.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/write-detected-config.sh"
VALIDATOR="$SCRIPT_DIR/validate-project-config.sh"

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3" output="$4"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected exit=$expected, got exit=$actual"
    [[ -n "$output" ]] && echo "    output: $output"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    expected output to contain: $needle"
    echo "    got: $haystack"
  fi
}

assert_file_equals() {
  local desc="$1" expected="$2" path="$3"
  local actual
  actual="$(cat "$path" 2>/dev/null || echo "<no file>")"
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    --- expected ---"
    echo "$expected"
    echo "    --- actual ---"
    echo "$actual"
  fi
}

TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/write-detected-config-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== write-detected-config.sh tests ==="

echo "[create] fresh file gets version + commands + paths, nothing else"
CFG="$TMPDIR_TEST/fresh.yaml"
OUT=$(bash "$WRITER" "$CFG" "run lint" "run tests" "" "start server" "specs" "http://localhost:3000/preview" 2>&1); ST=$?
assert_exit "fresh create succeeds (exit 0)" 0 $ST "$OUT"
assert_contains "reports the path written" "$CFG" "$OUT"
EXPECTED_FRESH='version: 1

commands:
  lint: "run lint"
  test: "run tests"
  build: ""
  serve: "start server"

paths:
  spec_dir: "specs"
  preview: "http://localhost:3000/preview"'
assert_file_equals "fresh file matches expected shape exactly" "$EXPECTED_FRESH" "$CFG"

echo "[cross-check] generated commands+paths splice into a full config that passes the Task 4 validator"
COMBINED="$TMPDIR_TEST/combined.yaml"
{
  echo "version: 1"
  echo
  echo "packs:"
  echo "  platform: example-platform"
  echo "  tracker: example-tracker"
  echo "  scm: example-scm"
  echo "  design: none"
  echo "  browser: example-browser"
  echo
  sed -n '/^commands:$/,$p' "$CFG"
  echo
  echo "routes:"
  echo "  - id: standard"
  echo "    stages: [intake, deliver]"
  echo "  default: standard"
  echo
  echo "limits:"
  echo "  questions_per_run: 3"
  echo "  fix_attempts_default: 2"
} > "$COMBINED"
OUT=$(bash "$VALIDATOR" "$COMBINED" 2>&1); ST=$?
assert_exit "spliced file passes validate-project-config.sh (exit 0)" 0 $ST "$OUT"

echo "[update] re-running on an existing file updates values in place, no duplication"
OUT=$(bash "$WRITER" "$CFG" "run lint --fix" "run tests" "run build" "start server" "specs" "http://localhost:3000/preview" 2>&1); ST=$?
assert_exit "update succeeds (exit 0)" 0 $ST "$OUT"
assert_contains "reports updated, not written" "updated" "$OUT"
EXPECTED_UPDATED='version: 1

commands:
  lint: "run lint --fix"
  test: "run tests"
  build: "run build"
  serve: "start server"

paths:
  spec_dir: "specs"
  preview: "http://localhost:3000/preview"'
assert_file_equals "updated file has new values, same shape, no dup blocks" "$EXPECTED_UPDATED" "$CFG"

echo "[reject] empty spec_dir"
CFG2="$TMPDIR_TEST/empty-spec-dir.yaml"
OUT=$(bash "$WRITER" "$CFG2" "" "" "" "" "" "http://localhost:3000/preview" 2>&1); ST=$?
assert_exit "empty spec_dir rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names spec_dir" "spec_dir" "$OUT"
if [[ -f "$CFG2" ]]; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: no file written on rejection"
else
  PASS=$((PASS + 1))
  echo "  ok: no file written on rejection"
fi

echo "[reject] empty preview"
CFG3="$TMPDIR_TEST/empty-preview.yaml"
OUT=$(bash "$WRITER" "$CFG3" "" "" "" "" "specs" "" 2>&1); ST=$?
assert_exit "empty preview rejected (exit 1)" 1 $ST "$OUT"
assert_contains "reason names preview" "preview" "$OUT"

echo "[reject] a value containing a double quote"
CFG4="$TMPDIR_TEST/bad-quote.yaml"
OUT=$(bash "$WRITER" "$CFG4" 'run "lint"' "" "" "" "specs" "http://localhost:3000/preview" 2>&1); ST=$?
assert_exit "quote-containing value rejected (exit 1)" 1 $ST "$OUT"

echo "[usage] wrong argument count"
OUT=$(bash "$WRITER" "$TMPDIR_TEST/x.yaml" "only-one-value" 2>&1); ST=$?
assert_exit "wrong arg count -> usage error (exit 2)" 2 $ST "$OUT"

echo "[create] parent directory does not exist yet — script creates it"
CFG6="$TMPDIR_TEST/nested/dir/config.yaml"
OUT=$(bash "$WRITER" "$CFG6" "run lint" "" "" "" ".ai/specs" "http://localhost:3000/preview" 2>&1); ST=$?
assert_exit "create under a missing parent directory succeeds (exit 0)" 0 $ST "$OUT"
if [[ -f "$CFG6" ]]; then
  PASS=$((PASS + 1))
  echo "  ok: file exists under the newly created parent directory"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: file was not created under the newly created parent directory"
fi

echo "[reject] existing file missing commands:/paths: blocks"
CFG5="$TMPDIR_TEST/no-blocks.yaml"
cat > "$CFG5" <<'EOF'
version: 1

packs:
  platform: example-platform
  tracker: example-tracker
  scm: example-scm
  design: none
  browser: example-browser
EOF
OUT=$(bash "$WRITER" "$CFG5" "a" "b" "c" "d" "specs" "http://localhost:3000/preview" 2>&1); ST=$?
assert_exit "malformed existing file rejected (exit 1)" 1 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
