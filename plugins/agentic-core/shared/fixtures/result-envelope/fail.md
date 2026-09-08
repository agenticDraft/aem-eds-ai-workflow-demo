# Stage: readiness

Read the fact record and looked up `readiness_criteria` for this item's `item_type`. The pack
declares criteria for two types; this item's type is not one of them.

An undeclared type is a failure, not a fall-through: applying another type's rules would answer a
question nobody asked, and guessing that the item is ready would put an unreviewed item into the
rest of the run. The pack author has to declare the type before an item of it can be worked.

## Result
verdict: fail
summary: The item's type has no declared readiness criteria, so this pack cannot judge whether it can be worked.
artifacts: []
next_action: none
