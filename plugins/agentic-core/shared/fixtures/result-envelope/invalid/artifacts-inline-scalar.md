# Stage: implement

Wrote one file, and the block below writes `artifacts:` as an inline scalar (the file path on the
same line as the key) instead of a YAML list — the failure mode this fixture exists to catch. Seen
live: `route-run-14` (Phase 6 / Task 1, G77) produced exactly this shape for a single-file change,
and the validator's own error message named the wrong field (`summary`, not `artifacts`) until
fixed alongside this fixture.

## Result
verdict: pass
summary: Implemented — all 3 plan steps done; the target file now applies the requested change.
artifacts: src/widget/widget.js
next_action: none
