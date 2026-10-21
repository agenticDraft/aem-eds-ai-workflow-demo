---
item_type: Story
item_id: EDS-30
summary: Link list external links in a new tab
---

## Description

Links in the link list block at blocks/link-list/ that point to another site open in a new
tab, so a reader does not leave this site by following one. A link to this site's own pages keeps
opening in the same tab.

## Acceptance criteria

AC-1 A link-list link whose host differs from the page's host carries target="_blank".
AC-2 A link-list link whose host differs from the page's host carries rel="noopener noreferrer".
AC-3 A link-list link to a page on the same host carries no target attribute.
AC-4 A link-list link given as a relative path carries no target attribute.
AC-5 Every link authored in the block is still rendered, in its authored order.
AC-6 The page loads with no new console errors.

## Out of scope

Links in any other block, the header or the footer; any added text that labels a link as external.
