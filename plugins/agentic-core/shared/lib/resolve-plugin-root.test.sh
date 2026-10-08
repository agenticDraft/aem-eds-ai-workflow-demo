#!/usr/bin/env bash
# Tests for resolve-plugin-root.sh. Run with:
#   bash plugins/agentic-core/shared/lib/resolve-plugin-root.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. The resolver is
# copied into a temp plugins folder, so its sibling folders are built here and
# no real plugin is read.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/resolve-plugin-root.sh"

PASS=0
FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; FAIL=$((FAIL + 1)); }
assert_eq() { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2" "got: $3"; fi; }
assert_has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "expected to contain: $2" "got: $3" ;; esac; }
assert_lacks() { case "$3" in *"$2"*) bad "$1" "must not contain: $2" "got: $3" ;; *) ok "$1" ;; esac; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/resolve-plugin-root.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
WORK=$(cd "$WORK" && pwd -P)

[ -f "$SOURCE" ] || { echo "  FAIL: resolve-plugin-root.sh does not exist"; echo; echo "=== 0 passed, 1 failed ==="; exit 1; }

PLUGINS="$WORK/plugins"
mkdir -p "$PLUGINS/core-x/shared/lib"
cp "$SOURCE" "$PLUGINS/core-x/shared/lib/resolve-plugin-root.sh"
RESOLVER="$PLUGINS/core-x/shared/lib/resolve-plugin-root.sh"
PROJECT="$WORK/project"
REGISTRY="$PROJECT/.ai/run-context/plugin-roots"
mkdir -p "$REGISTRY"

# entry <name> <content> — a registry file, written as given
entry() { printf '%s\n' "$2" > "$REGISTRY/$1"; }
# run <args…> — resolve with this test's project, capturing stdout and stderr apart
run() {
  OUT=$(bash "$RESOLVER" "$@" --project-dir "$PROJECT" 2>"$WORK/err"); CODE=$?
  ERR=$(cat "$WORK/err")
}

echo "=== resolve-plugin-root.sh tests ==="

echo "[1] a registry entry naming a directory that exists"
mkdir -p "$WORK/elsewhere/example-pack" "$PLUGINS/example-pack"
entry example-pack "$WORK/elsewhere/example-pack"
run example-pack
assert_eq "exit 0" "0" "$CODE"
assert_eq "prints the registered root" "$WORK/elsewhere/example-pack" "$OUT"
assert_eq "nothing on stderr" "" "$ERR"
assert_eq "one line on stdout" "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
echo "    (a sibling folder of the same name exists and is not taken)"

echo "[2] a registry entry naming a directory that does not exist is refused"
mkdir -p "$PLUGINS/stale-pack"
entry stale-pack "$WORK/gone/stale-pack"
run stale-pack
assert_eq "non-zero exit (3)" "3" "$CODE"
assert_eq "nothing on stdout" "" "$OUT"
assert_has "says refused" "refused" "$ERR"
assert_has "names the missing directory" "$WORK/gone/stale-pack" "$ERR"
echo "    (a sibling folder of the same name exists and is not taken)"

echo "[2b] other malformed entries are refused too"
entry empty-pack ""
run empty-pack
assert_eq "empty entry → exit 3" "3" "$CODE"
entry relative-pack "plugins/relative-pack"
mkdir -p "$PROJECT/plugins/relative-pack"
run relative-pack
assert_eq "relative path entry → exit 3" "3" "$CODE"
: > "$WORK/a-file"
entry file-pack "$WORK/a-file"
run file-pack
assert_eq "entry naming a file, not a directory → exit 3" "3" "$CODE"

echo "[3] no registry entry → the sibling folder of the core's plugin root"
mkdir -p "$PLUGINS/sibling-pack"
run sibling-pack
assert_eq "exit 0" "0" "$CODE"
assert_eq "prints the sibling folder" "$PLUGINS/sibling-pack" "$OUT"

