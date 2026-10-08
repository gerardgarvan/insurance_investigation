---
phase: 166-survivorship-modality-rates-and-anthracycline-to-echo-timing
plan: "04"
subsystem: survivorship-modality-rates
tags: [survivorship, workbook, xlsx, registration, smoke-test, slurm]
one_liner: "Workbook assembler R/168 + R/39 registration + SMOKE-166-01 section + SLURM wrapper for Phase 166"
dependency_graph:
  requires: ["166-02", "166-03"]
  provides: [survivorship_modality_rates_YYYYMMDD.xlsx, per-patient-exports, slurm/166_survivorship.sbatch]
  affects: [R/39_run_all_investigations.R, R/88_smoke_test_comprehensive.R, R/SCRIPT_INDEX.md]
tech_stack:
  added: []
  patterns: [openxlsx workbook assembly, display suppression, dated outputs, SLURM sbatch]
key_files:
  created:
    - R/168_survivorship_workbook.R
    - slurm/166_survivorship.sbatch
  modified:
    - R/39_run_all_investigations.R
    - R/88_smoke_test_comprehensive.R
    - R/SCRIPT_INDEX.md
decisions:
  - "R/39 expected_xlsx list not updated for dated workbook — dated filenames cannot be statically listed; workbook registered only via investigation_scripts (consistent with R/147 precedent)"
metrics:
  duration_minutes: 35
  completed_date: "2026-10-08"
  tasks_completed: 2
  tasks_total: 4
  files_modified: 5
requirements_completed: [SRATE-02, SRATE-03, SRATE-04]
---

# Phase 166 Plan 04: Workbook, Registration, SLURM — Summary

## What Was Built

R/168_survivorship_workbook.R assembles the deliverable workbook and per-patient exports from Plan 02 (R/166) and Plan 03 (R/167) parts. Key behaviors:

- Loads most-recent `survivorship_modality_rates_parts_*.rds` and `survivorship_echo_parts_*.rds`; warns if their run-dates differ
- Builds `long_all = bind_rows(long_rates, echo_rate_patient)` (includes `echo_post_anthracycline` modality)
- Pivots to wide per-patient table using `names_glue = "{modality}_rate_per_py"`
- Writes INTERNAL unsuppressed `.rds` (long + wide) and `.csv`
- `display_counts()` helper: counts 1-10 → "<11"; paired rate columns blanked when count suppressed (prevents back-calculation from rate × person-years)
- Workbook sheets in required order: KEY, A_rates_summary, B_rates_by_fu_year, C_anthracycline_echo, QC
- KEY records: run date, script names, echo_modality_name, follow-up definition, n_dates_col, reconciliation contract, interval boundaries, D-166-01 (d_166_01_record), D-166-02 (episode_file_used), Mitoxantrone note, D-14c caveat, rate formula, CIF/KM definitions, suppression rule
- QC sheet: interval reconciliation (FAIL rows flagged UF_ORANGE), n_zero_py_patients, echo QC block (counts suppressed), per-drug counts (counts suppressed)
- UF styling: header `#0021A5` white bold Arial; flag style `#FA4616`
- Saves `survivorship_modality_rates_{run_date}.xlsx`

## Registration and SLURM

R/39: three scripts added in dependency order after R/162:
- `R/166_survivorship_modality_rates.R` (rates driver)
- `R/167_anthracycline_echo.R` (echo driver)
- `R/168_survivorship_workbook.R` (workbook assembler)

R/88 Section 15ao (SMOKE-166-01): 12 checks covering file existence, all 5 rate functions + 4 echo functions defined, both test-166 files, R/39 registration, literal event levels, workbook sheet order, parts files presence. Footer: `SMOKE-166-01: <n> PASS / <m> FAIL`.

SCRIPT_INDEX.md: added 3 new rows for R/166, R/167, R/168; updated post-renumber count 20→23, utility count 12→14, total 106→111.

`slurm/166_survivorship.sbatch`: `module load R/4.5`; `cd /blue/erin.mobley-hl.bcu/insurance_investigation`; `set -e`; Step 0 runs both testthat files; Steps 1-3 run R/166, R/167, R/168 each to a dated log.

## Tasks Status

| Task | Name | Status | Commit |
|------|------|--------|--------|
| 1 | R/168_survivorship_workbook.R | COMPLETE | 9880fb3 |
| 2 | Registration + SLURM wrapper | COMPLETE | b0c08f6, 70f4846 |
| 3 | Run on HiPerGator | PENDING (checkpoint:human-action) | — |
| 4 | Review the workbook | PENDING (checkpoint:human-verify) | — |

## Deviations from Plan

**[Deviation - Minor] R/39 expected_xlsx not updated for dated workbook**
- **Found during:** Task 2
- **Issue:** The plan says "add the dated workbook to `expected_xlsx`". Dated filenames (e.g., `survivorship_modality_rates_20261008.xlsx`) cannot be listed statically in `expected_xlsx` because the date changes on each run.
- **Fix:** Consistent with `R/147`'s own precedent (its dated RDS is also not in `expected_xlsx`), the workbook is registered only in `investigation_scripts`. The smoke-test (SMOKE-166-01 check 12) verifies the parts files exist when produced.
- **Files modified:** none (no change required)

## Known Stubs

None. R/168 reads all data from parts files produced by R/166 and R/167 at runtime; no hardcoded empty values or placeholders.

## Self-Check: PARTIAL

Files created/modified:
- FOUND: R/168_survivorship_workbook.R ✓ (committed 9880fb3)
- FOUND: slurm/166_survivorship.sbatch ✓ (committed b0c08f6)
- FOUND: R/39 modifications ✓ (committed 70f4846)
- FOUND: R/88 modifications ✓ (committed b0c08f6)
- FOUND: SCRIPT_INDEX.md modifications ✓ (committed b0c08f6)

HiPerGator run (Tasks 3-4): PENDING — checkpoint returned to user. Final verification artifacts (test summaries, QC reconciliation result, SMOKE-166-01 footer) will be produced on HiPerGator.
