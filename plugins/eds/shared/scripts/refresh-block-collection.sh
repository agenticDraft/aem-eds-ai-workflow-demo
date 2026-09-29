#!/usr/bin/env bash
# refresh-block-collection.sh — Rewrites the pinned upstream block collection
# this pack ships (D528): the manifest, every block's vendored files, and the
# upstream license and notices. Run by hand only, never during a run; the
# result goes through a PR. The only script here that needs the network.
#
# Usage:
#   refresh-block-collection.sh <commit> [repo] [dest]
#
#   commit  the upstream commit to pin; a short id is recorded in full
#   repo    default https://github.com/adobe/aem-block-collection.git
#   dest    default ../block-collection beside this script
#
# Writes into <dest>:
#   manifest.txt              repo=, commit=, one block=<name> per upstream
#                             `blocks/<name>/` directory at that commit, sorted
#   LICENSE, NOTICE*          the upstream root's own, byte-identical
#   blocks/<name>/<file>      each block's files at that commit
#
# Everything is built in a temp dir first; <dest> is replaced only once the
# new copy is complete, so a failed refresh leaves the old pin untouched.
#
# Exit codes:
#   0 — refreshed
#   1 — upstream unusable (clone failed, commit unknown, no LICENSE, no blocks)
#   2 — usage error

set -euo pipefail

COMMIT="${1:-}"
REPO="${2:-https://github.com/adobe/aem-block-collection.git}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${3:-$SCRIPT_DIR/../block-collection}"

if [[ -z "$COMMIT" ]]; then
  echo "usage: refresh-block-collection.sh <commit> [repo] [dest]" >&2
  exit 2
fi

die() { echo "refresh-block-collection: $*" >&2; exit 1; }

# `mktemp -d` with an explicit template: bare `mktemp -d` ignores $TMPDIR on macOS.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/block-collection.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
SRC="$STAGE/src"
OUT="$STAGE/out"

git clone --quiet --no-checkout "$REPO" "$SRC" 2>/dev/null || die "cannot clone $REPO"
FULL="$(git -C "$SRC" rev-parse --verify --quiet "$COMMIT^{commit}")" || die "unknown commit $COMMIT"
git -C "$SRC" -c advice.detachedHead=false checkout --quiet "$FULL"

[[ -s "$SRC/LICENSE" ]] || die "no LICENSE at $FULL; its files cannot be redistributed"

mkdir -p "$OUT/blocks"
cp "$SRC/LICENSE" "$OUT/LICENSE"
for n in "$SRC"/NOTICE*; do
  [[ -f "$n" ]] && cp "$n" "$OUT/"
done

names=()
for d in "$SRC"/blocks/*/; do
  [[ -d "$d" ]] || continue
  name="$(basename "$d")"
  [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "unsafe block name upstream: $name"
  cp -R "$d" "$OUT/blocks/$name"
  names+=("$name")
done
[[ ${#names[@]} -gt 0 ]] || die "no blocks/ directories at $FULL"

{
  echo "# Upstream block collection, pinned (D528). Written by"
  echo "# refresh-block-collection.sh — never edit by hand; refresh through a PR."
  echo "repo=$REPO"
  echo "commit=$FULL"
  printf 'block=%s\n' "${names[@]}" | LC_ALL=C sort
} > "$OUT/manifest.txt"

# Swap in the finished copy. <dest> holds only what this script writes.
mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST.old"
[[ -e "$DEST" ]] && mv "$DEST" "$DEST.old"
mv "$OUT" "$DEST"
rm -rf "$DEST.old"

echo "commit=$FULL"
echo "blocks=${#names[@]}"
