# eds — platform pack for an Edge Delivery project

Binds every stage of the `agentic-core` default route to an Edge Delivery project: fifteen stage
adapters, three subagents the `conventions` stage dispatches, four manual skills for
design-system onboarding and test fixtures, one gate-reviewer agent, and the deterministic
scripts they call. It calls the `tracker`, `scm`, `design` and `browser` provider packs where a
stage needs them.

**A stage adapter normalises what a provider returned into this platform's own artifact. It
never returns a provider operation's output unchanged.**

## The problem it solves

The core knows no platform. Something has to know that a component is a block under `blocks/`,
that authored content is a `.plain.html` document, which lint command to run, how a preview is
served, and what a design value means against the project's own design system. This pack is
that something, and it is the only place that vocabulary lives.

## How it handles it

1. **`pack.yaml` declares the route.** Fifteen stages in order, each bound to a skill; four of
   them conditional on the fact record; three with a `fix_attempts` budget. Per-item-type
   readiness criteria, sixteen artifact ids with their paths under `.ai/run-context/`, and the
   onboarding-state and audit paths the core's pre-flight reads. `route.dot` is the same route
   as a digraph.
2. **Every stage skill runs isolated and reads fixed paths.** Each declares `context: fork`,
   takes no invocation argument except `intake` (`item_id`) and the two gates (`project_root`),
   reads `.ai/run-context/fact-record.yaml` itself, and ends with the result envelope.
3. **Provider packs are resolved from the project config.** A stage reads `packs.<role>` from
   `.ai/project-config.yaml`, opens `${CLAUDE_PLUGIN_ROOT}/../<pack>/pack.yaml` for the skill
   that implements the operation, and invokes `Skill(<pack>:<skill>)`.
4. **Gates run a script first, a reviewer second.** `plan-gate` and `publish-gate` run the core's
   deterministic criteria check, then hand only what survives to `agents/eds-gate-reviewer.md`,
   which runs in a worktree of its own and reports only findings it can defend.
5. **Decisions that can be scripts are scripts.** Reuse (`check-component-reuse.sh`), markup
   conventions, style grading, branch length, gate isolation, the draft cleanup, the preview
   poll, the design-value comparison and the intake fact record are all deterministic, each with
   a `.test.sh` beside it.
6. **Drafts are served by their own server.** `eds-serve` starts the project's configured serve
   command, which never mounts `drafts/`; a stage that renders a draft fixture uses the draft
   server described in `shared/draft-server.md`, and only `eds-serve`'s cleanup ever stops it.
7. **New blocks start from a pinned upstream copy.** See "Upstream Block Collection" below.

## The flow

```text
intake ──→ readiness ──→ [extract] ──→ conventions ──→ serve ──→ [baseline]
                                          │ styles · markup · component reuse
                                          ↓
        ──→ [prototype] ──→ [verify-design] ──→ plan ──→ plan-gate ──→ implement
        ──→ verify ──→ lint ──→ publish-gate ──→ deliver

[extract], [prototype], [verify-design]   when design_source=true OR design_mentioned=true
[baseline]                                when components=present
```

Design-system onboarding is not on the route. `eds-adopt-design-system` writes the token set,
breakpoints and manifest under `.ai/design/`, `eds-audit-design-system` compares the project
against them, and `eds-complete-design-onboarding` interviews a human and opens one pull request
with three commits. `eds-fixture` writes a placeholder `.plain.html` under `drafts/` for a block
with no authored content.

## Stages

| Stage           | Skill                | Runs when                                  | Budget | Writes                                              |
| --------------- | -------------------- | ------------------------------------------ | ------ | --------------------------------------------------- |
| `intake`        | `eds-intake`         | always, first                              |        | `fact-record.yaml`, `sanitized-spec.md`             |
| `readiness`     | `eds-readiness`      | always                                     |        |                                                     |
| `extract`       | `eds-extract`        | design source or design mentioned          |        | `design-reference.json`                             |
| `conventions`   | `eds-conventions`    | always                                     |        | `design-conventions.md`                             |
| `serve`         | `eds-serve`          | always                                     |        | `serve-report.md`                                   |
| `baseline`      | `eds-baseline`       | components present                         |        | `baseline-capture.json`                             |
| `prototype`     | `eds-prototype`      | design source or design mentioned          |        | `prototype-report.md`, `design-context-values.tsv`  |
| `verify-design` | `eds-verify-design`  | design source or design mentioned          | 2      | `verify-design-report.md`                           |
| `plan`          | `eds-plan`           | always                                     | 1      | `plan.yaml`                                         |
| `plan-gate`     | `eds-plan-gate`      | always                                     |        | `plan-gate-report.md`                               |
| `implement`     | `eds-implement`      | always                                     |        | project files                                       |
| `verify`        | `eds-verify`         | always                                     |        | `verify-report.md`, `evidence-manifest.json`        |
| `lint`          | `eds-lint`           | always                                     | 3      | `lint-report.md`                                    |
| `publish-gate`  | `eds-publish-gate`   | always                                     |        | `publish-gate-report.md`                            |
| `deliver`       | `eds-deliver`        | always, last                               |        | `delivery-report.md`                                |

