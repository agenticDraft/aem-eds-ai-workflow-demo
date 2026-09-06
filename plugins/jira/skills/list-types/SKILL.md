---
description: tracker.list_types — lists a Jira project's work-item types (used by setup, core contract §7). Requires JIRA_SITE, JIRA_EMAIL and JIRA_API_TOKEN in the environment.
---

# list-types

Implements the `tracker` role's `list_types` operation: list the work-item types configured for a
project on a real Jira Cloud site, scoped to the project the pipeline is being set up for — this is
what `setup` calls to seed a project's route table (core contract §7) rather than any
instance-wide, unscoped list.

## Input

One line in the invocation argument:

```
project: <tracker project key>
```

## What to do

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/list-types/scripts/list-types.sh <project>`.
2. Output the script's entire stdout, unchanged, as your entire response. Do not add commentary,
   reformat it, or summarize it — the script's own output already ends with the `## Result` block
   this operation must return (see the `agentic-core` plugin's `shared/result-envelope.md`, which
   this pack depends on, for the exact shape).

The script alone decides `pass` versus `fail` from the live HTTP response; nothing here makes that
decision, so there is no branch in this skill's own control flow.
