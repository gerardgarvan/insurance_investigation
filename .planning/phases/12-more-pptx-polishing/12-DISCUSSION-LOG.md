# Phase 12: More PPTX Polishing - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-01
**Phase:** 12-more-pptx-polishing
**Areas discussed:** Slide content fixes, Visual styling, New slides/analyses, Structural changes

---

## Slide Content Fixes

### Term Definitions

| Option | Description | Selected |
|--------|-------------|----------|
| Footnotes per slide | Small text at bottom of each slide defining terms used on THAT slide | |
| Definitions slide | Dedicated Slide 2 listing all terms before data slides begin | |
| Both | Definitions slide for full glossary + short footnotes on each data slide | ✓ |

**User's choice:** Both — glossary slide AND per-slide footnotes
**Notes:** User wants all payer terms defined (Primary Insurance, First Chemo, etc.)

### Column Header Renaming

| Option | Description | Selected |
|--------|-------------|----------|
| Rename headers | E.g., "First Chemo" → "First Chemo (±30d window)" | |
| Keep short + footnotes | Keep short names, define in footnotes | ✓ |

**User's choice:** Keep short column headers with footnotes for definitions
**Notes:** Specific definitions provided: Primary Insurance = most prevalent, First Chemo = ±30 day window around first chemo date, etc.

### Slide 16 Content Fix

**User's choice:** Remove "No Treatment Recorded" row from Slide 16
**Notes:** User specified this directly in initial input

---

## Visual Styling

### Slide 17 Histogram

**User's choice:** Collapse Unknown/Unavailable/Other into Missing on the Slide 17 histogram facets; add a ">500" bin to capture high-encounter patients
**Notes:** Currently the histogram caps at x=500 and excludes beyond. User wants a visible overflow bin instead.

### New Summary Stats Slide

**User's choice:** Add a full summary statistics table (by payer category) as a new slide immediately after Slide 17
**Notes:** Purpose is to verify nothing strange in the data — includes mean, median, min, max, Q1, Q3, N, N>500

### Slides 18-19 Masked Dates

**User's choice:** Filter out DX_YEAR = 1900 from both slides; add footnote noting excluded patients
**Notes:** Year 1900 is a masking/placeholder date in the PCORnet extract

### Slide 20 Label Clipping

**User's choice:** Fix bar chart so count labels above bars are not cut off
**Notes:** Current `vjust = -0.3` positions labels above bars but y-axis doesn't expand to show them

---

## New Slides/Analyses

**User's choice:** No new slides beyond the summary stats slide after Slide 17
**Notes:** User said "nothing new here"

---

## Structural Changes

**User's choice:** Remove Slide 1 (title slide)
**Notes:** Deck will start with definitions slide instead

---

## Claude's Discretion

- Exact wording of definitions on glossary slide and footnotes
- Formatting of summary statistics slide
- Slide renumbering approach after title slide removal

## Deferred Ideas

None — discussion stayed within phase scope
