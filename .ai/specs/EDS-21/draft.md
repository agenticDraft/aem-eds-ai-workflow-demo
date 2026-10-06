---
item_type: Bug
item_id: EDS-21
summary: Comparison table heading text overflows its fixed-height box
components: [table]
---

## Description

In blocks/table/ (blocks/table/table.css), the comparison variation gives the paragraph inside
each heading cell a fixed height of 16 px. The heading text is 21–23 px tall on one line and
35–47 px when it wraps, so it spills 7–19 px outside that box. The box's height should come from
the text it holds, so the heading text always stays inside it.

## Steps to reproduce

1. Open http://localhost:3001/drafts/EDS-21
2. Set the viewport to 1280 px wide
3. Compare each heading cell paragraph's height with the height of the text inside it

Expected: every heading paragraph is at least as tall as the text it holds.
Actual: every heading paragraph is 16 px tall, and its text extends above and below it.

## Acceptance criteria

AC-1 At 375, 768 and 1280 px wide, every comparison table heading paragraph is at least as tall
     as its text.
AC-2 When a heading's text wraps onto two lines, its paragraph is at least as tall as that text.
AC-3 No element in the table block that holds text is given a fixed height.

## Out of scope

The heading row growing from 96 px to about 113 px once the text sets its own height is accepted;
no stage should restore the 96 px. Any other change to blocks/table/table.css, to other blocks,
or to styles/styles.css.
