---
description: The pre-flight capability probe — what it checks, in what order, and why it never spawns a process to check availability. Every reader of a pre-flight result references this file rather than restating the checks inline.
---

# Pre-flight

Runs before `intake` — before any branch, file or outbound call exists (core contract §4). At
this point no fact record exists yet, so no route has been resolved (`resolve-route.sh` needs the
fact record `intake` produces): pre-flight cannot know which single route a work item will
resolve to. It checks every route project config declares could fire, not only the one that
eventually does.

**Never does:** decide which route a work item resolves to (`resolve-route.sh`'s job, over
`project-config.md`'s `routes:` shape, once a fact record exists), spawn or invoke an actual pack
skill to see whether it responds, or create anything.
Two structural reads only — project config and pack manifests, both already validated by
`validate-project-config.sh` and `validate-pack-manifest.sh` — and a comparison between them.

## Why never a health check

A capability probe that shells out to test whether a tool process is alive is coupled to how that
process happens to be launched, not to whether the capability it backs actually exists — a
sandbox or network condition unrelated to the pack's own correctness can make a live tool report
unavailable when it is not, or available when it is not fully configured. Because a false
negative here is PERMANENT by construction — it aborts a run before a branch exists, silently,
depending on conditions the pack author does not control — pre-flight reads only the pack's own
declarations: its manifest's `stages:` map and `operations:`/`unsupported:` lists, the same shape
`pack-manifest.md` already defines and `validate-pack-manifest.sh` already validates. "The
operation the pipeline will actually use" means the operation is declared implemented in the
manifest, never that a live call to it happened to succeed once.

## The two checks

1. **Every pack project config requires is installed.** For every role `packs:` names — `platform`,
   `tracker`, `scm`, `browser` always; `design` only when its value is not `none` — a pack manifest
   must be supplied for that role, and it must validate (`validate-pack-manifest.sh`) as the right
   kind: `platform` for the platform role, `provider` with a matching `role:` for the other four.
2. **Every declared role operation is available.** Two parts, both structural, using data pre-flight
   already has without knowing the resolved route:
   - **Stages.** Every stage id named in *any* route in `routes:` — not only the route a work item
     will eventually resolve to, since that resolution has not happened yet — has an entry in the
     platform pack manifest's `stages:` map. A route naming a stage id the platform pack dropped is
     exactly the drift `stage-runner.md`'s own resolution step would hit mid-run; pre-flight is
     where it is cheap to catch instead.
   - **Operations.** For each configured provider role, every operation §6 declares for that role is
     implemented — none of them appears in that pack's `unsupported:` list. A pack is free to decline
     an operation (`pack-manifest.md` allows it, and the manifest validator does not reject it), but
     project config configuring that pack for a role pre-flight cannot yet know will avoid the
     unsupported operation is the situation core contract §6 names explicitly: "the runner treats a
     route needing it as unrunnable and stops at pre-flight rather than mid-run."

## What a failure produces

Exits `1` with `invalid: <reason>` on stderr, naming exactly what is missing — the role with no
pack supplied, the stage id absent from the platform manifest (and which route names it), or the
operation a configured pack declares unsupported. This reason is what a caller hands to
`resolve-terminal-state.sh blocked <missing> <recorded-at>` (`terminal-states.md`) — pre-flight
failure is one of that contract's three `blocked` causes, not a fourth state of its own.

## Anti-patterns

- Checking process liveness (`command -v`, an MCP list call, a `health` skill invocation) in place
  of reading a manifest's own declarations. This is the exact false-negative failure mode
  `pack-manifest.md`'s completeness rule and this file exist to avoid.
- Checking only the route a work item resolved to. Pre-flight runs before that resolution exists.
- Writing a branch, a file, or any run state before every check passes.
- Treating a pack's declared `unsupported:` operation as passable "because this project probably
  never needs it" — pre-flight has no route yet to know that.

## Reference, not restatement

A skill or script that runs or reads a pre-flight result references this file with one line rather
than restating the two checks inline, the same convention `pack-manifest.md` and
`project-config.md` use for their own contracts.

## Fixtures

`fixtures/pre-flight/config-valid.yaml` — a project config whose one route's stages are a subset of
`fixtures/pack-manifest/platform-valid/pack.yaml`'s `stages:` map, `packs.design: none`.
`fixtures/pre-flight/config-design-required.yaml` — the same, with `packs.design` naming a pack.
`fixtures/pre-flight/config-unknown-stage.yaml` — a route naming `plan-gate`, which
`platform-valid/pack.yaml` does not declare.
`fixtures/pre-flight/providers/` — one pack root per role pre-flight can be asked to check:
`scm-valid`, `browser-valid`, `design-valid` (all operations implemented, `unsupported: []`), and
`scm-missing-operation` (`publish_change` declared unsupported). `tracker` reuses
`fixtures/pack-manifest/provider-valid/`.

## Verification

`lib/check-preflight.sh <project-config path> <role>=<path-to-pack.yaml> [<role>=<path> …]` — one
`role=path` pair per role project config requires (`role` one of `platform`, `tracker`, `scm`,
`design`, `browser`). No model involved, no side effects. Exits `0` and prints `ready` plus one
`<role>: ok` line per role checked (`design: none` when config declares no design pack is
required), `1` with `invalid: <reason>` on stderr for the first check that fails, `2` for a usage
error (no config argument, config not found, a malformed `role=path` pair, an unrecognized role
name).

```bash
bash plugins/agentic-core/shared/lib/check-preflight.test.sh
```
