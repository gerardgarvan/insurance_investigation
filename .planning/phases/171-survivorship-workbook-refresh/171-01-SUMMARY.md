---
phase: 171-survivorship-workbook-refresh
plan: "01"
subsystem: survivorship-workbook
tags: [survivorship, verification, phase-170-gate, r147, workbook]
requirements-met: [RFSH-02]
key-decisions:
  - "D-03 confirmed: no any-tier column flows into survivorship workbook; primary-only counts throughout"
  - "Gate uses run_date from pointer to derive surveillance_modality_patient_<date>.rds, not the pointer rds field"
  - "EXPECTED_DIFFS = character(0): all survivorship verify checks are affirmative assertions"
  - "QC reconciliation check reads n_py_fail/n_dates_fail as text and asserts == '0'"
key-files:
  created:
    - R/171_verify_survivorship.R
    - slurm/171_verify_survivorship.sbatch
  modified:
    - R/166_survivorship_modality_rates.R
    - R/168_survivorship_workbook.R
status: PARTIAL — awaiting HiPerGator run (Task 4 checkpoint)
---

# Phase 171 Plan 01: Survivorship Workbook Refresh — Partial Summary

**One-liner:** Phase 170 gate wired into R/166, KEY provenance rows added to R/168, and
dedicated verify script + sbatch wrapper written; HiPerGator run pending.

---

## Task 0 Findings (Read-only confirmations)

### 1. D-03: Any-tier columns in the survivorship workbook?

**Answer: NO — no any-tier column reaches `survivorship_modality_rates_<date>.xlsx`.**

Evidence:
- `R/166_survivorship_modality_rates.R` line 103: `n_dates_col <- "n_dates_post_primary"` —
  `compute_modality_rates()` is called with only the primary-tier count column.
  The `n_dates_<mod>_any` columns present in `surveillance_modality_patient_*.rds` are
  loaded but never referenced in SECTION 3 onward.
- `R/167_anthracycline_echo.R` line 184: echo events are filtered from
  `survivorship_dated_events_<date>.rds` (built from the option-a function chain, primary
  events only); no any-tier events are included.
