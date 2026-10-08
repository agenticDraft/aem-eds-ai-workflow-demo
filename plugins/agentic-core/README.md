# agentic-core — the delivery core that names no product

Runs one delivery route over one work item: it resolves the route from a platform pack's
manifest, spawns each stage's adapter as an isolated subagent, reads only the result envelope
that adapter returns, branches on its verdict, and ends the run in exactly one of three terminal
states.

**The core names roles, never products.** A tracker, an scm, a design source and a browser are
roles; which product fills each is a pack's business, and the core never learns its name.

## The problem it solves

A delivery automation that hardwires its tracker, its repository host and its browser has to be
rewritten when any of them changes, and its driver tends to drift: it reads a stage's files,
re-does part of the stage's work, and branches on prose. This core fixes both by contract. Every
stage returns one shape, the driver reads nothing else, and every product name lives in a pack
the core can be pointed at.

## How it handles it

1. **Roles and operations, not products.** Four roles — `tracker`, `scm`, `design`, `browser` —
   each with a fixed operation list a provider pack implements. Fifteen stage ids a platform pack
   binds to its own skills. `shared/lib/validate-naming-rule.sh` scans every file under the core
   for a 39-term denylist of product names; the run recorded below found none.
2. **One shape for every return.** The result envelope (`shared/result-envelope.md`) is the last
   thing any stage or operation emits:

   ```markdown
   ## Result
   verdict: pass | warn | fail | question
   summary: <one sentence, <=200 chars>
   artifacts:
     - <relative path written or updated>
   next_action: <short phrase, or "none">
   ```

   A stage writes it with `shared/lib/emit-envelope.sh`, which refuses a field the verdict does
   not allow; the driver validates it with `shared/lib/validate-result-envelope.sh`.
3. **The driver reads only the envelope.** `run-route` never opens a path listed under
   `artifacts:` and never retries a stage. A `PreToolUse` hook on `Read`,
   `skills/run-route/scripts/check-driver-read.sh`, denies any read the driver is not entitled
   to while a run is live (its orchestration marker exists) and logs each decision; with no run
   live it lets the read through.
   A second `PreToolUse` hook, on `Bash`, `skills/run-route/scripts/record-transcript-path.sh`,
   records the session transcript's path from the hook input into the run context, so every
   terminal state can render `analytics.md` (`shared/analytics.md`) from it through
   `shared/lib/render-run-analytics.sh` before the terminal line.
4. **Questions are asked at stage boundaries only.** A stage that cannot resolve something
   returns `verdict: question` with a `blocker`; in interactive mode the human answers and the
   stage is re-invoked once with the answer; in autonomous mode the blocker is written back
   through the tracker role and the run ends `blocked`. `limits.questions_per_run` caps the count.
5. **Exactly three terminal states.** `delivered` when `deliver` returns `pass`; `blocked` on an
   unanswered question, an exhausted budget, a pre-flight failure or a dirty tree at a fresh
   start; `failed` on a stage's own `fail` or on a contract violation. `warn` is never terminal.
6. **Configuration is written once.** `setup` detects the project's commands and paths, confirms
   them, and writes them into `.ai/project-config.yaml`, which holds six top-level keys:
   `version`, `packs`, `commands`, `paths`, `limits`, `trigger`. `limits` and `trigger` are human
   decisions that `setup` never writes. Every pack reads that one file.
7. **Every decision that can be a script is a script.** The shared library holds the validators,
   writers and checkers the driver and the packs call; each has a `.test.sh` beside it, and none
   involves a model.
