---
item_type: Story
summary: Dismissible zoran-block call-out
item_id: EDS-7
---

## Description

blocks/zoran-block/ already renders its authored text as a call-out: blocks/zoran-block/zoran-block.js
wraps that text in a single element, and blocks/zoran-block/zoran-block.css carries the rules for it.

Give the block a control a reader can activate to dismiss it, so a page can carry a notice the
reader is able to clear. The dismissal lasts for the current page view only — nothing is stored and
nothing is remembered on the next load.

## Content

Call-out text: Heads up — this notice can be cleared.

Control label: Dismiss

## Acceptance criteria

AC-1 The block renders a control a reader can activate.
AC-2 That control carries an accessible name a screen reader can announce.
AC-3 The block's call-out text is visible when the page first loads.
AC-4 Activating the control makes the block's call-out text no longer visible on the page.
AC-5 The control can be reached by keyboard alone.
AC-6 The control can be activated by keyboard alone.
AC-7 The block's authored text still renders inside the single call-out wrapper element it used
     before this change.
AC-8 A page containing the block loads with no new console errors.

## Out of scope

Any change to another block. Remembering the dismissal beyond the current page view, whether in
storage or on the server. Any animation or transition. Any authored content or configuration option
beyond a single paragraph of text. Any change to blocks/zoran-block/zoran-block.css beyond what the
new control itself requires.
