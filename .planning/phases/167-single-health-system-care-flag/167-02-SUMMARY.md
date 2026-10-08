---
phase: 167-single-health-system-care-flag
plan: 02
subsystem: single-source-care-flag
tags: [workbook, openxlsx, suppression, duckdb, registration, slurm]
dependency_graph:
  requires: [167-01]
  provides: [R/169 SECTIONS 4-5, slurm/167_single_source_care.sbatch]
  affects: [R/39, R/88, R/SCRIPT_INDEX.md]
tech_stack:
  added: [openxlsx]
  patterns: [sup_with_totals complementary suppression, encounter-band crosstab, pct_safe]
key_files:
  created: [slurm/167_single_source_care.sbatch]
  modified:
    - R/169_single_source_care.R
    - R/39_run_all_investigations.R
    - R/88_smoke_test_comprehensive.R
    - R/SCRIPT_INDEX.md
decisions:
  - openxlsx (not openxlsx2) — matches project convention from R/168
  - sup_with_totals applies complementary suppression: if exactly one interior cell in a row/column is 1-10, that row/column total is also suppressed
  - by_source_single_post uses primary_source (whole-record) for the post-anchor by-SOURCE breakdown — primary_source is defined over the whole record, which is the correct attribution
  - B_post_anchor uses n_enc_post_disp (NA for patients without anchor) so population_rows correctly reports them as "no encounters"
metrics:
  duration: ~30 min
  completed: 2026-10-08
  tasks: 2
  files_changed: 5
---

# Phase 167 Plan 02: Workbook Assembly, Registration, and SLURM Wrapper Summary

**One-liner:** openxlsx workbook (KEY/A_summary/B_post_anchor/QC) with encounter-band crosstab, 4+ n_sources cap, complementary suppression, sensitivity arithmetic — registered in R/39, SMOKE-167-01 in R/88, SLURM wrapper at slurm/167_single_source_care.sbatch.

## Tasks Completed

### Task 1: R/169 SECTIONS 4-5 — Workbook

Inserted SECTIONS 4-5 inside the `if (duckdb_ok)` block of `R/169_single_source_care.R`, before the `duckdb_unregister` cleanup.

**Display helpers added:**
- `sup(x)`: wraps `suppress_small(x)`
- `pct_safe(num, den)`: returns percentage rounded to 1 dp; returns `""` when num or den is 1-10
- `sup_with_totals(tab)`: suppresses interior cells 1-10 in a 2-way table with totals; applies complementary suppression to any row/column total that has exactly one suppressed interior cell

**SECTION 4 builders:**
- `population_rows()`: six rows — cohort, no encounters, all-blank SOURCE, flagged denominator, single-source, % single-source
- `band_crosstab()`: encounter bands 1 / 2-4 / 5-9 / 10+; restricted to non-NA flag patients
- `n_sources_dist()`: n_sources >= 1; capped at "4+"; "4+" sorts last
- `by_source_single()` / `by_source_single_post()`: single-source patients by primary_source, descending

**SECTION 5 workbook assembly (sheet order: KEY, A_summary, B_post_anchor, QC):**
- KEY: run date, script, decisions D-167-01 through D-167-07, date range, anchor source, SOURCE normalisation, flag definition, windows, suppression rule, sheet guide, internal-files note
- A_summary: whole-record window — population rows, band crosstab, n_sources distribution, by-SOURCE breakdown (blank row + title between blocks)
- B_post_anchor: post-anchor window — same structure; title states post-anchor population; uses n_enc_post_disp (NA for no-anchor patients) to correctly classify them as "no encounters"
- QC: n_na_admit, any-blank/all-blank SOURCE counts (flag_style on any-blank row), NA-reason counts (no anchor / no post-anchor encounters / all-blank post), SENSITIVITY block (n_single_primary − n_flip + n_all_blank with flag_style header), 2×2 whole×post through `sup_with_totals()`
- Workbook saved to `output/single_source_care_{run_date}.xlsx` before cleanup

**Commit:** 085158f

### Task 2: Registration + SLURM Wrapper

1. **R/39_run_all_investigations.R**: added `"R/169_single_source_care.R"` after `"R/168_survivorship_workbook.R"` with Phase 167 comment and output descriptions.

