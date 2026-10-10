#!/usr/bin/env bash
# preview-url.test.sh — the PR preview-URL decision (G31, D129). No framework;
# exits 0 when every case passes, 1 otherwise. The host suffix and the branch
# limit come from fixture configs built in a temp dir; nothing is read from the
# repository the suite sits in.
#
# Usage:
#   bash preview-url.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/preview-url.sh"
BRANCH_CHECK="$SCRIPT_DIR/check-branch-length.sh"

PASS=0
FAIL=0

ok()  { echo "  ok: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_eq()  { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $2 — got: $3"; fi; }
assert_has() { if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "expected to contain: $2 — got: $3"; fi; }

name_of_length() { printf 'b%.0s' $(seq 1 "$1"); }

WORK=$(TMPDIR="${TMPDIR:-/tmp}" mktemp -d "${TMPDIR:-/tmp}/preview-url.XXXXXX")
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
  echo "cannot create a temporary directory"; exit 1
fi
trap 'rm -rf "$WORK"' EXIT

# repo_with <file>… — a fresh repository whose main has one commit and whose
# HEAD is a branch adding the named files
repo_with() {
  local dir="$WORK/repo-$RANDOM$RANDOM"
  git init -q -b main "$dir"
  git -C "$dir" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  git -C "$dir" switch -q -c work
  local f
  for f in "$@"; do
    mkdir -p "$dir/$(dirname "$f")"
    echo x > "$dir/$f"
  done
  git -C "$dir" add -A
  git -C "$dir" -c user.email=t@t -c user.name=t commit -q -m change
  echo "$dir"
}

# A fixture project's own values: a 40-character host suffix, so a limit of 23.
SUFFIX="--a-fixture-site-repository--fixture-org"
CONFIG="$WORK/config.yaml"
printf 'version: 1\n\nbranch_name:\n  max_length: 23\n\nplatform:\n  preview_host_suffix: "%s"\n' "$SUFFIX" > "$CONFIG"
HOST_SUFFIX="$SUFFIX.aem.page"

# run <dir> <args>… — with the fixture config; stdout into OUT, stderr into
# ERR, exit code into CODE
run() {
  local dir="$1"; shift
  run_bare "$dir" "$@" --config "$CONFIG"
}
# run_bare <dir> <args>… — as run, with no --config added
run_bare() {
  local dir="$1"; shift
  OUT=$(cd "$dir" && bash "$SCRIPT" "$@" 2>"$WORK/err"); CODE=$?
  ERR=$(cat "$WORK/err")
}

echo "[served] a block change on a short branch gets the URL"
D=$(repo_with blocks/cards/cards.css)
run "$D" --branch psi-preview-url --base main
assert_eq "exit 0" "0" "$CODE"
assert_has "pr-type served" "pr-type: served" "$ERR"
assert_eq "body carries the URL block" \
  "$(printf 'URL for testing:\n\n- https://psi-preview-url%s/' "$HOST_SUFFIX")" "$OUT"

echo "[served] every served root counts"
for f in blocks/a/a.js styles/styles.css scripts/scripts.js fonts/x.woff2 icons/x.svg \
         tools/sidekick/config.json head.html 404.html favicon.ico; do
  D=$(repo_with "$f")
  run "$D" --branch short --base main
  assert_has "$f → served" "pr-type: served" "$ERR"
done

echo "[automation-only] no served path → no URL"
D=$(repo_with plugins/eds/skills/eds-deliver/SKILL.md .github/workflows/x.yaml docs/x.md)
run "$D" --branch psi-preview-url --base main
assert_eq "exit 0" "0" "$CODE"
assert_has "pr-type automation-only" "pr-type: automation-only" "$ERR"
assert_eq "no body text" "" "$OUT"

echo "[served] an uncommitted edit and an untracked file both count"
D=$(repo_with plugins/x.sh)
mkdir -p "$D/blocks/new" && echo x > "$D/blocks/new/new.js"
run "$D" --branch short --base main
assert_has "untracked block → served" "pr-type: served" "$ERR"
D=$(repo_with plugins/x.sh styles/styles.css)
git -C "$D" -c user.email=t@t -c user.name=t commit -q --amend -m change -- plugins/x.sh 2>/dev/null
git -C "$D" rm -q --cached styles/styles.css 2>/dev/null
git -C "$D" -c user.email=t@t -c user.name=t commit -q -m untrack
git -C "$D" add styles/styles.css
run "$D" --branch short --base main
assert_has "staged, uncommitted style → served" "pr-type: served" "$ERR"

