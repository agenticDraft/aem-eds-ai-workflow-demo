# Stage: intake

Fetched the work item through the `tracker` role and wrote the fact record. The summary below
wraps onto a second line instead of staying one sentence — the failure mode this fixture exists
to catch.

## Result
verdict: pass
summary: Fetched the work item, sanitized its text,
  and wrote the fact record.
artifacts:
  - .claude/run-context/fact-record.yaml
next_action: none
