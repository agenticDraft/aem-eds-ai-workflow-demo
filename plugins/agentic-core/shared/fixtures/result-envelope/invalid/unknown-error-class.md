# Operation: design.fetch_reference

The operation classified its own failure correctly but reported the class under a name no contract
defines, so a caller branching on it would fall through every branch.

## Result
verdict: fail
summary: The design reference names node 1-1043, which the provider has no record of.
artifacts: []
next_action: none
error_class: RETRYABLE