2. **R/88_smoke_test_comprehensive.R**: added Section 15ap / SMOKE-167-01 with 10 checks:
   - [1] R/169 exists
   - [2] defines build_single_source_result
   - [3] uses openxlsx (not openxlsx2)
   - [4] contains sheet literals KEY, A_summary, B_post_anchor, QC
   - [5] contains get_hl_any_dx_ids, duckdb_register, duckdb_unregister
   - [6] does NOT contain `quit(`
   - [7] registered in R/39
   - [8] test file exists
   - [9] output-gated: sheet order correct if xlsx found
   - [10] output-gated: column constraints if internal RDS found (flag values in {0,1,NA}; n_sources==0 invariant)

3. **R/SCRIPT_INDEX.md**: added R/169 row after R/168; incremented investigations count 23→24; total 111→112.

4. **slurm/167_single_source_care.sbatch**: created from 166 template; job name 167_single_source_care; account/qos erin.mobley-hl.bcu; 4 CPUs; 16gb; 02:00:00; logs/167_single_source_care_%j.out; `set -e`; `module load R/4.5`; `cd /blue/erin.mobley-hl.bcu/insurance_investigation`; runs testthat file → R/169 → R/88 each to a dated log.

**Commit:** 589244d

## Deviations from Plan

### Auto-added: by_source_single_post helper

**Rule 2 — missing functionality.** B_post_anchor's "by-SOURCE breakdown" filters on `single_source_care_post == 1`. The plan specified `by_source_single()` but that function filters on `single_source_care == 1` (whole-record). A separate `by_source_single_post()` was added to filter correctly on the post-anchor flag while reusing `primary_source` (whole-record most common site) for the breakdown column — which is the correct attribution.

### Auto-added: n_enc_post_disp column for B_post_anchor population_rows

**Rule 2 — correctness.** `population_rows()` treats NA `n_enc_col` values as "no encounters." For the post-anchor view, patients without an anchor date would have `n_encounters_post == 0` (coalesced in SECTION 2) but should appear in "no encounters in window" (because for them there is no post-anchor window at all). A `n_enc_post_disp` column is computed as NA when `hl_anchor_date` is NA, so `population_rows()` classifies those patients correctly.

## Pending: Tasks 3-4 (Human Action Required)

Tasks 3 and 4 require HiPerGator access and are not automatable.

### Task 3: HiPerGator Run (human-action gate)

Steps required:
1. Sync the following files to HiPerGator:
   - `R/169_single_source_care.R`
   - `tests/testthat/test-169-single-source-care.R` (if not yet synced)
   - `R/39_run_all_investigations.R`
   - `R/88_smoke_test_comprehensive.R`
   - `R/SCRIPT_INDEX.md`
   - `slurm/167_single_source_care.sbatch`
2. `cd /blue/erin.mobley-hl.bcu/insurance_investigation && sbatch slurm/167_single_source_care.sbatch`
3. Confirm: tests pass; R/169 completes; SMOKE-167-01 all PASS.
4. Paste the test summary, R/169 log tail, and SMOKE-167-01 footer.

### Task 4: Review Outputs (human-verify gate)

After the run, review:
1. `output/single_source_care_<date>.xlsx`: sheets KEY → A_summary → B_post_anchor → QC; UF headers.
2. A/B: population rows add up (cohort = no encounters + all blank + flagged); % uses the flagged denominator; bands, 4+ cap, by-SOURCE present.
3. No displayed 1-10; percentages blank where source count is "<11"; 2×2 totals suppressed where one interior cell is.
4. QC: sensitivity arithmetic shown (primary − flips + all-blank); NA-reason counts present.
5. `output/internal/` has the CSV and RDS with the D-167-07 columns; nothing patient-level in `output/` root.
6. The CSV joins onto a Phase 165/166 patient table on ID.

## Known Stubs

None. All workbook sections wire to in-run objects from SECTIONS 1-3. No hardcoded placeholder data.

## Self-Check

- R/169_single_source_care.R: modified (624 lines inserted)
- slurm/167_single_source_care.sbatch: created
- R/39 contains "R/169_single_source_care.R": confirmed (line 235)
- R/88 contains "SMOKE-167-01": confirmed (line 6121+)
- R/SCRIPT_INDEX.md contains R/169 row: confirmed
- Commits 085158f and 589244d exist

## Self-Check: PASSED
