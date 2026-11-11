# Phase 195 — Rerun and Reissue List

Run these in order on HiPerGator (interactive R session, `module load R/4.5`, repo root).
Prerequisites run before the scripts that depend on them.

---

## Before Phase 197 rerun (config safety)

- **Stale backup check (Phase 197-06):** `R/00_config.R.bak` exists on disk from an interrupted R/22 or R/50 run. Before any Phase 197 script rewrites `R/00_config.R`, verify the backup matches the live config and delete it:
  ```bash
  diff R/00_config.R R/00_config.R.bak
  rm R/00_config.R.bak
  ```
  Run these on HiPerGator from the repo root. If `diff` shows differences, review them before deleting. After Phase 197-06 ships, `trim_config_bak()` will keep only the last 5 timestamped backups and no plain `.bak` files will be written.

---

## Before rerun

- Snapshot taken at `output/baselines/pre_phaseA_20261111_0852/` (33 files + inventory.csv + cohort_final_fingerprint.rds).
- After R/02: verify `payer_summary.csv` md5 matches `output/baselines/pre_phaseA_20261111_0852/inventory.csv`; list differences before continuing if mismatch.
- After R/14: run `source("R/tools/check_cohort_fingerprint.R", local = new.env(parent = globalenv()))`. **STOP** rerun sequence on FAIL.
- After R/165: regression check vs `output/baselines/distance_cbc_association_20261110_ph195.xlsx` must PASS unchanged (validates the load_payer_summary refactor).
- R/49, R/52, R/142: **no rerun needed** (version unchanged).
- R/48: **rerun required** — Comparison sheet column-label swap fixed and baseline switched to R/47 refined (see R/48 section below).

## Run order

| Order | Script | Why |
|-------|--------|-----|
| 1 | `R/02_harmonize_payer.R` | Produces `output/tables/payer_summary.csv` consumed by all payer loaders |
| 2 | `R/14_build_cohort.R` | Fingerprint check; now writes `output/payer_at_chemo.csv` |
<!-- Note (D-197-01): R/14 sources R/02 internally — do not list both in R/39 or any rerun list that runs off R/39. This Phase 196 list is an exception: R/02 is listed first for the md5 verification step (line 11 above) before R/14 runs. -->
| 3 | `R/107_med_admin_dispensing_gap_diagnostic.R` | suppress_small fix |
| 4 | `R/109_med_admin_dispensing_fix_impact_audit.R` | suppress_small fix + cache path fix |
| 5 | `R/110_output_level_before_after_report.R` | suppress_small fix + stop() on missing payer_at_chemo.csv |
| 6 | `R/45_cancer_summary.R` | Produces `cancer_summary.csv` (R/47 must not have run after R/45 since the fix) |
| 7 | `R/46_cancer_summary_table.R` | Reads R/45 raw output |
| 8 | `R/47_cancer_summary_refined.R` | Writes `cancer_summary_refined.csv` |
| 9 | `R/165_distance_cbc_association.R` | Payer loader refactor — regression check vs baseline XLSX must PASS |
| 10 | `R/183_mice_sensitivity_distance.R` | **Priority rerun** — MICE sensitivity now includes payer covariate |

---

## Output files that will change

| Script | Old delivered file | What changes |
|--------|-------------------|--------------|
| R/107 | `output/med_admin_dispensing_gap_diagnostic.csv` (any date) | n_patients cells 1–10 now show `"<11"` instead of blank |
| R/109 | `output/med_admin_dispensing_fix_impact.xlsx` (any date) | n_patients cells 1–10 now show `"<11"`; regimen-impact sheet now populated (was always empty placeholder on HiPerGator) |
| R/110 | `output/output_level_before_after_report.xlsx` (any date) | n_patients cells 1–10 now show `"<11"`; payer-anchor sheet now populated |
| R/47 | `output/tables/cancer_summary.csv` — no longer overwritten | `output/tables/cancer_summary_refined.csv` is the new R/47 output |
| R/183 | `output/mice_sensitivity_distance_*.xlsx` (any date) | MICE model now fitted with payer covariate |
| R/14 | (new file) | `output/payer_at_chemo.csv` created for first time |

---

## Recipient notes

