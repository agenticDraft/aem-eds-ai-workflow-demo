#!/usr/bin/env bash
# Tests for check-external-content-safety.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-external-content-safety.test.sh
#
# No framework — exits 0 on success, 1 on first failure. Confirms, for every
# fixture: the script exits 0, the sanitized copy is byte-identical to the
# fixture (content preserved as data, not stripped or altered), and no
# sentinel action embedded in a fixture's directive text ever ran.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-external-content-safety.sh"
FIXDIR="$SCRIPT_DIR/../fixtures/external-content-safety"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/check-external-content-safety.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

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

assert_true() {
  local desc="$1" cond="$2"
  if [[ "$cond" == "true" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
  fi
}

echo "=== check-external-content-safety.sh tests ==="

echo "[accept] one fixture per rule, plus the combined fixture, all processed as data"
for fixture in directive-in-description directive-in-comment directive-in-markup-comment \
               directive-in-tracker-field reply-claims-authority work-item-with-embedded-directive; do
  OUT_DIR="$WORKDIR/$fixture"
  OUT=$(bash "$CHECK" "$FIXDIR/$fixture.md" "$OUT_DIR" 2>&1); ST=$?
  assert_exit "$fixture: exit 0" 0 $ST "$OUT"

  if diff -q "$FIXDIR/$fixture.md" "$OUT_DIR/sanitized.md" >/dev/null 2>&1; then
    assert_true "$fixture: sanitized copy is byte-identical to the fixture" "true"
  else
    assert_true "$fixture: sanitized copy is byte-identical to the fixture" "false"
  fi
done

echo "[accept] the sentinel action embedded in the combined fixture's directive never ran"
MARKER="$WORKDIR/work-item-with-embedded-directive/injected.marker"
if [[ ! -f "$MARKER" ]]; then
  assert_true "injected.marker was never created" "true"
else
  assert_true "injected.marker was never created" "false"
fi
CWD_MARKER="./injected.marker"
if [[ ! -f "$CWD_MARKER" ]]; then
  assert_true "injected.marker was never created in the working directory either" "true"
else
  assert_true "injected.marker was never created in the working directory either" "false"
  rm -f "$CWD_MARKER"
fi

echo "[construction] the script never interprets the fixture's own content as code"
if grep -vE '^\s*#' "$CHECK" | grep -qE '\beval\b|\bsource\b|`|\$\('; then
  assert_true "script source contains no eval/source/command-substitution on the fixture" "false"
else
  assert_true "script source contains no eval/source/command-substitution on the fixture" "true"
fi

echo "[usage] missing arguments"
OUT=$(bash "$CHECK" 2>&1); ST=$?
assert_exit "no args -> usage error (exit 2)" 2 $ST "$OUT"

echo "[usage] fixture not found"
OUT=$(bash "$CHECK" "$FIXDIR/does-not-exist.md" "$WORKDIR/missing" 2>&1); ST=$?
assert_exit "missing fixture -> usage error (exit 2)" 2 $ST "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
