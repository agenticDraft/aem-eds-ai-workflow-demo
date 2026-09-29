---
description: The plan gate's four criteria, written as answerable yes/no questions, plus the minimal plan shape they read. Every reader or writer of a plan-gate outcome references this file rather than restating the criteria inline.
---

# Plan criteria

`gate-contract.md` fixes what a gate is; this file is the plan gate's own deliverable — its four
criteria, each one a question with only two possible answers. A criterion that cannot be answered
yes or no does not belong here — see `gate-contract.md`'s reject condition.

1. **Does every requirement map to a stage?**
2. **Does every stage trace back to a requirement?** (the same question as "did anything
   unrequested appear", asked the other direction)
3. **Does the dependency order hold?**
4. **Is the verification defined?**

Criteria 1 and 2 are structural: whether a stage id string appears in a requirement's coverage is
checkable by comparing lists, with no judgment involved. Criteria 3 and 4 are not: whether a
given order is *correct*, and whether a given verification statement is actually *sufficient*,
requires understanding what the plan means, not just its shape. Per `gate-contract.md`'s fixed
order, 1 and 2 are a deterministic check that runs first; 3 and 4 are what the gate's reviewing
model answers on whatever survives.

## The plan, minimally

The two structural criteria need a plan to name, for each unit of work it proposes, which
requirement(s) it exists to satisfy. Nothing else about a plan's shape is fixed here — a plan may
carry additional fields (a dependency list per stage, a verification statement per requirement)
for the reviewing model to read when answering criteria 3 and 4; this contract defines only the
two fields the deterministic check consumes.

```yaml
requirements:
  - <requirement id>
  - …
stages:
  - id: <stage id>
    satisfies: [<requirement id>, …]
  - …
```

**`requirements`** is the closed list of what this plan is answerable to — one entry per
requirement id, unique within the list. **`stages`** is the work the plan proposes; each stage
names the requirement id(s) it exists to satisfy. A route's mandatory reserved stages (`intake`,
`deliver`, `plan-gate` and `publish-gate` themselves) are structural — every route carries them
regardless of what requirements exist — and are out of scope for this shape: this is the plan
*under review*, the proposed work between intake and delivery, not the route skeleton around it.

## Field rules

- `requirements` — non-empty. Duplicate ids are a contract violation, not a later entry silently
  shadowing an earlier one — the same rule `artifact-registry.md` holds its own `id` field to.
- `stages` — non-empty. Each entry's `satisfies` list is required, even when it would be empty;
  an empty list is exactly criterion 2 failing for that stage, not a stage exempted from the
  question.
- A `satisfies` entry naming a requirement id absent from `requirements` does not count toward
  covering that (nonexistent) requirement, and does not exempt the stage from criterion 2 either —
  the stage still needs at least one entry that resolves to a real requirement.

## Design relevance — a finding, never a criterion

When the item carries a design reference, the plan gate's deterministic half also asks whether the
design is about the same thing as the item. It is not a fifth criterion: it cannot fail the gate
and never asks a question. It only adds a finding.

- **Item keywords** — the tokens of the sanitized spec's summary (its first `# ` heading) and of
  each entry of the fact record's `components`.
- **Design names** — the design reference's `node_name`, and every `data-name` attribute value in
  the design-context file its `design_context.code_file` names — never a fixed path. Leading
  `Desktop/`, `Mobile/` and `Component/` are removed. These are element names; text between tags is
  rendered copy and is never read.
- **Tokens** — both sides alike: split at camel case and at every character that is not an ASCII
  letter or digit, lower-cased; tokens shorter than 3 characters, of digits only, or on the
  checker's fixed stop-word list are dropped; a trailing `s` (not `ss`) is dropped from a token of 4
  or more characters. The stop-word list is stated in the checker and printed by `--stop-words`.
- **Score** — the number of distinct design names with at least one token among the item keywords.

| Outcome | When | The gate |
|---|---|---|
| `match` | 2 or more matching names | records the line in its report; no finding |
| `low` | fewer than 2 | records a finding naming both keyword lists; at most `warn` |
| `not run` | the item has no design reference, or the reference's `design_context` is null | records the line in its report; no finding |

A checker that cannot run to a decision (exit `2`) is recorded as a finding naming its error — it
still never fails the gate.

Checker: `lib/check-design-relevance.sh <root> <spec> <fact record> <design reference>` — exit `0`
on every decision, first stdout line `relevance: match | low | not run (…)`; `2` for a usage error.
Fixtures: `fixtures/design-relevance/`.

```bash
bash plugins/agentic-core/shared/lib/check-design-relevance.test.sh
```

## Anti-patterns

- A stage with an empty `satisfies` list, on the theory that it is "obviously needed" — if it is,
  some requirement should name it; if no requirement does, criterion 2 is doing its job.
- A criterion phrased so its answer could be "sort of" or "mostly" — see `gate-contract.md`'s
  reject condition.
- Answering a `low` relevance score with `fail`, or reading a design's rendered copy as its names.
- Treating criteria 3 and 4 as skippable because 1 and 2 passed. Passing the deterministic half is
  what earns criteria 3 and 4 a model's attention, not a reason to skip them.

## Reference, not restatement

A skill or script that reads a plan or a plan-gate outcome references this file with one line
rather than restating the criteria or the plan shape inline, the same convention
`artifact-registry.md` and `pack-manifest.md` use for their own contracts.

## Fixtures

`fixtures/plan-criteria/clean.yaml` — every requirement mapped, every stage requested.
`fixtures/plan-criteria/invalid/` — one fixture per rejection case: `missing-stage-for-
requirement.yaml` (a requirement no stage satisfies), `unrequested-stage.yaml` (a stage naming a
requirement id that does not exist), `empty-satisfies.yaml` (a stage with an empty list),
`duplicate-requirement.yaml` (two requirements sharing an id).

## Verification

`lib/check-plan-criteria.sh <path-to-plan-file>` is the deterministic checker for criteria 1 and
2 — no model involved. It exits `0` and prints `valid: plan (<n> requirements, <m> stages)` for a
plan where both structural criteria hold, `1` with `invalid: <reason>` on stderr naming the exact
requirement or stage that failed, `2` for a usage error.

```bash
bash plugins/agentic-core/shared/lib/check-plan-criteria.test.sh
```
