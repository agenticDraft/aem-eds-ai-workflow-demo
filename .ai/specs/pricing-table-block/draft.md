---
item_type: Story
summary: Pricing table block
---

## Description

Add a pricing table block at blocks/pricing-table/, authored through the project's standard
content model. It renders a set of plans side by side, each with a plan name, a price, a list of
included features, and a call-to-action button linking to a signup page.

## Acceptance criteria

AC-1 A block directory blocks/pricing-table/ exists, authored through the project's standard
     content model.
AC-2 Each authored plan renders its name, price, feature list and call-to-action button.
AC-3 The call-to-action button renders through the project's existing global button conventions,
     with no duplicate button rules added by the block.
AC-4 The block remains fully readable and usable from a narrow phone width up to a wide desktop
     width.
AC-5 The page loads with no new console errors.

## Out of scope

Any change to another block, and any change to the global button conventions themselves.
