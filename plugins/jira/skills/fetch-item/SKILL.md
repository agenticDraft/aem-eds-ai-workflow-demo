---
description: tracker.fetch_item — returns a Jira work item's fields and text. Requires JIRA_SITE, JIRA_EMAIL and JIRA_API_TOKEN in the environment.
---

# fetch-item

Implements the `tracker` role's `fetch_item` operation: fetch a work item's fields and text from
a real Jira Cloud site.

## Input

One line in the invocation argument:

```
item_id: <tracker item key>
```

## What to do

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/fetch-item/scripts/fetch-item.sh <item_id>`, substituting the
   `item_id` value given above.
2. Output the script's entire stdout, unchanged, as your entire response. Do not add commentary,
   reformat it, or summarize it — the script's own output already ends with the `## Result` block
   this operation must return (see the `agentic-core` plugin's `shared/result-envelope.md`, which
   this pack depends on, for the exact shape).

The script alone decides `pass` versus `fail` from the live HTTP response; nothing here makes that
decision, so there is no branch in this skill's own control flow.