8. **Plugins find each other by name, never by folder.** The core and each pack are separate
   plugins. Installed, each one lives in its own versioned directory, so `..` from one plugin root
   does not reach another. Three directions, two mechanisms:
   - **Who is asked:** the core only knows roles. Project config maps each role to a plugin name
     (`packs:`); the core never holds a name of its own choosing.
   - **Core → pack, pack → pack: the root registry.** Each plugin's own `SessionStart` hook writes
     its `${CLAUDE_PLUGIN_ROOT}` to `.ai/run-context/plugin-roots/<name>`. Only the core's
     `shared/lib/resolve-plugin-root.sh <name>` reads it: a registry entry naming a directory that
     exists wins; an entry naming a missing directory is refused; with no entry, the sibling folder
     is tried, which exists only when every plugin is loaded by path from one source tree; otherwise
     it exits non-zero and says the name was not resolved.
   - **Pack → core: the `core` link.** Each pack carries `core`, a link to the core's `shared/`
     directory, and reaches every contract and script as `${CLAUDE_PLUGIN_ROOT}/core/<path>`.
   - **What crosses the boundary is the envelope.** Finding a plugin's root only lets a caller run
     that plugin's skill or script; what comes back is still the result envelope above.
   - **An unresolved plugin is an error.** The caller stops; it never guesses a path and never
     treats the plugin as optional.

   **Status: partly shipped.** Shipped: `register-plugin-root.sh`, `resolve-plugin-root.sh`, and a
   `SessionStart` entry with no `async` in this plugin's `hooks/hooks.json`; the run-context archive
   leaves `plugin-roots/` in place; each pack's `core` link, through which every pack → core
   reference, a pack's own hook included, now goes; `shared/lib/rewrite-core-refs.sh`, which moves a
   pack's references onto its link. Not shipped: no stage or script calls the resolver yet, and the
   core → pack and pack → pack references still go through `..`. Today every plugin is loaded by
   path side by side. What was
   measured, with throwaway plugins, before this rule was adopted:
   - a link inside a plugin to another plugin's directory arrived as regular files, executable bit
     kept, in the copy installed from a git-hosted marketplace; a directory marketplace loads in
     place, where the link resolves;
   - a `SessionStart` hook wrote the installed path in an interactive session, the source path when
     loaded by path, and the right one in a headless run in both layouts;
   - a marketplace pinned to a tag kept its clone at the tagged commit through an update, so one tag
     pins the core and every pack together;
   - the registry stays empty after a fresh project's first session, which fetches the plugins
     without running their hooks; a plugin loaded by path overrides an installed one of the same
     name; each pack's copy of the core is keyed by the pack's own `version`.

## The flow

```text
/agentic-core:setup ──→ .ai/project-config.yaml  (packs, commands, paths, limits)

/agentic-core:run-route <item> [autonomous]
  ↓
pre-flight: validate project config and every pack manifest; declared onboarding paths exist
  ├── failure → blocked
  ↓
intake (always first): Skill(<platform pack>:<intake skill>)  item_id: <item>
  ↓  fact record at .ai/run-context/fact-record.yaml
evaluate-stage-conditions.sh → which declared stages this item runs
  ↓
for each remaining stage, in manifest order:
  spawn  Skill(<platform pack>:<stage skill>)     (isolated, context: fork)
  capture envelope → validate → branch
    pass      → continue
    warn      → continue, warning recorded
    question  → ask (interactive) or write back and end blocked (autonomous)
    fail      → failed
    invalid envelope / unknown skill → failed (contract violation)
  write .ai/run-state.json and .ai/progress.md
  ↓
deliver returned pass → delivered; status table printed; run-state.json deleted
```

The non-obvious edge: a stage is never told the shape of the run. It reads the fact record and
its own answer file at fixed paths; which stages ran before it is the driver's knowledge alone.

## Skills

| Skill       | Invocation                                            | What it does                                                                                  |
| ----------- | ----------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `setup`     | `/agentic-core:setup`                                 | Detects commands and paths, proposes knowledge sources, picks provider packs with you, generates a platform pack from an interview. Writes `.ai/project-config.yaml`. Never installs. |
| `health`    | `/agentic-core:health`                                | Reports what is loaded, which pack each role resolves to, and each pack's declared preconditions with the remedy the pack states. Read-only. |
| `run-route` | `/agentic-core:run-route <work item id or URL> [autonomous]` | Drives one route to a terminal state. The only component allowed to spawn a stage adapter. |

All three set `disable-model-invocation: true`: a human starts them, the model does not.

## Shared contracts

Each file under `shared/` is referenced by the skills and packs rather than restated. The scripts
under `shared/lib/` make the contracts executable.

