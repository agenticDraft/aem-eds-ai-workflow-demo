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

- **platform** — `kind`, `stages`, `always_autonomous`, `artifacts`. All four required; the last
  two may be empty (`[]`) but must be present, the same way an empty `artifacts` list is present
  on every result envelope rather than omitted.
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

- `always_autonomous` or an artifact's `produced_by` naming a stage id absent from `stages`.
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

`fixtures/pack-manifest/platform-valid/` and `fixtures/pack-manifest/provider-valid/` are
well-formed examples, each a small pack root with a matching `skills/` directory.
`fixtures/pack-manifest/platform-invalid/` and `fixtures/pack-manifest/provider-invalid/` hold one
fixture directory per rejection case the validator must catch: `unknown-stage-always-autonomous`,
`unknown-stage-artifact-producer`, `dangling-skill`, `stage-not-isolated`, `unfilled-placeholder`
(platform); `missing-operation`, `unknown-operation`, `dangling-skill` (provider).

## Verification

`lib/validate-pack-manifest.sh <path-to-pack.yaml>` is the deterministic checker — no model
involved. It exits `0` and prints `valid: <kind>` for a conformant manifest, `1` with
`invalid: <reason>` on stderr for a contract violation, `2` for a usage error. Run its test suite
with:

```bash
bash plugins/agentic-core/shared/lib/validate-pack-manifest.test.sh
```
