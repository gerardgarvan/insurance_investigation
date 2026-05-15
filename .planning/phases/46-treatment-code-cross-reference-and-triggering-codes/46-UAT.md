---
status: complete
phase: 46-treatment-code-cross-reference-and-triggering-codes
source: [46-01-SUMMARY.md, 46-02-SUMMARY.md]
started: 2026-05-15T18:00:00Z
updated: 2026-05-15T18:10:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Cross-Reference Script Exists and Sources Config
expected: R/46_treatment_cross_reference.R exists, is ~1175 lines, and contains source("R/00_config.R") and source("R/01_load_pcornet.R") near the top.
result: pass

### 2. REFERENCE_CODES Covers All 4 Treatment Types
expected: R/46_treatment_cross_reference.R contains a REFERENCE_CODES named list with entries for chemo, radiation, sct, and immunotherapy — each with codes extracted from docx/xlsx reference files.
result: pass

### 3. Phase 45 Annotation Vector Has 46 Codes
expected: R/46_treatment_cross_reference.R contains PHASE45_ADDED_CODES vector with exactly 46 radiation CPT/G-codes (verified from git diff of commit f4de3c5).
result: pass

### 4. Styled 5-Sheet xlsx Output Logic
expected: R/46_treatment_cross_reference.R creates an openxlsx2 workbook with 5 sheets (one per treatment type + summary), uses color-coded rows by gap direction, and saves to output/tables/treatment_cross_reference.xlsx.
result: pass

### 5. Triggering Codes Extraction Functions Added to R/44
expected: R/44_treatment_episodes.R contains extract_dates_with_codes(type) dispatch function plus 4 type-specific functions (chemo, radiation, SCT, immunotherapy) returning 3-column tibbles (ID, treatment_date, triggering_code).
result: pass

### 6. Episode Output Includes triggering_codes Column
expected: R/44_treatment_episodes.R outputs triggering_codes as column 8 (last column) in both CSV and xlsx detail sheets. Codes are comma-separated bare codes per episode, aggregated via paste(sort(unique(na.omit())), collapse=",").
result: pass

### 7. R/43 Left Unmodified
expected: R/43_treatment_durations.R was NOT modified by this phase — existing extract_all_dates() and other consumers are unaffected.
result: pass

## Summary

total: 7
passed: 7
issues: 0
pending: 0
skipped: 0

## Gaps

