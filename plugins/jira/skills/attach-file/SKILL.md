---
description: tracker.attach_file — attaches a file to a Jira work item. Requires JIRA_SITE, JIRA_EMAIL and JIRA_API_TOKEN in the environment.
---

# attach-file

Implements the `tracker` role's `attach_file` operation: attach a file to a work item on a real
Jira Cloud site.

## Input

Two lines in the invocation argument:

```
item_id: <tracker item key>
file_path: <path to the file to attach>
```

## What to do

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/attach-file/scripts/attach-file.sh <item_id> <file_path>`.
2. Output the script's entire stdout, unchanged, as your entire response. Do not add commentary,
   reformat it, or summarize it — the script's own output already ends with the `## Result` block
   this operation must return (see the `agentic-core` plugin's `shared/result-envelope.md`, which
   this pack depends on, for the exact shape).

The script alone decides `pass` versus `fail` from the live HTTP response; nothing here makes that
decision, so there is no branch in this skill's own control flow.
