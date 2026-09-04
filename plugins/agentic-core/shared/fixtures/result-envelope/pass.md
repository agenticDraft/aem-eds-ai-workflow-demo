# Stage: intake

Fetched the work item through the `tracker` role, sanitized its text against
`external-content-safety.md`, and wrote the fact record.

- item_id: read from the tracker response
- item_type: read verbatim, not normalised
- design_source: false — no design reference present in the work item

No branch, file write or outbound call happened before this point other than the fetch itself.

## Result
verdict: pass
summary: Fetched the work item, sanitized its text, and wrote the fact record.
artifacts:
  - .ai/run-context/fact-record.yaml
next_action: none
