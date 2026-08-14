---
phase: 141-context-zip9-imputation
plan: "01"
title: Wire approximate_zip9() into R/115 and re-issue xlsx
status: complete
one-liner: >
  SECTION 11B wired into R/115: get_zip9_at_date() |> approximate_zip9() per encounter,
  RDS write, join onto encounter_zip (zip9_effective/has_zip9_after_imputation), and
  8-level imputation QC rows in qc_tbl; xlsx re-issued from HiPerGator (D-04 met);
  76.5% post-imputation coverage — 42,651 encounters gained via carry-forward, 0 via
  ZIP5-modal (zip5_modal_share lookup returned 0 rows, probe-first gate did not trigger).
subsystem: R/115 ZIP stability workbook
tags: [zip9-imputation, approximate_zip9, encounter-zip, qc-sheet, phase-141, d-04]
dependency_graph:
  requires: [Phase 140 complete, approximate_zip9() in utils_address.R]
  provides: [zip9_imputed_assignment_20260813.rds, encounter_zip imputation columns, imputation QC rows, re-issued xlsx]
  affects: [R/115_zip_stability_counts.R, tests/testthat/test-115-imputation-join.R]
tech_stack:
  added: []
  patterns: [get_zip9_at_date |> approximate_zip9 pipeline, factor(.drop=FALSE) for zero-count QC rows, saveRDS with dated filename]
key_files:
  created:
    - tests/testthat/test-115-imputation-join.R
  modified:
    - R/115_zip_stability_counts.R
decisions:
  - "SECTION 11B inserted after SECTION 11 closing message, before SECTION 12 (as planned)"
  - "SECTION 12 reviewer note added immediately after C-02 pass/fail message block"
  - "SECTION 13 QC rows added after crosswalk conditional block, before the assembled message"
requirements-met: [D-01, D-02, D-03, D-04]
metrics:
  duration_estimate: "~30 min (Tasks 1-2B local + Task 3 HiPerGator)"
  completed_tasks: 4
  total_tasks: 4
  completed_date: "2026-08-13"
---

# Phase 141 Plan 01: Wire approximate_zip9() into R/115 and re-issue xlsx — Summary

**Status: COMPLETE (4/4 tasks)**

## One-Liner

SECTION 11B added to `R/115_zip_stability_counts.R`: `get_zip9_at_date() |> approximate_zip9()` on
encounter-level distinct `(ID, ADMIT_DATE)` pairs, with RDS output, grain-guarded join back onto
`encounter_zip`, and 8-level imputation QC rows appended to `qc_tbl`. The re-issued xlsx from the
real HiPerGator run (D-04) shows 76.5% post-imputation coverage; 42,651 encounters gained ZIP9 via
address-history carry-forward; ZIP5-modal imputation resolved 0 encounters (zip5_modal = 0 rows in
the lookup), meaning the LDS reference file was present (probe-first gate did not trigger) but no
modal ZIP9 candidate was available for the encounters that still lacked ZIP9. `c02_reconciled` is
PASS in the re-issued workbook.

## Actual HiPerGator zip9_source Breakdown (from 2026-08-13 run)

| zip9_source | n_person_dates (distinct ID + ADMIT_DATE, pre-join) |
| --- | --- |
| zip9_observed | 743,564 |
| no_zip5 | 157,304 |
| none | 113,725 |
| zip5_modal | 0 |

Levels `zip5_no_zip9`, `reference_unavailable`, `invalid_input` not shown — zero rows, as expected
when the reference file is present and inputs are valid. `no_lookup_row` is a post-join QC
category, not a pre-join lookup outcome.

## Imputation Coverage Figures (from log)

- **Post-imputation coverage:** 76.5% (1,515,373 / 1,980,122 encounters have a ZIP9 after imputation)
- **n_encounters_gained_zip9_via_carryforward:** 42,651 (was `has_direct_zip9 == FALSE`, got `zip9_source == "zip9_observed"` — address-history interval carry-forward resolved these)
- **n_encounters_gained_zip9_via_zip5_modal_imputation:** 0 (zip5_modal = 0 in the lookup)
- **Probe-first gate (D-08):** Did NOT trigger — `reference_unavailable` rows = 0, confirming `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` was found at `CONFIG$data_dir`

## RDS Artifact

- **File:** `output/zip9_imputed_assignment_20260813.rds`
- **xlsx:** `output/zip_stability_counts_20260813.xlsx`

## C-02 Status

`c02_reconciled: PASS` — both `c02a_monotone` and `c02b_partition` pass in the re-issued workbook.
Imputation (SECTION 11B) does not affect `coalesce_zip5()` or the C-02 gate (as designed).

## Non-Blocking Warning

One `many-to-many relationship` warning from `dplyr::inner_join` inside `get_zip9_at_date()`
(`utils_address.R` internal join). This is pre-existing, internal to the lookup function, and not
in any of this plan's new code. Not a blocker; flagged for awareness.

## Tasks Completed

| Task | Commit | Description |
| --- | --- | --- |
| 1 | 4460eac | SECTION 11B: approximate_zip9() call, RDS write, join onto encounter_zip |
| 2 | 5c1c682 | SECTION 13 imputation QC rows (D-03), SECTION 12 reviewer note |
| 2B | 686cd8d | tests/testthat/test-115-imputation-join.R (3 fixture tests) |
| 3 | (HiPerGator) | Re-run confirmed; xlsx re-issued (D-04 met) |

## Deviations from Plan

None — all tasks executed exactly as written. No auto-fixes applied.

## Self-Check: PASSED

- [x] `approximate_zip9()` called once in SECTION 11B (line 1418); no double-call
- [x] `OUTPUT_RDS_IMPUTED` with dated filename `zip9_imputed_assignment_YYYYMMDD.rds` (lines 1427-1431)
- [x] `encounter_zip` gains `zip9_imputed`, `zip9_source`, `zip9_effective`, `has_zip9_after_imputation`
- [x] `qc_tbl` contains all 8 `n_zip9_source_{level}` rows (including zero-count levels via `.drop = FALSE`)
- [x] `n_encounters_zip9_after_imputation`, `n_encounters_gained_zip9_via_carryforward`, `n_encounters_gained_zip9_via_zip5_modal_imputation` rows present in qc_tbl
- [x] 3 fixture tests in `test-115-imputation-join.R`
- [x] HiPerGator re-run confirmed: xlsx re-issued, RDS written, script exited cleanly, `c02_reconciled` PASS
- [x] Commits 4460eac, 5c1c682, 686cd8d present in git log