- `R/168_survivorship_workbook.R`: consumes only `long_rates` (from R/166's primary rates),
  `A_rates_summary`, `B_rates_by_fu_year`, and R/167's `C_anthracycline_echo` — no any-tier
  object is read or written.

D-03 approach applies: cite Phase 170 verify log + add KEY-sheet "Phase 163 note" row (done
in Task 1). No direction-of-shift check added to Task 2.

### 2. Dates

- **R/166** (line 58): `run_date <- format(Sys.Date(), "%Y%m%d")` — names all outputs
  (`survivorship_modality_rates_parts_<run_date>.rds`, `survivorship_dated_events_<run_date>.rds`)
- **R/168** (line 39): `run_date <- format(Sys.Date(), "%Y%m%d")` — names the workbook
  `survivorship_modality_rates_<run_date>.xlsx`
- **R/147 input date** (new): `r147_run_date` derived from `147_verify_last_pass.txt` pointer
  in R/166 SECTION 1; saved in parts list for R/168 KEY row

### 3. Pointer format

From `R/147_verify_vs_1006.R` lines 539-545:
```
run_date=20261009
log=output/logs/147_verify_vs_1006_20261009.txt
rds=output/surveillance_patient_modality_dates_20261009.rds
workbook=<path>
```
Key names: `run_date`, `log`, `rds`, `workbook`. The gate uses `run_date` and `log` keys;
derives `surveillance_modality_patient_<run_date>.rds` from `run_date` (NOT from the `rds`
field, which holds `surveillance_patient_modality_dates_*` — a different file per D-01/CONTEXT).

### 4. QC labels (interval reconciliation block in R/168 / QC sheet)

`qc_interval_recon_summary` tibble columns written to QC sheet:
`n_checked`, `n_py_fail`, `n_dates_fail`, `recon_py_pass`, `recon_dates_pass`.

There is **no `result` column with a literal "PASS" string**. The verify check reads the
numeric fail counts as text (via `col_types = "text"`) and asserts both `n_py_fail == "0"`
and `n_dates_fail == "0"`. The `n_checked` label is used to locate the header row of the block.

### 5. Expected differences

From `170-BASELINE-DRIFT.md §7`: all expected differences are for the R/147 verify harness
(Phase 170), not for the survivorship workbook verify. For R/171:

- **`EXPECTED_DIFFS <- character(0)`** (empty). No survivorship-level check needs to be
  skipped. The workbook uses primary-tier counts only; Phase 163's any-tier changes do not
  affect it. All checks are affirmative assertions.

Mapping `170-BASELINE-DRIFT.md expected_differences` to 171 checks:

| 170 expected difference                  | 171 check affected | Action |
|------------------------------------------|--------------------|--------|
| A:excluded_rows_gone                     | none — not a survivorship sheet | n/a |
| Codeset_summary:excl_gone                | none | n/a |
| C_modality_with_sensitivity:Echo/ECG/Mammo/PFT | none — this is R/147's C sheet, not R/168's | n/a |
| D:Echo/ECG/Mammo/PFT:any_eq_primary      | none | n/a |
| QC:matched_rows_drop                     | none — this is R/147's QC sheet | n/a |

**None of the 170-BASELINE-DRIFT.md expected differences apply to the survivorship workbook.**

### 6. Reference workbook

`CONFIG$cache$outputs_dir/survivorship_modality_rates_20261008.xlsx` — existence cannot be
confirmed locally (HiPerGator filesystem only). The `input:ref_workbook` check in
`R/171_verify_survivorship.R` will FAIL if it is absent, which will surface clearly at
Task 4 runtime.

---

## Tasks Executed (pre-HiPerGator)

### Task 1: R/166 gate + R/168 KEY rows (commit 3e8af7e)

**R/166 SECTION 1:**
- Replaced `list.files()` glob with Phase 170 pointer-file gate
- Reads `output/logs/147_verify_last_pass.txt` → extracts `r147_run_date` and `r147_log`
- Validates `r147_run_date` format (`^[0-9]{8}$`) and log ends with `OVERALL: PASS`
- Derives `surveillance_modality_patient_<r147_run_date>.rds` from `run_date` key
- Warns if a newer unverified R/147 INTERNAL workbook exists
- `run_date <- format(Sys.Date(), "%Y%m%d")` still names all R/166 outputs (unchanged)
- `r147_run_date` added as additive element to parts list saved in SECTION 8

**R/168 KEY sheet:** Two new rows added (documentation only):
- `"R/147 input run date"` = `p02$r147_run_date` (or `"not recorded"` if absent)
- `"Phase 163 note"` = `"Phase 163 removed diagnosis-based sensitivity codes from R/147; survivorship rates and echo timing use the primary code set and are unaffected."`

### Task 2: R/171_verify_survivorship.R (commit c0b4b12)

Follows `R/147_verify_vs_1006.R` structure exactly. Log opens before any check. Checks:
1. `input:pointer` — pointer file exists; `run_date` valid 8-digit string
2. `input:ref_workbook` — `survivorship_modality_rates_20261008.xlsx` exists
3. `input:new_workbook` — `survivorship_modality_rates_<surv_date>.xlsx` exists
4. `provenance:r147_input_date` — KEY "R/147 input run date" == pointer `run_date`
5. `A_rates_summary` — sheet identical cell-by-cell as text
6. `B_rates_by_fu_year` — sheet identical cell-by-cell as text
7. `C_anthracycline_echo` — sheet identical (echo uses primary codes; Phase 163 unchanged)
8. `QC:interval_reconciliation` — `n_py_fail == "0"` and `n_dates_fail == "0"`

Final block always runs: tally PASS/FAIL/SKIP; write `OVERALL: PASS` or `OVERALL: FAIL (N checks)`;
`sink(); close(con); quit(status=0/1)`.

### Task 3: slurm/171_verify_survivorship.sbatch (commit dbabc72)

- 1 CPU, 8 GB, 00:30:00; `module load R/4.5`
- Chains `afterok:$JOB166`; R/88 chains `afterany:$JOB_VER`
- `SURV_RUN_DATE` passed via `--export`; echoed at job start
- No `set -e`; captures `rc=$?`; last line `exit $rc`

---

## Deviations from Plan

None — all three tasks executed exactly as specified.

---

## Awaiting HiPerGator (Task 4)

R/147 input run date: `20261009` (from pointer, if pointer is from Phase 170 run)
Survivorship run date: set via `SURV_RUN_DATE=$(date +%Y%m%d)` at submission time

Expected verify log path: `output/logs/171_verify_survivorship_<SURV_RUN_DATE>.txt`

Tasks 5 (SUMMARY completion, ROADMAP, STATE) pending verify results.

---

## Self-Check: PARTIAL

Tasks 1-3 complete and committed. HiPerGator run (Task 4) is the blocking gate.

Commits verified:
- 3e8af7e: feat(171-01): Phase 170 gate in R/166 + provenance KEY rows in R/168
- c0b4b12: feat(171-01): R/171_verify_survivorship.R — survivorship workbook verify script
- dbabc72: feat(171-01): slurm/171_verify_survivorship.sbatch — verify job wrapper
