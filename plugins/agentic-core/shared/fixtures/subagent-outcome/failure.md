# Subagent: measure named selectors

Rendered the target page at the requested width. The adapter asked for the computed box model of
`.hero-banner`, but no element on the rendered page matches that selector — checked against the
full rendered DOM, not just the visible viewport.

## Outcome
status: failure
summary: The named selector does not exist in the rendered page.
artifacts: []
next_action: none
blocker: selector '.hero-banner' not found in the rendered DOM
