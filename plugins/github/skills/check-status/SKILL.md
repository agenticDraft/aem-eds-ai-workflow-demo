---
description: scm.check_status — reports automated checks (CI) on a branch's open pull request. Requires gh authenticated on this machine (gh auth status).
---

# check-status

Implements the `scm` role's `check_status` operation: report the automated checks recorded against
a branch's open pull request on a real GitHub remote.

## Input

One line in the invocation argument:

```
branch: <branch name>
```

## What to do

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/check-status/scripts/check-status.sh <branch>`, substituting
   the `branch` value given above.
2. Output the script's entire stdout, unchanged, as your entire response. Do not add commentary,
   reformat it, or summarize it — the script's own output already ends with the `## Result` block
   this operation must return (see the `agentic-core` plugin's `shared/result-envelope.md`, which
   this pack depends on, for the exact shape).

The script alone decides `pass` versus `fail` from the checks it could or could not retrieve —
`pass` means the checks were read successfully, not that they are all green; the per-check outcome
is in the envelope's `summary` and `metrics` fields, not in `verdict`. Nothing here makes that
decision, so there is no branch in this skill's own control flow.
