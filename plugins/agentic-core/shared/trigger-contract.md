---
description: The trigger path's neutral half — the dispatch payload's field names, the order the receiving side applies its gates, and the rule that a tracker-side trigger definition and the project config must carry the same token. Names no product; the tracker-shaped and CI-shaped artifacts live in their own packs and reference this file.
---

# Trigger contract

An event-driven path from a token comment to a started run. This file states only what is true
regardless of which tracker raises the event and which CI platform receives it. See
`project-config.md` for where the token and the allowlist live, and D25 and D98 in
`03-core-design.md` for why the path has this shape.

**Never does:** name a tracker or a CI product, hold a credential, or describe how a particular
vendor's rule is configured. Those belong to the packs and to the consumer repository.

## The payload

Seven fields, all strings, all required and non-empty:

- `item_id` — the work item the run is for. **Read from the event, never rediscovered by querying
  the tracker.** The event is the selection.
- `comment_id` — the triggering comment's own id. The dedup key, paired with `item_id`.
- `author_id` — the comment author's opaque identity handle, checked against
  `trigger.allowed_identities`.
- `author_name` — a human-readable author label, for the record only. Never gated on.
- `item_type` — the work item's type, carried for the run's title and for the readiness gate to
  report against. **Never gated on** — D98 declined an item-type allowlist by name.
- `rule_version` — the version of the tracker-side definition that sent this payload.
- `override` — `1` when the comment carries the trigger token followed by the route policy's
  break-glass word, else `0`. The tracker-side definition computes it from the comment and sends
  only the flag. What it lifts, and for whom, is `route-policy.md`'s business. A payload from a
  definition older than this field is read as `0`.

**The comment body is not a field, and must not be added.** The body is the one string that contains
the literal token; keeping it out of the payload makes D98's self-retrigger rule structural rather
than a discipline anything has to remember.

## Gate order

Applied by the receiving side, in this order, stopping at the first that does not pass:

1. **Shape.** All seven fields present and non-empty, `override` exactly `0` or `1`. A failure here is a defect in the tracker-side
   definition — it is reported as a failure, loudly, not as a refusal.
2. **Identity.** `author_id` against `trigger.allowed_identities` (`check-trigger-identity.sh`). A
   failure here is a refusal: it is recorded with the author and the item id, and the receiving run
   ends **successfully**. A refused trigger is a correct outcome, and a path that reports correct
   outcomes as failures teaches its readers to ignore failures.
3. **Duplicate.** A run already handled this `item_id` + `comment_id` pair. Best-effort: if the
   check itself cannot be performed, it is logged and the run proceeds. The guarantee that a
   repeated run is harmless belongs to the runner being idempotent, not to this check.

## Token agreement

The project config holds the token, and the route policy holds the break-glass word. A
tracker-side definition that filters on the token, and on the token followed by the word, holds
copies. The copy is derived; the config is the source. `check-trigger-config.sh` proves the two agree
and is run by the consumer repository's own validation, which supplies the definition's path —
this core holds no path into any pack.
