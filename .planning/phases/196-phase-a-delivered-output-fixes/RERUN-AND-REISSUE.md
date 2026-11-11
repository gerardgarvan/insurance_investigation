# Phase 195 — Rerun and Reissue List

Run these in order on HiPerGator (interactive R session, `module load R/4.5`, repo root).
Prerequisites run before the scripts that depend on them.

---

## Before rerun

- Snapshot taken at `output/baselines/pre_phaseA_20261111_0852/` (33 files + inventory.csv + cohort_final_fingerprint.rds).
- After R/02: verify `payer_summary.csv` md5 matches `output/baselines/pre_phaseA_20261111_0852/inventory.csv`; list differences before continuing if mismatch.
- After R/14: run `source("R/tools/check_cohort_fingerprint.R", local = new.env(parent = globalenv()))`. **STOP** rerun sequence on FAIL.
- After R/165: regression check vs `output/baselines/distance_cbc_association_20261110_ph195.xlsx` must PASS unchanged (validates the load_payer_summary refactor).
- R/48, R/49, R/52, R/142: **no rerun needed** (version unchanged).

## Run order

| Order | Script | Why |
|-------|--------|-----|
| 1 | `R/02_harmonize_payer.R` | Produces `output/tables/payer_summary.csv` consumed by all payer loaders |
| 2 | `R/14_build_cohort.R` | Fingerprint check; now writes `output/payer_at_chemo.csv` |
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

## A3 — R/30 workbook finding

R/30 already uses `wb_load(AUDIT_XLSX)` at line 270 before saving — the audit concern was a false alarm. No code change made. `episode_classification_audit.xlsx` on HiPerGator should contain both R/28's and R/30's sheets; verify with `openxlsx2::wb_load("output/episode_classification_audit.xlsx")$get_sheet_names()` on HiPerGator.
