# Stage: intake

Fetched the work item through the `tracker` role and wrote the fact record. The stage itself
finished cleanly, but the block below borrows the subagent-outcome contract's `success` literal
instead of this contract's own vocabulary — the tier mix-up this fixture exists to catch.

## Result
verdict: success
summary: Fetched the work item, sanitized its text, and wrote the fact record.
artifacts:
  - .ai/run-context/fact-record.yaml
next_action: none
