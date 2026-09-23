---
description: The error-class contract. Every stage adapter and every provider operation classifies a failure before recovering from it, and reports the class in the result envelope. Reference this file rather than restate the classes inline.
---

# Error handling

**Classify before recovering. Never retry blindly.**

A failure belongs to exactly one of three classes. The class decides what the failing operation
does next, and it travels to the caller in the result envelope's `error_class` field — see
`result-envelope.md` for that field's syntax and the verdicts it is valid with.

A caller branches on the class, so the class is determined from what actually failed, never
assumed from what usually fails. Where no class fits cleanly, report the closest one and quote the
underlying error verbatim, so the caller can see what the classification was made from.

## The three classes

### `TRANSIENT`

The operation could succeed unchanged if it ran again. Nothing about the request is wrong and
nothing about the environment is missing — it is busy, rate-limited, or not ready yet.

Typical: a rate limit or quota response; a request that timed out; a local endpoint not yet
accepting connections.

**Recovery: retry twice, backing off 2 seconds then 4 seconds.** If the third attempt fails, the
operation is exhausted and **escalates** — see below. Never retry more than that, and never retry a
failure of either other class.

### `VALIDATION`

What the operation was asked to do is wrong. Retrying it unchanged cannot succeed, because the
input, not the environment, is the problem.

Typical: a reference that is malformed, or that names something the provider has no record of;
content that does not satisfy a contract the next stage will read; a check that the operation is
expected to make pass and cannot.

**`VALIDATION` means the input was invalid, whether or not a fix loop exists for it.** Some
VALIDATION failures have a bounded auto-fix loop — the operation edits what was flagged, re-runs
the check, and repeats up to a bound the owning stage declares. That loop is a property some of
these failures have; it is not what makes a failure `VALIDATION`. A failure with no loop to run is
still `VALIDATION`, and stops immediately.

**Recovery: where a bounded loop is declared, run it and re-check, then stop with a diagnosis on
exhaustion.** Where none is declared, stop with the diagnosis at once. The diagnosis names what was
invalid and what would make it valid — never only that a check failed.

### `PERMANENT`

The operation cannot run here at all, and no number of attempts changes that. The request may be
perfectly well formed.

Typical: a required command-line tool that is not installed; credentials that are absent, rejected
or not authorized for this resource; a network destination that is refused rather than slow; an
input file that is present but unreadable as what it claims to be.

**Recovery: none. Stop, report, exit cleanly.** Report through the `tracker` role where the run has
one, so the failure reaches the work item rather than only the console.

## What the classes separate

`TRANSIENT` and `PERMANENT` both describe **the environment the operation ran in** — whether it is
busy or whether it is missing something. `VALIDATION` describes **what the operation was asked to
do**.

That is the distinction a caller branches on. A caller deciding whether some alternative path is
open to it — a second source, a degraded mode, a different input — may take one when the
environment failed, and must not when the request itself was wrong: substituting something the
caller chose for something the request named is a guess, and a guess reported as a result is worse
than the failure it replaced.

## Escalation

`TRANSIENT` exhaustion does not return `fail`. It returns **`verdict: question`**, because a
human doing one concrete thing — waiting for a window to reset, starting a service, refreshing a
credential — is what unblocks it, and the question protocol already routes that to a human in one
execution mode and to the work item in the other. See `question-protocol.md`.

The `blocker` field names **the literal command or action that would unblock it**, not a request to
investigate. "Please investigate" is not a blocker; a command a reader can run is.

`VALIDATION` and `PERMANENT` keep their own shapes — a diagnosis on exhaustion, and a report plus
clean exit, respectively. Neither escalates to a question.

## The escalation report

Whenever an operation escalates or stops, what it emits above the envelope carries four things, in
this order:

1. The class, and the sub-type where the operation knows one.
2. The error exactly as it was returned — first three lines are enough. Never reworded into
   something more general, and never a guess at the cause when the underlying error said something
   else.
3. What was attempted, including how many attempts and over what backoff where a retry ran.
4. The suggested next action, concrete enough to act on.

The envelope's own `summary` carries one sentence of this; the detail sits above the block, which
is where a narrative summary belongs when one is worth writing at all.

## Anti-patterns

- Retrying a `VALIDATION` or `PERMANENT` failure, in the hope that it is really transient.
- Returning `fail` after `TRANSIENT` retries are exhausted, so nothing asks the human who could
  fix it in one step.
- A `blocker` that describes the problem again instead of naming what to do about it.
- Reporting a class the operation did not determine, or omitting `error_class` on a `fail` or
  `question` envelope, which leaves a caller branching on an absent value.
- Widening an error into a more general one — "the provider failed" where the provider said which
  resource was missing.
