---
description: The fact record contract. Every reader or writer of a fact record references this file rather than restating the shape inline.
---

# Fact record

Emitted by `intake`, consumed by the route resolver. Facts only — no conclusions. The stage that
produces this record must not decide anything from it: a field it cannot determine is omitted, or
written as the literal `null` — never guessed.

## Format

```yaml
item_id: <string>
item_type: <string>
labels: [<string>, …]
components: [<string>, …]
design_source: true | false
files_named: [<path>, …]
explicit_route: <route id> | null
```

## Field rules

- `item_id` — non-empty string. Required.
- `item_type` — verbatim from the tracker, not normalised. Required.
- `labels` — the work item's labels/tags, verbatim. May be an empty list.
- `components` — the work item's declared components, verbatim. May be an empty list.
- `design_source` — whether a design reference is present. `true` or `false`.
- `files_named` — paths the work item's text names, if any. May be an empty list.
- `explicit_route` — a route id stated by the invoker or by the item itself, or the literal
  `null` when none was stated. Never inferred from `item_type`, `labels` or any other field —
  that inference is the route resolver's job, not intake's.

**Fields may be omitted.** Unlike the project config's top-level keys, a fact record field with
no determinable value does not appear at all, or appears as `null`. A missing key and an explicit
`null` are equivalent to every reader of this file. Field order is not significant.

## Example

```yaml
item_id: "1234"
item_type: task
labels: [backend]
components: [api]
design_source: false
files_named: []
explicit_route: null
```

## Anti-patterns

- A guessed value in place of an omitted or `null` field.
- `explicit_route` set from a rule derived by reading `item_type`/`labels` rather than from an
  explicit statement in the work item or the invocation.
- A conclusion (a chosen route, a classification) recorded alongside the facts.

## Reference, not restatement

A skill, script or stage adapter that reads or writes a fact record references this file with one
line rather than restating the shape inline, the same convention `project-config.md` and
`result-envelope.md` use for their own contracts.

## Fixtures

One well-formed example lives at `fixtures/fact-record/valid.yaml`. The route resolver's own test
fixtures, which combine a fact record with a project config to exercise resolution rules, live
under `fixtures/route-resolution/` instead — see `lib/resolve-route.sh`.
