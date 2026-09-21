---
description: The pre-flight capability probe — what it checks, in what order, why it never spawns a process to check availability, and the one notice it prints rather than checks. Every reader of a pre-flight result references this file rather than restating the checks inline.
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

A fourth item is not a check at all but a **notice** (D94): when the platform pack declares a
`serve` stage, pre-flight says which preview that run will need and what is configured to start
it. It reads two values the project config already declares, reaches nothing, and has no failing
verdict.

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

**The need a health check would serve is real, and the notice is what answers it.** A run whose
preview never answers fails several stages in, long after a branch exists and outbound calls have
been made, and the human watching it had no way to know a server was wanted. That is an
information problem, not a verification one, and information can be given from a declaration: the
notice names the preview and the configured serve command before `intake`, without asking anything
of a live process. Where nothing is configured to start that preview, it says so as a warning —
never a block, because a preview that is already answering makes an unconfigured serve command
harmless, and only the probe this file refuses could tell those two apart.

**A declared-path file test (the third check, below) is not a health check either, though it does
touch the project's own disk.** The first two checks read what a process reports about itself,
which can go wrong for reasons the pack does not control. Testing whether a path the pack itself
named exists in the project's own working tree is different in kind: the pack already knows and
states the path; the test asks nothing about a running process, a network condition, or a tool's
own liveness — only whether a file the pack expects is there. This is what "structural" still means
for a check that, unlike the first two, is not purely about the pack in isolation.

## The three checks, and the notice

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
   platform pack's manifest may declare `onboarding_state_path`, `audit_findings_path` and/or
   `audit_digest_path` (`pack-manifest.md`). None is required; a pack declaring none runs this check as a no-op —
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
   - **`audit_digest_path`** (G500) — read only when the file exists; an audit written before the
     pack declared a digest has none, and that is not a failure. The file is a digest list: one
     `<sha256>  <relative path>` line per file the audit judged. The check re-hashes the paths the
     digest itself names — so the core tests files whose meaning it never learns (D28) — and any
     path whose content has moved, or that is no longer readable, produces a **warning** naming that
     path, capping confidence `low` the same way an absent `onboarding_state_path` does. It never
     blocks: a moved file is missing evidence, not a finding. A file that is not a digest list at
     all is a different matter — the check reports `invalid` and stops, because a gate that cannot
     read its own input must not report a pass.

   Checks on `audit_findings_path` and `audit_digest_path` run in that order on purpose: an open
   `poisoning` finding blocks and ends the run, so a freshness warning about the same project is
   never reached. The digest's shape is decided by the check itself rather than by whichever
   system checksum tool is installed, because the two in common use disagree — GNU `sha256sum -c`
   warns and exits `0` on a malformed list where `shasum -a 256 -c` exits `1`.
4. **The serve notice, when the platform pack declares a `serve` stage (D94).** A pack whose
   `stages:` list has no `serve` stage runs this as a no-op — the same shape checks 2 and 3
   already use for an undeclared thing. For a pack that does declare one, two values the project
   config already carries are read — `paths.preview` and `commands.serve` — and one line is
   printed alongside the `ready` output:
   - **A serve command is configured** — the line names the preview and the command that will
     start it. Nothing is required of the human; this is the run saying what it is about to need.
   - **`commands.serve` is empty** — a warning, never a block. Nothing in this project can start
     that preview, so it must already be answering by the time the run reaches the `serve` stage.
     The run still proceeds, because that is a perfectly ordinary situation and pre-flight cannot
     tell it apart from the failing one without probing.

   The notice is the one part of pre-flight's output that exists for a human rather than for the
   runner's own branching. It is emitted before `intake`, which is the whole point of putting it
   here: the `serve` stage runs some way into a route, and a route that will need a preview should
   say so before it starts spending outbound calls.

## What a failure produces

Exits `1` with `invalid: <reason>` on stderr, naming exactly what is missing — the role with no
pack supplied, the operation a configured pack declares unsupported, or (check 3) the open
poisoning finding and the file it names. This reason is what a caller hands to
`resolve-terminal-state.sh blocked <missing> <recorded-at>` (`terminal-states.md`) — pre-flight
failure is one of that contract's three `blocked` causes, not a fourth state of its own. Check 3's
`onboarding_state_path` half never produces this exit; an absent onboarding-state file is reported
as a `onboarding: warn — …` line alongside the `ready` output instead, and the run still proceeds.

