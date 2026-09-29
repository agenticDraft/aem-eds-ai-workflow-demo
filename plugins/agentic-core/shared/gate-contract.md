---
description: The fixed contract shared by both gate stage ids — plan-gate and publish-gate — the order deterministic checks run in relative to a reviewing model, and what each verdict means. Every reader of a gate's outcome references this file rather than restating the contract inline.
---

# Gate contract

Two stage ids carry a fixed contract, present in any route that publishes:

- **`plan-gate`** — runs after planning, before implementing. Reviews the plan a prior stage
  produced against `plan-criteria.md`'s four criteria.
- **`publish-gate`** — runs before `deliver`, on the actual change rather than a description of
  it. Reviews the change against `publish-criteria.md`'s four criteria.

**Never does:** replace either gate's own criteria doc with prose here (each gate's criteria are
its own deliverable, not restated in this shared contract), or grant either gate special runner
behaviour — both resolve, spawn and branch exactly like any other stage id.

## Both are ordinary stages

Resolved from the pack manifest, spawned as subagents, emitting the result envelope — see
`stage-runner.md` and `result-envelope.md`. No second invocation mechanism, no runner code path
that treats a gate differently from any open, pack-declared stage id.

## Fixed order: deterministic checks first, judgment second

The cheapest review is no model at all. Everything mechanically checkable about what a gate is
reviewing is a deterministic script, run before any reviewing model starts — `check-plan-
criteria.sh` and `check-design-relevance.sh` for `plan-gate`, `check-publish-criteria.sh` for
`publish-gate`. What survives the
deterministic pass is judgment by
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
- `verdict: warn` — the run continues; the finding is recorded in the gate's report,
  `.ai/run-context/<gate id>-report.md` under its given `project_root`, not silently dropped.
- An envelope that fails to validate, or a deterministic check that could not run to a verdict at
  all, is a contract violation — indistinguishable in consequence from any other stage's
  unparseable return.

## Adapter hardening

A gate adapter writes exactly two files, both under the `project_root` it is given (see below),
on every verdict:

- `.ai/run-context/<gate id>-report.md` — its findings, listed under the envelope's `artifacts:`;
- `.ai/run-context/envelope-<gate id>.txt` — its envelope.

It writes nothing else: no other file under `project_root`, nothing in its own worktree, nothing
through any role. It runs in an isolated worktree, and reports findings it is confident in rather
than everything it noticed — confidence-based filtering, not exhaustive listing. These
are obligations on whichever pack supplies the gate's adapter skill. The write rule alone is also
enforced, by the driver, under `project_root` (see "The driver guards the tree" below).

## Isolation is checked, not assumed

The harness may run a gate without its isolated worktree, and nothing tells the gate or the driver
when it does. So a gate checks it itself, before reviewing anything: compare its own working
directory with the `project_root` it was given, both resolved to physical paths (`pwd -P`).

- **Different** — isolated. Review as usual.
- **Equal** — not isolated. Record `isolation: absent` in the report, and return at most `warn`: a
  review that would pass returns `warn` instead, and a `fail` stays `fail`. **Review anyway.** An
  unisolated gate is still a working review; it is the read-only guarantee that is weaker, and the
  driver's guard below covers that.

Never refuse to run, and never `fail`, only because the gate is not isolated.

## The driver guards the tree

The driver takes a snapshot of `project_root` right before it invokes either gate, and compares it
right after the gate returns, with `shared/lib/check-tree-unchanged.sh`. The snapshot holds `HEAD`
and every tracked change and untracked file, each with a hash of its content. The allowlist is
exactly the gate's two files above.

- **No change outside the allowlist** — the gate's envelope is judged as usual.
- **Any other change** — a moved `HEAD`, or any tracked or untracked path added, edited, staged,
  reverted or deleted — the gate's stage ends `fail`, whatever its envelope says. The guard names
  every such path.

This makes "a gate writes nothing else" hold with or without the harness's isolation. It does not
see files ignored by version control, and it does not see writes outside `project_root`.

## The run context is given, never inferred

A gate runs in an isolated worktree, which holds tracked files only — so the run's own
`.ai/run-context/` is absent from it, and the gate has to read that directory from the checkout the
run is actually in. **That location is passed to the gate; the gate never derives it.** The runner
knows its own working directory with certainty and hands it over as the gate's one invocation
argument, `project_root:`.

Deriving it instead is what this rule exists to forbid, because every ambient source a gate can
reach names the wrong directory. A gate's own working directory is its temp worktree, not the
run's; its gitdir pointer resolves back to that same temp worktree; and a repository's shared
metadata directory — `git rev-parse --git-common-dir` — is by definition identical for every
worktree, so its parent is always the **main** checkout, whichever checkout the run is in. Each of
these is right exactly when the run happens to be in the main checkout, and silently wrong
otherwise.

**Before reviewing anything, a gate proves the given root belongs to its own run.** Read
`<project root>/.ai/run-context/fact-record.yaml` and compare its `item_id` against the one the
artifact under review carries. On a mismatch — or if either file is absent — report a contract
violation naming both paths, and review nothing.

Know what this check does and does not catch (G97). It catches a gate that ignored the root it was
given. It does **not** separate two runs of the *same* work item: re-running one item from a second
checkout leaves two run contexts that both name that item, and the comparison passes on either.
Until a run-scoped identity replaces it, a gate that finds itself reading a context it was not
handed should say so rather than assume a matching `item_id` proves anything.

This check is not defensive padding. A wrong root does not produce a missing file: it produces a
*plausible* one, of the right shape, belonging to a different run, which every later step then
reads without complaint — confirmed by direct measurement, twice, on both gates (G89). A gate that
skips the comparison can return a confident verdict about a change it never saw. Plausibility is
not identity, and only an explicit comparison turns that silent wrong answer into a loud one.

## Reference, not restatement

A skill or script that resolves or reads a gate's outcome references this file with one line
rather than restating the order or verdict semantics inline, the same convention `stage-runner.md`
and `result-envelope.md` use for their own contracts.

## Fixtures

No fixtures of its own: this file states the contract shared by both gate ids. `plan-gate`'s own
deterministic check has its fixtures under `fixtures/plan-criteria/` — see `plan-criteria.md`.
`publish-gate`'s own deterministic check reads live git state rather than a fixture file — see
`publish-criteria.md`.
