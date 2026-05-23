# Phase 56: Temporal Filtering - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-22
**Phase:** 56-temporal-filtering
**Areas discussed:** Script architecture, Comparison output, EXPLORATORY labeling, Edge case handling

---

## Script Architecture

| Option | Description | Selected |
|--------|-------------|----------|
| New R/56 script | Separate R/56_cancer_summary_post_hl.R that reads confirmed_hl_cohort.rds + cancer_summary.csv from R/55, applies temporal filter, produces _post_hl suffixed outputs. R/55 baseline untouched. | ✓ |
| Extend R/55 with flag | Add a RUN_POST_HL flag to R/55 that, when TRUE, also produces post-HL variant outputs after baseline. Single script handles everything. | |
| You decide | Claude picks the approach based on existing patterns and maintainability. | |

**User's choice:** New R/56 script (Recommended)
**Notes:** Follows the same standalone script pattern established in the project. Keeps R/55 baseline untouched per SC-1.

---

## Comparison Output

| Option | Description | Selected |
|--------|-------------|----------|
| Comparison sheet in post-HL xlsx | Add a 'Comparison' sheet to cancer_summary_table_post_hl.xlsx showing baseline vs post-HL counts per category: total patients, total codes, and delta. Keeps everything in one workbook. | ✓ |
| Separate comparison xlsx | Create cancer_summary_comparison.xlsx as its own file with baseline column, post-HL column, and difference column per category. | |
| Console log only | Print comparison summary to console during R/56 execution. No separate output file — the user reads the log. | |

**User's choice:** Comparison sheet in post-HL xlsx (Recommended)
**Notes:** Consolidates all post-HL outputs into a single workbook for easy review.

---

## EXPLORATORY Labeling

| Option | Description | Selected |
|--------|-------------|----------|
| Sheet title + footnote row | Each sheet name includes '[EXPLORATORY]' prefix. Plus a footnote row at bottom with immortal time bias note. | ✓ |
| Header row only | A merged header row at the top of each sheet with bold red text. Sheet names stay clean. | |
| You decide | Claude picks the labeling approach that balances visibility with readability. | |

**User's choice:** Sheet title + footnote row (Recommended)
**Notes:** Dual visibility — sheet tabs clearly marked and footnote provides clinical context.

---

## Edge Case Handling

### Same-day diagnoses (DX_DATE == first_hl_dx_date)

| Option | Description | Selected |
|--------|-------------|----------|
| Exclude same-day (strict >) | DX_DATE > first_hl_dx_date. More conservative, cleaner temporal separation. | |
| Include same-day (>=) | DX_DATE >= first_hl_dx_date. Captures cancers found during same diagnostic workup. | |
| You decide | Claude picks based on clinical standard for temporal comparisons. | ✓ |

**User's choice:** You decide
**Notes:** Deferred to Claude's discretion based on clinical standard.

### NA first_hl_dx_date handling

| Option | Description | Selected |
|--------|-------------|----------|
| Exclude from post-HL | Patients without a computable first HL date are excluded from post-HL variant entirely. Comparison sheet shows exclusion count. | ✓ |
| Include all their cancers | Treat NA as 'unknown timing' and include all cancers. More inclusive but muddies filter. | |
| You decide | Claude picks based on data integrity considerations. | |

**User's choice:** Exclude from post-HL (Recommended)
**Notes:** Clean temporal filter requires a valid reference date. Exclusion count reported in comparison sheet.

---

## Claude's Discretion

- Same-day DX_DATE == first_hl_dx_date: strict > vs >= decision deferred to Claude
- Console logging verbosity
- Xlsx styling (reuse R/55 dark header pattern)
- PREFIX_MAP handling approach

## Deferred Ideas

None — discussion stayed within phase scope
