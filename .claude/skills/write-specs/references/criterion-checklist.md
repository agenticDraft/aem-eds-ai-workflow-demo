# Criterion checklist

The judgement half. Everything here is a question a script cannot answer, which is why it is a
checklist for a reader rather than another rule in the checker.

The checker has already proved, before you get here, that each criterion carries an id, stands on
its own and says something. What it cannot tell you is whether the thing said is the thing that
matters. Walk each criterion through the eight questions below; a criterion that fails one goes
back for revision with the question named, so it does not return merely reworded.

## 1. Does it state an outcome, or dictate a recipe?

A criterion describes the state of the world when the work is done. It does not choose the
implementation — that choice belongs to whoever plans the work, who can see the codebase and the
existing conventions, which the item's author generally cannot.

- Recipe: "Use a CSS grid with three columns."
- Outcome: "The features render in three columns at the widest project breakpoint."

The test: could this be satisfied two different ways, both of them fine? If only one implementation
satisfies it, the criterion has made a decision it was not entitled to make. There is one honest
exception — when the implementation genuinely *is* the requirement, as in "the block reuses the
existing button component rather than restyling one," which is a constraint, not an incidental
choice. Say so plainly when that is the case, rather than disguising a constraint as an outcome.

## 2. Would two people reading it reach the same verdict?

Name the threshold, the breakpoint, the state, the condition. "Loads quickly" and "looks right at
mobile" cannot fail, because there is nothing to fail against — which means they cannot pass either,
and a criterion that can only be waved through is decoration.

The checker already rejects a closed list of words that never carry a threshold. That list is a
floor, not a ceiling: it catches the familiar phrasings, and it will not catch a new vague phrase
nobody has written before. This question is what catches those.

## 3. Is it observable from outside?

Something has to be able to look at the result and say yes or no: the rendered page, the file tree,
a command's output, a measurement. A criterion about an intention, a rationale or a feeling has
nothing to observe.

- Not observable: "The block is maintainable."
- Observable: "The block's styles are scoped to the block's own class, so they apply to nothing
  outside it."

## 4. Is it about *this* item?

Scope creep enters through the criteria more often than through the description, because a criterion
looks small. A criterion that requires something the item never asked for expands the work silently,
and — worse — expands it at the gate, where the expansion is discovered as a failure rather than as a
decision.

If it belongs to the work but not to this item, it belongs in **Out of scope**, or in another item.

## 5. Does it restate a rule that already holds everywhere?

A project-wide convention — the linter passes, the code is formatted, nothing hardcodes a secret —
is already enforced for every item. Repeating it here adds a line to read and nothing to check.

Keep the ones that are genuinely at risk in *this* change, and cut the rest. "The page loads with no
new console errors" earns its place in a block that adds JavaScript; it is filler in a
colour-only change.

## 6. Is the set complete?

Read the criteria as a whole and ask: if every one of these is true, is the item done?

If something could satisfy all of them and still not be what was asked for, a criterion is missing —
and it is usually the unglamorous one, the criterion asserting that what already worked still works.
A fix that moves an element at one breakpoint can move it at all of them; nothing reports that
unless a criterion says the others are unchanged.

## 7. Could a finding cite it usefully?

Imagine the sentence a gate or a verification report would write: "AC-3 failed." Does that sentence
tell the reader what is wrong?

If AC-3 covers three things, the sentence is useless — the reader still has to go and look at all
three. This is the same defect the checker catches mechanically when the compound is joined by a
semicolon or a second sentence, appearing in a form no pattern can see: a single clause that happens
to assert several things at once.

## 8. Is the design reference the right one?

When the item carries one:

- Does the link point at the **specific frame or node** the work implements, rather than at a file
  containing dozens of them? A whole-file link makes the comparison ambiguous, and an ambiguous
  comparison is one nobody can fail.
- Does the item say which viewport width the reference represents, where that matters? A design
  frame is one width; the criteria almost always cover more than one.
- If the reference is an image rather than a link, does the item say what the image is of? An image
  carries no values, no names and no structure, so whatever it does not show has to be written down.
