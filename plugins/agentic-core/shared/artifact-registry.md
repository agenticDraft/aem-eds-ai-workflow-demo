---
description: The core artifact registry — the fixed shape of a registry entry, the closed set of valid producers, and the data file that lists what the core actually ships. Every reader checking whether a core-owned artifact is real, rather than a line of prose, validates against this file rather than restating the shape inline.
---

# Artifact registry

The core owns a small set of cross-stage artifacts — files one stage writes and a later stage, or
the runner itself, reads. A platform pack owns a different, larger set of its own, declared in its
own `pack.yaml` (see `pack-manifest.md`'s `artifacts:` field) and checked against that pack's own
stage ids. This file is the core's own registry: fixed, versioned, and never extended by a pack.

**Never does:** describe a pack's own artifacts (that is `pack-manifest.md`'s job), or validate an
artifact's actual on-disk content against `required_content` — this contract fixes only the
registry's own shape and its producer vocabulary. Checking a fact record's `item_id` or a run
state's route id is a separate contract's job (`run-state.md`, and whichever contract owns each
other artifact), not this one's.

## Format

A bare list, one entry per core-owned artifact:

```yaml
- id: <artifact id>
  version: "<major.minor>"
  produced_by: <producer>
  required_content: <what the artifact must contain, in prose>
  validation: <the rule that content must satisfy, in prose>
  …
```

## Field rules

- `id` — names the artifact. Unique across the registry; two entries sharing an id is a contract
  violation, not a later entry silently shadowing an earlier one.
- `version` — bumped when the artifact's shape changes, so a stale reader can tell at a glance
  that what it is holding no longer matches what it expects.
- `produced_by` — the one thing this contract checks structurally. Must be one of the core's own
  fixed producers:
  - `intake` — the reserved first stage of every route
  - `deliver` — the reserved last stage of every route
  - `plan-gate` — the gate stage after planning, before implementing
  - `publish-gate` — the gate stage before `deliver`
  - `runner` — the core component that drives a route, not a stage a pack supplies
  An artifact naming anything else — an open, pack-declared stage id included — is a **producer
  that does not exist**: this registry is the core's own, and the core's own producers are this
  closed set, never a pack's vocabulary.
- `required_content` and `validation` — both required on every entry, present even when short.
  Their content is prose read by whoever implements the artifact's actual writer or reader; this
  contract only checks that both fields exist, not that the prose is followed.

## Anti-patterns

- An entry with no `produced_by` at all — the field is present but empty, or missing outright.
- An entry naming an open, pack-declared stage id as its producer. A core-owned artifact is never
  produced by a pack's own stage.
- Two entries sharing an `id`.
- An entry missing `required_content` or `validation` — a registry entry that only names an
  artifact and its producer, with no stated shape or rule, is a placeholder, not a real entry.
- Treating this file's prose as the registry itself. The registry a validator reads is the data
  file below; this document is the shape that data must conform to.

## Reference, not restatement

A skill or script that reads the artifact registry references this file with one line rather than
restating the producer vocabulary or field list inline, the same convention `pack-manifest.md` and
`run-state.md` use for their own contracts.

## The registry itself

`lib/artifact-registry.yaml` is the data — the core's seven artifacts as they are actually built:
the fact record and sanitized spec (both `intake`), run state, progress and the orchestration
marker (all `runner`), the question-answer file the question protocol writes at a stage
boundary (`runner`), and the analytics file rendered from the session transcript at a terminal
state (`runner`). An eighth artifact earns a row here only when a later task actually ships it,
never in anticipation of one.

## Fixtures

`fixtures/artifact-registry/valid.yaml` is a well-formed registry that exercises every one of the
five valid producers, including two — `plan-gate` and `publish-gate` — the real registry does not
currently use, so the producer check is proven against the full vocabulary rather than only the
subset the shipped data happens to exercise. `fixtures/artifact-registry/invalid/` holds one
fixture per rejection case: `no-producer.yaml`, `unknown-producer.yaml`, `missing-field.yaml`,
`duplicate-id.yaml`.

## Verification

`lib/validate-artifact-registry.sh <path-to-registry-file>` is the deterministic checker — no
model involved. It exits `0` and prints `valid: artifact registry (<n> entries)` for a conformant
registry, `1` with `invalid: <reason>` on stderr for a contract violation, `2` for a usage error.
Run its test suite with:

```bash
bash plugins/agentic-core/shared/lib/validate-artifact-registry.test.sh
```

The suite runs the validator against `lib/artifact-registry.yaml` itself, not only against
fixtures — the same practice `validate-naming-rule.test.sh` follows, so a defect in the real,
shipped registry is caught here rather than only in a fixture that stands in for it.
