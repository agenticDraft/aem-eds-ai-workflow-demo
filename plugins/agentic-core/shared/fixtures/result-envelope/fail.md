# Stage: route resolution

The fact record carries `explicit_route: <unregistered-route-id>`. Per the spec, an explicit
route wins over the signal table and is never second-guessed by a model.

Looked up `<unregistered-route-id>` in `routes` in the project config. No entry with that id
exists — the route table has three rows and a default, none matching it. This is a contract
violation, not an ambiguity a question could resolve: the work item names a route the project
config does not have.

## Result
verdict: fail
summary: The work item's declared route id does not exist in the configured route table.
artifacts: []
next_action: none
