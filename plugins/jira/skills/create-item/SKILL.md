---
description: tracker.create_item — creates a new Jira work item from an authored draft and reports the key the tracker assigns. Requires JIRA_SITE, JIRA_EMAIL and JIRA_API_TOKEN in the environment.
---

# create-item

Implements the `tracker` role's `create_item` operation: create a work item on a real Jira Cloud
site from an authored draft.

## Input

Two lines in the invocation argument:

```
project_key: <the tracker project the item belongs in>
draft: <the authored draft — front matter, then the description body>
```

## What to do

1. Write the `draft` text to a new temporary file, exactly as given, with no shell interpolation
   of its content — this keeps arbitrary draft text (quotes, newlines, special characters) out of
   any command line.
2. Run `${CLAUDE_PLUGIN_ROOT}/skills/create-item/scripts/create-item.sh <project_key> <draft file>`.
3. Delete the temporary file.
4. Output the script's entire stdout, unchanged, as your entire response. Do not add commentary,
   reformat it, or summarize it — the script's own output already ends with the `## Result` block
   this operation must return (see the `agentic-core` plugin's `shared/result-envelope.md`, which
   this pack depends on, for the exact shape).

The script alone decides `pass` versus `fail` from the live HTTP response; nothing here makes that
decision, so there is no branch in this skill's own control flow.

Pass the draft whole, as `update_item` takes it. The front matter supplies the summary and the
item type, both of which a create requires and neither of which the description can carry.

## The key comes back in an artifact, not in the summary

This operation's result does not exist until the tracker produces it, and the envelope has no
field for a returned value. So the script writes the created item's key to
`.ai/tracker/create-item-<KEY>.json` and names that file in the envelope's `artifacts:` list —
the same way a fetch reports what it retrieved.

Read the key from that artifact. Do not parse it out of the summary line, and do not predict it
from the project's last known number: the tracker assigns it, and a key that was free a moment ago
belongs to someone else's item by the time this one is created.
