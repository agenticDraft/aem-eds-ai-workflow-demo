---
description: The stage runner's job and decision vocabulary. Every reader of a stage's outcome references this file rather than restating the shape inline.
---

# Stage runner

For one stage in a resolved route, the runner does exactly four things, in order: resolve which
skill implements the stage from the platform pack manifest, spawn that skill as an isolated
subagent, read the subagent's result envelope, and branch on its verdict. Print and record are the
same loop's remaining two responsibilities, carried by later steps once a decision exists.

**Never does:** read a file the stage produced, parse anything in the subagent's output other than
the envelope block, or retry a stage that returned `fail`. A stage's own fix loop, if it has one,
is internal to that stage — the runner sees only the final envelope.

## Resolving the adapter

A stage id resolves to a skill name by looking it up in the platform pack manifest's `stages:`
map — see `pack-manifest.md`. A stage id absent from that map is a contract violation: the route
resolver only ever hands the runner stage ids that exist somewhere, but a pack that dropped one
from its manifest after a route was resolved is exactly the drift this check catches.

## Reading the envelope

The subagent's return is read as a result envelope — see `result-envelope.md`. A return that does
not validate against that contract (an unknown verdict, a missing `artifacts:` list, trailing
text, or no `## Result` block at all) is a **contract violation**, indistinguishable in
consequence from a stage that never ran: the runner cannot know what happened, so it cannot
continue.

## Decision vocabulary

Every stage produces exactly one of these outcomes:

| Outcome                       | From                             | Meaning                                          |
| ------------------------------ | --------------------------------- | ------------------------------------------------- |
| `continue`                   | `verdict: pass`                 | Proceed to the next stage.                        |
| `continue-warn`               | `verdict: warn`                 | Proceed to the next stage; the warning is recorded, not silently dropped. |
| `terminate-failed`           | `verdict: fail`                 | The run ends `failed`. Not a contract violation — the stage ran, evaluated its own work, and reported failure. |
| `terminate-contract-violation` | an unresolvable stage id, or an envelope that fails validation | The run ends `failed`. The runner cannot tell what the stage did. |

`verdict: question` is read and reported like any other verdict, but what happens next — asking at
the stage boundary, autonomous mode's write-back, the per-run budget — belongs to
`question-protocol.md`, a separate contract. This file does not define a decision for it.

## Anti-patterns

- Branching on anything in the subagent's transcript above the `## Result` block.
- Opening a path listed under the envelope's `artifacts:` — the runner hands paths forward, it
  never reads them.
- Re-spawning a stage that returned `terminate-failed`, with or without changed input.
- Treating `terminate-failed` and `terminate-contract-violation` as the same case in a report to a
  human — one is the stage's own judgment, the other is the runner's inability to read it.

## Reference, not restatement

A skill or script that resolves a stage or reads its outcome references this file with one line
rather than restating the decision vocabulary inline, the same convention `pack-manifest.md` and
`result-envelope.md` use for their own contracts.

## Fixtures

No fixtures of its own: `lib/run-stage.sh` exercises the platform pack manifest fixtures already
under `fixtures/pack-manifest/platform-valid/` (as the stub adapters a stage id resolves against)
together with the result envelope fixtures under `fixtures/result-envelope/` (as the stage
outcomes a decision is read from).

## Verification

`lib/run-stage.sh <path-to-pack.yaml> <stage id> <path-to-envelope>` is the deterministic
implementation of this file — no model involved in the branching itself; only the actual spawn
step (choosing the runtime action for the resolved adapter) sits above this script, in whichever
skill drives a full route. It exits `0` and prints `decision: continue` or `decision:
continue-warn`, `1` with `invalid: <reason>` on stderr and `decision: terminate-contract-violation`
for a contract violation, `3` and `decision: terminate-failed` for a stage's own `fail` verdict,
`2` for a usage error. Run its test suite with:

```bash
bash plugins/agentic-core/shared/lib/run-stage.test.sh
```
