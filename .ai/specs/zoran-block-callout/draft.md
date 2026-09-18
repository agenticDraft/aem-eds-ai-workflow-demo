---
item_type: Story
summary: Zoran-block renders its text as a call-out
labels: [demo]
---

## Description

Give blocks/zoran-block/ a decorate() function in blocks/zoran-block/zoran-block.js (currently
empty). Today the block has no behavior: it renders as plain, undecorated text. Wrap the block's
own authored text content in a single call-out wrapper element, and add CSS rules for that
wrapper's border and border-radius to blocks/zoran-block/zoran-block.css.

## Acceptance criteria

AC-1 blocks/zoran-block/zoran-block.js exports a decorate() function that runs without throwing
     when the block is authored with a single paragraph of text.
AC-2 The block's authored text content ends up inside a single wrapper element carrying a
     dedicated class defined in blocks/zoran-block/zoran-block.css.
AC-3 That wrapper element has a border on all four sides, with a nonzero width.
AC-4 That wrapper element has a nonzero border-radius on all four corners.
AC-5 The block's original authored text remains present, unchanged, inside the wrapper element.
AC-6 The page loads with no new console errors.

## Out of scope

Any change to another block. Any authored content or configuration options beyond a single
paragraph of text. Any animation or interactive behavior.
