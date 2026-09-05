---
description: The pack manifest schema — platform and provider shapes. Every reader of a pack.yaml validates against this file rather than restating the shape inline.
---

# Pack manifest

A pack declares itself with `pack.yaml` at its own root, alongside its `skills/` directory. There
are two kinds, each with its own fixed shape.

## Location

`pack.yaml` at the root of the pack. Skills it names resolve to
`<pack root>/skills/<skill name>/SKILL.md`.

## Format — platform pack

```yaml
kind: platform
stages:
  <stage id>: <skill name>
  …
always_autonomous: [<stage id>, …]
artifacts:
  - id: <artifact id>
    produced_by: <stage id>
    path: "<relative path>"
  …
skip_when_missing:            # optional
  <stage id>: "<relative path>"
  …
```

## Format — provider pack

```yaml
kind: provider
role: tracker | scm | design | browser
operations:
  <operation name>: <skill name>
  …
unsupported: [<operation name>, …]
```

## Top-level keys

Fixed per kind, in order.

- **platform** — `kind`, `stages`, `always_autonomous`, `artifacts`, `skip_when_missing`. The
  first four are required; the second and third may be empty (`[]`) but must be present, the same
  way an empty `artifacts` list is present on every result envelope rather than omitted.
  `skip_when_missing` is the one optional key in either shape, and always last: a pack that skips
  no stage omits it entirely rather than writing it empty.
- **provider** — `kind`, `role`, `operations`, `unsupported`. All four required; `unsupported` may
  be empty (`[]`) but must be present.

## Field rules — platform

- `stages` — one or more entries, each a stage id mapped to a skill name. The stage ids a
  platform pack declares here are the ones a route may reference; nothing outside this document
  fixes the vocabulary (open stage ids per the core contract).
- `always_autonomous` — every entry must be a stage id present in `stages` above. A stage id here
  that is not a key of `stages` is a dangling reference — **binding an unknown stage**.
- `artifacts` — every entry's `produced_by` must be a stage id present in `stages` above, for the
  same reason. `id` names the artifact; `path` is the relative path it is written to.
- Every skill name that appears anywhere in the manifest — every value in `stages` — must resolve
  to `<pack root>/skills/<skill name>/SKILL.md`. A skill name with no matching directory is a
  **dangling skill reference**.
- Every skill named as a value in `stages` must declare isolated execution in its own
  frontmatter — the literal key is `context: fork`. Every stage runs as an isolated subagent
  (see `stage-runner.md`); a skill that omits the declaration still resolves and still returns a
  valid envelope, so nothing about a run visibly fails — what fails silently is the cost model,
  because that stage's context then accumulates in whichever component drives the route instead of
  dying with the stage. This check applies only to a platform pack's stage skills, never to a
  provider pack's operation skills.
- `skip_when_missing` — optional. Each entry names a stage id from `stages` above and one path,
  relative to the **project root** (never the pack root): when that path does not exist, the stage
  is skipped on this run. This is the only thing that causes a stage to be skipped — see "Why a
  skip is declared here" below. Each stage id appears at most once; an absolute path, an empty
  path, a duplicate stage id, a stage id absent from `stages`, or the key present with no entries
  is a contract violation. `intake` and `deliver` may never appear: every route begins with one and
  ends with the other (core contract §4), so a route that skipped `intake` would have no fact
  record to resolve itself from, and one that skipped `deliver` could never reach `delivered`.

## Why a skip is declared here

A skip is a **property of the pack**, fixed when the pack is authored, not something a running
stage decides. The pack author knows that its `publish-gate` stage has nothing to do without a gate
input, or that its design stage is inert without a design reference; a stage in the middle of a run
does not know the route's shape and has no standing to alter it.

That keeps the direction of control one-way, which two other contracts already depend on:

- A result envelope stays a **report**, never a directive. `result-envelope.md` says `next_action`
  is *"a short phrase … never an instruction to the runner — a name, not a directive."* Reading a
  skip out of an envelope would have made that field the one exception.
- The skip state is **recomputable from disk at any moment**, so nothing has to remember it.
  `progress-output.md` already forbids caching a `<total>` across a skip decision, precisely
  because a skip can appear or disappear between two stages — a stage that writes the missing path
  un-skips a later stage automatically, with no bookkeeping anywhere.

There is deliberately exactly one condition kind — path absent. It covers the cases a delivery
route actually has, and a richer condition language is a thing to add when a real pack needs one,
not before.

**A failed stage is not a skip cause.** A `fail` verdict terminates the run (`terminal-states.md`),
so there are never downstream stages left to skip.

## Field rules — provider

