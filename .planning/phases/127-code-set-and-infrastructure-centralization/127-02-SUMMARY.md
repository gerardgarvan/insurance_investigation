---
phase: 127-code-set-and-infrastructure-centralization
plan: "02"
subsystem: utils
tags: [doi, icd-classification, dx-type-gate, fixture, utils_doi]
dependency_graph:
  requires:
    - "127-01 (DOI_CODE_MAP in R/00_config.R)"
    - "R/utils/utils_icd.R (normalize_icd)"
  provides:
    - "R/utils/utils_doi.R — is_doi_code() + classify_doi_codes()"
    - "tests/fixtures/DIAGNOSIS_Mailhot_V1.csv — 2 DoI rows exercising both coding systems"
  affects:
    - "Phase 128 — DoI classification can now call is_doi_code() / classify_doi_codes()"
tech_stack:
  added: []
  patterns:
    - "DX_TYPE-gated prefix detection (mirrors is_hl_diagnosis pattern from utils_icd.R)"
    - "4-char-before-3-char cascade (mirrors classify_codes pattern from utils_cancer.R)"
    - "Source-time key partitioning (.doi_keys_icd9 / .doi_keys_icd10) for collision prevention"
key_files:
  created:
    - R/utils/utils_doi.R
  modified:
    - tests/fixtures/DIAGNOSIS_Mailhot_V1.csv
decisions:
  - "is_doi_code() uses DX_TYPE gate (not is_cancer_code() style) — numeric prefix keys like 714 would false-positive on ICD-10 records without gating"
  - "classify_doi_codes() is NOT DX_TYPE-gated — callers filter with is_doi_code() first, matching classify_codes() contract"
  - "4-char keys D692/D693 and H460/H461/H468/H469 in DOI_CODE_MAP drive 4-char-before-3-char priority — without it D69.2->Vasculitis and D69.3->Hematologic Autoimmune would both resolve to NA (no 3-char D69 key)"
  - "Fixture rows appended to existing PT001/PT002 (not new patients) — avoids ENROLLMENT/DEMOGRAPHIC fixture edits"
metrics:
  duration_minutes: 15
  completed_date: "2026-07-15"
  tasks_completed: 2
  files_changed: 2
---

# Phase 127 Plan 02: DoI Utility Layer (utils_doi.R + Fixture) Summary

**One-liner:** DX_TYPE-gated is_doi_code() prefix detector and 4-char-before-3-char classify_doi_codes() cascade targeting DOI_CODE_MAP, with ICD-10 and ICD-9 fixture rows exercising both coding systems.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create R/utils/utils_doi.R | d1c9976 | R/utils/utils_doi.R (created, 117 lines) |
| 2 | Augment DIAGNOSIS fixture with DoI rows | 6bb4fa1 | tests/fixtures/DIAGNOSIS_Mailhot_V1.csv (+2 rows) |

## What Was Built

### R/utils/utils_doi.R

New utility module providing:

- `is_doi_code(dx, dx_type)`: DX_TYPE-gated vectorized detector. Mirrors `is_hl_diagnosis()` signature and NA-gate pattern from `utils_icd.R`. Computes `.doi_keys_icd9` and `.doi_keys_icd10` once at source time by partitioning `names(DOI_CODE_MAP)` on leading character (numeric = ICD-9, alpha = ICD-10). ICD-10 records only match alpha-leading keys; ICD-9 records only match numeric keys. NA or non-"09"/"10" DX_TYPE returns FALSE.

- `classify_doi_codes(codes)`: 4-char-before-3-char prefix cascade over `DOI_CODE_MAP`. Mirrors `classify_codes()` from `utils_cancer.R`. Not DX_TYPE-gated — callers apply `is_doi_code()` filter first.

Auto-sourced by existing `R/utils/*.R` glob in `R/00_config.R` — zero config changes required.

### tests/fixtures/DIAGNOSIS_Mailhot_V1.csv

Added two rows to the existing 23-line fixture:
- `DX021,PT001,...,M05.9,10,...` — ICD-10 Rheumatoid Arthritis (secondary dx)
- `DX022,PT002,...,714.0,09,...` — ICD-9 Rheumatoid Arthritis (secondary dx)

Both attached to existing patients (PT001, PT002) so no ENROLLMENT/DEMOGRAPHIC/ENCOUNTER fixture changes were needed.

## Verification Results

All Rscript acceptance tests pass (R 4.6.0 with `library(glue)` pre-loaded for config dependency):

- DX_TYPE gate: `is_doi_code("M05.9","10")` TRUE, `is_doi_code("C81.90","10")` FALSE, `is_doi_code("714.0","09")` TRUE, `is_doi_code("714.0","10")` FALSE, `is_doi_code("M05.9",NA)` FALSE, `is_doi_code("M05.9","SM")` FALSE
- Cascade: `classify_doi_codes("D69.2")` "Vasculitis", `classify_doi_codes("D69.3")` "Hematologic Autoimmune", `classify_doi_codes("M05.9")` "Rheumatoid Arthritis", `classify_doi_codes("K50.90")` "Inflammatory Bowel Disease", `classify_doi_codes("C81.90")` NA
- Vectorized NA: `is_doi_code(c("M05.9","714.0","714.0","C81.90",NA), c("10","09","10","10","10"))` == c(TRUE,TRUE,FALSE,FALSE,FALSE)
- End-to-end fixture: exactly 2 DoI flags (PT001+PT002), both "Rheumatoid Arthritis"

## Deviations from Plan

None — plan executed exactly as written.

Note: `source("R/00_config.R")` requires `library(glue)` to be loaded first when running from bare Rscript (config calls `glue()` before `library(glue)` in the utils load section). This is a pre-existing config ordering issue unrelated to this plan's changes; not fixed here (out-of-scope per deviation rule boundary).

## Known Stubs

None.

## Self-Check: PASSED

- `R/utils/utils_doi.R` exists: FOUND
- Commit d1c9976 exists: FOUND
- Commit 6bb4fa1 exists: FOUND
- Fixture has 25 lines (1 header + 20 + 2 DoI + trailing newline): VERIFIED
- All Rscript checks exit 0: VERIFIED
