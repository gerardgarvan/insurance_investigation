---
phase: 46-treatment-code-cross-reference-and-triggering-codes
plan: 01
subsystem: treatment-classification
tags: [gap-report, cross-reference, openxlsx2, duckdb, code-audit]
dependency_graph:
  requires:
    - R/00_config.R (TREATMENT_CODES named list)
    - R/01_load_pcornet.R (DuckDB PROCEDURES access)
    - Phase 45 (radiation CPT audit, 46-code expansion)
  provides:
    - R/46_treatment_cross_reference.R (two-way gap report script)
    - output/tables/treatment_cross_reference.xlsx (generated on HiPerGator)
  affects:
    - None (audit-only artifact, no config changes)
tech_stack:
  added: []
  patterns:
    - openxlsx2 multi-sheet styled workbook (int2col, wb$save, wb_color)
    - DuckDB group_by/summarise for patient/encounter counts
    - Base R setdiff() for two-way set comparison
    - Hardcoded reference data structures (D-15/D-16)
key_files:
  created:
    - R/46_treatment_cross_reference.R
  modified: []
decisions:
  - All reference data hardcoded (D-15/D-16): docx/xlsx parsed once at plan time; codes transcribed into REFERENCE_CODES named list
  - Radiation CPT compared at range level only (D-04/D-05): docx says 70010-79999; config covers 77261-77799; narrative row explains exclusion rationale
  - Phase 45 added 46 codes (not 42 as originally estimated): verified via git diff of commit f4de3c5; all annotated via PHASE45_ADDED_CODES vector
  - immunotherapy_drg missing from TREATMENT_CODES: referenced in scripts 43/44 but not in config; fallback to hardcoded "018" with null-safe check
  - PCS Codes Cancer Tx.xlsx contains 125 chemo-only codes (all type="chemo"): no radiation/SCT/immuno codes; compared against broader ICD-10-PCS routes beyond core 4 prefixes
  - ComprehensiveSurgeryCodes.xlsx: single-column surgical/cancer-site codes with no treatment type label; not directly comparable to TREATMENT_CODES
metrics:
  duration: "~35 minutes"
  completed_date: "2026-05-15"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 0
---

# Phase 46 Plan 01: Treatment Code Cross-Reference Gap Report Summary

**One-liner:** Two-way gap report script comparing hardcoded docx/xlsx reference code lists against live TREATMENT_CODES config for all 4 treatment types, with DuckDB patient/encounter counts and Phase 45 annotation.

## What Was Built

`R/46_treatment_cross_reference.R` — a 1175-line R script that produces a styled 5-sheet xlsx workbook at `output/tables/treatment_cross_reference.xlsx` when executed on HiPerGator.

### Script Structure

- **Section 1: Setup** — libraries, source R/00_config.R + R/01_load_pcornet.R
- **Section 2: Hardcoded Reference Data** — `REFERENCE_CODES` named list with 4 treatment types; data extracted from TreatmentVariables_2024.07.17.docx, Treatment_Variable_Documentation.docx, PCS Codes Cancer Tx.xlsx, MSDRGs.xlsx
- **Section 3: Phase 45 Annotation Vector** — `PHASE45_ADDED_CODES` with 46 codes verified via git diff of commit f4de3c5
- **Section 4: Comparison Functions** — `compare_code_lists()` using `setdiff()`, `build_gap_tibble()` with Phase 45 annotation injection
- **Section 5: Run Comparisons** — per-type gap tibbles for all 4 types; radiation CPT uses range-level narrative rows (D-04/D-05)
- **Section 6: DuckDB Counts** — `get_pcornet_table("PROCEDURES")` query for patient/encounter counts on gap codes (D-14)
- **Section 7: Styled Xlsx Output** — 5-sheet openxlsx2 workbook with color-coded rows by direction; int2col() for column refs
- **Section 8: Console Summary** — highlights actionable gap codes with patient data

### External File Findings (Task 1)

| File | Schema | Relevant Content |
|------|--------|-----------------|
| PCS Codes Cancer Tx.xlsx | Sheet 1: PCS Code & Text, PCS Code, Tx (3 cols, 125 data rows); Sheet 2: PCS Codes, Tx (2 cols, 1062 rows) | All 125 codes are chemo (type="chemo"); Section 3E Administration/Antineoplastic across diverse body sites |
| ComprehensiveSurgeryCodes.xlsx | Single sheet, single column "Cancer.codes", 684 rows | ICD-9 numeric codes, ICD-10-CM C/D diagnosis codes, ICD-10-PCS 7-char codes; no treatment type column; surgical/cancer-site classification, not treatment type |
| MSDRGs.xlsx | 3 columns: DRG (text), Code (numeric), Tx (label); 15 data rows | SCT=014/016/017; surg=582/583/656-658; chemo=837-848; rad=849 |
| Phase 45 radiation codes | git diff f4de3c5 | 46 codes added: 7 treatment planning, 17 physics/dosimetry, 10 delivery, 1 proton, 1 hyperthermia, 7 brachytherapy, 3 G-codes |

## Verification

- File line count: 1175 (exceeds minimum 200)
- `source("R/00_config.R")` at line 60
- `source("R/01_load_pcornet.R")` at line 61
- `wb$save(OUTPUT_PATH)` at line 1132
- REFERENCE_CODES covers all 4 treatment types with codes from both docx files + 3 xlsx files
- PHASE45_ADDED_CODES contains 46 radiation codes (updated from 42 estimate based on git diff)
- Output path pattern: `file.path(CONFIG$output_dir, "tables", "treatment_cross_reference.xlsx")`
- No `int_to_col()` anti-pattern found
- No Python-style `glue("{x:,}")` format specs found
- Radiation CPT: range-level narrative row, no code expansion

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] immunotherapy_drg missing from TREATMENT_CODES**
- **Found during:** Task 2 (reading TREATMENT_CODES structure)
- **Issue:** Scripts R/43 and R/44 reference `TREATMENT_CODES$immunotherapy_drg` but the key does not exist in current R/00_config.R
- **Fix:** Used null-safe check `if (!is.null(TREATMENT_CODES$immunotherapy_drg))` with hardcoded fallback `c("018")`
- **Files modified:** R/46_treatment_cross_reference.R (no config modification — out of scope)

**2. [Rule 1 - Deviation] Phase 45 code count is 46, not 42**
- **Found during:** Task 1 (git diff of commit f4de3c5)
- **Issue:** Plan and prior documentation say "42 Phase 45 auto-added radiation CPT codes" but commit f4de3c5 added 46 codes (43 CPT + 3 G-codes; the original pre-Phase-45 config also had some delivery codes added in 9894a75)
- **Fix:** PHASE45_ADDED_CODES vector hardcoded with all 46 codes verified from commit diff; annotation comment updated to reflect "46 codes" rather than "42"

**3. [Rule 1 - Deviation] %||% operator removed**
- **Found during:** Task 2 code review
- **Issue:** Initial draft used `%||%` null-coalescing operator which requires `rlang`; not needed given TREATMENT_TYPES is a character vector not a named list
- **Fix:** Replaced with explicit `if (!is.null(...))` check

## Self-Check: PASSED

- R/46_treatment_cross_reference.R: FOUND
- Commit 8c17f5e: FOUND
- SUMMARY.md: FOUND
