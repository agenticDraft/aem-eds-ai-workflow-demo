#!/usr/bin/env bash
# Tests for rewrite-core-refs.sh. Run with:
#   bash plugins/agentic-core/shared/lib/rewrite-core-refs.test.sh
#
# No framework — exits 0 when every case passes, 1 otherwise. Every plugin is
# built in a temp dir; the core there has a made-up folder name, so a pass
# proves the script reads that name from the pack's link, never from a literal.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REWRITE="$SCRIPT_DIR/rewrite-core-refs.sh"

PASS=0
FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; shift; for l in "$@"; do echo "    $l"; done; FAIL=$((FAIL + 1)); }
assert_eq() { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2" "got: $3"; fi; }
assert_has() { if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else bad "$1" "expected to contain: $2" "got: $3"; fi; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/rewrite-core-refs.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
WORK=$(cd "$WORK" && pwd -P)

[ -f "$REWRITE" ] || { echo "  FAIL: rewrite-core-refs.sh does not exist"; echo; echo "=== 0 passed, 1 failed ==="; exit 1; }

run() { OUT=$(bash "$REWRITE" "$@" 2>"$WORK/err"); CODE=$?; ERR=$(cat "$WORK/err"); }
# tree <dir> — a checksum of every regular file under <dir>, links not followed
tree() { (cd "$1" && find . -type f | LC_ALL=C sort | xargs cksum); }

# core <plugins dir> — a core named the-core, with the files the packs reference
core() {
  mkdir -p "$1/the-core/shared/lib"
  echo "# envelope" > "$1/the-core/shared/result-envelope.md"
  echo "# taxonomy" > "$1/the-core/shared/audit-taxonomy.md"
  printf '#!/usr/bin/env bash\n' > "$1/the-core/shared/lib/emit-envelope.sh"
  # a core file that names its own path: under a pack's link, never rewritten
  echo "see ../the-core/shared/result-envelope.md" > "$1/the-core/shared/self.md"
}

# ---------------------------------------------------------------------------
P="$WORK/one/plugins"
core "$P"
PACK="$P/a-pack"
mkdir -p "$PACK/skills/s1/scripts" "$PACK/shared/scripts" "$PACK/hooks"
ln -s ../the-core/shared "$PACK/core"

cat > "$PACK/skills/s1/SKILL.md" <<'EOF'
Read `../../../the-core/shared/result-envelope.md` and `../../../the-core/shared/audit-taxonomy.md`.
Run `${CLAUDE_PLUGIN_ROOT}/../the-core/shared/lib/emit-envelope.sh`.
A wrapped one (`../../../the-core/shared/audit-
   taxonomy.md`'s example).
Then run `../../../the-core/shared/
lib/emit-envelope.sh . <file>`.
Untouched: the-core plugin's `shared/result-envelope.md`.
Attempt `../../../the-core/shared/lib/emit-envelope.sh
   .ai/next-argument.yaml` with every pair.
EOF
cat > "$PACK/skills/s1/scripts/x.sh" <<'EOF'
EMITTER="$SCRIPT_DIR/../../../../the-core/shared/lib/emit-envelope.sh"
EOF
cat > "$PACK/shared/scripts/y.sh" <<'EOF'
CORE_LIB="$SCRIPT_DIR/../../../the-core/shared/lib"
EOF
cat > "$PACK/hooks/hooks.json" <<'EOF'
{"args": ["${CLAUDE_PLUGIN_ROOT}/../the-core/shared/lib/emit-envelope.sh"]}
EOF
cat > "$PACK/README.md" <<'EOF'
$ bash plugins/the-core/shared/lib/emit-envelope.sh x
EOF
cat > "$PACK/notes.txt" <<'EOF'
# (see ../the-core/shared/audit-taxonomy.md)
EOF
CORE_BEFORE=$(tree "$P/the-core")

echo "=== rewrite-core-refs.sh tests ==="

echo "[dry run] counts what it would rewrite, writes nothing"
BEFORE=$(tree "$PACK")
run --dry-run "$PACK"
assert_eq "exit 0" "0" "$CODE"
assert_eq "no file changed" "$BEFORE" "$(tree "$PACK")"
assert_has "md counted" "md: files=2 lines=6" "$OUT"
assert_has "the total" "total: files=6 lines=10" "$OUT"

echo "[write] every form, rewritten"
run "$PACK"
assert_eq "exit 0" "0" "$CODE"
assert_eq "nothing on stderr" "" "$ERR"
assert_has "md: two files, six lines" "md: files=2 lines=6" "$OUT"
assert_has "sh: two files, two lines" "sh: files=2 lines=2" "$OUT"
assert_has "json: one file, one line" "json: files=1 lines=1" "$OUT"
assert_has "txt: one file, one line" "txt: files=1 lines=1" "$OUT"
assert_has "the total" "total: files=6 lines=10" "$OUT"
assert_eq "bare relative, two on one line" \
  'Read `${CLAUDE_PLUGIN_ROOT}/core/result-envelope.md` and `${CLAUDE_PLUGIN_ROOT}/core/audit-taxonomy.md`.' \
  "$(sed -n 1p "$PACK/skills/s1/SKILL.md")"
assert_eq "plugin root, one up" 'Run `${CLAUDE_PLUGIN_ROOT}/core/lib/emit-envelope.sh`.' "$(sed -n 2p "$PACK/skills/s1/SKILL.md")"
assert_eq "a path wrapped after a hyphen" 'A wrapped one (`${CLAUDE_PLUGIN_ROOT}/core/audit-' "$(sed -n 3p "$PACK/skills/s1/SKILL.md")"
assert_eq "a path wrapped after a slash" 'Then run `${CLAUDE_PLUGIN_ROOT}/core/' "$(sed -n 5p "$PACK/skills/s1/SKILL.md")"
assert_eq "prose naming the core, untouched" 'Untouched: the-core plugin'"'"'s `shared/result-envelope.md`.' "$(sed -n 7p "$PACK/skills/s1/SKILL.md")"
assert_eq "a whole path at a line end is not joined to the next line" \
  'Attempt `${CLAUDE_PLUGIN_ROOT}/core/lib/emit-envelope.sh' "$(sed -n 8p "$PACK/skills/s1/SKILL.md")"
assert_eq "script dir, four up → three up" 'EMITTER="$SCRIPT_DIR/../../../core/lib/emit-envelope.sh"' "$(cat "$PACK/skills/s1/scripts/x.sh")"
assert_eq "script dir, three up → two up" 'CORE_LIB="$SCRIPT_DIR/../../core/lib"' "$(cat "$PACK/shared/scripts/y.sh")"
assert_eq "hook entry" '{"args": ["${CLAUDE_PLUGIN_ROOT}/core/lib/emit-envelope.sh"]}' "$(cat "$PACK/hooks/hooks.json")"
assert_eq "plugins-relative, through the pack's own link" '$ bash plugins/a-pack/core/lib/emit-envelope.sh x' "$(cat "$PACK/README.md")"
assert_eq "bare relative at the pack root" '# (see ${CLAUDE_PLUGIN_ROOT}/core/audit-taxonomy.md)' "$(cat "$PACK/notes.txt")"
assert_eq "the rewritten script dir path exists" "yes" \
  "$( [ -f "$PACK/skills/s1/scripts/../../../core/lib/emit-envelope.sh" ] && echo yes || echo no)"
assert_eq "the core itself, untouched (the link is not followed)" "$CORE_BEFORE" "$(tree "$P/the-core")"

echo "[idempotent] a second run finds nothing"
run "$PACK"
assert_eq "exit 0" "0" "$CODE"
assert_has "total zero" "total: files=0 lines=0" "$OUT"

# ---------------------------------------------------------------------------
echo "[refused] a new path that does not exist → exit 1, nothing written"
P2="$WORK/two/plugins"
core "$P2"
mkdir -p "$P2/b-pack/skills/s"
ln -s ../the-core/shared "$P2/b-pack/core"
printf 'Read `../../../the-core/shared/result-envelope.md`.\nRead `../../../the-core/shared/missing.md`.\n' > "$P2/b-pack/skills/s/SKILL.md"
BEFORE=$(tree "$P2/b-pack")
run "$P2/b-pack"
assert_eq "exit 1" "1" "$CODE"
assert_has "names the file and line" "skills/s/SKILL.md:2" "$ERR"
assert_has "names the missing path" "core/missing.md" "$ERR"
assert_eq "no file changed, the good line included" "$BEFORE" "$(tree "$P2/b-pack")"

echo "[refused] a relative path that does not reach the core → exit 1"
printf 'Read `../../the-core/shared/result-envelope.md`.\n' > "$P2/b-pack/skills/s/SKILL.md"
run "$P2/b-pack"
assert_eq "exit 1" "1" "$CODE"
assert_has "says it does not reach the core" "does not reach the core" "$ERR"

echo "[refused] an anchor it cannot place → exit 1"
printf 'X="$OTHER/../the-core/shared/result-envelope.md"\n' > "$P2/b-pack/skills/s/SKILL.md"
run "$P2/b-pack"
assert_eq "exit 1" "1" "$CODE"
assert_has "names the anchor" 'OTHER' "$ERR"

echo "[usage] no core link → exit 2"
mkdir -p "$P2/c-pack"
run "$P2/c-pack"
assert_eq "exit 2" "2" "$CODE"
assert_has "says the link is missing" "no core link" "$ERR"

echo "[usage] core is a folder, not a link → exit 2"
mkdir -p "$P2/d-pack/core"
run "$P2/d-pack"
assert_eq "exit 2" "2" "$CODE"
assert_has "says the link is missing" "no core link" "$ERR"

echo "[usage] no argument → exit 2"
run
assert_eq "exit 2" "2" "$CODE"

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