- `role` — exactly one of the four core roles: `tracker`, `scm`, `design`, `browser`. Each role
  has a fixed set of operation names it must account for:
  - `tracker` — `fetch_item`, `post_note`, `attach_file`, `list_types`
  - `scm` — `create_branch`, `publish_change`, `check_status`
  - `design` — `fetch_reference`
  - `browser` — `render`, `capture`, `measure`
- `operations` — a mapping of operation name to skill name. Every key must be an operation that
  role actually has; an operation name outside that role's set is a contract violation, not a
  typo to tolerate.
- `unsupported` — a list of operation names this pack declines to implement. Every entry must be
  an operation that role actually has, and must not also be a key of `operations` — an operation
  cannot be both implemented and declared unsupported.
- **Completeness.** Every operation the declared role has must appear either as a key of
  `operations` or as an entry of `unsupported`. One that appears in neither is silently missing —
  the runner would only discover it mid-run.
- Every skill name that appears as a value in `operations` must resolve to
  `<pack root>/skills/<skill name>/SKILL.md`. A skill name with no matching directory is a
  **dangling skill reference**.

## Example — platform

```yaml
kind: platform
stages:
  intake: intake
  implement: implement
  deliver: deliver
always_autonomous: [deliver]
artifacts:
  - id: fact-record
    produced_by: intake
    path: ".ai/run-context/fact-record.yaml"
  - id: change-summary
    produced_by: implement
    path: ".ai/run-context/change-summary.md"
```

## Example — provider

```yaml
kind: provider
role: tracker
operations:
  fetch_item: fetch
  post_note: note
  attach_file: attach
  list_types: list
unsupported: []
```

## Anti-patterns

- `always_autonomous`, an artifact's `produced_by`, or a `skip_when_missing` key naming a stage id
  absent from `stages`.
- A `skip_when_missing` path that is absolute, empty, or declared twice for the same stage; or the
  key present with no entries.
- A stage announcing a skip from inside its own result envelope. A skip is declared by the pack,
  evaluated from disk, and owned by whatever drives the route — see "Why a skip is declared here".
- `operations` or `unsupported` naming an operation outside the declared role's set.
- An operation in both `operations` and `unsupported`.
- A role operation in neither `operations` nor `unsupported`.
- A skill name with no `<pack root>/skills/<skill name>/SKILL.md` on disk.
- A stage skill's frontmatter omitting `context: fork`.
- A top-level key outside the fixed set for the manifest's `kind`, or one of the required keys
  missing.
- Any file under the pack root — `pack.yaml` or any `skills/*/SKILL.md` — containing the literal
  sequence `{{`, the reserved marker for an unfilled template placeholder. A pack generated from a
  template (core contract §7.1) that still carries one is a failed setup, not a pack with a hole in
  it (core contract §13 validator 10).

## Reference, not restatement

A skill or script that reads a pack manifest references this file with one line rather than
restating the shape inline, the same convention `project-config.md` and `result-envelope.md` use
for their own contracts.

## Fixtures

`fixtures/pack-manifest/platform-valid/`, `fixtures/pack-manifest/platform-valid-skip-conditions/`
(the same pack plus a `skip_when_missing:` block) and `fixtures/pack-manifest/provider-valid/` are
well-formed examples, each a small pack root with a matching `skills/` directory.
`fixtures/pack-manifest/platform-invalid/` and `fixtures/pack-manifest/provider-invalid/` hold one
fixture directory per rejection case the validator must catch: `unknown-stage-always-autonomous`,
`unknown-stage-artifact-producer`, `dangling-skill`, `stage-not-isolated`, `unfilled-placeholder`,
`skip-condition-unknown-stage` (platform); `missing-operation`, `unknown-operation`,
`dangling-skill` (provider). The remaining `skip_when_missing` rejection cases — a duplicate stage
id, an absolute path, an empty block — are shape errors inside one block, written inline in the
validator's test suite rather than given a fixture directory each.

## Verification

`lib/validate-pack-manifest.sh <path-to-pack.yaml>` is the deterministic checker — no model
involved. It exits `0` and prints `valid: <kind>` for a conformant manifest, `1` with
`invalid: <reason>` on stderr for a contract violation, `2` for a usage error. Run its test suite
with:

```bash
bash plugins/agentic-core/shared/lib/validate-pack-manifest.test.sh
```

`lib/evaluate-skip-conditions.sh <path-to-pack.yaml> [project-root]` evaluates the
`skip_when_missing` map against a project's current state and prints one `skipped: <stage id>` line
per skipped stage, in manifest order — nothing when none is. Also deterministic, also no model, and
safe to re-run at any point in a run. Its test suite:

```bash
bash plugins/agentic-core/shared/lib/evaluate-skip-conditions.test.sh
```
