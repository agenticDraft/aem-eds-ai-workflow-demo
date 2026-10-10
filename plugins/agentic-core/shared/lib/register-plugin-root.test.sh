#!/usr/bin/env bash
# Tests for register-plugin-root.sh. Run with:
#   bash plugins/agentic-core/shared/lib/register-plugin-root.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Every plugin and
# project is built in a temp dir; the hook's environment is set per call.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTER="$SCRIPT_DIR/register-plugin-root.sh"
RESOLVER="$SCRIPT_DIR/resolve-plugin-root.sh"

PASS=0
FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; FAIL=$((FAIL + 1)); }
assert_eq() { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2" "got: $3"; fi; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/register-plugin-root.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
WORK=$(cd "$WORK" && pwd -P)

[ -f "$REGISTER" ] || { echo "  FAIL: register-plugin-root.sh does not exist"; echo; echo "=== 0 passed, 1 failed ==="; exit 1; }

# plugin <dir> <manifest json> — a plugin root carrying that manifest
plugin() { mkdir -p "$1/.claude-plugin"; printf '%s\n' "$2" > "$1/.claude-plugin/plugin.json"; }
# hook <plugin root> <project dir> — run as a SessionStart hook would, hook input on stdin
hook() {
  OUT=$(printf '{"hook_event_name":"SessionStart","source":"startup","cwd":"%s"}' "$2" \
    | CLAUDE_PLUGIN_ROOT="$1" CLAUDE_PROJECT_DIR="$2" bash "$REGISTER" 2>"$WORK/err"); CODE=$?
  ERR=$(cat "$WORK/err")
}

PROJECT="$WORK/project"
REGISTRY="$PROJECT/.ai/run-context/plugin-roots"
mkdir -p "$PROJECT"

echo "=== register-plugin-root.sh tests ==="

echo "[write] the caller's root, under its manifest name, in a registry that did not exist"
plugin "$WORK/plugins/example-pack" '{"name": "example-pack", "version": "0.1.0"}'
hook "$WORK/plugins/example-pack" "$PROJECT"
assert_eq "exit 0" "0" "$CODE"
assert_eq "nothing on stdout (a SessionStart hook's stdout reaches the model)" "" "$OUT"
assert_eq "nothing on stderr" "" "$ERR"
assert_eq "the file holds the root" "$WORK/plugins/example-pack" "$(cat "$REGISTRY/example-pack" 2>&1)"
assert_eq "no other file in the registry" "example-pack" "$(ls -A "$REGISTRY" 2>&1)"

echo "[name] the name comes from the manifest, never from the folder"
plugin "$WORK/cache/market/named-pack/0.1.0" '{"name": "named-pack"}'
hook "$WORK/cache/market/named-pack/0.1.0" "$PROJECT"
assert_eq "exit 0" "0" "$CODE"
assert_eq "a versioned folder is registered under the plugin's name" "$WORK/cache/market/named-pack/0.1.0" "$(cat "$REGISTRY/named-pack" 2>&1)"
[ ! -e "$REGISTRY/0.1.0" ] && ok "nothing named after the folder" || bad "nothing named after the folder"

echo "[overwrite] a later session replaces an earlier entry"
plugin "$WORK/other/example-pack" '{"name": "example-pack"}'
hook "$WORK/other/example-pack" "$PROJECT"
assert_eq "exit 0" "0" "$CODE"
assert_eq "the newer root wins" "$WORK/other/example-pack" "$(cat "$REGISTRY/example-pack" 2>&1)"

echo "[canonical] a root reached through another spelling is written in canonical form"
ln -s "$WORK/other" "$WORK/other-link"
hook "$WORK/other-link/example-pack" "$PROJECT"
assert_eq "exit 0" "0" "$CODE"
assert_eq "the link is resolved" "$WORK/other/example-pack" "$(cat "$REGISTRY/example-pack" 2>&1)"

echo "[round trip] the resolver reads back what was written"
if [ -f "$RESOLVER" ]; then
  RESOLVED=$(bash "$RESOLVER" example-pack --project-dir "$PROJECT" 2>&1); RC=$?
  assert_eq "resolver exit 0" "0" "$RC"
  assert_eq "resolver prints the registered root" "$WORK/other/example-pack" "$RESOLVED"
else
  bad "resolve-plugin-root.sh does not exist"
fi

echo "[refused] nothing is written when the hook's input is incomplete"
BEFORE=$(ls -A "$REGISTRY")
OUT=$(CLAUDE_PROJECT_DIR="$PROJECT" bash "$REGISTER" </dev/null 2>&1); CODE=$?
[ "$CODE" -ne 0 ] && ok "no CLAUDE_PLUGIN_ROOT → non-zero" || bad "no CLAUDE_PLUGIN_ROOT → non-zero" "exit $CODE"
OUT=$(env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT="$WORK/plugins/example-pack" bash "$REGISTER" </dev/null 2>&1); CODE=$?
[ "$CODE" -ne 0 ] && ok "no CLAUDE_PROJECT_DIR → non-zero" || bad "no CLAUDE_PROJECT_DIR → non-zero" "exit $CODE"
hook "$WORK/no-such-root" "$PROJECT"
[ "$CODE" -ne 0 ] && ok "root that is not a directory → non-zero" || bad "root that is not a directory → non-zero" "exit $CODE"
hook "$WORK/plugins/example-pack" "$WORK/no-such-project"
[ "$CODE" -ne 0 ] && ok "project dir that does not exist → non-zero" || bad "project dir that does not exist → non-zero" "exit $CODE"
[ ! -e "$WORK/no-such-project" ] && ok "a missing project dir is not created" || bad "a missing project dir is not created"
mkdir -p "$WORK/no-manifest"
hook "$WORK/no-manifest" "$PROJECT"
[ "$CODE" -ne 0 ] && ok "no plugin manifest → non-zero" || bad "no plugin manifest → non-zero" "exit $CODE"
plugin "$WORK/no-name" '{"version": "1.0.0"}'
hook "$WORK/no-name" "$PROJECT"
[ "$CODE" -ne 0 ] && ok "manifest without a name → non-zero" || bad "manifest without a name → non-zero" "exit $CODE"
plugin "$WORK/escape" '{"name": "../escape"}'
hook "$WORK/escape" "$PROJECT"
[ "$CODE" -ne 0 ] && ok "a name that is a path → non-zero" || bad "a name that is a path → non-zero" "exit $CODE"
plugin "$WORK/broken" '{"name": '
hook "$WORK/broken" "$PROJECT"
[ "$CODE" -ne 0 ] && ok "manifest that is not JSON → non-zero" || bad "manifest that is not JSON → non-zero" "exit $CODE"
assert_eq "the registry is unchanged by every refusal" "$BEFORE" "$(ls -A "$REGISTRY")"
[ ! -e "$PROJECT/.ai/run-context/escape" ] && ok "nothing written outside the registry" || bad "nothing written outside the registry"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
