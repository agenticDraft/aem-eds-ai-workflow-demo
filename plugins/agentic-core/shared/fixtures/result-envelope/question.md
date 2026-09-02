# Stage: route resolution

The fact record has no `explicit_route`, so resolution moved to the signal table. Every row in
`routes` was checked; each `when` block names `packs.tracker` as a match key, and project config
has no `packs.tracker` value at all — the field is absent, not merely empty.

Rather than guess a pack, this stage finished everything that does not depend on the answer —
the fact record is already written and valid — and stops here, per §8: a stage that cannot
resolve something runs to completion and returns `question` rather than suspending.

## Result
verdict: question
summary: Route resolution needs packs.tracker and project config does not set it.
artifacts: []
next_action: none
question: Which pack should own the tracker role for this project?
options:
  - Use the pack already declared for scm
  - List available tracker packs
blocker: packs.tracker is unset in project config
