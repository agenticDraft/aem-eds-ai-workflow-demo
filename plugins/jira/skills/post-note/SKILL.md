---
description: tracker.post_note — attaches a note (comment) to a Jira work item. Requires JIRA_SITE, JIRA_EMAIL and JIRA_API_TOKEN in the environment.
---

# post-note

Implements the `tracker` role's `post_note` operation: post a comment to a work item on a real
Jira Cloud site.

## Input

Two lines in the invocation argument:

```
item_id: <tracker item key>
note: <note text>
```

## What to do

1. Write the `note` text to a new temporary file, exactly as given, with no shell interpolation of
   its content — this keeps arbitrary note text (quotes, newlines, special characters) out of any
   command line.
2. Run `${CLAUDE_PLUGIN_ROOT}/skills/post-note/scripts/post-note.sh <item_id> <note text file>`.
3. Delete the temporary file.
4. Output the script's entire stdout, unchanged, as your entire response. Do not add commentary,
   reformat it, or summarize it — the script's own output already ends with the `## Result` block
   this operation must return (see the `agentic-core` plugin's `shared/result-envelope.md`, which
   this pack depends on, for the exact shape).

The script alone decides `pass` versus `fail` from the live HTTP response; nothing here makes that
decision, so there is no branch in this skill's own control flow.
