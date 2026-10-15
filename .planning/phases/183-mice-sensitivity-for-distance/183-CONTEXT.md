# Phase 183: MICE Sensitivity for Distance - Context

**Gathered:** 2026-10-15 (revised 2026-10-15 after plan review)
**Status:** Ready for planning

<domain>
## Phase Boundary

Run multiple imputation (mice, m = 20) for the 614 patients still missing the exposure after Phase 182/182.1, refit the Phase 179 GEE in each imputed dataset, pool with Rubin's rules written out in code, and produce a workbook plus a short script-generated memo comparing the pooled OR to the complete-case OR and the Phase 180 bounds. Imputation is at the **patient level**: the exposure is one value per patient (median post-anchor distance), and the 614 are missing it for every year.

</domain>

<decisions>
## Implementation Decisions

### Imputation target
- **D-01 (primary):** Impute `log_dist = log1p(median_distance)` by PMM. Derive `far = as.integer(expm1(log_dist) > CONFIG$far_from_care_cutoff_mi)`. `log1p` avoids extreme values for distance 0 (same-ZIP patients).
- **D-02 (sensitivity):** Impute `far` directly with `logreg` (`far` stored as a factor with levels "0","1"; convert back with `as.integer(as.character(.))`).
- **D-02a:** D-01 and D-02 are **two separate mice runs**. D-01 data contain `log_dist` and not `far`; D-02 data contain `far` and not `log_dist`. (In the observed data `far` is a deterministic function of `log_dist`; one joint run would give complete separation in the logreg model and circular imputation.)
- **D-03:** One row per patient (all 8,632 cohort patients in the pinned Phase 179 RDS). Imputed patient values are joined back to patient-years; observed `far` is never changed.

### MICE settings
- **D-04:** `m = 20`, `maxit = 20`, seed `20261015` (both runs; recorded in KEY).

### Predictor set (one row per patient; all computed for ALL patients, observed and missing)
- **D-05 (outcome — mandatory):** `prop_cbc_years` = mean(`cbc_year`) and `n_years_observed` = number of rows, over **all rows of the pinned Phase 179 RDS** for that patient (the RDS holds only fully observed years — the same years the GEE uses). No `exposure_missing` filter: the outcome is observed for the 614; only the exposure is missing.
- **D-06 (auxiliary — mandatory where computable):** `dist_to_source_facility_mi` = haversine distance (miles) between the gazetteer centroid of the patient's modal post-anchor patient ZIP5 and the gazetteer centroid of the **modal facility ZIP5 of the patient's main SOURCE**, where the SOURCE modal facility ZIP5 is computed from `distance_status == "computed"` encounters across all patients. Computed for every patient with a usable patient ZIP5; NA otherwise (mice imputes it).
- **D-07 (standard):**
  - `age_at_anchor`, `sex` (factor) — source confirmed in Task 0;
  - `main_source` (factor) = modal SOURCE across the patient's post-anchor encounters in the pinned R/122 RDS;
  - `post_anchor_enc_count` = all post-anchor encounters in the pinned R/122 RDS, **any distance_status**;
  - `single_source_care_post` (factor) from the pinned R/169 RDS;
  - `payer` (factor) — source confirmed in Task 0;
  - `adi` — from the patient's modal post-anchor ZIP5 joined to `data/reference/zip5_adi_summary.csv` (column confirmed in Task 0).
- **D-07a:** Anchor date = `min(year_start)` per patient from the Phase 179 RDS (year 1 starts at the anchor); post-anchor = encounter date > anchor.
- **D-07b:** `payer` and `adi` are optional: if no usable source exists, or a variable is missing for all patients, drop it and record the reason in the KEY. Never drop silently. The outcome variables and the auxiliary are never optional.
- **D-07c:** `miss_reason` is **not** a predictor (it is constant, "none", for every observed patient). It is kept for reporting only.
- **D-08:** Variables with missing values other than the target (ADI, auxiliary, payer, …) are imputed in the same run with mice defaults (pmm numeric, logreg/polyreg factors).
- **D-08a:** All character/logical predictors are converted to factors before mice. Predictor matrix = mice default for the variables present (ID excluded, diagonal 0).

### Hard stops (script stops with an error)
- **D-09:**
  1. Any NA in the target (`log_dist` for D-01, `far` for D-02) in any completed dataset.
  2. `loggedEvents` shows `prop_cbc_years`, `n_years_observed` or `dist_to_source_facility_mi` removed.
  3. A GEE error in any imputed dataset (report branch, subset, dataset number).
  4. Task 0 reproduction failure (see D-16).
- **D-10 (produced, not blocking):** trace plots (chain mean/SD of the target per iteration), observed vs imputed distribution of `log_dist` and observed vs imputed far proportion, FMI per pooled estimate, number of patients imputed. Differences between observed and imputed values are expected under MAR and do not fail the run.

### Pooling
- **D-11:** Refit the Phase 179 GEE in each completed dataset using the `run_gee()` specification copied verbatim from R/179 (formula, year-category construction, `arrange(ID, year_index)`, integer cluster id, `droplevels`, `CONFIG$distance_gee_corstr`, robust `Std.err`). Do not re-derive the specification.
- **D-12:** Rubin's rules written out in code (cite Rubin 1987):
  `Q_bar = mean(Q)`, `U_bar = mean(SE^2)`, `B = var(Q)`, `T = U_bar + (1 + 1/m) B`,
  `r = (1 + 1/m) B / U_bar`, `df = (m - 1) (1 + 1/r)^2` (Inf if B = 0),
  CI = `Q_bar ± qt(0.975, df) * sqrt(T)`, `FMI = (r + 2/(df + 3)) / (r + 1)`; report on the OR scale.