echo "[automation-only] a Markdown file under a served root is not served (.hlxignore: *.md)"
D=$(repo_with blocks/cards/README.md AGENTS.project.md)
run "$D" --branch short --base main
assert_has "Markdown only → automation-only" "pr-type: automation-only" "$ERR"
assert_eq "no body text" "" "$OUT"

echo "[automation-only] a root outside the served list is not served"
D=$(repo_with triggers/x.yaml)
run "$D" --branch short --base main
assert_has "triggers/ → automation-only" "pr-type: automation-only" "$ERR"

echo "[automation-only] wins over a long branch — the type is not branch-too-long"
D=$(repo_with plugins/x.sh)
run "$D" --branch "$(name_of_length 40)" --base main
assert_has "automation-only" "pr-type: automation-only" "$ERR"
assert_eq "no body text" "" "$OUT"

echo "[length] 23 characters → label 63 → URL; 24 → label 64 → no URL"
D=$(repo_with blocks/cards/cards.js)
run "$D" --branch "$(name_of_length 23)" --base main
assert_has "23 → served" "pr-type: served" "$ERR"
assert_has "23 → URL" "https://$(name_of_length 23)$HOST_SUFFIX/" "$OUT"
run "$D" --branch "$(name_of_length 24)" --base main
assert_eq "24 → exit 0" "0" "$CODE"
assert_has "24 → branch-too-long" "pr-type: branch-too-long label_length=64 limit=63" "$ERR"
assert_eq "24 → no body text" "" "$OUT"

echo "[length] real over-long branches from G31"
run "$D" --branch phase-9-task-2-trigger-path --base main
assert_has "phase-9-task-2-trigger-path → label 67" "label_length=67" "$ERR"
assert_eq "no body text" "" "$OUT"
run "$D" --branch phase-2-task-1-core-plugin-scaffold --base main
assert_has "phase-2-task-1-core-plugin-scaffold → label 75" "label_length=75" "$ERR"

echo "[length] agrees with D539's checker on every length from 1 to 40"
AGREE=1
for n in $(seq 1 40); do
  B=$(name_of_length "$n")
  run "$D" --branch "$B" --base main
  if bash "$BRANCH_CHECK" "$B" --config "$CONFIG" >/dev/null; then WANT=served; else WANT=branch-too-long; fi
  [[ "$ERR" == *"pr-type: $WANT"* ]] || { AGREE=0; bad "length $n" "check-branch-length says $WANT — got: $ERR"; }
done
[ "$AGREE" -eq 1 ] && ok "1–40 agree"

echo "[slash and case] a slash becomes '-', upper case is lowered"
run "$D" --branch Feature/Cards --base main
assert_has "host label" "https://feature-cards$HOST_SUFFIX/" "$OUT"

echo "[characters] outside a-z 0-9 - (after / → - and lower case) → no URL"
for b in eds_18 eds.18 'eds+18' 'eds@18'; do
  run "$D" --branch "$b" --base main
  assert_has "$b → branch-unsupported" "pr-type: branch-unsupported" "$ERR"
  assert_eq "$b → no body text" "" "$OUT"
done
run "$D" --branch eds-18 --base main
assert_has "eds-18 → served" "pr-type: served" "$ERR"

echo "[errors] usage and an unreadable diff"
run "$D" --base main
assert_eq "no --branch → exit 2" "2" "$CODE"
run "$D" --branch x
assert_eq "no --base → exit 2" "2" "$CODE"
run "$D" --branch x --base no-such-ref
assert_eq "unknown base → exit 3" "3" "$CODE"
assert_eq "unknown base → no body text" "" "$OUT"

