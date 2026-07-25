---
phase: 133-critical-correctness-fixes
plan: 01
subsystem: analytics
tags: [R, dplyr, cancer-summary, episode-classification, overlap-detection, reference-manual]

requires:
  - phase: 132-crash-fixes
    provides: crash-free baseline scripts for all 11 modified files

provides:
  - "R/47: SENTINEL_CUTOFF pre-min filter replacing post-hoc 1900 nullify"
  - "R/28: treatment_type == 'SCT' string literal (was 'Stem Cell Transplant')"
  - "R/46: total_records at code grain (not patient-inflated)"
  - "R/48: HL anchor code exclusion matching R/49"
  - "R/49: both_count as true patient-level category intersection"
  - "R/67 + R/95: (admit_date, source) swap bound as unit in pmin/pmax mutate"
  - "R/68 + R/96: comment confirming admit_date/source binding inherited from upstream"
  - "R/89: header_end anchored to 3rd === bar capturing all field content"
  - "R/101: age_at_episode computed before episode_start collapses to min()"

affects:
  - phase-134-ingest-integrity
  - confirmed_hl_cohort.rds consumers (R/48, R/49, downstream)
  - multi_source_same_week_detail CSV consumers (R/68, R/96)

tech-stack:
  added: []
  patterns:
    - "Sentinel pre-filter pattern: filter before group_by/min() rather than post-hoc nullify"
    - "Record-count aggregation: always join at the grain you need, not at patient grain"
    - "Bound-unit swap: swap all columns tied to a key together in the same mutate()"
    - "summarise() column ordering: columns referenced by which.min/which.max must precede the column being reassigned"

key-files:
  created: []
  modified:
    - R/47_cancer_summary_refined.R
    - R/28_episode_classification.R
    - R/46_cancer_summary_table.R
    - R/48_cancer_summary_post_hl.R
    - R/49_cancer_summary_pre_post.R
    - R/67_multi_source_overlap_detection.R
    - R/68_overlap_classification.R
    - R/95_multi_source_overlap_av_th.R
    - R/96_overlap_classification_av_th.R
    - R/89_generate_reference_manual.R
    - R/101_gantt_lifespan_collapse.R

key-decisions:
  - "Sentinel filter applied only to dx_hl inside SECTION 5 date derivation, NOT to the SECTION 4 dx_hl pull that determines cohort membership (code-based)"
  - "total_records in R/46 split: category grain via code_record_totals join; code grain via direct dx_record_counts join — no summing from patient rows"
  - "both_count at category grain in R/49 uses inner_join(pre_patients_by_category, post_patients_by_category) not grouping patients_both by category"
  - "TOTAL row both_count uses intersect(unique(patients_pre$ID), unique(patients_post$ID)) for consistency with corrected per-category counts"

patterns-established:
  - "SENTINEL_CUTOFF constant defined once near output path definitions, referenced in filter before min()"
  - "pmin/pmax source reorder: always include _new helper columns for bound dates, reassign originals in same mutate(), let select() drop helpers"

requirements-completed: [DATA-01, DATA-02, DATA-03, DATA-04, DATA-05, DATA-06, DATA-07, DOCS-01]

duration: 25min
completed: 2026-07-25
---

# Phase 133 Plan 01: Critical Correctness Fixes Summary

**8 analytic bugs fixed across 11 R scripts: SCT detection now fires, total_records reflects true code-level counts, first_hl_dx_date retains real dates over sentinels, post-HL set excludes HL anchor codes, both_count reconciles at category grain, overlap source/date pairs stay bound through pmin/pmax reorder, and reference manual now extracts actual script header fields**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-07-25T00:00:00Z
- **Completed:** 2026-07-25
- **Tasks:** 9 (Fixes 1-9 across 11 files)
- **Files modified:** 11

## Accomplishments

- Fixed all 8 defects identified in the 2026-07-23 code review with no new capabilities added
- All 11 modified files parse without error (verified via Rscript --vanilla parse batch)
- String-check verification confirmed: 0 occurrences of "Stem Cell Transplant", "1900", and "[2]" on header_end; correct patterns present for all other fixes

## Task Commits

All 9 fixes committed atomically in a single task commit (all fixes had no interdependencies requiring separate commits):

1. **All 9 fixes: 11 R scripts** - `549e8a8` (fix)

## Files Created/Modified

- `R/47_cancer_summary_refined.R` - SENTINEL_CUTOFF constant + pre-min filter; removed post-hoc 1900 nullify
- `R/28_episode_classification.R` - "Stem Cell Transplant" -> "SCT" in sct_dates filter (line ~648)
- `R/46_cancer_summary_table.R` - removed patient-level dx_record_counts join; code_record_totals at code->category grain; code_summary direct join
- `R/48_cancer_summary_post_hl.R` - added HL anchor exclusion filter (C81*/201.x) after sentinel filter in SECTION 4
- `R/49_cancer_summary_pre_post.R` - cat_both_by_category and v2 use inner_join at category grain; TOTAL both_count uses intersect()
- `R/67_multi_source_overlap_detection.R` - admit_date_1_new/admit_date_2_new helpers bound to source swap in mutate
- `R/68_overlap_classification.R` - added comment confirming (admit_date, source) ordering inherited from R/67
- `R/95_multi_source_overlap_av_th.R` - identical fix as R/67 (AV+TH scope)
- `R/96_overlap_classification_av_th.R` - identical comment as R/68 confirming ordering from R/95
- `R/89_generate_reference_manual.R` - header_end `[2]` -> `[3]` at line 65
- `R/101_gantt_lifespan_collapse.R` - age_at_episode moved before episode_start = min() in summarise()

## Decisions Made

- Sentinel filter in R/47 placed only in the SECTION 5 date derivation path, not in SECTION 4's dx_hl pull, to preserve cohort membership (code-based confirmation is independent of date quality)
- R/46 total_records redesigned with two separate join paths (category grain via code_record_totals, code grain via direct join) plus two correctness guards (duplicated cancer_code check + orphan code log)
- R/49 TOTAL row both_count switched from n_distinct(patients_both$ID) to intersect() to maintain reconciliation consistency with corrected per-category counts

## Deviations from Plan

None - plan executed exactly as written. All 9 fixes applied exactly per specifications.

## Issues Encountered

None. All edits applied cleanly; Rscript not in Bash PATH on Windows dev but available at full path via PowerShell.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 134 (Ingest Integrity and Honest Tests) can proceed — all Phase 133 script modifications are complete and parse-verified
- Numeric correctness of R/46 and R/49 results remains unverifiable until run against real data on HiPerGator (structural fix is confirmed; runtime numbers require the DuckDB connection)

---
*Phase: 133-critical-correctness-fixes*
*Completed: 2026-07-25*
