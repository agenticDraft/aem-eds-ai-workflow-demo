#!/usr/bin/env bash
# Tests for check-own-root-refs.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-own-root-refs.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Every plugin is
# built in a temp dir; only [shipped] reads the real plugins, registered into a
# temp project first. The parent segment is assembled at run time, so this file
# holds no reference of the form it tests.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-own-root-refs.sh"

PASS=0
FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; FAIL=$((FAIL + 1)); }
assert_eq()    { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2" "got: $3"; fi; }
assert_has()   { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "expected to contain: $2" "got: $3" ;; esac; }
assert_lacks() { case "$3" in *"$2"*) bad "$1" "must not contain: $2" "got: $3" ;; *) ok "$1" ;; esac; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-own-root-refs.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

[ -f "$CHECK" ] || { echo "  FAIL: check-own-root-refs.sh does not exist"; echo; echo "=== 0 passed, 1 failed ==="; exit 1; }

UP='..'
BRACED='${CLAUDE_PLUGIN_ROOT}'
BARE='$CLAUDE_PLUGIN_ROOT'

# plugin <folder> <name> — a plugin root whose manifest declares <name>
plugin() {
  mkdir -p "$WORK/$1/.claude-plugin" "$WORK/$1/skills/s"
  printf '{"name": "%s"}\n' "$2" > "$WORK/$1/.claude-plugin/plugin.json"
}
# line <folder> <file> <text> — append one line to a file under that plugin
line() { mkdir -p "$(dirname "$WORK/$1/$2")"; printf '%s\n' "$3" >> "$WORK/$1/$2"; }
run() { OUT=$(bash "$CHECK" "$@" 2>&1); CODE=$?; }

echo "=== check-own-root-refs.sh tests ==="

echo "[valid] a plugin that reaches its own files through its root"
plugin clean clean
line clean skills/s/SKILL.md "Run \`$BRACED/shared/scripts/x.sh\`."
run "$WORK/clean"
assert_eq "exit 0" "0" "$CODE"
assert_has "says valid" "valid" "$OUT"

echo "[invalid] its own name through the parent, braced form"
plugin alpha alpha
line alpha skills/s/SKILL.md "first line"
line alpha skills/s/SKILL.md "Run \`$BRACED/$UP/alpha/shared/x.sh\`."
run "$WORK/alpha"
assert_eq "exit 1" "1" "$CODE"
assert_has "names file and line" "skills/s/SKILL.md:2" "$OUT"
assert_has "says invalid" "invalid" "$OUT"

echo "[invalid] the bare form, in an executed script"
plugin beta beta
line beta shared/run.sh "X=\"$BARE/$UP/beta/lib/y.sh\""
run "$WORK/beta"
assert_eq "exit 1" "1" "$CODE"
assert_has "names the script" "shared/run.sh:1" "$OUT"

echo "[name] the name comes from the manifest, not the folder"
plugin gamma-folder gamma
line gamma-folder skills/s/SKILL.md "Read $BRACED/$UP/gamma/pack.yaml"
run "$WORK/gamma-folder"
assert_eq "manifest name matched → exit 1" "1" "$CODE"
plugin delta-folder delta
line delta-folder skills/s/SKILL.md "Read $BRACED/$UP/delta-folder/pack.yaml"
run "$WORK/delta-folder"
assert_eq "folder name alone is not its name → exit 0" "0" "$CODE"

echo "[scope] another plugin's name is not this check's finding"
plugin eps eps
line eps skills/s/SKILL.md "Read $BRACED/$UP/other-pack/pack.yaml"
run "$WORK/eps"
assert_eq "exit 0" "0" "$CODE"

echo "[scope] a name that only starts with the plugin's name is not matched"
plugin zeta zeta
line zeta skills/s/SKILL.md "Read $BRACED/$UP/zeta-two/pack.yaml"
run "$WORK/zeta"
assert_eq "exit 0" "0" "$CODE"

echo "[links] a linked directory is not followed"
mkdir -p "$WORK/target"
printf '%s\n' "$BRACED/$UP/eta/x" > "$WORK/target/a.md"
plugin eta eta
ln -s ../target "$WORK/eta/core"
run "$WORK/eta"
assert_eq "exit 0" "0" "$CODE"

echo "[many] several roots in one call, each by its own name"
run "$WORK/clean" "$WORK/alpha" "$WORK/beta"
assert_eq "exit 1" "1" "$CODE"
assert_has "alpha reported" "alpha/skills/s/SKILL.md:2" "$OUT"
assert_has "beta reported" "beta/shared/run.sh:1" "$OUT"
assert_has "counts both" "invalid: 2" "$OUT"

echo "[usage]"
run
assert_eq "no argument → exit 2" "2" "$CODE"
run "$WORK/nope"
assert_eq "not a directory → exit 2" "2" "$CODE"
mkdir -p "$WORK/no-manifest"
run "$WORK/no-manifest"
assert_eq "no plugin manifest → exit 2" "2" "$CODE"
mkdir -p "$WORK/no-name/.claude-plugin"
echo '{}' > "$WORK/no-name/.claude-plugin/plugin.json"
run "$WORK/no-name"
assert_eq "manifest without a name → exit 2" "2" "$CODE"

echo "[shipped] every plugin in this source tree, registered in a temp project"
. "$SCRIPT_DIR/register-source-tree.sh"
REAL="$WORK/real-project"
register_source_tree "$REAL"; CODE=$?
assert_eq "the source tree's plugins are registered" "0" "$CODE"
ROOTS=()
while IFS=$'\t' read -r name root; do [ -n "$root" ] && ROOTS+=("$root"); done \
  < <(bash "$SCRIPT_DIR/resolve-plugin-root.sh" --list --project-dir "$REAL")
[ "${#ROOTS[@]}" -gt 1 ] && ok "registered ${#ROOTS[@]} plugins" || bad "expected more than one plugin" "${#ROOTS[@]}"
run "${ROOTS[@]}"
assert_eq "every shipped plugin passes" "0" "$CODE"
assert_lacks "no finding" "invalid" "$OUT"

echo
echo "=== ${PASS} passed, ${FAIL} failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
