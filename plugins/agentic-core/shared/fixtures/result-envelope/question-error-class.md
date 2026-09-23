# Stage: extract

The design provider refused three attempts over a 2s then 4s backoff, every one with the same
`429 Too Many Requests — monthly credit limit reached`. The work item carries no image attachment
to fall back to, so this stage has no alternative path left.

Transient exhaustion with nothing left to substitute does not return `fail`: one concrete human
action — waiting for the credit window to reset, or raising the plan's limit — is what unblocks it,
and the question protocol is what routes that to a human or to the work item.

## Result
verdict: question
summary: The design provider refused three attempts with a credit-limit error, so no reference could be retrieved.
artifacts: []
next_action: none
error_class: TRANSIENT
question: Wait for the design provider's credit window to reset, or raise the plan limit?
options:
  - Wait for the window to reset
  - Raise the plan limit now
blocker: Reset the design provider's monthly credit window, or raise its limit, then re-run this stage
