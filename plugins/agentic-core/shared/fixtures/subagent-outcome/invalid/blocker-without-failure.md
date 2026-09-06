# Subagent: measure named selectors

Rendered the target page and read the computed values successfully, but the block below carries a
`blocker` field anyway — valid only with `status: failure` — the failure mode this fixture exists
to catch.

## Outcome
status: success
summary: Rendered the three named selectors and wrote their computed values.
artifacts:
  - .ai/run-context/measurements.json
next_action: none
blocker: selector '.hero-banner' not found in the rendered DOM
