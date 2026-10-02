---
item_type: Story
item_id: EDS-23
summary: Comparison table header matches the design height
components: [table]
---

## Description

In blocks/table/ (blocks/table/table.css), the comparison variation's header row renders about
113 px tall at a 1280 px wide viewport, while the design reference below shows it 96 px tall. The
header row should be the height the design shows, with each heading's text where the design places
it.

## Design reference

https://www.figma.com/design/B1rwvloGdmUrozvkBQ0vKP/Zoki?node-id=1-195

The reference represents one wide viewport only, so AC-1 to AC-3 are compared at 1280 px wide.

## Acceptance criteria

AC-1 At 1280 px wide, the comparison table's header row is 96 px tall, measured as the design
     measures it: including the cells' padding and their bottom border.
AC-2 At 1280 px wide, the WebSurge and HyperView headings' text starts 40 px below the top of the
     header row.
AC-3 At 1280 px wide, the Area heading's text starts 41 px below the top of the header row.
AC-4 No paragraph or other text element inside a table cell is given a fixed height.
AC-5 At 375 px, 768 px and 1280 px wide, every heading's text stays inside its heading cell.
AC-6 Every data cell of the comparison table still renders the supported or unsupported mark the
     design reference shows for it.

## Out of scope

Loading the typefaces the design names. Any change to blocks/table/ beyond the comparison header
row, to other blocks, or to styles/styles.css.
