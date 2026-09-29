# Trigger rule export

`route-trigger.rule.json` is the Jira automation rule that turns a token comment into a
`repository_dispatch` for this repository, exported from the Jira console unchanged. It is a
**derived copy**: the source of truth for the token is `trigger.token` in `.ai/project-config.yaml`,
and `plugins/agentic-core/shared/lib/check-trigger-config.sh` fails CI if the two disagree.

The export exists because a rule that lives only in the Jira console is invisible to anyone reading
this repository. Re-export after every change to the rule, and commit the export as Jira produces it.

It lives here, in the consuming repository, and not in the tracker pack: it names one site, one
project, one actor and this repository's dispatch URL, and a pack ships to every consumer. Its
Jira smart values (`{{issue.key}}` and the rest) would also fail the pack manifest's
unfilled-placeholder check, which rejects `{{` anywhere under a pack root.

## What the rule does

- **Name:** `agentic-run → GitHub dispatch`.
- **Trigger:** `jira.issue.event.trigger:commented` with `eventTypes: ["PRIMARY_ACTION"]` — in the
  console, *Issue commented*, "Comment is the main action".
- **Condition:** `jira.comparator.condition`, `{{comment.body}}` `CONTAINS` `@agentic-run`. The match
  is case-sensitive.
- **Action:** `jira.issue.outgoing.webhook`, `POST
  https://api.github.com/repos/agenticDraft/aem-eds-ai-workflow-demo/dispatches`, headers `Accept:
  application/vnd.github+json` and `Authorization`, custom body with `event_type: agentic-route`.
  `.github/workflows/route-trigger.yaml` is the only workflow that receives that event type.

## Payload

The body's `client_payload` carries six fields: `item_id` (`{{issue.key}}`), `comment_id`
(`{{comment.id}}`), `author_id` (`{{comment.author.accountId}}`), `author_name`
(`{{comment.author.displayName}}`), `item_type` (`{{issue.issueType.name}}`) and `rule_version`
(`"1"`). Their meanings and the order the receiving side gates them in are defined once, in
`plugins/agentic-core/shared/trigger-contract.md`. Do not add a seventh — in particular, not the
comment body, which carries the literal token.

**`item_type` is carried, never filtered on.** It rides along for the run title and for the
readiness gate to report against. D98 declined an item-type allowlist by name: a platform pack
already declares per-item-type readiness criteria, and a second list naming item types would be a
second source of truth for the same question. Do not add a condition on it, here or in the
workflow.

## The `Authorization` header is empty on purpose

The committed file has `"name": "Authorization", "value": "", "headerSecure": true`. Jira strips a
hidden header's value on export, so no credential leaves the console. Whoever imports the rule must
re-enter the header value as `Bearer <token>`, marked **Hidden**, using a fine-grained GitHub
personal access token scoped to this repository with **Contents: Read and write** — the permission
GitHub lists for `POST /repos/{owner}/{repo}/dispatches`.

## Environment-specific values

These identify one Jira site and change on import into another:

- **Scope:** `ruleScope`, `ruleHome` and the trigger's `eventFilters` name project `10000` (EDS) on
  one site, by its cloud id.
- **Actor:** `actor.value` is the account the rule runs as. It is not an entry in
  `trigger.allowed_identities`; the allowlist gates the comment author, not the rule's actor.
- **Ids:** `id`, `idUuid`, `clientKey`, `partitionId`, `authorAccountId`, the component `id`s, the
  timestamps and `checksum` are assigned by the site that holds the rule.
