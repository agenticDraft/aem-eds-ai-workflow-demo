---
description: tracker.update_item — replaces a Jira work item's description and structured fields from an authored draft. Requires JIRA_SITE, JIRA_EMAIL and JIRA_API_TOKEN in the environment.
---

# update-item

Implements the `tracker` role's `update_item` operation: replace a work item's description and
structured fields on a real Jira Cloud site.

## Input

Two lines in the invocation argument:

```
item_id: <tracker item key>
draft: <the authored draft — front matter, then the description body>
```

## What to do

1. Write the `draft` text to a new temporary file, exactly as given, with no shell interpolation
   of its content — this keeps arbitrary draft text (quotes, newlines, special characters) out of
   any command line.
2. Run `${CLAUDE_PLUGIN_ROOT}/skills/update-item/scripts/update-item.sh <item_id> <draft file>`.
3. Delete the temporary file.
4. Output the script's entire stdout, unchanged, as your entire response. Do not add commentary,
   reformat it, or summarize it — the script's own output already ends with the `## Result` block
   this operation must return (see the `agentic-core` plugin's `shared/result-envelope.md`, which
   this pack depends on, for the exact shape).

The script alone decides `pass` versus `fail` from the live HTTP response; nothing here makes that
decision, so there is no branch in this skill's own control flow.

Pass the draft whole. The script splits it: the front matter sets the fields the tracker holds
outside the description, and the body becomes the description. Splitting it beforehand and passing
only the body loses the fields; pasting the whole thing into the description instead is how front
matter ends up visible in the item as literal text.

This operation **replaces** the description rather than appending to it. The script saves the
previous description before writing and names that file in the envelope's artifacts, so whoever
reads the result can see what was overwritten.
