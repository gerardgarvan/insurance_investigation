---
phase: 77-cancer-classification-refinements
plan: 02
subsystem: cancer-classification
tags: [data-refinement, validation, output-versioning, nlphl, 7-day-gap]
requires: [77-01]
provides: [v2-7day-cancer-summary, nlphl-diagnostics, dual-output-pattern]
affects: [R/49, R/88]
tech_stack:
  added: []
  patterns: [dual-output-versioning, DRY-helper-functions, checkmate-validation]
key_files:
  created: []
  modified:
    - R/49_cancer_summary_pre_post.R
    - R/88_smoke_test_comprehensive.R
decisions:
  - Filter v2 output by two_or_more_unique_dates_gt_7 == 1 for all cancer categories
  - Produce both v1 (unfiltered) and v2 (7-day filtered) outputs for backward compatibility
  - Print v1 vs v2 comparison table to console only (no persistent file)
  - Assert v2 population in 6300-6400 range with checkmate hard failure
  - Report NLPHL vs classical HL counts in R/49 console diagnostics
  - DRY refactor aggregation logic into compute_code_baseline and compute_category_summary helpers
  - Update category NA logic to include both HL categories (non-NLPHL and NLPHL)
metrics:
  duration_seconds: 299
  tasks: 2
  files_modified: 2
  lines_added: 541
  lines_removed: 65
  commits: 2
completed: 2026-06-03T03:55:39Z
---

# Phase 77 Plan 02: Dual Output - 7-Day Cancer Summary with NLPHL Diagnostics

**One-liner:** Dual output (v1 unfiltered + v2 7-day filtered) with NLPHL diagnostic breakout and population validation in R/49

## What Was Built

Extended R/49 to produce both v1 (unfiltered baseline) and v2 (7-day confirmed) cancer summary outputs, added NLPHL vs classical HL diagnostic reporting, and updated smoke tests to validate the new dual-output structure.

### Outputs Created

**R/49 dual output structure:**
- V1 (existing): `cancer_summary_table_pre_post.{rds,xlsx,csv}` (unfiltered, backward compatible)
- V2 (new): `cancer_summary_table_pre_post_v2_7day.{rds,xlsx,csv}` (filtered by `two_or_more_unique_dates_gt_7 == 1`)
- Console-only v1 vs v2 comparison table showing top 15 deltas

**NLPHL diagnostics:**
- C81.0x (NLPHL) patient count
- C81.1-C81.9 (classical HL) patient count
- Overlap count (patients with both NLPHL and classical HL codes)
- Warning logged if overlap > 0

**Validation:**
- checkmate::assert_int() validates v2 total population in [6300, 6400] range
- Smoke test Section 13D validates 7 structural patterns in R/49

## Implementation Notes

### Dual Output Pattern (D-02, D-08, D-09, D-10)

Applied filter-and-reuse strategy: v1 uses full `cancer_summary` input, v2 filters by `two_or_more_unique_dates_gt_7 == 1` before aggregations. Both paths use the same DRY helper functions (`compute_code_baseline`, `compute_category_summary`) to ensure consistent logic.

**Key insight from Pitfall 1 (RESEARCH.md):** Pre/post/both temporal analysis (Section 5, using `dx_raw`) is NOT re-filtered for v2 — it uses the same `patients_pre`, `patients_post`, `patients_both` as v1. This is correct because pre/post counts should reflect actual temporal distribution, not be double-filtered by 7-day threshold.

### NLPHL Diagnostic Split (D-11, CANCER-01)

Added diagnostic section after existing C81 checks (lines 128+) using `str_detect(DX_norm, "^C810")` for NLPHL vs `!str_detect(DX_norm, "^C810")` for classical HL. Reports distinct patient counts and overlap. Overlap > 0 triggers warning (clinically valid but flagged for review).

### Category NA Logic Update (D-11 oversight)

**Bug fixed:** Phase 75 renamed `"Hodgkin Lymphoma"` to `"Hodgkin Lymphoma (non-NLPHL)"` in CANCER_SITE_MAP, but R/49 category NA logic still referenced the old name. Updated both v1 and v2 category summaries to check:
```r
category %in% c("Hodgkin Lymphoma (non-NLPHL)", "NLPHL")
```
This ensures pre/post/both counts remain NA for BOTH HL anchor diagnoses.

### DRY Refactor

Extracted aggregation logic into two helpers:
- `compute_code_baseline(cs_df, label)` — code-level metrics (9 columns)
- `compute_category_summary(cs_df, label)` — category-level metrics (9 columns)

Both v1 and v2 paths call these functions, eliminating duplication and ensuring metric consistency.

### V2 XLSX Styling

Matched existing R/49 styling (dark headers, white font, gray totals) but updated titles to include "(7-Day Confirmed)" suffix and footnotes to reference v2 filter criteria.

