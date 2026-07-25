---
phase: 135-shared-helper-standardization
plan: "01"
subsystem: shared-utilities
tags: [normalization, icd-codes, pattern-b, utils_cancer, utils_doi, survivorship]
dependency_graph:
  requires: []
  provides: [".normalize_code helper", "consistent code normalization in utils_cancer/utils_doi/R13/R42"]
  affects: [R/utils/utils_cancer.R, R/utils/utils_doi.R, R/13_survivorship_encounters.R, R/42_build_code_descriptions.R]
tech_stack:
  added: []
  patterns: ["private .normalize_code() helper shared via source-order glob", "dot-stripped key normalization in named vectors"]
key_files:
  created: []
  modified:
    - R/utils/utils_cancer.R
    - R/utils/utils_doi.R
    - R/13_survivorship_encounters.R
    - R/42_build_code_descriptions.R
decisions:
  - ".normalize_code() defined in utils_cancer.R (sourced first by glob) and reused in utils_doi.R — no separate file needed"
  - "R/13 filter uses OR expansion (gsub pre-computed outside lazy query) rather than normalizing DX column to avoid schema mutation"
  - "R/42 hardcoded ICD-10 encounter keys replaced with undotted forms; ICD-9 procedure codes (41.xx, 92.xx, 99.xx) left unchanged as they are standardly dotted in ICD-9 and not the target of this fix"
metrics:
  duration_minutes: 15
  completed_date: "2026-07-25"
  tasks_completed: 3
  tasks_total: 3
  files_changed: 4
requirements: [PATTERN-B]
---

# Phase 135 Plan 01: Shared Code Normalization Standardization Summary

Single-line: Established `.normalize_code()` (strip all dots + toupper) as the sole normalization entry point in `utils_cancer.R`, `utils_doi.R`, R/13, and R/42 — eliminating first-dot-only strip bugs, missing toupper(), and dotted-vs-undotted HL code mismatches.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add .normalize_code() to utils_cancer.R; update classify_codes/is_cancer_code | c689253 | R/utils/utils_cancer.R |
| 2 | Update classify_doi_codes() to use .normalize_code() | 179405f | R/utils/utils_doi.R |
| 3 | Fix R/13 HL-code dotted/undotted mismatch; R/42 hardcoded dotted keys | 8a879d4 | R/13_survivorship_encounters.R, R/42_build_code_descriptions.R |

## What Was Built

**Task 1 — utils_cancer.R:**
- Added private `.normalize_code <- function(x) toupper(gsub("\\.", "", x, fixed = FALSE))` before `is_cancer_code()`
- `is_cancer_code()`: replaced `str_remove(dx, "\\.")` with `.normalize_code(dx)`
- `classify_codes()`: replaced `str_remove(codes, "\\.")` with `.normalize_code(codes)`
- Both functions now handle lowercase input and codes with multiple dots correctly

**Task 2 — utils_doi.R:**
- `classify_doi_codes()`: replaced `str_remove(codes, "\\.")` with `.normalize_code(codes)`
- `.normalize_code` is available because `utils_cancer.R` is sourced before `utils_doi.R` via the `R/utils/*.R` glob in `R/00_config.R`
- `is_doi_code()` already calls `normalize_icd()` (equivalent contract) — left unchanged

**Task 3 — R/13 and R/42:**
- R/13 Level 2: pre-computed `hl_icd10_clean` and `hl_icd9_clean` (gsub dot-stripped) outside the DuckDB lazy query, then OR-expanded the filter to match both the raw DX value and the dot-stripped DX value against both raw and stripped reference codes
- R/42: replaced dotted hardcoded keys `"Z51.11"`, `"Z51.12"`, `"V58.11"`, `"V58.12"`, `"Z51.0"` with their undotted equivalents (`"Z5111"`, `"Z5112"`, `"V5811"`, `"V5812"`, `"Z510"`) so they match dot-stripped consumers

## Deviations from Plan

**1. [Rule 2 - Missing Fix] R/42 additional dotted keys beyond Z51.11**

- **Found during:** Task 3
- **Issue:** The Z51.12, V58.11, V58.12, and Z51.0 keys in the same block also carried dots
- **Fix:** Applied the same dot-stripping to all five adjacent encounter/diagnosis keys in the `config_descriptions` block
- **Files modified:** R/42_build_code_descriptions.R
- **Commit:** 8a879d4

No other deviations — plan executed as written.

## Known Stubs

None. All four files now use consistent normalization. No placeholder values wired to UI rendering.

## Self-Check: PASSED

- R/utils/utils_cancer.R: FOUND (contains `.normalize_code`)
- R/utils/utils_doi.R: FOUND (contains `.normalize_code(codes)` in classify_doi_codes)
- R/13_survivorship_encounters.R: FOUND (contains `hl_icd10_clean` and OR expansion)
- R/42_build_code_descriptions.R: FOUND (contains `"Z5111"` key replacing `"Z51.11"`)
- Commits c689253, 179405f, 8a879d4: all present in git log
