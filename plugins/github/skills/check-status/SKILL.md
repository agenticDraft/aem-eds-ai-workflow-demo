---
description: scm.check_status — reports the state of a branch's pull request (open, merged, closed, or none) and the automated checks (CI) on it. Requires gh authenticated on this machine (gh auth status).
---

# check-status

Implements the `scm` role's `check_status` operation: find a branch's pull request on a real GitHub
remote in any state, report that state as `change_state` (`open`, `merged`, `closed`, or `none` when
the branch has no pull request), and report the automated checks recorded against it.

## Input

One or two lines in the invocation argument:

```
branch: <branch name>
envelope: <file path>             # optional; see "Where the envelope goes" below
```

## What to do

**This script calls `gh`, and the default Bash sandbox's network-filtering proxy does TLS
interception that breaks `gh`'s own Go TLS client — a consistent, every-time failure
(`connect EPERM`-shaped errors or a token reported invalid), not a flaky occasional one; `curl` and
the token itself are unaffected, only `gh`'s own HTTP client (G68).** Run
every step below with `dangerouslyDisableSandbox: true`, unconditionally, on the first attempt.

1. Run, with `dangerouslyDisableSandbox: true`:
   `${CLAUDE_PLUGIN_ROOT}/skills/check-status/scripts/check-status.sh [--envelope <file>] <branch>`,
   substituting the `branch` value given above, and passing `--envelope <file>` with the `envelope`
   value when that line is given.
2. Output the script's entire stdout, unchanged, as your entire response. Do not add commentary,
   reformat it, or summarize it — the script's own output already ends with the `## Result` block
   this operation must return (see the `agentic-core` plugin's `shared/result-envelope.md`, which
   this pack depends on, for the exact shape).

## Where the envelope goes

This operation always ends its output with the `## Result` block. **When an `envelope:` line is
given, it also leaves that same block in the named file**, written by the `agentic-core` plugin's
emitter — the caller that named the file (the route driver, before it creates the working branch)
reads the operation's own envelope from there and never transcribes the printed block.

The script alone decides `pass` versus `fail` from the checks it could or could not retrieve —
`pass` means the checks were read successfully, not that they are all green; the per-check outcome
is in the envelope's `summary` and `metrics` fields, not in `verdict`. The script also decides
`change_state`: `none` is a `pass` with no checks, and a lookup that failed carries no
`change_state` at all, because an unknown state must never read as "no pull request". Nothing here makes those
decisions, so there is no branch in this skill's own control flow.