- **D-12a:** Four pooled estimates: D-01 years 2+ (primary), D-02 years 2+, D-01 all years, D-02 all years.

### Comparison table (MICE-02)
- **D-13:** All reference values are read at run time by exact label from the pinned workbooks, reusing the exact-label readers and label constants already in R/180 (Phase 179 "Primary: years 2+") and R/182 (Phase 180 KEY rows for missing → far=1 and missing → far=0). One match required; otherwise stop and print the available labels. Include CIs where the source row has them. No numeric reference values in code.
- **D-13a:** Rows: complete-case years 2+ (Phase 179), complete-case all years (Phase 179, only if an exact label exists — confirmed in Task 0), Phase 180 missing → far=1, Phase 180 missing → far=0, and the four pooled MICE estimates (OR, 95% CI, FMI, df).
- **D-14:** Counts 1–10 shown as "<11"; percentages only when numerator and denominator are both ≥ 11. KEY leftmost; UF colours.

### Input pinning
- **D-15:** Pinned inputs, each overridable by env var; path and pinned TRUE/FALSE recorded in KEY; every file checked to exist at startup:
  - `R183_P179_RDS` (`output/internal/cbc_patient_year_20261015.rds`)
  - `R183_P179_XLSX` (`output/cbc_patient_year_20261015.xlsx`)
  - `R183_P180_XLSX` (`output/cbc_missing_capture_20261015.xlsx`)
  - `R183_R122_RDS` (`output/encounter_distance_20261015.rds`)
  - `R183_R169_RDS` (`output/internal/single_source_care_20261008.rds` — the file R/180 used; confirm location in Task 0)
  - `R183_ADI_CSV` (`data/reference/zip5_adi_summary.csv`)
  - Demographics/payer source as confirmed in Task 0 (pinned the same way if it is a file; if from DuckDB, read-only connection, recorded in KEY).

### Task 0 and the Plan 01 checkpoint
- **D-16:** Task 0 (read-only, local grep of the writing scripts) records the exact column names in the Phase 179 RDS, R/122 RDS, R/169 RDS, the ADI CSV and the demographics/payer source, plus the exact labels in the Phase 179 workbook and Phase 180 KEY, before any code is written. The script holds these names as constants and stops, printing the available names, if any is absent.
- **D-16a:** Plan 01 ends at the reproduction gate: a complete-case GEE on the pinned RDS must reproduce "Primary: years 2+" (OR and both CI bounds within 0.005). Plan 01 closes with a HiPerGator checkpoint that runs the script up to that gate and prints the predictor availability table; Plan 02 starts only after it passes.

### Privacy
- **D-17:** Patient-level inputs, both `mids` objects and completed datasets go only to `output/internal/`. No patient IDs or ZIPs in the workbook, memo, PNGs or `.planning/`. Counts 1–10 as "<11".

### Outputs and execution
- **D-18:** Workbook `output/mice_sensitivity_distance_<YYYYMMDD>.xlsx`, sheets KEY, MICE-01 (settings, methods, loggedEvents, FMI, imputed counts, observed vs imputed far proportion, PNG names), MICE-02 (comparison table). PNGs: `output/mice_trace_<YYYYMMDD>.png`, `output/mice_density_<YYYYMMDD>.png` (aggregate only).
- **D-19:** Memo written by the script to `output/183-MEMO_<YYYYMMDD>.md` (neutral language; for the record). Copied into the phase folder at close-out, not hand-edited.
- **D-20:** Script `R/183_mice_sensitivity_distance.R`; registered in R/39 (one-off section) and SCRIPT_INDEX. No R/88 section; R/88 is rerun at the checkpoint to confirm the 982-pass baseline holds.
- **D-21:** Interactive R on HiPerGator from the repo root (`module load R/4.5`; `source(f, local = new.env(parent = globalenv()))`). No SLURM, no Rscript. No R on the local machine: local checks are grep only.

### Claude's Discretion
- Workbook formatting following R/179–181 (same xlsx package as R/180).
- Base-R PNGs (no new plotting dependency).

</decisions>

<canonical_refs>
## Canonical References
- `R/179_cbc_patient_year.R` — `run_gee()` (copy verbatim), RDS schema, `sup()` / `show_rate()`
- `R/180_cbc_missing_capture.R` — exact-label reader for Phase 179 "Primary: years 2+"; DuckDB read-only pattern; xlsx pattern
- `R/182_facility_zip_recovery_report.R` — exact-label constants/readers for Phase 180 KEY rows
- `R/181_cbc_prior_year.R` — script-generated memo pattern
- `R/122_encounter_distance.R` — RDS columns (patient/facility ZIP5, SOURCE, encounter date, distance_status)
- `R/169_single_source_care.R` — `single_source_care_post`
- `R/utils/utils_address.R` — gazetteer loader and haversine helper (confirm names and units in Task 0)
- `data/reference/zcta_gazetteer_centroids.csv` (tab-delimited), `data/reference/zip5_adi_summary.csv`
</canonical_refs>

<specifics>
## Specific Ideas
- Reference values for orientation only (never in code): complete-case 0.834 (0.719–0.967); Phase 180 far=1 0.692 (0.614–0.781), far=0 0.871 (0.751–1.009).
- 614 patients missing exposure of 8,632; 58,595 patient-years.
</specifics>

<deferred>
## Deferred Ideas
None.
</deferred>

---
*Phase: 183-mice-sensitivity-for-distance — revised after plan review 2026-10-15*
