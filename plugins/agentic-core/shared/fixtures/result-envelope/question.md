# Stage: readiness

Read the fact record. `design_source` is true and the only reference the item carries is an
attached image; no resolvable design reference is present.

An attached image is ambiguous by nature — a screenshot of a defect and a mockup of the intended
state are structurally identical, and nothing in the item distinguishes them. Comparing an
implementation against a screenshot of the bug it was meant to fix is the failure this question
prevents, and nothing downstream would catch it: the verification stage would report a clean match
against the wrong target.

Everything that did not depend on the answer is finished, so this stage runs to completion and
raises the question at its own boundary rather than suspending.

## Result
verdict: question
summary: The item's only design reference is an attached image, which could be the intended state or the defect.
artifacts: []
next_action: none
question: Which attachment is the design reference for this change?
options:
  - The first attachment
  - The second attachment
blocker: An image-only design source cannot be identified as reference or evidence without a human
