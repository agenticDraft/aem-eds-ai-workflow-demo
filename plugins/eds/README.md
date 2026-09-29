# eds

The Edge Delivery pack for `agentic-core`.

## Upstream Block Collection

Before a block is built new, the pack looks it up in a pinned copy of
[`adobe/aem-block-collection`](https://github.com/adobe/aem-block-collection). A block found there
is copied into the project as the starting point, and the work item's changes are applied on top.

### What is stored

`shared/block-collection/`, written only by the refresh script — never edit it by hand:

- `manifest.txt` — the upstream repo, the full pinned commit, one `block=<name>` line per block.
- `blocks/<name>/<name>.css`, `blocks/<name>/<name>.js` — each block's files at that commit.
- `LICENSE` — the upstream Apache-2.0 license, plus any upstream `NOTICE*` file (none today).

The directory is excluded from ESLint (`.eslintignore`): its imports (`../../scripts/aem.js`)
resolve only once a block is copied into the project's `blocks/`.

### During a run

1. **`conventions`** — its `component reuse` subagent runs
   `skills/eds-conventions-component-reuse/scripts/check-component-reuse.sh`. For every block the
   work item names it answers, in this order:
   - `reuse=<name>` — already in the project's `blocks/`;
   - `upstream=<name>` — not there, but in the pinned collection;
   - `new=<name>` — in neither;
   - `upstream_unknown=<name>` — not in `blocks/`, and the manifest is missing or malformed, so the
     collection could not be checked. The subagent returns `warning`, the stage `warn`, and the
     run continues as new. It is never reported as "not in the collection".
2. **`prototype`** (design routes only) — runs `shared/scripts/copy-upstream-blocks.sh` before it
   builds anything. Every `upstream=` block is copied into `blocks/<name>/`, and the design is
   applied to those files.
3. **`plan`** — runs the same script. If `prototype` already copied, the block now answers `reuse=`
   and nothing is copied; otherwise it copies here. The plan's steps are changes to the copied
   files.
4. **`implement`** — runs the same script once more, for routes where neither earlier stage copied,
   then carries out the plan.

Whichever of the three runs first copies; the later ones never overwrite. No stage copies by hand
or chooses the names itself. The run never touches the network: everything is read from disk.

Each copied file starts with one comment line, the change notice Apache-2.0 §4(b) asks of a
modified copy. Keep it when changing the file:

```
/* Changed in this project. Derived from https://github.com/adobe/aem-block-collection blocks/table/table.js at <commit>, Apache-2.0. */
```

### Moving the pin

1. From the repository root, on a branch cut from an up-to-date `main`:

   ```sh
   bash plugins/eds/shared/scripts/refresh-block-collection.sh <commit>
   ```

   A short commit id is recorded in full. Optional arguments: `[repo] [dest]`.
2. Review the diff of `shared/block-collection/`: added, removed and changed blocks, and the
   license.
3. Run the tests listed below.
4. Put the change through a PR.

- This is the only script that needs the network. Run it by hand, never during a run.
- It builds the new copy in a temp directory and swaps it in whole. If the refresh fails (clone
  fails, unknown commit, no upstream `LICENSE`, no blocks), the existing pinned copy stays
  untouched.

### Tests

```sh
bash plugins/eds/skills/eds-conventions-component-reuse/scripts/check-component-reuse.test.sh
bash plugins/eds/shared/scripts/copy-upstream-blocks.test.sh
bash plugins/eds/shared/scripts/refresh-block-collection.test.sh
```

All three run offline; the refresh test uses a local git repository as its upstream.

### Known differences from aem.live

The [aem.live Block Collection page](https://www.aem.live/developer/block-collection) lists
Breadcrumbs, but the repository's `blocks/` has no `breadcrumbs` at the pinned commit. The manifest
follows the repository, so that name answers `new`.
