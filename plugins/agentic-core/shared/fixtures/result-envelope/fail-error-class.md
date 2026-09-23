# Operation: design.fetch_reference

Called the provider for the node the work item's reference names. The call returned
`Node 1-1043 not found in file abc123`.

Retrying that unchanged cannot succeed: the reference names something the provider has no record
of, which is the input being wrong rather than the environment being busy or missing. The class is
what lets the caller tell those apart — a caller may take an alternative path when the environment
failed, and must not when the request itself was wrong.

## Result
verdict: fail
summary: The design reference names node 1-1043, which the provider has no record of.
artifacts: []
next_action: none
error_class: VALIDATION