**The notice never produces this exit either, on any project.** It has no failing verdict: an
unconfigured serve command warns, and everything else reports. A non-zero exit from the notice's
own script is therefore never a statement about the project — both of its inputs were validated by
the checks above it — and is reported as what it is, a check that could not run.

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
- Blocking a run because `onboarding_state_path` is absent, or because a digest at
  `audit_digest_path` is stale. Both warn and cap confidence; only an open `poisoning` finding at
  `audit_findings_path` blocks — D80's whole point is that the checks behave differently on purpose,
  and collapsing them into one severity defeats it.
- Running the onboarding gate against a pack that declares none of the three paths. Undeclared means
  ungated, the same rule this file already applies to a provider's `unsupported:` list.
- Deciding a stale digest from `git log` rather than from content. A trusted file edited in the
  working tree and not yet committed is exactly the case this check exists for, and no commit
  timestamp can see it.
- **Letting the serve notice grow a verdict.** Polling the preview to decide what it says, or
  blocking a run because no serve command is configured, turns the one part of this file's output
  that costs nothing into the health check the rest of it refuses. It reports; it does not decide.
- Printing the serve notice for a platform pack whose stage list has no `serve` stage. The core
  acts on the declaration, not on an assumption that every project has a preview to serve.

## Reference, not restatement

A skill or script that runs or reads a pre-flight result references this file with one line rather
than restating the three checks or the notice inline, the same convention `pack-manifest.md` and
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
`both-declared` (both keys, both files present, clean), and — for `audit_digest_path` —
`digest-fresh` / `digest-stale` / `digest-absent` / `digest-unreadable` / `digest-malformed`
(every hash matching, one hash moved, no digest written yet, a listed file deleted, and a file that
is not a digest list), plus `digest-stale-and-poisoning`, which proves the finding outranks the
freshness warning. `check-onboarding-gate.test.sh` exercises
these directly; `check-preflight.test.sh` reuses `fixtures/pack-manifest/platform-valid-onboarding/`
(the same two keys, on an otherwise-conformant manifest) for its own integration cases.

`fixtures/pre-flight/serve/` — the notice's own inputs: `pack-with-serve.yaml` and
`pack-without-serve.yaml` (a stage list with and without a `serve` stage), and
`config-serve-empty.yaml` (`config-valid.yaml` with `commands.serve` empty). The configured case
reuses `config-valid.yaml` itself. `check-preflight.test.sh` reuses
`fixtures/pack-manifest/platform-valid-full-route/`, which declares every stage including `serve`,
for its own integration cases.

## Verification

`lib/check-preflight.sh <project-config path> <role>=<path-to-pack.yaml> [<role>=<path> …]` — one
`role=path` pair per role project config requires (`role` one of `platform`, `tracker`, `scm`,
`design`, `browser`). No model involved, no side effects. Exits `0` and prints `ready` plus one
`<role>: ok` line per role checked (`design: none` when config declares no design pack is
required), then check 3's own line(s) when the platform pack declares either onboarding path
(omitted entirely when it declares neither), then the notice's own line when that pack declares a
`serve` stage (omitted entirely when it does not); `1` with `invalid: <reason>` on stderr for the
first check that fails; `2` for a usage error (no config argument, config not found, a malformed
`role=path` pair, an unrecognized role name).

`lib/check-onboarding-gate.sh <path-to-platform-pack.yaml>` is check 3 on its own — reusable
standalone, and what `check-preflight.sh` delegates to. Resolves each declared path relative to the
current working directory. Exits `0` and prints `not-gated` (neither key declared) or one line per
declared key (`onboarding: ok|warn — …`, `audit: ok|ok — no audit yet — …`); `1` with
`invalid: <reason>` on stderr naming the open poisoning finding; `2` for a usage error.

`lib/check-serve-notice.sh <project-config path> <path-to-platform-pack.yaml>` is the notice on its
own — reusable standalone, and what `check-preflight.sh` delegates to. Exits `0` and prints
`not-declared` (the pack declares no `serve` stage) or one line (`serve: ok — …`,
`serve: warn — …`); `2` for a usage error. **It has no exit `1`** — the notice cannot fail a run.

```bash
bash plugins/agentic-core/shared/lib/check-preflight.test.sh
bash plugins/agentic-core/shared/lib/check-onboarding-gate.test.sh
bash plugins/agentic-core/shared/lib/check-serve-notice.test.sh
```