echo "[agreement] every name the core accepts, with this pack's pattern and the config's limit, gets a preview URL"
CORE_LIB="$SCRIPT_DIR/../../core/lib"
CORE_CHECK="$CORE_LIB/check-branch-name.sh"
# This pack's name, as its SessionStart hook registers it, from its own manifest.
OWN_NAME=$(jq -r .name "$SCRIPT_DIR/../../.claude-plugin/plugin.json")
. "$CORE_LIB/register-source-tree.sh"
ROOTS="$WORK/roots-project"
register_source_tree "$ROOTS" || bad "the source tree's plugins are registered"
{ printf 'version: 1\n\npacks:\n  platform: %s\n\n' "$OWN_NAME"; sed -n '/^branch_name:/,$p' "$CONFIG"; } > "$WORK/core-config.yaml"
D=$(repo_with blocks/a/a.js)
AGREE=1
CHECKED=0
for b in eds-18 feature/cards psi-preview-url "$(name_of_length 23)" "$(name_of_length 24)" eds_18 eds.18 EDS-18; do
  bash "$CORE_CHECK" "$b" --config "$WORK/core-config.yaml" --project-dir "$ROOTS" >/dev/null 2>&1 || continue
  CHECKED=$((CHECKED + 1))
  run "$D" --branch "$b" --base main
  [[ "$ERR" == *"pr-type: served"* ]] || { AGREE=0; bad "$b accepted but gets no URL" "$ERR"; }
done
[ "$AGREE" -eq 1 ] && [ "$CHECKED" -eq 4 ] && ok "the 4 accepted names all get a URL"
[ "$CHECKED" -eq 4 ] || bad "expected 4 accepted names" "got $CHECKED"

echo "[config] the host is the config's, and its length moves the limit"
printf 'version: 1\n\nplatform:\n  preview_host_suffix: "--site--org"\n' > "$WORK/short.yaml"
D=$(repo_with blocks/a/a.js)
run_bare "$D" --branch "$(name_of_length 52)" --base main --config "$WORK/short.yaml"
assert_has "a 11-character suffix: 52 → label 63 → served" "pr-type: served label_length=63" "$ERR"
assert_has "the URL carries that suffix" "https://$(name_of_length 52)--site--org.aem.page/" "$OUT"
run_bare "$D" --branch "$(name_of_length 53)" --base main --config "$WORK/short.yaml"
assert_has "53 → label 64 → too long" "pr-type: branch-too-long label_length=64" "$ERR"

echo "[config] the default is .ai/project-config.yaml in the current directory"
D=$(repo_with blocks/a/a.js)
mkdir -p "$D/.ai" && cp "$CONFIG" "$D/.ai/project-config.yaml"
run_bare "$D" --branch short --base main
assert_has "served from the project's own config" "pr-type: served" "$ERR"
assert_has "its suffix" "https://short$HOST_SUFFIX/" "$OUT"

echo "[not-configured] a served change with no suffix gets no URL, never a guessed one"
D=$(repo_with blocks/a/a.js)
run_bare "$D" --branch short --base main
assert_eq "no config → exit 4" "4" "$CODE"
assert_has "says not-configured" "pr-type: not-configured key=platform.preview_host_suffix" "$ERR"
assert_eq "no body text" "" "$OUT"
printf 'version: 1\n\nplatform:\n  other: "x"\n' > "$WORK/nosuffix.yaml"
run_bare "$D" --branch short --base main --config "$WORK/nosuffix.yaml"
assert_eq "no preview_host_suffix → exit 4" "4" "$CODE"
for v in '""' '"no-leading-dashes"' '"--Upper--Case"' '"--a.b--c"'; do
  printf 'version: 1\n\nplatform:\n  preview_host_suffix: %s\n' "$v" > "$WORK/badsuffix.yaml"
  run_bare "$D" --branch short --base main --config "$WORK/badsuffix.yaml"
  assert_eq "suffix $v → exit 4" "4" "$CODE"
  assert_eq "suffix $v → no body text" "" "$OUT"
done
printf 'version: 1\n\nother:\n  preview_host_suffix: "--a--b"\n' > "$WORK/elsewhere.yaml"
run_bare "$D" --branch short --base main --config "$WORK/elsewhere.yaml"
assert_eq "read only under platform → exit 4" "4" "$CODE"

echo "[not-configured] an automation-only change needs no suffix"
D=$(repo_with plugins/x.sh)
run_bare "$D" --branch short --base main
assert_eq "exit 0" "0" "$CODE"
assert_has "automation-only" "pr-type: automation-only" "$ERR"

echo "[usage] --config without a path"
run_bare "$D" --branch short --base main --config
assert_eq "exit 2" "2" "$CODE"

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
