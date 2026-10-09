#!/usr/bin/env bash
# Tests for check-no-narrative.sh. Run with:
#   bash plugins/agentic-core/shared/lib/check-no-narrative.test.sh
#
# No framework — exits 0 on success, 1 if anything failed.
#
# Half of these cases are near-misses rather than violations. Both rules were
# written, run against the real tree, and found to fire on files that were
# fine — a heading listing input files, and a fixture holding a plausible URL.
# A check that cries wolf gets ignored, so the cases that must NOT fire are
# kept here as the guard against tightening it back into noise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-no-narrative.sh"
FIX="$SCRIPT_DIR/../fixtures/no-narrative"

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

echo "=== check-no-narrative.sh tests ==="

# --- usage ------------------------------------------------------------------
OUT="$(bash "$CHECK" 2>&1)"; assert_exit "no argument -> usage error" 2 $? "$OUT"
OUT="$(bash "$CHECK" "$FIX/does-not-exist" 2>&1)"
assert_exit "root that is not a directory -> usage error" 2 $? "$OUT"
assert_contains "and says so" "not a directory" "$OUT"

# --- the clean case ---------------------------------------------------------
echo "[accept] a shipped file naming only what the repository publishes"
OUT="$(bash "$CHECK" "$FIX/clean" 2>&1)"; ST=$?
assert_exit "accepted (exit 0)" 0 $ST "$OUT"
assert_contains "reports what it scanned" "valid: no narrative" "$OUT"

echo "[a lock file and installed dependencies are not read]"
LOCK_WORK=$(mktemp -d "${TMPDIR:-/tmp}/no-narrative-lock.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[[ -n "$LOCK_WORK" && -d "$LOCK_WORK" ]] || { echo "cannot create a temp dir" >&2; exit 2; }
CITE_WORK=$(mktemp -d "${TMPDIR:-/tmp}/no-narrative-cite.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
[[ -n "$CITE_WORK" && -d "$CITE_WORK" ]] || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$LOCK_WORK" "$CITE_WORK"' EXIT
git init -q "$LOCK_WORK" && printf 'node_modules/\n' > "$LOCK_WORK/.gitignore"
mkdir -p "$LOCK_WORK/core/shared/runner/node_modules/dep"
printf '{ "packages": { "node_modules/dep": { "version": "1.0.0" } } }\n' > "$LOCK_WORK/core/shared/runner/package-lock.json"
printf 'see node_modules/dep/README.md\n' > "$LOCK_WORK/core/shared/runner/node_modules/dep/README.md"
OUT=$(cd "$LOCK_WORK" && bash "$CHECK" "$LOCK_WORK/core" 2>&1); ST=$?
assert_exit "a lock file naming installed paths is accepted (exit 0)" 0 $ST "$OUT"

# --- rule 1 -----------------------------------------------------------------
# The cited path must exist and be ignored in the repository under scan, so the
# case builds its own repository rather than relying on this one's ignored files.
echo "[reject] a shipped file citing a path this repository does not publish"
git init -q "$CITE_WORK/ignored" && printf 'docs/\n' > "$CITE_WORK/ignored/.gitignore"
mkdir -p "$CITE_WORK/ignored/docs/implementation-plan" "$CITE_WORK/ignored/core"
printf 'contracts\n' > "$CITE_WORK/ignored/docs/implementation-plan/01-core-contracts.md"
cp "$FIX/cites-unpublished/cites.md" "$CITE_WORK/ignored/core/"
OUT="$(bash "$CHECK" "$CITE_WORK/ignored/core" 2>&1)"; ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "names the path" "01-core-contracts.md" "$OUT"
assert_contains "says why it matters" "cannot open it" "$OUT"

echo "[accept] the same citation, where the repository publishes the path"
git init -q "$CITE_WORK/published"
mkdir -p "$CITE_WORK/published/docs/implementation-plan" "$CITE_WORK/published/core"
printf 'contracts\n' > "$CITE_WORK/published/docs/implementation-plan/01-core-contracts.md"
cp "$FIX/cites-unpublished/cites.md" "$CITE_WORK/published/core/"
OUT="$(bash "$CHECK" "$CITE_WORK/published/core" 2>&1)"; ST=$?
assert_exit "accepted (exit 0)" 0 $ST "$OUT"

# --- rule 2 -----------------------------------------------------------------
echo "[reject] a shipped file carrying its own rationale section"
OUT="$(bash "$CHECK" "$FIX/provenance-section" 2>&1)"; ST=$?
assert_exit "rejected (exit 1)" 1 $ST "$OUT"
assert_contains "names the section" "Rationale" "$OUT"
assert_contains "says where it belongs" "belongs with the task" "$OUT"

# --- the near-misses --------------------------------------------------------
# Both of these were real false positives before the rules were narrowed, found
# by running the check against the tree rather than by imagining cases.
echo "[accept] a heading that begins with a flagged word but is not a rationale"
OUT="$(bash "$CHECK" "$FIX/near-misses" 2>&1)"; ST=$?
assert_exit "'## Source files' is not flagged (exit 0)" 0 $ST "$OUT"
[[ "$OUT" != *"Source"* ]]
assert_exit "and is not mentioned at all" 0 $? "$OUT"

echo "[accept] a path-shaped string that resolves to nothing is not a citation"
[[ "$OUT" != *"drafts/4001"* ]]
assert_exit "a fixture URL is not flagged" 0 $? "$OUT"

# --- the real tree ----------------------------------------------------------
# The point of the check is the shipped packs, so it runs against them here.
# If this ever fails, the finding is real and belongs in the pack, not here.
echo "[accept] every shipped plugin in this source tree, registered in a temp project"
. "$SCRIPT_DIR/register-source-tree.sh"
REAL_PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/no-narrative-real.XXXXXX")" || { echo "cannot create a temp dir" >&2; exit 2; }
[[ -n "$REAL_PROJECT" && -d "$REAL_PROJECT" ]] || { echo "cannot create a temp dir" >&2; exit 2; }
register_source_tree "$REAL_PROJECT"
assert_exit "the source tree's plugins are registered" 0 $? ""
SEEN=0
while IFS=$'\t' read -r name root; do
  [[ -n "$root" ]] || continue
  SEEN=$((SEEN + 1))
  OUT="$(bash "$CHECK" "$root" 2>&1)"; ST=$?
  assert_exit "$name is clean (exit 0)" 0 $ST "$OUT"
done < <(bash "$SCRIPT_DIR/resolve-plugin-root.sh" --list --project-dir "$REAL_PROJECT")
[[ "$SEEN" -gt 1 ]]
assert_exit "more than one plugin checked ($SEEN)" 0 $? ""
rm -rf "$REAL_PROJECT"

if [[ "$FAIL" -eq 0 ]]; then
  echo "=== $PASS passed, 0 failed ==="
  exit 0
fi
echo "=== $PASS passed, $FAIL failed ==="
exit 1