- **R/107 reissue:** "Suppressed counts (1–10 patients) now labelled `<11` instead of blank — no counts changed."
- **R/109 reissue:** "Suppressed counts now `<11`; regimen-label section previously always empty on HiPerGator due to wrong cache path — now populated."
- **R/110 reissue:** "Suppressed counts now `<11`; payer-anchor sheet now populated from R/14 output."
- **R/183 reissue (priority):** "MICE sensitivity analysis now includes payer (PAYER_CATEGORY_PRIMARY) as a covariate. Prior runs lacked it because payer_summary was only written as CSV, not RDS. Results may differ."
- **R/47:** `cancer_summary_refined.csv/xlsx` replaces `cancer_summary.csv` as the R/47 deliverable. `cancer_summary.csv` is now R/45's unfiltered output only.

---

## R/47 — output path renamed (2026-11-11, quick-261111-e84)
- **Why:** OUTPUT_TABLE_XLSX renamed from cancer_summary_table.xlsx to cancer_summary_refined_table.xlsx to prevent overwriting R/46 output.
- **Must rerun:** R/47_cancer_summary_refined.R — produces output/tables/cancer_summary_refined_table.xlsx
- **Then rerun:** R/48_cancer_summary_post_hl.R — BASELINE_TABLE_XLSX now points to cancer_summary_refined_table.xlsx
- **dep_map note:** Rerun dep_map.R on HiPerGator after these reruns to confirm cancer_summary_table.xlsx no longer appears as an R/47 output in the dependency map.

---

## R/48 — Comparison sheet column-label swap fixed (2026-11-11)

- **Why:** The delivered 2026-10-06 workbook had "Baseline Patients" and "Post-HL Patients" column headers swapped relative to the data. Column B held post-HL counts but was labelled "Baseline Patients". Delta and % Retained were computed correctly. Additionally, the 2026-10-06 baseline was R/46 raw (9,331 patients, 54 categories including D-code rows); commit 1afc456 already rewired BASELINE_TABLE_XLSX to R/47 refined (7,696 confirmed HL patients, 49 categories, no D-codes), making the comparison like-for-like.
- **Decision D-196-01:** Comparison baseline = R/47 refined (confirmed HL, D-codes removed). Column order now matches headers: baseline_patients written to Column B, post_hl_patients to Column C.
- **Must rerun after R/47:** R/48_cancer_summary_post_hl.R — produces output/tables/cancer_summary_table_post_hl.xlsx with corrected Comparison sheet.
- **Reissue note:** "Comparison sheet column labels were swapped in the prior delivered version (2026-10-06). Column B now correctly shows Baseline Patients (R/47 refined, 7,696 confirmed HL patients, 49 categories) and Column C shows Post-HL Patients. Delta and % Retained values were unaffected by the label error."
- **Status:** COMPLETE — rerun 2026-11-11 17:03 (0.7 min); label swap confirmed; included in 2026-11-11 re-issue to Amy/Erin.

## A3 — R/30 workbook finding

R/30 already uses `wb_load(AUDIT_XLSX)` at line 270 before saving — the audit concern was a false alarm. No code change made. `episode_classification_audit.xlsx` on HiPerGator should contain both R/28's and R/30's sheets; verify with `openxlsx2::wb_load("output/episode_classification_audit.xlsx")$get_sheet_names()` on HiPerGator.

---

## R/183 — payer 'Missing' recode to NA (2026-11-11, quick-261111-eqg)
- **Why:** The literal "Missing" level (183 patients) was treated as an observed MICE category instead of being imputed. D-196 decision: MICE treats "Missing"/"Unknown"/"UNKNOWN"/"" as NA (imputed); R/165 tables keep "Missing" as a reported category (D-195-02 assert).
- **Must rerun:** R/183_mice_sensitivity_distance.R — produces output/mice_sensitivity_distance_<date>.xlsx
- **Reissue note:** "MICE sensitivity: payer 'Missing' (183 patients) now recoded to NA and imputed rather than treated as an observed category. Pooled ORs expected to move <=0.023 vs 20261111 run; no change in conclusions anticipated."
- **Phase B/C candidate:** main_sourceUCI dropped from dist_to_source_facility_mi model in every iteration (~400 loggedEvents; also present in 10/15 run). Log the dep/out table from the new run.
