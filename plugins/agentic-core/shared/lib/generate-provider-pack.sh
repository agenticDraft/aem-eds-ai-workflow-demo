#!/usr/bin/env bash
# generate-provider-pack.sh — Mechanical generator for a provider pack
# skeleton. Given a role, writes the smallest manifest that validates: the
# role declared, no operation implemented, and every operation that role
# owns listed as unsupported.
#
# No judgment involved, and deliberately no operation logic. The skeleton is
# a shell for a later task to fill in one operation at a time, moving each
# name out of `unsupported:` and into `operations:` as its skill appears.
# Until then the manifest tells the truth about a pack that can do nothing:
# pre-flight refuses a route needing any of these operations, by name,
# before the run starts.
#
# `operations: {}` and a full `unsupported:` list is not a degenerate case —
# it is the one honest starting state. A skeleton that declared operations
# it has no skills for would fail validation; one that omitted them would
# fail the completeness rule, which requires every operation of the role to
# appear in exactly one of the two lists.
#
# This script never overwrites. A pack root that already holds a manifest is
# an installed pack, and replacing it would discard operation logic this
# script cannot regenerate. It reports the collision and stops; whether to
# keep, re-detect or edit is a question for the caller to put to a human,
# not for a mechanical generator to decide.
#
# Usage:
#   generate-provider-pack.sh <pack-root> <role>
#
# <role> is one of: tracker scm design browser
#
# Exit codes:
#   0 — success; "written: <pack-root>/pack.yaml" on stdout, followed by one
#       "unsupported: <operation>" line per operation in the skeleton
#   1 — contract violation: an unknown role, an empty pack root, or a
#       manifest already present at <pack-root>
#   2 — usage error: wrong argument count

set -uo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: generate-provider-pack.sh <pack-root> <role>" >&2
  exit 2
fi

PACK_ROOT="$1"
ROLE="$2"

fail() {
  echo "invalid: $1" >&2
  exit 1
}

[[ -z "$PACK_ROOT" ]] && fail "pack root is empty"

# The operation table is the contract's own, per role. It is duplicated from
# the manifest validator on purpose — this script must not depend on that one
# at run time — and the test suite fails if the two ever disagree.
case "$ROLE" in
  tracker) ROLE_OPS=(fetch_item post_note attach_file list_types) ;;
  scm)     ROLE_OPS=(create_branch publish_change check_status) ;;
  design)  ROLE_OPS=(fetch_reference) ;;
  browser) ROLE_OPS=(render capture measure interact) ;;
  *)       fail "unknown role '$ROLE'; expected one of: tracker scm design browser" ;;
esac

if [[ -f "$PACK_ROOT/pack.yaml" ]]; then
  fail "a manifest already exists at '$PACK_ROOT/pack.yaml'; this script never overwrites an installed pack — ask first, then remove it deliberately"
fi

mkdir -p "$PACK_ROOT" || fail "could not create pack root '$PACK_ROOT'"

JOINED=""
for op in "${ROLE_OPS[@]}"; do
  [[ -n "$JOINED" ]] && JOINED+=", "
  JOINED+="$op"
done

{
  printf 'kind: provider\n'
  printf 'role: %s\n' "$ROLE"
  printf 'operations: {}\n'
  printf 'unsupported: [%s]\n' "$JOINED"
} > "$PACK_ROOT/pack.yaml" || fail "could not write '$PACK_ROOT/pack.yaml'"

echo "written: $PACK_ROOT/pack.yaml"
for op in "${ROLE_OPS[@]}"; do
  echo "unsupported: $op"
done
