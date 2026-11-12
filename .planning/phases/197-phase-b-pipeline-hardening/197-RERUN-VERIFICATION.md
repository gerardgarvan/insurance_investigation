# Phase 197 Rerun Verification

Generated: 2026-11-11. Run each step in order on HiPerGator. Mark PASS/FAIL.

## HiPerGator session setup

```
module load R/4.5
R --no-save
source("R/00_config.R", local = new.env(parent = globalenv()))
```

Then for each step below:
```
source("R/<NNN>_<script>.R", local = new.env(parent = globalenv()))
```

---

## Ordered Verification Table

| # | Script | What to check | Expected result | PASS/FAIL |
|---|--------|---------------|-----------------|-----------|
| 1 | R/02_harmonize_payer.R | `nrow()` and `head(5, ID)` of `payer_at_chemo.csv`; rows should be sorted ascending by ID | Same row count as pre-Phase 197; IDs in ascending order in the first 5 rows | |
| 2 | R/14_build_cohort.R | Cohort attrition counts at each step (paste the final attrition block) | Counts unchanged from Phase 196-A final run | |
| 3 | R/26_treatment_episodes.R | Checkpoint message: `[R/26] treatment_episodes_stage1.rds written — N rows` | File written; no reference to `treatment_episodes.rds` in the message | |
| 4 | R/53_death_date_validation.R | Checkpoint message: `validated_death_dates.rds written` | File present in output path | |
| 5 | R/29_first_line_and_death_analysis.R | (a) `[R/29] Pre-write validation: PASS` message; (b) `[R/29] treatment_episodes.rds written (canonical)` message; (c) `is_first_line: N TRUE` where N > 0 | All three appear; no stop() error; first-line count > 0 | |
| 6a | R/107_med_admin_dispensing_gap_diagnostic.R | Log line showing versioned output path (e.g., `_v2` suffix if same date as prior run) | Versioned path logged; no silent overwrite | |
| 6b | R/109_med_admin_dispensing_fix_impact_audit.R | Log line showing versioned output path | Versioned path logged; no silent overwrite | |
| 6c | R/110_output_level_before_after_report.R | Log line showing versioned output path; `is_first_line` column guard message does NOT stop | Guard passes silently (column present); versioned path logged | |
| 7a | R/46_cancer_summary_table.R | Output file `cancer_summary_table.xlsx` written; row counts match Phase 196-A | Counts unchanged | |
| 7b | R/47_cancer_summary_refined.R | Output file is `cancer_summary_refined_table.xlsx` (not `cancer_summary_table.xlsx`) | Correct filename; no overwrite of R/46 output | |
| 7c | R/48_cancer_summary_comparison.R | Comparison workbook written; Baseline column sourced from R/47 output | No fatal error; Comparison column labels correct | |
| 8 | R/165_distance_cbc_association.R | Regression check vs Phase 195 baseline: OR and both CI bounds within 0.005 | `[R/165] regression check: PASS` | |
| 9 | R/183_mice_sensitivity_distance.R | `COLLAPSE_RARE_SOURCE` reads as `FALSE`; main_source level counts logged without modification; no MICE rerun | Log line: `[R/183] COLLAPSE_RARE_SOURCE=FALSE — skipping collapse`; script completes without error | |
| 10 | R/tools/check_cohort_fingerprint.R | Fingerprint check vs pre_phaseA baseline | All four lines show OK: `n_rows: OK`, `n_unique_id: OK`, `sorted_id_md5: OK`, `columns: OK` | |
| 11 | R/tools/mice_convergence_diagnostic.R | Writes `197-MICE-CONVERGENCE.md`; paste back: (a) full main_source level counts table, (b) full R-hat convergence table, (c) `[diag] Report written:` line | Report written without error; paste the three sections | |
| 12 | R/tools/dep_map.R | New `dep_map_risk_report_v*.md` written to `output/dep_map/`; paste back its full contents | Zero CRITICAL run-order issues; zero duplicate-writer issues for treatment_episodes.rds and rxnorm cache; unpinned count reduced from pre-197 baseline | |

---

## Notes

- **Step 9 (R/183):** Do NOT rerun MICE. The flag check only reads `COLLAPSE_RARE_SOURCE` from env; the full MICE computation is not triggered unless you explicitly set `COLLAPSE_RARE_SOURCE=TRUE` and source R/183 for a full run.
- **Step 11 (mice diagnostic):** Uses the 2026-11-11 mids files (`mice_input_patient_20261111.rds`, `mice_mids_20261111.rds`) by default. Set `MICE_DIAG_INPUT` / `MICE_DIAG_MIDS` env vars to override.
- **Step 12 (dep_map):** The new report will be `dep_map_risk_report_v6.md` (or the next increment after the current highest version in `output/dep_map/`). Paste the full file content.
- **R/00_config.R.bak (action before any config-writing run):** Verify and delete the stale plain `.bak` file that pre-dates Phase 197-06:
  ```bash
  diff R/00_config.R R/00_config.R.bak
  rm R/00_config.R.bak
  ```
  If `diff` shows differences, review before deleting.
