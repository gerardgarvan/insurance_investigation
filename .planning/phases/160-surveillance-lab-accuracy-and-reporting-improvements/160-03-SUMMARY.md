---
phase: 160-surveillance-lab-accuracy-and-reporting-improvements
plan: "03"
subsystem: R/147_surveillance_modality_frequency
tags: [wiring, A3-diagnostic, eligible-sex, suppression, codeset-summary]
dependency_graph:
  requires: [160-01, 160-02]
  provides: [R/147 Phase 160 wiring]
  affects: [surveillance_modality_frequency_INTERNAL_<date>.xlsx, surveillance_modality_frequency_<date>.xlsx]
tech_stack:
  added: []
  patterns: [Phase-160-function-wiring, eligible-sex-denominators, complementary-suppression, A3-missing-analyte-diagnostic]
key_files:
  created: []
  modified:
    - R/147_surveillance_modality_frequency.R
decisions:
  - "Rscript unavailable on Windows host; keyword + paren/brace balance structural check used in place of Rscript parse; testthat and full runtime deferred to HiPerGator (160-04 Task 2)"
metrics:
  duration_minutes: 10
  completed_date: "2026-09-25"
  tasks_completed: 1
  files_modified: 1
---

# Phase 160 Plan 03: Wire Phase 160 Functions into R/147 Summary

R/147 updated from Phase 159 to Phase 160: seven new Phase 160 functions from utils_surveillance.R wired in, adding the A3 missing-analyte diagnostic, female-denominator eligible-sex columns for breast imaging, complementary suppression, and an auto-generated Codeset_summary sheet.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Update R/147 | d78e218 | R/147_surveillance_modality_frequency.R |

## What Was Built

**R/147_surveillance_modality_frequency.R — Phase 160 wiring (127 net insertions):**

- **Run constants added:** `A3_SEED` (2026L), `A3_MAX_DAYS` (5000L), `A3_TOP_N` (25L), `CODESET_PATH`, `CROSSWALK_PATH`
- **SECTION 1:** `elig <- modality_eligible_sex(mod_lookup)` added after `mod_lookup`; updated header comment to reference 160-CONTEXT.md D-01..D-13
- **SECTION 2:** `demo_tbl <- lazy_table("DEMOGRAPHIC")` added for Phase 160 IMP-04
- **SECTION 6:** `sex_lookup` pull from `demo_tbl` (ID + SEX, filtered to `followup$ID`) added after `followup` computation
- **SECTION 8 stats_for:** Replaced flat `compute_modality_stats()` calls with `compute_eligible_modality_stats()` for modality-level rows via `mod_stats()`; L-5 guard `stopifnot("L-5: eligibility must not change the all-patient B columns" = ...)` wired using `plain_B` vs `chk_B`
- **SECTION 8 A3 block:** Full A3 section wired — `summarise_missing_analyte()`, reconciliation `stopifnot`, `select_a3_sample()`, DB-side date join via `tmp_surv_a3_days` temp table, `surv_sql_date_expr()` dialect detection (`duckdb` vs `sqlite`), `rank_candidate_codes()`, `a3_raw_top` RAW-flag warning
- **SECTION 8:** `build_codeset_summary()` call producing `codeset_summary`
- **SECTION 8 QC:** Three new rows — sex distribution, A3 sample size/coverage/seed, A3 RAW-flag count
- **SECTION 9 KEY:** Three new rows — A3_missing_analyte description, breast imaging denominators (D-04 wording with live female N), Codeset_summary description
- **SECTION 9 write_workbook:** `sup_elig()` helper for complementary suppression; `A3_missing_analyte` sheet added (block 1); `Codeset_summary` sheet added; B/C sheets wrapped with `sup_elig()`; A3 blocks 1b/2 and Codeset_summary block 2 appended below their primary tables via extra `writeData()` calls; release `a3_rank_out` filters RAW-only and drops raw code/name columns
- **Sheet order:** KEY, A_code_presence, A2_analyte_presence, A3_missing_analyte, B_modality_primary, C_modality_with_sensitivity, D_pre_vs_post_anchor, E_patient_modality_dates (INTERNAL only), QC, Codeset_summary

## Deviations from Plan

None — plan executed exactly as written. The plan provided the complete replacement file verbatim; the current file matched the Phase 159 baseline exactly, with no unexpected changes to report.

## Known Stubs

None. All Phase 160 wiring paths are fully connected to the functions delivered in 160-02. The actual runtime (data paths, DuckDB queries, xlsx output) is deferred to HiPerGator per the plan's own verification clause.

## Verification Status

**Rscript unavailable on Windows dev host.** Structural fallback used (per plan `<verification>` clause):

- All 12 required keywords present: summarise_missing_analyte, select_a3_sample, surv_sql_date_expr, tmp_surv_a3_days, rank_candidate_codes, compute_eligible_modality_stats, suppress_eligible_columns, build_codeset_summary, A3_missing_analyte, Codeset_summary, "screening-population uptake", "L-5: eligibility" — all FOUND
- Paren balance: 0 (balanced)
- Brace balance: 0 (balanced)

Per the plan's fallback clause: "If Rscript is unavailable (Windows dev host), do not skip silently: run the structural fallback below, record in the SUMMARY that the testthat run is deferred, and 160-04 Task 2 runs it on HiPerGator first."

160-04 Task 2 (HiPerGator run) will execute `testthat::test_dir("tests/testthat", filter = "15[89]|160", stop_on_failure = TRUE)` and the full end-to-end workbook run before the workbook ships.

## Self-Check: PASSED

Files exist:
- `R/147_surveillance_modality_frequency.R` (modified): FOUND

Commits exist:
- d78e218 (feat(160-03): wire Phase 160 functions into R/147): verified via git log
