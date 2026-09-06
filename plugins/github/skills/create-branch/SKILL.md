---
description: scm.create_branch — creates a working branch from the repository's base branch and pushes it to origin. Requires gh authenticated on this machine (gh auth status).
---

# create-branch

Implements the `scm` role's `create_branch` operation: create a branch from the repository's base
branch on a real GitHub remote.

## Input

One or two lines in the invocation argument:

```
branch: <new branch name>
base: <base branch name>          # optional, defaults to the repository's default branch
```

## What to do

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/create-branch/scripts/create-branch.sh <branch> [base]`,
   substituting the `branch` and `base` values given above. Omit the second argument if no `base`
   line was given.
2. Output the script's entire stdout, unchanged, as your entire response. Do not add commentary,
   reformat it, or summarize it — the script's own output already ends with the `## Result` block
   this operation must return (see the `agentic-core` plugin's `shared/result-envelope.md`, which
   this pack depends on, for the exact shape).

The script alone decides `pass` versus `fail` from the live `git`/`gh` outcomes; nothing here makes
that decision, so there is no branch in this skill's own control flow.
