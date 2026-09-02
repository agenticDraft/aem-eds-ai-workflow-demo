# Stage: route resolution

Evaluated the fact record against the configured route table, top to bottom. Every `when` block
was checked; none of them matched on every key present, so no row fired.

Fell through to `routes.default`, which the config schema requires every route table to declare.
This is not an error — a route table with no matching row is exactly what `default` is for — but
it is worth surfacing, since a route table that never matches any real row is a sign the table
itself may be out of date.

## Result
verdict: warn
summary: Route resolved to the default row; no signal table entry matched the fact record.
artifacts:
  - .claude/run-context/route.yaml
next_action: continue to the first resolved stage
