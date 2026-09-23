---
description: scm.create_branch — creates a working branch from the caller's current HEAD, or from the repository's default branch when that is where the caller is, and pushes it to origin. Requires gh authenticated on this machine (gh auth status).
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
