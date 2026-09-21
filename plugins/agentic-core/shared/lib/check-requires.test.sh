#!/usr/bin/env bash
# Tests for check-requires.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-requires.test.sh
#
# No framework — exits 0 on success, 1 if any case failed.
#
# Every probe in here resolves to a command the test itself creates in a
# temporary directory, or to a name nothing can resolve. Nothing in this
# suite depends on what happens to be installed on the machine running it,
# which is the only way a test of a machine-probing script stays honest.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/check-requires.sh"
TMPDIR_TEST="$(mktemp -d "${TMPDIR:-/tmp}/check-requires-test.XXXXXX")"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

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

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS + 1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"
    echo "    expected output NOT to contain: $needle"
    echo "    got: $haystack"
  fi
}

# A stand-in for an installed tool, and one that always fails, both created
# here so no test depends on the host's own software.
BIN="$TMPDIR_TEST/bin"
mkdir -p "$BIN"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/present-tool"
printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/failing-tool"
chmod +x "$BIN/present-tool" "$BIN/failing-tool"
export PATH="$BIN:$PATH"

echo "=== check-requires.sh tests ==="

echo "[usage]"
OUT=$("$CHECKER" 2>&1); assert_exit "no argument -> usage error" 2 $? "$OUT"
OUT=$("$CHECKER" "$TMPDIR_TEST/nope.yaml" 2>&1); assert_exit "missing file -> usage error" 2 $? "$OUT"

echo "[ok] a manifest declaring no requirements"
NONE="$TMPDIR_TEST/none.yaml"
cat > "$NONE" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
EOF
OUT=$("$CHECKER" "$NONE" 2>&1); RC=$?
assert_exit "absent requires -> exit 0" 0 "$RC" "$OUT"
assert_contains "says there was nothing to check" "no requirements declared" "$OUT"

echo "[ok] every declared tool present"
PRESENT="$TMPDIR_TEST/present.yaml"
cat > "$PRESENT" <<'EOF'
kind: provider
role: browser
operations: {}
unsupported: [render, capture, measure, interact]
requires:
  - tool: present-tool
    probe: [present-tool, --version]
    remedy: "install present-tool"
EOF
OUT=$("$CHECKER" "$PRESENT" 2>&1); RC=$?
assert_exit "present tool -> exit 0" 0 "$RC" "$OUT"
assert_contains "reports it present" "ok: present-tool" "$OUT"
assert_not_contains "says nothing about a remedy when nothing is missing" "install present-tool" "$OUT"

echo "[missing] a tool that is not installed"
ABSENT="$TMPDIR_TEST/absent.yaml"
cat > "$ABSENT" <<'EOF'
kind: provider
role: browser
operations: {}
unsupported: [render, capture, measure, interact]
requires:
  - tool: absent-tool
    probe: [no-such-command-anywhere, --version]
    remedy: "install absent-tool, then download its runtime"
EOF
OUT=$("$CHECKER" "$ABSENT" 2>&1); RC=$?
assert_exit "missing tool -> exit 1" 1 "$RC" "$OUT"
assert_contains "names the tool" "missing: absent-tool" "$OUT"
assert_contains "prints the declared remedy verbatim" "install absent-tool, then download its runtime" "$OUT"
assert_contains "states plainly that nothing was installed" "nothing was installed" "$OUT"

echo "[missing] a probe that resolves but exits non-zero"
FAILING="$TMPDIR_TEST/failing.yaml"
cat > "$FAILING" <<'EOF'
kind: provider
role: browser
operations: {}
unsupported: [render, capture, measure, interact]
requires:
  - tool: half-installed
    probe: [failing-tool, list-runtimes]
    remedy: "download the runtime"
EOF
OUT=$("$CHECKER" "$FAILING" 2>&1); RC=$?
assert_exit "a resolvable command exiting non-zero counts as missing" 1 "$RC" "$OUT"
assert_contains "names it" "missing: half-installed" "$OUT"

echo "[mixed] one present, one missing — both reported, exit reflects the missing one"
MIXED="$TMPDIR_TEST/mixed.yaml"
cat > "$MIXED" <<'EOF'
kind: provider
role: browser
operations: {}
unsupported: [render, capture, measure, interact]
requires:
  - tool: present-tool
    probe: [present-tool, --version]
    remedy: "install present-tool"
  - tool: absent-tool
    probe: [no-such-command-anywhere]
    remedy: "install absent-tool"
EOF
OUT=$("$CHECKER" "$MIXED" 2>&1); RC=$?
assert_exit "any missing -> exit 1" 1 "$RC" "$OUT"
assert_contains "the present one still reports present" "ok: present-tool" "$OUT"
assert_contains "the missing one is named" "missing: absent-tool" "$OUT"
assert_contains "the count is of the missing, over the checked" "1 of 2 declared tools are missing" "$OUT"

