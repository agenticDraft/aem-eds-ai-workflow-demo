---
description: The orchestration marker contract — a file's presence and mtime, nothing else. Every reader or writer of the marker references this file rather than restating the lifecycle inline.
---

# Orchestration marker

A single file whose only meaning is its own presence and mtime — see core contract §9. It carries
no fields and no content is ever parsed from it. It exists so an isolated stage adapter, which
starts cold and cannot rely on inheriting the caller's environment, can tell by reading one file
whether it is running inside a route (and should return the result envelope alone) or standalone
(and should also produce a human-facing summary).

**Never does:** carry any field, get read for its content by anything in this contract, or decide
*what* an adapter should do once it knows it is inside a route — that decision belongs to whichever
adapter reads it. This contract fixes only the marker's lifecycle: when it is written, when its
mtime is refreshed, and when it is removed.

## Lifecycle

- **Created** by whichever skill drives a full route, once, before the first stage of a run — the
  same moment `run-state.md`'s `run-state.json` is first written.
- **Refreshed** — its mtime touched forward — after every stage, alongside `run-state.json`'s own
  full rewrite. There is no separate schedule; a caller that refreshes `run-state.json` on a stage
  boundary refreshes this file at the same boundary.
- **Removed** at **every** terminal state — `delivered`, `blocked` and `failed` alike. This is
  the one place this contract's lifecycle differs from `run-state.json`'s: that file is deleted
  only on `delivered` and left in place on `blocked`/`failed` for a human to inspect, while this
  marker is removed on all three, because its only job is signalling "a route is in progress" and
  no route is in progress once any terminal state is reached.

## Staleness

Carries the same 2-hour window `run-state.md` defines for `run-state.json`, checked the same way:
by the file's own mtime, never by a field inside it (it has none). A marker **less than 2 hours
old** means a route is genuinely in progress. One **2 hours old or older** means the process that
should have refreshed or removed it did not — most likely a crashed run — and is treated as absent:
stale, deleted, not a signal. Without this window, a marker orphaned by a crash would convince
every later standalone invocation, indefinitely, that it is running inside a route it is not.

## Anti-patterns

- Writing any content into the marker and later reading it back. Presence and mtime are the entire
  contract; a reader that parses the file's body is reading something this contract does not
  define.
- Refreshing `run-state.json` on a stage boundary without refreshing this marker at the same
  boundary, or vice versa — the two are written together specifically so neither staleness check
  can trip while the other still looks fresh.
- Leaving the marker in place on a `blocked` or `failed` terminal state "since the human still
  needs to look at things" — that reasoning applies to `progress.md`, which is never deleted, and
  to `run-state.json` on those two states; it does not apply to this marker, which signals only
  whether a route is currently running.
- An adapter treating an absent or stale marker as a contract violation. Standalone execution
  (no marker, or a stale one) is the normal case for an adapter invoked directly rather than through
  a route.

## Reference, not restatement

A skill or script that writes, refreshes, checks or removes the marker references this file with
one line rather than restating the lifecycle or the staleness window inline, the same convention
`run-state.md` and `stage-runner.md` use for their own contracts.

## Fixtures

No static fixtures: like `run-state.md`'s resume/staleness behavior, this contract's own staleness
check is mtime-dependent, so `lib/check-orchestration-flag.test.sh` builds and backdates its own
marker files in a temporary directory rather than reading committed ones whose mtime git does not
preserve meaningfully.

## Verification

`lib/write-orchestration-flag.sh <flag-path>` creates the marker (creating its parent directory if
needed) or, if it already exists, refreshes its mtime — the single call both the initial write and
every per-stage refresh use. Exits `0` and prints `written: <path>` (created) or `refreshed: <path>`
(already existed), `2` for a usage error (missing argument).

`lib/check-orchestration-flag.sh <flag-path>` reports whether a route is currently in progress, by
mtime only. Exits `0` and prints `status: none` (no file), `status: fresh` (mtime under 2 hours —
a route is in progress), or `status: stale-deleted` (mtime 2 hours or older — the file is removed
and treated as absent), `2` for a usage error (missing argument).

`lib/finalize-orchestration-flag.sh <flag-path>` removes the marker unconditionally, for use at
every terminal state alike. Exits `0` and prints `status: deleted` or `status: not-found` —
idempotent either way. Exits `2` for a usage error (missing argument).

```bash
bash plugins/agentic-core/shared/lib/write-orchestration-flag.test.sh
bash plugins/agentic-core/shared/lib/check-orchestration-flag.test.sh
bash plugins/agentic-core/shared/lib/finalize-orchestration-flag.test.sh
```
