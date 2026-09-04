---
description: The fixed contract shared by both gate stage ids — plan-gate and publish-gate — the order deterministic checks run in relative to a reviewing model, and what each verdict means. Every reader of a gate's outcome references this file rather than restating the contract inline.
---

# Gate contract

Two stage ids carry a fixed contract, present in any route that publishes:

- **`plan-gate`** — runs after planning, before implementing. Reviews the plan a prior stage
  produced against `plan-criteria.md`'s four criteria.
- **`publish-gate`** — runs before `deliver`, on the actual change rather than a description of
  it. Its own criteria are not this file's to invent — see Open below.

**Never does:** replace either gate's own criteria doc with prose here (each gate's criteria are
its own deliverable, not restated in this shared contract), or grant either gate special runner
behaviour — both resolve, spawn and branch exactly like any other stage id.

## Both are ordinary stages

Resolved from the pack manifest, spawned as subagents, emitting the result envelope — see
`stage-runner.md` and `result-envelope.md`. No second invocation mechanism, no runner code path
that treats a gate differently from any open, pack-declared stage id.

## Fixed order: deterministic checks first, judgment second

The cheapest review is no model at all. Everything mechanically checkable about what a gate is
reviewing is a deterministic script, run before any reviewing model starts — for `plan-gate`,
that is `check-plan-criteria.sh`. What survives the deterministic pass is judgment by
construction: a criterion a script could answer would already have been a script, not a question
handed to a model. This is why a gate adapter runs on a stronger model tier than an ordinary
stage — declared per adapter in the pack that supplies it, never fixed in the core.

**A criterion that cannot be answered yes or no does not belong in a gate.** A gate whose
criteria admit "sort of" or "mostly" cannot fail cleanly, and a check that cannot fail is not a
check — it produces agreeable noise instead of a verdict. Every criterion a gate states, whether
answered by a script or by a reviewing model, is phrased so only two answers exist.

## Verdict semantics

Both gates emit the same result envelope every stage does, and both read `stage-runner.md`'s
ordinary decision vocabulary — nothing about being a gate changes what a verdict means:

- `verdict: fail` — terminal. The run ends `failed`, the same outcome any other stage's `fail`
  produces.
- `verdict: warn` — the run continues; the finding is recorded, not silently dropped.
- An envelope that fails to validate, or a deterministic check that could not run to a verdict at
  all, is a contract violation — indistinguishable in consequence from any other stage's
  unparseable return.

## Adapter hardening

A gate adapter is read-only, runs in an isolated worktree, and reports findings it is confident
in rather than everything it noticed — confidence-based filtering, not exhaustive listing. These
are obligations on whichever pack supplies the gate's adapter skill; this contract states them,
it does not enforce them mechanically.

## Open

`publish-gate`'s own criteria — reviewing the actual change rather than a plan describing it — are
not designed here. Naming criteria before the work that needs them exists produces guessed
criteria nobody has evidence for; the same restraint `plan-criteria.md`'s deterministic check
applies to only what is actually checkable applies to not inventing a second gate's questions in
advance of a task scoped to build them.

## Reference, not restatement

A skill or script that resolves or reads a gate's outcome references this file with one line
rather than restating the order or verdict semantics inline, the same convention `stage-runner.md`
and `result-envelope.md` use for their own contracts.

## Fixtures

No fixtures of its own: this file states the contract shared by both gate ids. `plan-gate`'s own
deterministic check has its fixtures under `fixtures/plan-criteria/` — see `plan-criteria.md`.
