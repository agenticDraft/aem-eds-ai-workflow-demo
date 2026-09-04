---
description: The three terminal states a run can end in — delivered, blocked, failed — their causes and required output. Every reader or writer of a run's end references this file rather than restating the table inline.
---

# Terminal states

**Exactly three states end a run** (core contract §10). Nothing else does — a stage returning
`warn` continues, with the warning recorded, never terminal.

| State       | Cause                                                          | Required output                                    |
| ----------- | --------------------------------------------------------------- | --------------------------------------------------- |
| `delivered` | `deliver` returned `pass`                                    | The status table, and the published location.      |
| `blocked`   | Question unanswered, budget exhausted, or a pre-flight failure | What is missing, and where it was recorded.        |
| `failed`    | A stage returned `fail`, or a contract violation             | The failing stage, and its summary.                |

**Never does:** decide *which* state a run ends in — that decision is already made by
`stage-runner.md`'s and `question-protocol.md`'s decision vocabularies below — or perform the
cleanup a terminal state triggers (`run-state.md`'s `finalize-run-state.sh` deleting
`run-state.json` on `delivered`; the orchestration marker's removal, the route driver's job per
core contract §9). This contract only fixes what gets printed once a state is reached.

## Where each state comes from

Reuses `stage-runner.md`'s and `question-protocol.md`'s decision vocabularies rather than
inventing a fourth one:

- **`delivered`** — the `deliver` stage's own decision was `continue` (`verdict: pass`). Unlike
  every other stage, `deliver` has no next stage to continue to, so whichever skill drives the
  route treats its `continue` as the run's end rather than an advance.
- **`blocked`** — `question-protocol.md`'s `terminate-blocked`: an interactive run's per-run
  question cap exhausted, or an autonomous run's blocker written back. A pre-flight capability
  check, once built, produces this same state for a capability missing before any stage runs.
- **`failed`** — `stage-runner.md`'s `terminate-failed` (the stage's own `fail` verdict) or
  `terminate-contract-violation` (an unresolvable stage id, or an envelope that fails validation).
  Both end the run `failed`; only the report to a human distinguishes which one happened —
  `stage-runner.md`'s anti-patterns section already forbids collapsing that distinction.

## Anti-patterns

- Ending a run on `warn`. It is not a terminal state; the run continues past it.
- Inventing a fourth terminal state, or reporting a stage's outcome without mapping it to one of
  the three.
- Printing the status table before a run has actually reached `delivered` — `progress-output.md`
  already reserves that table for the final summary, emitted once.
- Deleting `run-state.json` or removing the orchestration marker from inside this contract's own
  formatter. Both are the caller's responsibility, using the scripts `run-state.md` and core
  contract §9 already define.

## Reference, not restatement

A skill or script that reports a run's end references this file with one line rather than
restating the three-state table or the required output inline, the same convention
`stage-runner.md` and `question-protocol.md` use for their own contracts.

## Fixtures

No fixtures of its own: `lib/resolve-terminal-state.sh` exercises the progress fixture already
under `fixtures/progress/status-table-mixed.txt` (via `print-status-table.sh`, reused rather than
reimplemented) for the `delivered` case; `blocked` and `failed` take their inputs as arguments
directly, since neither reads a file of its own.

## Verification

`lib/resolve-terminal-state.sh <delivered|blocked|failed> <state-specific args>` is the
deterministic formatter — no model involved, no side effects. It exits `0` and prints:

- `delivered <progress-file> <published-location>` — `terminal: delivered`, the status table (via
  `print-status-table.sh`), then `published: <location>`.
- `blocked <missing> <recorded-at>` — `terminal: blocked`, `missing: <missing>`, `recorded:
  <recorded-at>`.
- `failed <stage-id> <summary>` — `terminal: failed`, `stage: <stage-id>`, `summary: <summary>`.

Exits `2` with `invalid: <reason>` on stderr for any other first argument — including `warn`,
named explicitly so "a run never ends on warn" is enforced, not just documented — for a missing
state, for the wrong argument count for the given state, or (for `delivered`) a progress file that
does not exist.

```bash
bash plugins/agentic-core/shared/lib/resolve-terminal-state.test.sh
```