Every path in the last column is under `.ai/run-context/`. Readiness requires, per item type:
Story and Task `has_description` and `has_acceptance_criteria`; Bug `has_description`,
`has_reproduction_url` and `has_reproduction_steps`.

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

## What it looks like

**Manifest validation, this run:**

```text
$ claude plugin validate plugins/eds
Validating plugin manifest: .../plugins/eds/.claude-plugin/plugin.json

✔ Validation passed
```

**Pack manifest check by the core, this run:**

```text
$ bash plugins/agentic-core/shared/lib/validate-pack-manifest.sh plugins/eds/pack.yaml
valid: platform
```

**The project config that binds this pack**, as committed in the project this pack was built
against:

```yaml
packs:
  platform: eds
  tracker: jira
  scm: github
  design: figma
  browser: playwright

commands:
  lint: "npm run lint"
  test: ""
  build: ""
  serve: "npm run up"

paths:
  spec_dir: ".ai/specs"
  preview: "http://localhost:3000/preview"
```

**The offline test suites, this run:** 25 test files, every one exit 0.

## Running it yourself

1. Load the pack with the core and one provider pack per role, from the directory that holds
   `plugins/`:

   ```text
   claude --plugin-dir ./plugins/agentic-core --plugin-dir ./plugins/eds \
          --plugin-dir ./plugins/jira --plugin-dir ./plugins/github \
          --plugin-dir ./plugins/figma --plugin-dir ./plugins/playwright
   ```

   This pack declares `"dependencies": ["agentic-core"]` in `.claude-plugin/plugin.json`.
2. Configure the project with `/agentic-core:setup`, or write `.ai/project-config.yaml` as shown
   above with `packs.platform: eds`.
3. Onboard the design system once, if the project has one: `/eds:eds-adopt-design-system`, then
   `/eds:eds-audit-design-system`, then `/eds:eds-complete-design-onboarding`. `pack.yaml`
   declares `onboarding_state_path: styles/design-system.md` and
   `audit_findings_path: .ai/design/audit.md`; the core's pre-flight warns when the
   onboarding-state file is absent and blocks on an open poisoning finding at the audit path.
4. Run a route: `/agentic-core:run-route <work item id or URL>`.
5. Validate after any edit, and reload without restarting:

   ```text
   claude plugin validate plugins/eds
   /reload-plugins
   ```

6. Run the offline tests; each file exits 0 on success:

   ```text
   for t in plugins/eds/shared/scripts/*.test.sh plugins/eds/skills/*/scripts/*.test.sh; do
     bash "$t" || echo "FAILED: $t"
   done
   ```

7. Before shipping a change under `plugins/eds`, run the core's no-narrative check:

   ```text
   bash plugins/agentic-core/shared/lib/check-no-narrative.sh plugins/eds
   ```

## Limits you should know

- **Bound to one platform's shape.** Blocks under `blocks/`, `.plain.html` content, `drafts/` for
  fixtures, `styles/design-system.md` for the adopted design system. Another platform needs its
  own pack.
- **A preview server is required.** `eds-serve` polls `paths.preview` and starts
  `commands.serve` when nothing answers; the draft stages need loopback, and a command sandbox
  that denies it turns them into transient failures.
- **The gates need a checkout of their own.** `eds-gate-reviewer` runs in a worktree, so the two
  gates are passed `project_root` and read tracked files only.
- **The provider packs are named in the config, not here.** This pack works with whichever pack
  implements each role; the four named in the config above are the ones it was built against.
- **No route was run to produce this README.** The stage adapters are specified in their
  `SKILL.md` files and their scripts are tested; the end-to-end behaviour was not observed here.

## Design rules this pack follows

A stage owns its own finding. It reads the fact record and prior artifacts from fixed paths,
calls a role operation when it needs one, and writes what it learned in this platform's own
shape, never a provider's. Where the answer can be computed, a script computes it and the skill
reads the script's output.

This pack applies that rule fifteen times. What the tracker said, what the browser measured and
what the design tool returned each cross one boundary and come out the other side as an
artifact `pack.yaml` declares.

This pack adapts patterns from earlier work under the terms recorded in [NOTICE](NOTICE).

---

agenticDraft

License: not declared in `.claude-plugin/plugin.json`. The pinned block collection carries its
own Apache-2.0 `LICENSE` under `shared/block-collection/`. Attribution and terms for adapted
material: [NOTICE](NOTICE).
