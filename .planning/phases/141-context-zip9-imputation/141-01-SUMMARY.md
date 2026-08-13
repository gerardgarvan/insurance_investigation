---
phase: 141-context-zip9-imputation
plan: "01"
title: Wire approximate_zip9() into R/115 and re-issue xlsx
status: awaiting-human-action
one-liner: >
  SECTION 11B wired into R/115: get_zip9_at_date() |> approximate_zip9() per encounter,
  RDS write, join onto encounter_zip (zip9_effective/has_zip9_after_imputation), and
  8-level imputation QC rows appended to qc_tbl; HiPerGator re-run (D-04) pending.
subsystem: R/115 ZIP stability workbook
tags: [zip9-imputation, approximate_zip9, encounter-zip, qc-sheet, phase-141]
dependency_graph:
  requires: [Phase 140 complete, approximate_zip9() in utils_address.R]
  provides: [zip9_imputed_assignment RDS, encounter_zip imputation columns, imputation QC rows]
  affects: [R/115_zip_stability_counts.R, tests/testthat/test-115-imputation-join.R]
tech_stack:
  added: []
  patterns: [get_zip9_at_date |> approximate_zip9 pipeline, factor(.drop=FALSE) for zero-count QC rows]
key_files:
  created:
    - tests/testthat/test-115-imputation-join.R
  modified:
    - R/115_zip_stability_counts.R
decisions:
  - "SECTION 11B inserted after SECTION 11 closing message, before SECTION 12 (as planned)"
  - "SECTION 12 reviewer note added immediately after C-02 pass/fail message block"
  - "SECTION 13 QC rows added after crosswalk conditional block, before the assembled message"
metrics:
  duration_estimate: "~20 min (Tasks 1-2B)"
  completed_tasks: 3
  total_tasks: 4
  completed_date_partial: "2026-08-13"
---

# Phase 141 Plan 01: Wire approximate_zip9() into R/115 and re-issue xlsx — Summary

**Status: AWAITING HUMAN ACTION (Task 3 — HiPerGator re-run, D-04)**

## Tasks Completed (1, 2, 2B)

### Task 1 — SECTION 11B: approximate_zip9() call site, RDS write, join (commit 4460eac)

Added SECTION 11B to `R/115_zip_stability_counts.R` immediately after SECTION 11's closing
`message("=====...====\n")` line, before SECTION 12:

- `enc_lookup_input` deduped to distinct `(ID, ADMIT_DATE)` then renamed `query_date`
- `get_zip9_at_date(ids, dates) |> approximate_zip9()` → `zip9_imputed_assignment`
- `imputed_src_counts` log of `zip9_source` breakdown (pre-join)
- `OUTPUT_RDS_IMPUTED` path: `output/zip9_imputed_assignment_YYYYMMDD.rds`; `saveRDS()` + reload hint
- Re-run safety: `select(-any_of(c("zip9_imputed","zip9_source","zip9_effective","has_zip9_after_imputation")))`
- Grain guard: `n_dup_lookup` check → `stop()` if duplicates found
- `nrow` guard: `stopifnot(nrow(encounter_zip) == n_encounter_zip_before)`
- `left_join` with `relationship = "many-to-one"`, adds `zip9_imputed` and `zip9_source`
- `mutate` adds `zip9_effective = coalesce(direct_zip9, zip9_imputed)` and `has_zip9_after_imputation`
- `n_gained_carryforward` and `n_gained_modal` computed and logged

Also added SECTION 12 reviewer note (commit 4460eac — same commit) immediately after the
C-02 pass/fail message block, clarifying that the completeness waterfall still uses
`scenario_assigned` (not `has_zip9_after_imputation`).

### Task 2 — Imputation QC rows in SECTION 13 (commit 5c1c682)

Added after the block-group crosswalk conditional in SECTION 13:

- `ZIP9_SOURCE_LEVELS` constant (8 levels including `no_lookup_row`)
- `imputation_qc_rows` transmute via `factor(coalesce(zip9_source, "no_lookup_row"), levels=..., .drop=FALSE)` — zero-count rows guaranteed
- `bind_rows` appending to `qc_tbl`:
  - `n_encounters_zip9_after_imputation`
  - `n_encounters_gained_zip9_via_carryforward`
  - `n_encounters_gained_zip9_via_zip5_modal_imputation`
  - `zip5_modal_share_median_among_imputed`
  - `zip5_modal_share_iqr_among_imputed`
  - `zip5_n_candidates_median_among_imputed`
  - 8 × `n_zip9_source_{level}` rows (encounter grain)

### Task 2B — tests/testthat/test-115-imputation-join.R (commit 686cd8d)

Three fixture-based tests:
- `(a)` many-to-one join preserves `nrow(encounter_zip)` — patient A has 2 encounters on the same date; join must not inflate
- `(b)` duplicate `(ID, query_date)` in lookup triggers `stop()` — simulates SECTION 11B's grain guard
- `(c)` `zip9_effective` equals `direct_zip9` wherever `direct_zip9` is non-NA — coalesce priority check

## Deviations from Plan

None — all three auto tasks executed exactly as written.

## Awaiting: Task 3 (HiPerGator re-run, D-04)

See `141-01-PLAN.md` Task 3 `<how-to-verify>` for the full 7-step verification checklist.

Once the HiPerGator run is approved, update this SUMMARY with:
- Actual `zip9_source` breakdown table from the log
- `n_encounters_gained_zip9_via_carryforward` and `n_encounters_gained_zip9_via_zip5_modal_imputation` values
- Whether the probe-first gate triggered (`reference_unavailable` rows > 0 means LDS file was absent)
- `c02_reconciled` status from the new run
- RDS filename and file size from `ls -lh`

## Self-Check: PARTIAL (pre-Task-3)

- [x] SECTION 11B present between SECTION 11 and SECTION 12: confirmed via grep (line 1395)
- [x] `approximate_zip9()` called once (lines 1418, no double-call)
- [x] `OUTPUT_RDS_IMPUTED` with dated filename pattern (lines 1427-1431)
- [x] `encounter_zip` gains all 4 new columns (lines 1437-1462)
- [x] `qc_tbl` imputation rows appended in SECTION 13 (lines 1854-1907)
- [x] 8-level `ZIP9_SOURCE_LEVELS` with `no_lookup_row` included
- [x] Test file created with 3 tests (lines 1, 27, 43)
- [x] Commits: 4460eac (Task 1), 5c1c682 (Task 2), 686cd8d (Task 2B)
- [ ] Task 3: HiPerGator re-run pending
