# Phase 17: Visualization Polish - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-03
**Phase:** 17-visualization-polish
**Areas discussed:** 1900 sentinel scope, Post-treatment metric, Stacked histogram design, Gap closure approach

---

## 1900 Sentinel Scope

| Option | Description | Selected |
|--------|-------------|----------|
| PPTX display layer | Filter 1900 dates only where they'd appear in PPTX tables/graphs. Keeps raw data intact for audit. | ✓ |
| Cohort build layer | Nullify all 1900 dates in 04_build_cohort.R at data prep time. Cleaner downstream but changes raw cohort output. | |
| Both layers | Nullify at cohort level AND add PPTX-level guards as safety net. Most thorough but more code. | |

**User's choice:** PPTX display layer (recommended default)
**Notes:** User deferred to Claude's recommendation for all areas.

---

## Post-Treatment Metric

| Option | Description | Selected |
|--------|-------------|----------|
| Post-last-treatment anchor | Unique encounter dates counted after max(LAST_CHEMO, LAST_RADIATION, LAST_SCT). Exclude no-treatment patients. | ✓ |

**User's choice:** Post-last-treatment anchor (recommended default)
**Notes:** Distinct from existing N_UNIQUE_DATES_POST_TX which uses post-diagnosis anchor.

---

## Stacked Histogram Design

| Option | Description | Selected |
|--------|-------------|----------|
| New histogram alongside existing | Add stacked histogram as new figure. Pre-treatment top, post-treatment bottom. Faceted by payer. Raw encounter counts. | ✓ |

**User's choice:** New histogram alongside existing (recommended default)
**Notes:** Patients with no treatment excluded. Uses same metric (raw encounters) as existing histogram.

---

## Gap Closure Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Verify existing code | PPTX2-04 and PPTX2-07 code already appears implemented. Verify correctness, don't rewrite. | ✓ |

**User's choice:** Verify existing code (recommended default)
**Notes:** Code for overflow bin and label clipping already exists in 16_encounter_analysis.R.

---

## Claude's Discretion

- Color palette for pre/post stacking
- Binwidth and x-axis cap for stacked histogram
- Whether to add summary stats companion slide
- Footnote/subtitle wording for new slides

## Deferred Ideas

None — discussion stayed within phase scope.