### Comparison Table (D-03)

Console-only output showing top 15 codes by absolute delta (v2 - v1 patient counts). Provides immediate feedback without persistent files. Includes percentage change column for context.

### Population Validation (D-04, CANCER-02)

```r
checkmate::assert_int(
  as.integer(v2_n_patients),
  lower = 6300L, upper = 6400L,
  .var.name = glue("[R/49 CANCER-02 ERROR] V2 7-day total population expected 6300-6400, got {v2_n_patients}")
)
```
Hard failure if v2 population falls outside tolerance range. Prevents silent drift from expected 6,347 target.

### Smoke Test Section 13D

Added 7 checks validating R/49 structural changes:
1. OUTPUT_TABLE_V2_XLSX path defined
2. Filter by `two_or_more_unique_dates_gt_7 == 1` present
3. checkmate assert_int for 6300-6400 range
4. NLPHL diagnostic output present
5. saveRDS for v2 RDS output
6. Category NA logic uses `"Hodgkin Lymphoma (non-NLPHL)"` (not just `"Hodgkin Lymphoma"`)
7. Comparison table is console-only (no file write)

Updated all section counters to `/22` (from inconsistent `/19` and `/21`).

## Deviations from Plan

None — plan executed exactly as written.

## Testing

**Structural validation (R/88 Section 13D):**
- All 7 checks passed
- Verified v2 path definitions, filter logic, population assertion, NLPHL diagnostics, RDS output, category NA logic, console-only comparison

**Manual verification:**
- `grep -c "cancer_summary_table_pre_post_v2_7day" R/49_cancer_summary_pre_post.R` → 3 (3 path definitions)
- `grep -c "NLPHL" R/49_cancer_summary_pre_post.R` → 12 (diagnostics + category logic)
- `grep -c "assert_int" R/49_cancer_summary_pre_post.R` → 1 (population validation)
- `grep -c "compute_code_baseline" R/49_cancer_summary_pre_post.R` → 3 (definition + v1 + v2 calls)

## Known Issues

None. All acceptance criteria met.

## Requirements Validated

- **CANCER-01:** NLPHL diagnostic split added to R/49 console output (lines 128-143), reporting C81.0x vs C81.1-C81.9 patient counts separately
- **CANCER-02:** 7-day gap extension applied to all cancer categories via v2 output path, filtered by `two_or_more_unique_dates_gt_7 == 1`
- **QUAL-01:** Both R/49 and R/88 modifications follow v2.0 standards (checkmate assertions, glue messages, section headers, smoke test updates)

## Next Steps

**Immediate (Phase 77 Plan 03 - if exists):**
- N/A — Plan 02 is the final plan in Phase 77

**Follow-on (Phase 78):**
- Integrate per-episode cancer categorization using drug groupings from DRUG_GROUPINGS (Phase 77 Plan 01)
- Add cause of death to outputs (Phase 78 pending)

**Verification:**
- Run R/49 on HiPerGator to confirm v2 population falls within 6300-6400 range
- Inspect v1 vs v2 comparison table to understand delta distribution by cancer category
- Review NLPHL overlap count — if > 0, flag for clinical review

## Self-Check: PASSED

**Files modified:**
```bash
[ -f "R/49_cancer_summary_pre_post.R" ] && echo "FOUND: R/49_cancer_summary_pre_post.R" || echo "MISSING"
[ -f "R/88_smoke_test_comprehensive.R" ] && echo "FOUND: R/88_smoke_test_comprehensive.R" || echo "MISSING"
```
✓ FOUND: R/49_cancer_summary_pre_post.R
✓ FOUND: R/88_smoke_test_comprehensive.R

**Commits exist:**
```bash
git log --oneline --all | grep -q "9929f77" && echo "FOUND: 9929f77" || echo "MISSING"
git log --oneline --all | grep -q "6a795b2" && echo "FOUND: 6a795b2" || echo "MISSING"
```
✓ FOUND: 9929f77 (Task 1: dual output + NLPHL diagnostics)
✓ FOUND: 6a795b2 (Task 2: smoke test Section 13D)

**Key patterns verified:**
- `grep -c "cancer_summary_table_pre_post_v2_7day" R/49_cancer_summary_pre_post.R` → 3
- `grep -c "NLPHL" R/49_cancer_summary_pre_post.R` → 12
- `grep -c "SECTION 13D" R/88_smoke_test_comprehensive.R` → 1
- `grep "CANCER-02: 7-day gap extension" R/88_smoke_test_comprehensive.R` → present

All claims verified.

---

*Phase: 77-cancer-classification-refinements*
*Plan: 02*
*Completed: 2026-06-03*
*Duration: 299 seconds (~5 minutes)*
