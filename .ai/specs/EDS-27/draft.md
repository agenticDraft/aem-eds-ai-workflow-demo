---
item_type: Story
summary: Table font size on the single breakpoint
item_id: EDS-27
components: [table]
---

## Description

The table block at blocks/table/ (blocks/table/table.css) changes its text size at two viewport
widths, 600 and 900 pixels. This project defines a single breakpoint, 900 pixels, and the 600-pixel
step came with the block from the upstream block collection rather than from this project's
design. Make the table's text size change only at the project's breakpoint: below it the table
renders at the extra-small body size, at and above it at the medium body size, so between 600 and
899 pixels wide the table no longer renders at the small body size it uses today.

## Design reference

https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-195

The reference shows the comparison table at one wide viewport width only. It says nothing about
narrower widths; AC-1 to AC-3 follow from the project's single breakpoint, not from matching the
reference at narrower widths.

## Acceptance criteria

AC-1 At every viewport width below 900 pixels, the table's text renders at the extra-small body
     font size.
AC-2 At every viewport width of 900 pixels or more, the table's text renders at the medium body
     font size.
AC-3 The table's text renders at the same font size at 599 pixels wide as at 600 pixels wide.
AC-4 The block's rendered layout holds at every breakpoint the project defines.
AC-5 A page containing the block loads with no new console errors.

## Out of scope

Any other value of the table block (colours, borders, spacing, column widths), the comparison
variation's own rules, any other block, the global styles, and loading the design's typefaces.
