# Story template

For an item that adds or changes behaviour. Copy the skeleton, replace every angle-bracket
placeholder, delete the sections marked optional when they do not apply, and run the checker.

## Skeleton

```markdown
---
item_type: <the tracker's own name for this type>
summary: <a phrase, not a sentence>
item_id: <KEY-123>
labels: [<label>, <label>]
components: [<the tracker's own component name>]
---

## Description

<Two to six lines. What changes, where, and why it is wanted. Name every component directory
and file involved, spelled exactly as the repository spells it, trailing separator included.>

## Design reference

<A link to the specific design node, or "attached: <filename>" for an image on the item.
Required whenever the description talks about appearance. Delete this section when it does not.>

## Content

<The copy, labels and text the item supplies, verbatim. Delete when the item supplies none.>

## Acceptance criteria

AC-1 <one assertion>
AC-2 <one assertion>

## Out of scope

<What this item deliberately does not cover.>
```

## Why each part is here

**The front matter is not part of the description.** It carries what the tracker holds in its own
fields, so the checker can build an item shaped like a real one and run the real detectors over it.
`item_type` and `summary` are always required; the rest are filled when they are known. `components`
is the tracker's structured component field, which is not the same thing as a path mentioned in the
description — some stage conditions read the field and ignore the prose.

**The summary is a phrase.** It is a label in a list of a hundred other labels, and a sentence there
is a sentence nobody finishes reading. The requirement goes in the description, which is the part
built for it.

**`AC-<n>`, numbered from 1, one assertion each.** The id is the point. A stable id lets a gate
finding, a review comment and a verification report all cite the same criterion — "AC-3 failed at
the narrow breakpoint" — instead of quoting a fragment of prose and hoping everyone finds it. One
assertion per id is what makes that citation mean something: a criterion carrying three assertions
can only ever be reported as partly failed, which is not a result anyone can act on.

**Out of scope is a section, not an omission.** It is where the boundary of the work is written
down, and writing it down is what stops an implementation from expanding into the next item.

## Worked example

```markdown
---
item_type: Story
summary: Feature list block
---

## Description

Add a feature list block at <component-directory>/, authored through the project's standard
content model. It renders a numbered list of features and a single call-to-action button.

## Design reference

<link to the design node>

## Acceptance criteria

AC-1 A block directory <component-directory>/ exists, authored through the project's standard
     content model.
AC-2 Every spacing, type-scale and colour value in the rendered block resolves to an adopted
     design-system token where the project defines an equivalent.
AC-3 A value with no project equivalent is the only kind taken raw from the design.
AC-4 The numbered list renders through the project's existing global styles.
AC-5 The button renders through the project's existing global styles, with no duplicate button
     styling added by the block.
AC-6 The block's layout holds at every project breakpoint, not only at the design frame width.
AC-7 The page loads with no new console errors.

## Out of scope

Any change to another block, and any change to the global styles themselves.
```

Note what AC-4 and AC-5 are: one sentence in an earlier draft, saying the list and the button both
render through the global styles and the block adds no duplicate button styling. Three assertions,
one id, one verdict. Split, each one can pass or fail on its own, which is the only reason a
criterion exists.

AC-2 draws a review note from the checker, for the `and` in "spacing, type-scale and colour", and
it is kept anyway — which is what a review note is for. That `and` joins a list of value kinds
inside one rule, not two rules: a run reports it as one result, and splitting it would produce
three criteria that always pass or fail together. The note exists because no pattern can tell that
case from a genuine compound; deciding is the reader's job, and a note nobody read is the same as
no note at all.

Note also what the front matter of this example does *not* have: a `components` entry. Run the
checker on it and the route half reports that the stage which captures a component's current state
is skipped, because that condition reads the tracker's structured component field and this item
leaves it empty. For a brand-new block that is correct — there is no before-state to capture. For a
change to an existing one it is a silent loss, and the description naming the directory three times
does not fix it. Fill the field.
