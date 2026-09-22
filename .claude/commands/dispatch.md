---
description: Fire a repository_dispatch event and report the resulting workflow run
allowed-tools: Bash(gh api:*), Bash(gh run:*)
---

Usage: `/dispatch <TICKET-KEY>`

Run:

```
gh api repos/agenticDraft/aem-eds-ai-workflow-demo/dispatches -f event_type=my-event -f 'client_payload[ticket]=$ARGUMENTS'
```

Then wait a few seconds and run:

```
gh run list --workflow=dispatch.yml --limit 3
```

Report the status and URL of the new run.
