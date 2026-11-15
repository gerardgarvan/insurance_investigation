# Quick task 261114-uzz: W-RAD, W-NOTX, W-COMBO

Status: **code complete and verified locally; two HiPerGator runs plus a probe PENDING.**

## What changed
- `R/207_radiation_gap_probe.R` (new): W-RAD findings workbook (KEY, A_summary, B_codes_not_in_pipeline, C_codes_in_pipeline_but_missed, D_by_source, QC). Internal RDS under `output/internal/`.
- `R/208_site_treatment_data_completeness.R` (new): W-NOTX workbook (KEY, A_site_table_presence, A2_site_table_detail, B_site_treatment_capture, C_vs_203_no_tx, QC). A2 is an added long-form detail sheet.
- `R/utils/utils_regimen.R`: `assign_lot(combine_cross_type = FALSE, concurrency_window_days)` + `combine_cross_type_family()`. Adds `lot_family` only when TRUE.
- `R/205_lot_output.R`: `R205_LOT_ONLY` (default FALSE), `R205_PREV_LOT_RDS`. TRUE: recompute LOT, write `output/internal/lot_summary_p205_combo.rds/.csv`, print before/after report, skip Gantt reconciliation (Gantt never read).
- `tests/testthat/test-205-lot-counter.R`: 6 new tests for the merge rule.
- Registered in `R/39` investigation_scripts and `R/SCRIPT_INDEX.md`; `R/88` section 15bi (SMOKE-207-01, 11 structural checks).
- `REGL-06-decisions.md`: W-COMBO note (candidate only).
- Not touched: `gantt_episodes_180.csv`, `gantt_episodes.csv`, R/26, R/28, R/52, R/142, R/206, pipeline code lists.

## Verification (local)
- `tools/rcheck.sh parse` on all 7 changed/new `.R` files: 0 failed.
- `tools/rcheck.sh test 205`: 4 files, 0 failed, 0 errors.
- R/88 not run locally (`test 88` finds no testthat file); run it on HiPerGator.

## Assumptions (headless run)
- Default OFF for the merge: R/28 also calls `assign_lot()`, so a default-on change would alter the delivered path. `lot_family` exists only when `combine_cross_type = TRUE`.
- Merge scope: Immunotherapy-type episodes labelled BV mono / PD-1 mono / BV+Nivo / BV+PD-1 pair with the earliest still-unpaired non-ABVD-family Chemotherapy episode that overlaps or starts within `CONCURRENCY_WINDOW_DAYS` (either direction). Family = both labels with " mono" stripped, joined by "+". Maintenance and conditioning labels are unchanged.
- Column names for PROCEDURES (`ID, PX, PX_TYPE, PX_DATE, SOURCE`), DIAGNOSIS (`DX, DX_DATE, SOURCE`), PRESCRIBING (`RX_ORDER_DATE`), MED_ADMIN (`MEDADMIN_START_DATE`), DISPENSING (`DISPENSE_DATE`), ENCOUNTER (`PROVIDERID`), PROVIDER (`PROVIDER_SPECIALTY_PRIMARY`) come from `R/01_load_pcornet.R` column specs, not a `.planning/schemas` probe. Both scripts check them at run time and stop with the available columns. See PENDING probe.
- Radiation-oncology provider = NUCC `2085R0001X` (`PROVIDER_SPECIALTIES`). PCORnet `ENC_TYPE` has no radiation value, so it is not used.
- R/207 TR flags are pinned to `tr_lymphoma_flags_all_patients_20261113.rds` (R/202 uses a newest-file glob).
- R/208 R/203 input: newest `203_no_treatment_characterization_<YYYYMMDD>[_vN].rds` chosen by file name (you asked for "newest"; no mtime). Pin with `R208_203_RDS`; KEY records pinned FALSE and the file.
- R/208 flag rule: median is over sites with a non-zero rate in that table; treatment tables = PROCEDURES, PRESCRIBING, MED_ADMIN, DISPENSING.
- Rates per 100 encounters appear only when rows >= 11 and encounters >= 11.

## PENDING HIPERGATOR
1. Probe first (names not yet probed). In `R --no-save` after `module load R/4.5`:
   ```r
   source("R/00_config.R"); source("R/utils/utils_schema_probe.R")
   probe_inputs("207_208_cdm", tables = c("PROCEDURES", "DIAGNOSIS", "ENCOUNTER", "PROVIDER", "PRESCRIBING", "MED_ADMIN", "DISPENSING"))
   ```
   Paste back: the written `.planning/schemas/207_208_cdm_schema_*.md` column lists (names and types only), or the first error.
2. W-COMBO:
   ```r
   Sys.setenv(R205_LOT_ONLY = "TRUE")
   source("R/205_lot_output.R", local = new.env(parent = globalenv()))
   ```
   Paste back: the `W-COMBO` console lines (n_lines before/after, > 4 lines, top-10 sequences, top-15 `lot_family`) plus any error with ~20 lines.
3. W-RAD: `source("R/207_radiation_gap_probe.R", local = new.env(parent = globalenv()))`. Paste back: `A_summary` and `QC` console tables.
4. W-NOTX: `source("R/208_site_treatment_data_completeness.R", local = new.env(parent = globalenv()))`. Paste back: `A_site_table_presence` and `QC` console tables.
5. Then `source("R/88_smoke_test_comprehensive.R")` and paste the `SMOKE-207-01:` line.

## Decisions needed
- D-205-XTYPE stays OPEN until the W-COMBO report is reviewed.
