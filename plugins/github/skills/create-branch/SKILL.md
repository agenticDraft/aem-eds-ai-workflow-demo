---
description: scm.create_branch — ensures a working branch exists and is checked out, basing a new one on the caller's current HEAD (or on the repository's default branch when that is where the caller is) and pushing it to origin. Idempotent: an existing branch is reported, not refused. Requires gh authenticated on this machine (gh auth status).
---

# create-branch

Implements the `scm` role's `create_branch` operation: create a branch from the repository's base
branch on a real GitHub remote.

## Input

One or two lines in the invocation argument:

```
branch: <new branch name>
base: <base branch name>          # optional; see the default below
```

**When no `base` is given**, the branch's base depends on where the caller is:

- On the repository's default branch — `origin/<default>`, fetched first. A local default branch
  left behind by an already-merged change would otherwise drag that change's pre-merge commit onto
  the new branch.
- Anywhere else, including a detached HEAD — the current `HEAD`. Being on another branch is
  deliberate, and this operation checks the working tree out to the branch it creates, so basing on
  the default branch would discard the caller's own commits while still reporting `pass`.

A `base` given explicitly always wins, and is always taken from `origin/<base>`.

## When the branch already exists

This operation ensures rather than creates, so a run that is resumed — or re-started on the same
work item — lands back on the branch it was already using instead of being refused. `metrics`
carries which of three things happened:

- `branch_action=existing` — it was already checked out; nothing moved.
- `branch_action=switched` — it existed locally, or only on origin, and was checked out.
- `branch_action=created` — it did not exist and was created from the base above.

**One case is refused, and it reports `question` rather than acting.** An existing branch that does
not contain the caller's current `HEAD` cannot be checked out without discarding commits the caller
is standing on. The envelope names how many would be lost and what to do instead; nothing in the
working tree is moved. `base` is not consulted in that case — the question is about what already
exists, not about where a new branch would start.

## What to do

**This script calls `gh`, and the default Bash sandbox's network-filtering proxy does TLS
interception that breaks `gh`'s own Go TLS client — a consistent, every-time failure
(`connect EPERM`-shaped errors or a token reported invalid), not a flaky occasional one; `curl` and
the token itself are unaffected, only `gh`'s own HTTP client (G68).** Run
every step below with `dangerouslyDisableSandbox: true`, unconditionally, on the first attempt.

1. Run, with `dangerouslyDisableSandbox: true`:
   `${CLAUDE_PLUGIN_ROOT}/skills/create-branch/scripts/create-branch.sh <branch> [base]`,
   substituting the `branch` and `base` values given above. Omit the second argument if no `base`
   line was given.
2. Output the script's entire stdout, unchanged, as your entire response. Do not add commentary,
   reformat it, or summarize it — the script's own output already ends with the `## Result` block
   this operation must return (see the `agentic-core` plugin's `shared/result-envelope.md`, which
   this pack depends on, for the exact shape).

The script alone decides `pass` versus `fail` from the live `git`/`gh` outcomes; nothing here makes
that decision, so there is no branch in this skill's own control flow.