echo "[read-only] the remedy is never executed"
# The remedy here would create a file if anything ever ran it. Nothing may.
CANARY="$TMPDIR_TEST/canary-should-not-exist"
SIDE="$TMPDIR_TEST/side-effect.yaml"
cat > "$SIDE" <<EOF
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
requires:
  - tool: absent-tool
    probe: [no-such-command-anywhere]
    remedy: "touch $CANARY"
EOF
OUT=$("$CHECKER" "$SIDE" 2>&1); RC=$?
assert_exit "still just reports" 1 "$RC" "$OUT"
if [[ -e "$CANARY" ]]; then
  FAIL=$((FAIL + 1)); echo "  FAIL: the remedy was executed — it must only ever be printed"
else
  PASS=$((PASS + 1)); echo "  ok: the remedy was printed, not executed"
fi

echo "[read-only] the manifest is not modified"
BEFORE="$(cat "$MIXED")"
"$CHECKER" "$MIXED" >/dev/null 2>&1
assert_contains "manifest unchanged after a run" "$BEFORE" "$(cat "$MIXED")"

echo "[no shell] a probe is argv, so shell syntax is not interpreted"
# If this reached a shell, the redirection would create the file and the
# probe would succeed. As argv, the whole thing is one unresolvable name.
SHELL_CANARY="$TMPDIR_TEST/shell-canary-should-not-exist"
SHELLY="$TMPDIR_TEST/shelly.yaml"
cat > "$SHELLY" <<EOF
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
requires:
  - tool: shell-probe
    probe: [present-tool > $SHELL_CANARY]
    remedy: "install shell-probe"
EOF
OUT=$("$CHECKER" "$SHELLY" 2>&1); RC=$?
assert_exit "shell syntax in a probe does not run -> reported missing" 1 "$RC" "$OUT"
if [[ -e "$SHELL_CANARY" ]]; then
  FAIL=$((FAIL + 1)); echo "  FAIL: the probe reached a shell — redirection took effect"
else
  PASS=$((PASS + 1)); echo "  ok: the probe did not reach a shell"
fi

echo "[pack-relative] a probe may name a script the pack itself ships"
# The point of the <pack>/ prefix: a pack whose "is it present" question
# needs real logic ships that logic, and the probe still runs from anywhere.
OWNPROBE="$TMPDIR_TEST/ownprobe"
mkdir -p "$OWNPROBE/scripts"
printf '#!/usr/bin/env bash\nexit 0\n' > "$OWNPROBE/scripts/probe-ok.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$OWNPROBE/scripts/probe-absent.sh"
chmod +x "$OWNPROBE/scripts/probe-ok.sh" "$OWNPROBE/scripts/probe-absent.sh"
cat > "$OWNPROBE/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
requires:
  - tool: own-probe
    probe: [<pack>/scripts/probe-ok.sh]
    remedy: "install own-probe"
EOF
OUT=$("$CHECKER" "$OWNPROBE/pack.yaml" 2>&1); RC=$?
assert_exit "a <pack>/ probe resolves and runs -> exit 0" 0 "$RC" "$OUT"
assert_contains "reports it present" "ok: own-probe" "$OUT"

# Run it from an unrelated directory: a bare relative path would resolve
# against the caller's cwd, which is exactly what the prefix rules out.
OUT=$(cd "$TMPDIR_TEST" && "$CHECKER" "$OWNPROBE/pack.yaml" 2>&1); RC=$?
assert_exit "resolves against the pack root, not the caller's directory" 0 "$RC" "$OUT"

cat > "$OWNPROBE/pack.yaml" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
requires:
  - tool: own-probe
    probe: [<pack>/scripts/probe-absent.sh]
    remedy: "install own-probe"
EOF
OUT=$("$CHECKER" "$OWNPROBE/pack.yaml" 2>&1); RC=$?
assert_exit "a pack's own probe answering 'absent' is honoured" 1 "$RC" "$OUT"
assert_contains "names the tool" "missing: own-probe" "$OUT"

echo "[malformed] refuses to guess"
BAD="$TMPDIR_TEST/bad.yaml"
cat > "$BAD" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
requires:
  - tool: example-tool
    remedy: "install example-tool"
EOF
OUT=$("$CHECKER" "$BAD" 2>&1); RC=$?
assert_exit "a requires entry with no probe -> usage error" 2 "$RC" "$OUT"
assert_contains "says what is malformed" "has no 'probe:' list" "$OUT"

cat > "$BAD" <<'EOF'
kind: provider
role: design
operations: {}
unsupported: [fetch_reference]
requires:
EOF
OUT=$("$CHECKER" "$BAD" 2>&1); RC=$?
assert_exit "an empty requires block -> usage error" 2 "$RC" "$OUT"

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "=== $PASS passed, 0 failed ==="
  exit 0
fi
echo "=== $PASS passed, $FAIL failed ==="
exit 1
