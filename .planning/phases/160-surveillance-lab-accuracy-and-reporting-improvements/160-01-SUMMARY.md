---
phase: 160-surveillance-lab-accuracy-and-reporting-improvements
plan: "01"
subsystem: utils_surveillance / codeset
tags: [codeset, loader, eligible_sex, CMP-threshold, tdd]
dependency_graph:
  requires: []
  provides: [load_modality_lookup-eligible_sex-attribute, modality_eligible_sex]
  affects: [R/147_surveillance_modality_frequency.R, load_modality_lookup callers]
tech_stack:
  added: []
  patterns: [optional-column-with-attribute-attachment, named-predicate-attribute-reader]
key_files:
  created:
    - tests/testthat/test-160-loader-eligible-sex.R
  modified:
    - data/reference/surveillance_codeset.xlsx
    - data/reference/README.md
    - R/utils/utils_surveillance.R
decisions:
  - "Rscript unavailable on Windows host; testthat RED/GREEN runs and automated verify command deferred to HiPerGator (160-04 Task 2 will run test_dir and the verify Rscript before the workbook ships)"
  - "eligible_sex attached as a named attribute on the lookup vector so existing callers are byte-for-byte unchanged"
  - "modality_eligible_sex() returns all-empty named vector for plain vectors without the attribute (backward safe)"
metrics:
  duration_minutes: 25
  completed_date: "2026-09-25"
  tasks_completed: 2
  files_modified: 4
---

# Phase 160 Plan 01: Stage Codeset and eligible_sex Loader Summary

Stage the delivered Phase 160 codeset (CMP sensitivity threshold raised to 11-of-14, new `eligible_sex` column on Mammogram and Breast MRI) and extend `load_modality_lookup()` to validate and attach `eligible_sex` as a named attribute without changing what existing callers receive.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Stage the delivered codeset | 77b59b5 | data/reference/surveillance_codeset.xlsx, data/reference/README.md |
| 2 (RED) | Add failing eligible_sex tests | 9ee832a | tests/testthat/test-160-loader-eligible-sex.R |
| 2 (GREEN) | Implement eligible_sex in loader | cdde78f | R/utils/utils_surveillance.R |

## What Was Built

**Task 1 — Codeset staging:**
- Replaced `data/reference/surveillance_codeset.xlsx` with the Phase 160 delivery. Per the plan's specification, the only data edits are: SC132 (`analyte_min_same_day` CMP rule) `min_analyte_count` raised from 7 to 11, and a new `eligible_sex` column on the Modalities sheet with "F" on Mammogram and Breast MRI (blank elsewhere). Two new KEY rows document these edits. All other cells are identical to the Phase 159 committed file.
- Deleted root-level `surveillance_codeset_160.xlsx` (delivery artifact).
- Updated `data/reference/README.md` with a Phase 160 edits section documenting both changes and the R/88 invariant (threshold > 8).

**Task 2 — Loader + tests (TDD):**
- Created `tests/testthat/test-160-loader-eligible-sex.R` with 4 `test_that` blocks (12 expectations):
  1. Staged codeset: CMP threshold > 8 (BMP-excluding rule) and == 11; eligible_sex == "F" exactly on Mammogram and Breast MRI, blank elsewhere.
  2. Missing `eligible_sex` column → same named vector, all eligibility "".
  3. F and lowercase m read back as F and M; `lk[["Mammogram"]]` unchanged; plain vector with no attribute → all "".
  4. Invalid `eligible_sex` value "X" → error mentioning `eligible_sex`.
- Extended `load_modality_lookup()` in `R/utils/utils_surveillance.R`:
  - If `eligible_sex` column absent, defaults to "". Always uppercased.
  - Invalid values (not blank/F/M) stop with a descriptive error naming the offending modality.
  - `eligible_sex` attached as a named attribute (`attr(lookup, "eligible_sex")`) — additive, never modifies the vector itself.
- New `modality_eligible_sex(lookup)` function: returns the attribute, or all-"" named vector if the attribute is absent (handles plain vectors without the attribute safely).

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. The loader change is complete; downstream consumers (R/147 Wave 3) wire the attribute in Plan 160-03.

## Verification Status

**Rscript is unavailable on this Windows development host.** The following are deferred to HiPerGator per the plan's own fallback clause:

- `testthat::test_file("tests/testthat/test-160-loader-eligible-sex.R")` — GREEN confirmation of the 12 expectations
- `testthat::test_dir("tests/testthat", filter = "15[89]|160-loader", stop_on_failure = TRUE)` — confirm no Phase 158/159 regressions
- `Rscript -e "... stopifnot(cs$min_analyte_count[cs$codeset_row_id == 'SC132'] == '11', ...)"` — automated verify from the plan

Per 160-CONTEXT.md and the plan's `<verification>` clause, 160-04 Task 2 (HiPerGator run) will execute these before the workbook ships.

**Structural fallback (passed):**
- `modality_eligible_sex <- function`: 1 match in utils_surveillance.R
- `eligible_sex must be blank, F, or M`: 1 match in utils_surveillance.R
- Brace/paren balance: 712/712 parens, 34/34 braces

## Self-Check: PASSED

Files exist:
- `tests/testthat/test-160-loader-eligible-sex.R`: FOUND
- `R/utils/utils_surveillance.R` (modified): FOUND
- `data/reference/surveillance_codeset.xlsx` (replaced): FOUND
- `data/reference/README.md` (updated): FOUND

Commits exist:
- 77b59b5 (codeset staging): FOUND
- 9ee832a (RED test): FOUND
- cdde78f (GREEN implementation): FOUND
