---
description: Fire a repository_dispatch event and report the resulting workflow run
allowed-tools: Bash(curl *), Bash(python3 -c ' *)
---

Usage: `/dispatch <TICKET-KEY>`

Fire the dispatch event:

```
curl -sS -o /dev/null -w '%{http_code}\n' -X POST \
  -H "Authorization: Bearer $GH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/agenticDraft/aem-eds-ai-workflow-demo/dispatches \
  -d '{"event_type":"my-event","client_payload":{"ticket":"$ARGUMENTS"}}'
```

A `204` means the event fired.

Wait a few seconds, then list the dispatch workflow's most recent runs:

```
curl -sS \
  -H "Authorization: Bearer $GH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/agenticDraft/aem-eds-ai-workflow-demo/actions/workflows/dispatch.yml/runs?per_page=3" \
| python3 -c 'import json,sys; d=json.load(sys.stdin); [print(r["status"], r["conclusion"], r["html_url"]) for r in d["workflow_runs"]]'
```

Report the status and URL of the newest run (first line).
