---
description: The pre-flight capability probe — what it checks, in what order, and why it never spawns a process to check availability. Every reader of a pre-flight result references this file rather than restating the checks inline.
---

# Pre-flight

Runs before `intake` — before any branch, file or outbound call exists (core contract §4). At
this point no fact record exists yet, so no stage has been filtered against one: pre-flight cannot
know which of the platform pack's stages a work item will actually run. It checks the pack and
project config as declared, not against any one item's eventual run.

**Never does:** decide which of a pack's stages a work item will run (`evaluate-stage-conditions.sh`'s
job, over the fact record `intake` produces), spawn or invoke an actual pack skill to see whether it
responds, probe a process or the network to answer a question a declaration already answers, or
create anything.
Three structural reads — project config and pack manifests, both already validated by
`validate-project-config.sh` and `validate-pack-manifest.sh`, and a comparison between them; plus,
when the platform pack declares one (D80), one file-existence test per declared onboarding path
against the project's own working tree. The third read stays inside the same discipline as the
first two: it tests whether a path the pack itself already named is present, never what a live
process reports about itself.

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

**A declared-path file test (the third check, below) is not a health check either, though it does
touch the project's own disk.** The first two checks read what a process reports about itself,
which can go wrong for reasons the pack does not control. Testing whether a path the pack itself
named exists in the project's own working tree is different in kind: the pack already knows and
states the path; the test asks nothing about a running process, a network condition, or a tool's
own liveness — only whether a file the pack expects is there. This is what "structural" still means
for a check that, unlike the first two, is not purely about the pack in isolation.

## The three checks

1. **Every pack project config requires is installed.** For every role `packs:` names — `platform`,
   `tracker`, `scm`, `browser` always; `design` only when its value is not `none` — a pack manifest
   must be supplied for that role, and it must validate (`validate-pack-manifest.sh`) as the right
   kind: `platform` for the platform role, `provider` with a matching `role:` for the other four.
2. **Every declared role operation is available.** For each configured provider role, every
   operation §6 declares for that role is implemented — none of them appears in that pack's
   `unsupported:` list. A pack is free to decline an operation (`pack-manifest.md` allows it, and
   the manifest validator does not reject it), but project config configuring that pack for a role
   whose unsupported operation the pack declares is the situation core contract §6 names
   explicitly: "the runner treats a stage needing it as unrunnable and stops at pre-flight rather
   than mid-run."
3. **The onboarding gate, when the platform pack declares it (D80, core contract §6.3).** A
   platform pack's manifest may declare `onboarding_state_path` and/or `audit_findings_path`
   (`pack-manifest.md`). Neither is required; a pack declaring neither runs this check as a no-op —
   the same shape check 2 already uses for a provider's `unsupported:` declaration: the core acts
   on a declaration, never on knowledge of the thing declared. For each path the pack does declare,
   resolved relative to the project root:
   - **`onboarding_state_path`** — a plain file-existence test. Present: nothing to report. Absent:
     a warning, never a block — the project has not completed design-system onboarding, so every
     design value a later stage reads is a guess, and the run's confidence is capped `low` (D20,
     G21). The run still proceeds.
   - **`audit_findings_path`** — read only when the file exists; a project that has never audited
     has nothing open to block on. Parsed against `audit-taxonomy.md`'s findings shape: if any
     entry's `severity` is `poisoning`, the run stops here — before `intake`, before any branch,
     file or outbound call exists — naming that finding, the file it names, and that it must be
     resolved through the project's own onboarding-completion flow before this run can proceed. A
     `cosmetic` finding never blocks.

## What a failure produces

Exits `1` with `invalid: <reason>` on stderr, naming exactly what is missing — the role with no
pack supplied, the operation a configured pack declares unsupported, or (check 3) the open
poisoning finding and the file it names. This reason is what a caller hands to
`resolve-terminal-state.sh blocked <missing> <recorded-at>` (`terminal-states.md`) — pre-flight
failure is one of that contract's three `blocked` causes, not a fourth state of its own. Check 3's
`onboarding_state_path` half never produces this exit; an absent onboarding-state file is reported
as a `onboarding: warn — …` line alongside the `ready` output instead, and the run still proceeds.