| Concern               | Contract                                                        | Script                                                        |
| --------------------- | --------------------------------------------------------------- | ------------------------------------------------------------- |
| What a stage returns  | `result-envelope.md`, `subagent-outcome.md`                     | `emit-envelope.sh`, `validate-result-envelope.sh`             |
| How a stage is run    | `stage-runner.md`, `question-protocol.md`, `terminal-states.md` | `run-stage.sh`, `handle-question.sh`, `resolve-terminal-state.sh` |
| What a pack declares  | `pack-manifest.md`, `readiness-criteria.md`                     | `validate-pack-manifest.sh`, `check-requires.sh`, `evaluate-stage-conditions.sh` |
| Project configuration | `project-config.md`, `pre-flight.md`                            | `validate-project-config.sh`, `check-preflight.sh`, `write-detected-config.sh` |
| Run bookkeeping       | `run-state.md`, `progress-output.md`, `orchestration-flag.md`   | `write-run-state.sh`, `print-progress-line.sh`, `print-status-table.sh` |
| Gates                 | `gate-contract.md`, `plan-criteria.md`, `publish-criteria.md`   | `check-plan-criteria.sh`, `check-publish-criteria.sh`, `check-tree-unchanged.sh` |
| Design onboarding     | `design-manifest.md`, `breakpoint-thresholds.md`, `audit-taxonomy.md`, `convention-record.md` | `write-design-manifest.sh`, `derive-breakpoints.sh`, `classify-severity.sh` |
| Safety and neutrality | `external-content-safety.md`, `naming-rule.md`, `skill-authoring.md` | `check-external-content-safety.sh`, `validate-naming-rule.sh`, `validate-contracts.sh` |

Also under `shared/`: `fact-record.md`, `fix-loop.md`, `error-handling.md`,
`evidence-manifest.md`, `artifact-registry.md`, `analytics.md`, `role-operations.md` (a stage calls
another pack only through its operation's skill; `check-direct-script-calls.sh` reads a transcript
for the exceptions), and the fixtures every test reads under `shared/fixtures/`.

## What it looks like

**Manifest validation, this run:**

```text
$ claude plugin validate plugins/agentic-core
Validating plugin manifest: .../plugins/agentic-core/.claude-plugin/plugin.json

✔ Validation passed
```

**An envelope written by the emitter, this run:**

```text
$ bash plugins/agentic-core/shared/lib/emit-envelope.sh $TMPDIR/envelope-demo.txt \
    --verdict pass --summary "Fetched the work item." --artifact .ai/run-context/fact-record.yaml
emitted: pass envelope with 1 artifact(s) -> /tmp/claude-501/envelope-demo.txt
$ cat $TMPDIR/envelope-demo.txt
## Result
verdict: pass
summary: Fetched the work item.
artifacts:
  - .ai/run-context/fact-record.yaml
next_action: none
$ bash plugins/agentic-core/shared/lib/validate-result-envelope.sh $TMPDIR/envelope-demo.txt
verdict: pass
```

**A pack manifest checked by the core, this run,** against a platform pack and a provider pack
loaded beside it:

```text
$ bash plugins/agentic-core/shared/lib/validate-pack-manifest.sh plugins/<platform pack>/pack.yaml
valid: platform
$ bash plugins/agentic-core/shared/lib/validate-pack-manifest.sh plugins/<provider pack>/pack.yaml
valid: provider
$ bash plugins/agentic-core/shared/lib/check-requires.sh plugins/<provider pack>/pack.yaml
ok: no requirements declared
```

**The core's own conformance checks, this run:**

```text
$ bash plugins/agentic-core/shared/lib/validate-naming-rule.sh plugins/agentic-core
valid: naming rule (547 files scanned, 39 terms checked)
$ bash plugins/agentic-core/shared/lib/check-no-narrative.sh plugins/agentic-core
valid: no narrative (477 files scanned)
```

**The test suites, this run:** 63 test files, every one exit 0.

## Running it yourself

1. Load the core together with one platform pack and one provider pack per role the project
   uses, from the directory that holds `plugins/`. Every configured pack must be loaded: the
   driver spawns a stage as `Skill(<pack>:<skill>)`, and an unloaded pack is reported as a
   contract violation, not worked around.

   ```text
   claude --plugin-dir ./plugins/agentic-core \
          --plugin-dir ./plugins/<platform pack> \
          --plugin-dir ./plugins/<tracker pack> \
          --plugin-dir ./plugins/<scm pack> \
          --plugin-dir ./plugins/<design pack> \
          --plugin-dir ./plugins/<browser pack>
   ```

   Loaded this way, every plugin sits beside the others, which is the only layout the shipped code
   handles today (see "Plugins find each other by name" above).
   Installed from a marketplace, use `claude plugin install agentic-core@<marketplace>`; a pack
   that declares `"dependencies": ["agentic-core"]` enables the core with it.