echo "[3b] the sibling is taken from the core's real location, not the path it was called through"
mkdir -p "$PLUGINS/linking-pack"
ln -s ../core-x/shared "$PLUGINS/linking-pack/core"
OUT=$(bash "$PLUGINS/linking-pack/core/lib/resolve-plugin-root.sh" sibling-pack --project-dir "$PROJECT" 2>&1); CODE=$?
assert_eq "exit 0 through a link" "0" "$CODE"
assert_eq "the core's sibling, not the linking pack's" "$PLUGINS/sibling-pack" "$OUT"

echo "[4] an unknown name → non-zero, not resolved"
run unknown-pack
assert_eq "exit 1" "1" "$CODE"
assert_eq "nothing on stdout" "" "$OUT"
assert_has "says not resolved" "not resolved" "$ERR"
assert_lacks "never says absent" "absent" "$ERR"
assert_lacks "never claims it is not installed" "installed" "$ERR"

echo "[5] /tmp/<x> and /private/tmp/<x> resolve equal, both directions"
if [ "$(cd /tmp && pwd -P)" = "/private/tmp" ]; then
  case "$WORK" in
    /private/tmp/*)
      ALIAS="${WORK#/private}"
      mkdir -p "$WORK/canon/alias-pack"
      entry alias-pack "$ALIAS/canon/alias-pack"
      run alias-pack
      assert_eq "entry written as /tmp/… → exit 0" "0" "$CODE"
      assert_eq "entry written as /tmp/… → the /private/tmp/… form" "$WORK/canon/alias-pack" "$OUT"
      FIRST="$OUT"
      entry alias-pack "$WORK/canon/alias-pack"
      run alias-pack
      assert_eq "entry written as /private/tmp/… → the same answer" "$FIRST" "$OUT"
      OUT=$(bash "$RESOLVER" alias-pack --project-dir "$ALIAS/project" 2>&1); CODE=$?
      assert_eq "project dir passed as /tmp/… finds the same registry" "$FIRST" "$OUT"
      ;;
    *) bad "the temp dir is not under /private/tmp, so the alias cannot be built" "$WORK" ;;
  esac
else
  echo "  skipped: /tmp and /private/tmp are not the same directory on this machine"
fi

echo "[6] no registry directory at all → not resolved, the sibling fallback is tried"
BARE="$WORK/bare-project"
mkdir -p "$BARE"
OUT=$(bash "$RESOLVER" sibling-pack --project-dir "$BARE" 2>&1); CODE=$?
assert_eq "sibling found without a registry → exit 0" "0" "$CODE"
assert_eq "prints the sibling" "$PLUGINS/sibling-pack" "$OUT"
OUT=$(bash "$RESOLVER" unknown-pack --project-dir "$BARE" 2>&1); CODE=$?
assert_eq "neither → exit 1" "1" "$CODE"
assert_has "says not resolved" "not resolved" "$OUT"
assert_has "names the sibling it tried" "$PLUGINS/unknown-pack" "$OUT"
assert_lacks "never says absent" "absent" "$OUT"
assert_lacks "never claims it is not installed" "installed" "$OUT"

echo "[7] the project dir defaults to CLAUDE_PROJECT_DIR"
OUT=$(cd "$WORK" && CLAUDE_PROJECT_DIR="$PROJECT" bash "$RESOLVER" example-pack 2>&1); CODE=$?
assert_eq "exit 0" "0" "$CODE"
assert_eq "reads that project's registry" "$WORK/elsewhere/example-pack" "$OUT"

echo "[8] usage errors"
for name in "" "../escape" "a/b" "." "Upper"; do
  OUT=$(bash "$RESOLVER" "$name" --project-dir "$PROJECT" 2>&1); CODE=$?
  assert_eq "name '$name' → exit 2" "2" "$CODE"
done
OUT=$(bash "$RESOLVER" 2>&1); CODE=$?
assert_eq "no arguments → exit 2" "2" "$CODE"
OUT=$(bash "$RESOLVER" example-pack --project-dir 2>&1); CODE=$?
assert_eq "--project-dir without a value → exit 2" "2" "$CODE"
OUT=$(bash "$RESOLVER" example-pack --project-dir "$WORK/no-such-project" 2>&1); CODE=$?
assert_eq "project dir that does not exist → exit 2" "2" "$CODE"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
