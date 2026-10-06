---
item_type: Story
summary: Equal comparison table columns
components: [table]
---

## Description

In the comparison variation of the table block at blocks/table/ (blocks/table/table.css), render
the three columns at equal widths, as the design reference lays them out: each column takes one
third of the table's width regardless of how long its heading or cell text is. Today the widths
follow the automatic table layout and differ by column (at the design's width they measure about
382, 426 and 392 pixels against three equal 400-pixel columns in the design), so the emphasised
first column is narrower than the one beside it.

## Design reference

https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-195

The reference shows the table at one wide viewport width with the three columns side by side and
of equal width. It says nothing about narrower widths; AC-6 is satisfied by the table staying
readable and unbroken at the project's other breakpoints, not by matching the reference at them.

## Acceptance criteria

AC-1 In the comparison variation, at the design's viewport width, every column renders at the same
     width as every other column, within one pixel.
AC-2 The column widths stay equal when one heading or cell holds longer text than the others.
AC-3 Every column heading shows its full text inside its own header cell.
AC-4 Every data cell shows its full text inside its own cell.
AC-5 The block placed without the comparison variation keeps its current automatic column layout.
AC-6 The block's rendered layout holds at every breakpoint the project defines.
AC-7 A page containing the block loads with no new console errors.

## Out of scope

Any other value of the design (colours, borders, spacing, typography), the base table block's own
rendering, any other block, the global styles, and loading the design's typefaces.