## Anti-patterns

- Checking process liveness (`command -v`, an MCP list call, a `health` skill invocation) in place
  of reading a manifest's own declarations. This is the exact false-negative failure mode
  `pack-manifest.md`'s completeness rule and this file exist to avoid.
- **Probing the environment** for anything check 3's declared paths do not cover — a running
  server, a network endpoint, an installed binary's version. A declared path is a structural read
  of the pack's own manifest plus one file test against the project's own working tree,
  deterministic and offline; a health check is a live probe of a process the pack does not control.
  Check 3 is the former; it must never grow into the latter.
- Checking only the stages a work item will end up running. Pre-flight runs before any fact record
  exists to filter one.
- Writing a branch, a file, or any run state before every check passes.
- Treating a pack's declared `unsupported:` operation as passable "because this project probably
  never needs it" — pre-flight has no fact record yet to know that.
- Blocking a run because `onboarding_state_path` is absent. Absence warns and caps confidence; only
  an open `poisoning` finding at `audit_findings_path` blocks — D80's whole point is that the two
  checks behave differently on purpose, and collapsing them into one severity defeats it.
- Running the onboarding gate against a pack that declares neither path. Undeclared means ungated,
  the same rule this file already applies to a provider's `unsupported:` list.

## Reference, not restatement

A skill or script that runs or reads a pre-flight result references this file with one line rather
than restating the three checks inline, the same convention `pack-manifest.md` and
`project-config.md` use for their own contracts.

## Fixtures

`fixtures/pre-flight/config-valid.yaml` — a well-formed project config, `packs.design: none`.
`fixtures/pre-flight/config-design-required.yaml` — the same, with `packs.design` naming a pack.
`fixtures/pre-flight/providers/` — one pack root per role pre-flight can be asked to check:
`scm-valid`, `browser-valid`, `design-valid` (all operations implemented, `unsupported: []`), and
`scm-missing-operation` (`publish_change` declared unsupported). `tracker` reuses
`fixtures/pack-manifest/provider-valid/`.

`fixtures/pre-flight/onboarding/` — one directory per check-3 case, each doubling as a "project
root" the declared paths resolve against: `ungated` (neither key declared), `onboarding-present` /
`onboarding-absent` (`onboarding_state_path` declared, the file present or absent),
`audit-absent` / `audit-clean` / `audit-poisoning` (`audit_findings_path` declared, the file
absent, present with only a `cosmetic` finding, or present with one `poisoning` finding), and
`both-declared` (both keys, both files present, clean). `check-onboarding-gate.test.sh` exercises
these directly; `check-preflight.test.sh` reuses `fixtures/pack-manifest/platform-valid-onboarding/`
(the same two keys, on an otherwise-conformant manifest) for its own integration cases.

## Verification

`lib/check-preflight.sh <project-config path> <role>=<path-to-pack.yaml> [<role>=<path> …]` — one
`role=path` pair per role project config requires (`role` one of `platform`, `tracker`, `scm`,
`design`, `browser`). No model involved, no side effects. Exits `0` and prints `ready` plus one
`<role>: ok` line per role checked (`design: none` when config declares no design pack is
required), then check 3's own line(s) when the platform pack declares either onboarding path
(omitted entirely when it declares neither); `1` with `invalid: <reason>` on stderr for the first
check that fails; `2` for a usage error (no config argument, config not found, a malformed
`role=path` pair, an unrecognized role name).

`lib/check-onboarding-gate.sh <path-to-platform-pack.yaml>` is check 3 on its own — reusable
standalone, and what `check-preflight.sh` delegates to. Resolves each declared path relative to the
current working directory. Exits `0` and prints `not-gated` (neither key declared) or one line per
declared key (`onboarding: ok|warn — …`, `audit: ok|ok — no audit yet — …`); `1` with
`invalid: <reason>` on stderr naming the open poisoning finding; `2` for a usage error.

```bash
bash plugins/agentic-core/shared/lib/check-preflight.test.sh
bash plugins/agentic-core/shared/lib/check-onboarding-gate.test.sh
```
