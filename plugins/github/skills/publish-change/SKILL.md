---
description: scm.publish_change — pushes the current branch and opens (or reuses) a pull request on GitHub. Requires gh authenticated on this machine (gh auth status).
---

# publish-change

Implements the `scm` role's `publish_change` operation: push the working branch and open a pull
request for review on a real GitHub remote, or report the pull request already open for it.

## Input

Three or four lines in the invocation argument:

```
branch: <branch name>              # must be the currently checked-out branch
title: <pull request title>        # one line
body: <pull request body text>     # may span multiple lines
base: <base branch name>           # optional, defaults to the repository's default branch
```

## What to do

1. Write the `body` text to a new temporary file, exactly as given, with no shell interpolation of
   its content — this keeps arbitrary body text (quotes, newlines, special characters) out of any
   command line.
2. Run `${CLAUDE_PLUGIN_ROOT}/skills/publish-change/scripts/publish-change.sh <branch> <title>
   <body text file> [base]`, substituting the values given above. Omit the final argument if no
   `base` line was given.
3. Delete the temporary file.
4. Output the script's entire stdout, unchanged, as your entire response. Do not add commentary,
   reformat it, or summarize it — the script's own output already ends with the `## Result` block
   this operation must return (see the `agentic-core` plugin's `shared/result-envelope.md`, which
   this pack depends on, for the exact shape).

The script alone decides `pass` versus `fail` from the live `git`/`gh` outcomes; nothing here makes
that decision, so there is no branch in this skill's own control flow.
