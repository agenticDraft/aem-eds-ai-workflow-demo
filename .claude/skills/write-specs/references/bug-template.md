# Bug template

For an item that reports something broken. Copy the skeleton, replace every angle-bracket
placeholder, and run the checker.

A bug is checked against different readiness criteria from a story — it has to be reproducible
before it can be worked — so the sections differ, and the order the checker expects differs with
them. The checker reads both the criteria and the heading wording from the packs, so let it tell
you what this project's type actually requires rather than trusting this file.

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

<Two to six lines. What is wrong, where it is wrong, and what should have happened instead.
Name every component directory and file involved, spelled exactly as the repository spells it,
trailing separator included.>

## Steps to reproduce

1. Open <the full URL of the page where it happens>
2. <action>
3. <action>

Expected: <what should happen>
Actual: <what happens>

## Design reference

<A link to the specific design node, or "attached: <filename>" for an image on the item.
Required whenever the description talks about appearance. Delete this section when it does not.>

## Acceptance criteria

AC-1 <one assertion>
AC-2 <one assertion>

## Out of scope

<Optional for a bug. Worth writing when the broken thing sits next to something else that is
also wrong but is not being fixed here.>
```

## Why each part is here

**The reproduction section carries a real URL, not a page name.** A full `http(s)` address anywhere
in the text is what makes the item reproducible to something that is not a person — the automated
run has to be able to open the page before it can see the defect. A step that says "go to the
homepage" is a step only a human who already knows the site can follow.

**Expected and actual are separate lines.** A bug report that only says what is wrong leaves the
fix's target implicit, and an implicit target is the one thing every reviewer will later disagree
about.

**Acceptance criteria on a bug are not the reproduction steps restated.** The steps say how to see
the defect; the criteria say what must be true afterwards — including, usually, that the defect's
own reproduction no longer reproduces it, and that the neighbouring behaviour the fix could plausibly
break still works.

**`AC-<n>`, numbered from 1, one assertion each** — for the same reason as on a story. The id is
what a gate finding, a review comment and a verification report can all cite.

## Worked example

```markdown
---
item_type: Bug
summary: Carousel arrows overlap the last slide
---

## Description

On <component-directory>/, the previous and next controls sit on top of the slide content at
narrow viewport widths instead of beside it, covering the final slide's call to action.

## Steps to reproduce

1. Open <the full URL of the page carrying the block>
2. Narrow the viewport to the project's smallest breakpoint
3. Advance to the last slide

Expected: the controls sit outside the slide content and the call to action stays clickable.
Actual: the next control covers the call to action, which cannot be clicked.

## Design reference

<link to the design node showing the intended control placement>

## Acceptance criteria

AC-1 At the project's smallest breakpoint, the carousel controls do not overlap the slide
     content.
AC-2 The last slide's call to action is clickable at every project breakpoint.
AC-3 The control positions at wider breakpoints are unchanged from their current rendering.
AC-4 The page loads with no new console errors.

## Out of scope

The carousel's keyboard navigation, which is tracked separately.
```

AC-3 is the one people leave out. A fix that moves the controls at one breakpoint can move them at
every breakpoint, and without a criterion saying the wider ones are unchanged, nothing checks that
and nothing can report it.

**The design reference on a bug surprises people.** This example carries one because the checker
refuses the item without it: the word "breakpoint" is in the design keyword list, so the detectors
read the item as asking for a visual change, and a visual change with no reference is terminal at
the readiness gate. The reaction that first suggests itself — reword the description until the
detectors stop noticing — is the wrong one, and it is worth being clear about why. A bug about
where controls sit on the page *is* a visual bug. Something has to decide where they should sit
instead, and if the item does not say, the run decides by guessing. Attach the reference, or write
down in the description the rule the placement must satisfy so a reader can check it without one.
The first draft of this example did neither, and the checker caught it.
