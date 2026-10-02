---
item_id: EDS-22
item_type: Bug
summary: Long button labels are cut off
---

## Description

In styles/styles.css, a button whose label is longer than the space available is cut off and
ended with "…" instead of showing the whole label. On a 375 px wide screen the label of the
primary button on the buttons test page needs about 411 px but is given 323 px, so the reader
cannot tell what the button does. The whole label should stay readable, wrapping onto more than
one line when it does not fit on one.

## Steps to reproduce

1. Open https://main--aem-eds-ai-workflow-demo--agenticdraft.aem.page/buttons-test
2. Make the window 375 px wide
3. Read the label of the primary button

Expected: the whole label "Download the complete enterprise comparison report as a PDF" is visible.
Actual: the label stops part-way and ends with "…".

## Acceptance criteria

AC-1 At 375 px wide, the primary button on the buttons test page shows its whole label, with no text cut off.
AC-2 At 1280 px wide, a button whose label fits on one line still shows that label on one line.

## Out of scope

Any other change to how buttons are styled.
