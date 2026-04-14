---
phase: 07-look-at-dx-info
plan: 01
subsystem: data-quality,gap-analysis
tags: [neither-patients, diagnosis-exploration, tumor-registry, enrollment-crossref, gap-classification]
completed: 2026-03-25

dependency_graph:
  requires:
    - phase: 06-rectify-issues
      provides: HL_SOURCE classification with Neither patients identified
  provides:
    - R/09_dx_gap_analysis.R (standalone gap analysis script)
    - Per-patient gap classification (phantom, coding gap, non-HL codes)
    - 3 CSV outputs (all diagnoses, lymphoma codes, patient summary)
  affects:
    - Phase 18 (one enrolled person investigation consumed these findings)

tech_stack:
  added: []
  patterns:
    - Standalone diagnostic script pattern (load data, filter, analyze, CSV output)
    - Per-patient classification via case_when gap logic
    - Site-stratified tabyl() breakdown

key_files:
  created:
    - R/09_dx_gap_analysis.R
  modified: []

decisions: []

requirements-completed: [GAP-01, GAP-02, GAP-03]

metrics:
  tasks_completed: 1
  tasks_total: 1
  commits: 1
  files_modified: 1
---

# Phase 07 Plan 01: Gap Analysis for Neither Patients Summary

**Created gap analysis script (408 lines) investigating 19 "Neither" patients across 7 analytical sections including DIAGNOSIS exploration, ENROLLMENT/TUMOR_REGISTRY cross-reference, gap classification, and site-stratified breakdown with 3 CSV outputs**

## Performance

- **Duration:** Committed 2026-03-25
- **Commit:** c605ae1
- **Tasks:** 1/1 complete
- **Files created:** 1 (R/09_dx_gap_analysis.R, 408 lines)

## What Was Built

Created `R/09_dx_gap_analysis.R` as a standalone diagnostic script investigating the 19 patients classified as "Neither" (no HL evidence from DIAGNOSIS or TUMOR_REGISTRY tables) by the Phase 6 pipeline rebuild. The script has 7 sections:

1. **Load excluded patients** -- Reads hl_cohort CSV, filters to HL_SOURCE == "Neither"
2. **DIAGNOSIS exploration** -- Pulls all DX codes for these patients, filters to lymphoma/cancer range (ICD-10 C81-C96, ICD-9 200-208)
3. **ENROLLMENT cross-reference** -- Checks enrollment records and payer data for Neither patients
4. **TUMOR_REGISTRY exploration** -- Cross-references TR tables for histology codes
5. **Gap classification** -- Per-patient classification (phantom record, coding gap, non-HL lymphoma codes, etc.)
6. **Console summary** -- Site-stratified breakdown using janitor::tabyl()
7. **CSV outputs** -- Three diagnostic CSVs to output/diagnostics/

## Accomplishments

- Characterized all 19 Neither patients with full diagnosis code inventory
- Filtered to lymphoma/cancer-related ICD codes for focused analysis
- Classified each patient's gap reason (phantom enrollment, non-HL lymphoma, etc.)
- Site-level stratification revealed partner-specific data patterns
- Findings later consumed by Phase 18 which resolved the one remaining actionable patient

## Task Commits

1. **Task 1: Create gap analysis script** -- `c605ae1` (feat)
   - R/09_dx_gap_analysis.R created (408 lines, 7 sections)
   - Follows established patterns: semi_join, normalize_icd(), message+glue, write_csv
   - Null-safe TR table checks, coalesce for left join NAs

## Files Created/Modified

- `R/09_dx_gap_analysis.R` -- Standalone gap analysis script (408 lines) with 7 analytical sections investigating Neither patients

### Output files (generated on HiPerGator)

- `output/diagnostics/neither_all_diagnoses.csv` -- All DX codes for 19 Neither patients
- `output/diagnostics/neither_lymphoma_codes.csv` -- Lymphoma/cancer ICD code subset
- `output/diagnostics/neither_patient_summary.csv` -- Per-patient gap classification

## Decisions Made

None -- followed plan as specified.

## Deviations from Plan

None -- plan executed exactly as written.

## Known Stubs

None. Script is a standalone diagnostic tool with complete analytical logic and CSV outputs.

## Impact & Next Steps

**Immediate impact:** Provided detailed characterization of all 19 Neither patients, enabling data-driven decisions about pipeline modifications.

**Downstream consumption:** Phase 18 ("One Enrolled Person Does Not Have an HL Diagnosis Caught") used these findings to investigate and resolve the one remaining actionable patient by adding bare ICD-9 code 201 to ICD_CODES.

## Self-Check: PASSED

- R/09_dx_gap_analysis.R: FOUND (408 lines)
- Commit c605ae1: FOUND

---
*Phase: 07-look-at-dx-info*
*Completed: 2026-03-25*