2. Configure the project once: `/agentic-core:setup`. It confirms every value before writing
   `.ai/project-config.yaml`.
3. Check the environment: `/agentic-core:health`.
4. Run a route: `/agentic-core:run-route <work item id or URL>`, or with `autonomous` appended
   to write blockers back instead of asking.
5. After editing any file under `skills/` or `shared/`, validate and reload without restarting:

   ```text
   claude plugin validate plugins/agentic-core
   /reload-plugins
   ```

6. Run the offline tests; each file exits 0 on success:

   ```text
   for t in plugins/agentic-core/shared/lib/*.test.sh \
            plugins/agentic-core/skills/run-route/scripts/*.test.sh; do
     bash "$t" || echo "FAILED: $t"
   done
   ```

7. Before shipping a change under `plugins/agentic-core`, run the two checks under "What it
   looks like": the naming rule and the no-narrative check. Both exit 1 with one line per finding.

## Layout

```text
agentic-core/
├── .claude-plugin/plugin.json     # name, description, version, author
├── NOTICE                          # attribution for adapted material
├── skills/
│   ├── setup/SKILL.md
│   ├── health/SKILL.md
│   └── run-route/
│       ├── SKILL.md                # the driver; declares the Read and Bash hooks
│       └── scripts/check-driver-read.sh
└── shared/
    ├── *.md                        # the contracts
    ├── lib/                        # scripts, one .test.sh beside each
    │   └── naming-denylist.txt
    └── fixtures/                   # inputs the tests read
```

## Limits you should know

- **Nothing runs without packs.** The core ships no stage and no operation; it is a driver, a
  configurator and a diagnostic. A route needs a platform pack and a provider pack for every
  role the project config names.
- **`setup` does not choose the browser pack.** Its own description says so; `packs.browser` is
  set by hand.
- **Pre-flight reads declarations only.** It never probes a process, so a tool missing from the
  machine is found by `health` or by the operation that needs it, not before the run starts.
- **Run state goes stale at two hours.** A `.ai/run-state.json` older than that is deleted and
  the run starts fresh; a younger one is offered for resume.
- **No route was run to produce this README.** The outputs above come from the scripts and the
  validators; the driver's behaviour is specified in `skills/run-route/SKILL.md` and covered by
  the script tests, not observed here end to end.
- **The naming denylist is not complete.** It grows when a new concrete name comes up; a term
  not on it passes the validator.

## Design rules a pack must respect

The runner never opens what a stage wrote, so everything the next decision needs goes in the
envelope and everything the next stage needs goes to a fixed path under `.ai/run-context/`. A
stage skill declares `context: fork` and ends with the envelope; a provider operation returns its
script's stdout unchanged and lets the script decide the verdict. A stage is never told which
stages ran before it.

How a pack reaches anything outside itself:

- **The core, through `${CLAUDE_PLUGIN_ROOT}/core/…`** — never `${CLAUDE_PLUGIN_ROOT}/../<core>/…`.
- **Another plugin, through its role.** A stage calls another pack only through that role's
  operation skill (`shared/role-operations.md`). When it needs that pack's root, it asks
  `resolve-plugin-root.sh <name>` with the name project config gives the role; it never builds
  `../<pack>/` itself and never hard-codes a pack name.
- **Its own files, through `${CLAUDE_PLUGIN_ROOT}/…`** — never through `../<own name>/`, which
  breaks the moment the plugin is installed or renamed.
- **A registry writer of its own.** Each pack's `SessionStart` hook writes its root to the registry
  and declares no `async`, so the entry exists before the session's first tool call.

This core is a small instance of one rule: what the driver cannot see, it cannot drift into
re-doing. A pack can be swapped only because the core never learned its name.

This plugin adapts patterns from earlier work under the terms recorded in [NOTICE](NOTICE).

---

agenticDraft

License: not declared in `.claude-plugin/plugin.json`. Attribution and terms for adapted
material: [NOTICE](NOTICE).
