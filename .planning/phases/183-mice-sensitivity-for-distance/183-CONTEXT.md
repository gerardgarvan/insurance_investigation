# Phase 183: MICE Sensitivity for Distance - Context

**Gathered:** 2026-10-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Run multiple imputation (mice, m ≥ 20) on the ~614 remaining missing-exposure patients after Phase 182/182.1 ZIP recovery, refit the Phase 179 primary GEE specification in each imputed dataset, pool estimates via manually implemented Rubin's rules, and produce a workbook + short script-generated memo comparing pooled OR to complete-case OR and Phase 180 bounding ORs. Imputation is performed at the **patient level** (not patient-year), since the 614 patients are missing their single median post-anchor distance value for every year.

</domain>

<decisions>
## Implementation Decisions

### Imputation Target
- **D-01 (primary):** Impute `log(median_distance)` using predictive mean matching (PMM). After imputation, derive `far = (exp(imputed_log_dist) > CONFIG$far_from_care_cutoff_mi)`. Logged distance is less skewed; PMM only draws from actually observed values, which is appropriate for a bounded, right-skewed variable.
- **D-02 (sensitivity):** Also run a parallel imputation of `far` directly using logistic regression (`method = "logreg"`). If pooled ORs from D-01 and D-02 agree, that is reported as reassurance in the memo.
- **D-03:** Imputation is at the **patient level** (one row per patient), not patient-year. The 614 missing patients are missing for all years, so patient-year–level imputation would allow far to flip between years for the same patient — statistically incoherent.

### MICE Settings
- **D-04:** `m = 20`, `maxit = 20`, fixed seed (record in KEY). With ~7% missing patients, m = 20 is sufficient.

### Predictor Set
The imputation model must include the **outcome summary** (to avoid biasing the pooled OR toward 1) and the strongest **auxiliary variable**.

- **D-05 (outcome in imputation model — mandatory):** Include in the predictor matrix:
  - `prop_cbc_years` — proportion of observed years with a CBC (patient-level summary of outcome)
  - `n_years_observed` — number of observed follow-up years
- **D-06 (strongest auxiliary):** For patients in triage group (b) (patient ZIP known, only facility ZIP missing — ~416 patients), compute `dist_to_modal_facility`: haversine distance from the patient's ZIP centroid to the modal facility ZIP of the patient's main SOURCE. This is computable without new data from R/122 and the gazetteer. Include as a predictor (NA for groups where patient ZIP is also missing).
- **D-07 (standard predictors):** age at anchor, sex, payer, ADI, SOURCE (HL_SOURCE), single_source_care_post, post-anchor encounter count, `miss_reason` (factor encoding the Phase 180 D-02 reason groups a–f).
- **D-08 (ADI missing):** ADI will be missing for most group (a) patients (patient ZIP unknown). Let MICE impute ADI alongside distance rather than dropping it. ADI is included in the predictor matrix as a variable with its own imputation column.

### Hard-Stop Convergence Criteria
- **D-09:** The script **stops with an error** (non-zero exit) if:
  1. Any `NA` remains in `far` or `log_dist` after imputation in any of the m datasets.
  2. `loggedEvents` from mice includes the outcome summary (`prop_cbc_years`) or the main auxiliary variable (`dist_to_modal_facility`) being dropped from any predictor column.
  3. Pooling fails (e.g., all GEEs fail to converge in a single imputed dataset — stop and report which).
- **D-10 (produced but not blocking):** Trace plots (mean and SD per iteration for each imputed variable), density overlays (observed vs imputed `log_dist`; observed vs imputed `far` proportion), and the fraction of missing information (FMI) for the `far` coefficient. These go in the MICE-01 diagnostics sheet. Differences between observed and imputed distributions are expected under MAR and do not themselves fail the run.

### Rubin's Rules Pooling
- **D-11:** `mice::pool()` does not support `geeglm`. Implement Rubin's rules in code:
  - Fit Phase 179 primary GEE (`cbc_year ~ far + year_index_cat`, `id = ID`, `corstr = CONFIG$distance_gee_corstr`, `family = binomial("logit")`) on each of the m imputed datasets.
  - Use the **robust** standard error from `geeglm` (sandwich SE) for each fit.
  - Pool: `Q_bar = mean(Q_i)`, `U_bar = mean(Var_i)`, `B = var(Q_i)`, `T = U_bar + (1 + 1/m)*B`.
  - Report pooled log-OR, 95% CI = Q_bar ± 1.96 * sqrt(T), back-transformed to OR scale.
  - Do this for: primary (D-01, log-dist imputed), sensitivity (D-02, far imputed directly), and for years 2+ (primary analytic set) and all years (secondary) — matching the Phase 179 structure.
- **D-12:** Write the Rubin's rules computation out explicitly in R code (not a wrapper). Include an inline comment citing Rubin (1987) for auditability.

### Comparison Table
- **D-13:** MICE-02 sheet contains the comparison table with rows:
  - Complete-case OR: 0.834 (95% CI 0.719–0.967) — **pinned from Phase 179 20261015 RDS run**
  - Phase 180 lower bound (all far): 0.692
  - Phase 180 upper bound (all not-far): 0.871 (95% CI 0.751–1.009)
  - Pooled MICE OR — primary (log-dist PMM, years 2+)
  - Pooled MICE OR — primary sensitivity (far logreg, years 2+)
  - Pooled MICE OR — all years (log-dist PMM)
- **D-14:** Counts 1–10 → `"<11"`. Percentages only when both counts ≥ 11. UF color palette.

### Input Pinning
- **D-15:** Phase 179 RDS pinned to the `20261015` dated file (the post-182.1 re-run). Record exact filename in KEY. Script stops if file is absent (use `assert_file_exists()` from checkmate, consistent with pipeline conventions).

### Outputs and Execution
- **D-16:** Workbook: `output/mice_sensitivity_distance_<YYYYMMDD>.xlsx`
  - Sheet order: KEY (leftmost), MICE-01 (diagnostics: settings, loggedEvents, trace plots embedded, density overlays), MICE-02 (pooled results + comparison table)
  - KEY records: input file names + dates, m, maxit, seed, predictor list, target variable, D-01 branch vs D-02 branch, hard-stop outcome (pass/fail each D-09 criterion)
- **D-17:** Short memo generated by the script: `.planning/phases/183-mice-sensitivity-for-distance/183-MEMO.md`. For the record — not being sent to team. Summarizes the sensitivity conclusion (pooled OR similar to / differs from complete-case OR) in neutral language.
- **D-18:** Script name: `R/183_mice_sensitivity_distance.R`. Register in `R/39` (one-off section) and `SCRIPT_INDEX`. No R/88 section unless team requests.
- **D-19:** Interactive R on HiPerGator from repo root: `module load R/4.5`; `source("R/183_mice_sensitivity_distance.R", local = new.env(parent = globalenv()))`. No SLURM.

### Claude's Discretion
- Exact column widths, freeze panes, and minor workbook formatting — follow Phase 179/180/181 precedent.
- Choice of `predictorMatrix` structure in mice (whether to zero out outcome-on-outcome entries) — follow standard mice guidance.
- Whether to embed trace plots as PNG in the xlsx or write them to `output/` as separate files — follow whichever approach is consistent with the existing pipeline output convention.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 179 — Primary GEE (the model being re-fitted)
- `R/179_cbc_patient_year.R` — GEE specification (`cbc_year ~ far + year_index_cat`, corstr, years 2+ primary), RDS schema, `far` derivation, `exposure_missing` flag, `triage` column
- `.planning/phases/` (infer path) — Phase 179 CONTEXT for GEE spec details

### Phase 180 — Bounding ORs (comparison table inputs)
- `.planning/phases/180-cbc-per-patient-year/180-CONTEXT.md` — D-04 (bounding spec), D-05 (branch decision), bounding OR values
- `R/180_cbc_missing_capture.R` — MISS-02/03 sheet structure, bounding logic

### Phase 182 / 182.1 — Updated exposure RDS (primary input)
- `.planning/phases/182.1-zip-centroid-mapping-for-unique-po-box-and-placeholder-zips/182.1-CONTEXT.md` — D-09 (new dated RDS), D-08 (distance_method column), D-07a (distance_status after fallback)
- `R/122_encounter_distance.R` — encounter-level distance columns, `zip_not_in_db` status, modal facility ZIP derivable here

### Gazetteer (for dist_to_modal_facility auxiliary)
- `data/reference/zcta_gazetteer_centroids.csv` — tab-delimited; columns GEOID, INTPTLAT, INTPTLONG
- `R/utils/utils_address.R` — `.load_zcta_gazetteer()`, `haversine_distance_mi()` already implemented

### Phase 181 — Memo format reference
- `.planning/phases/181-cbc-prior-year-vs-distance/181-CONTEXT.md` — D-13/D-14 (memo structure for script-generated markdown)

### Phase 169 — single_source_care_post
- `R/169_single_source_care.R` RDS — `single_source_care_post` column (for predictor D-07)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/utils/utils_address.R`: `.load_zcta_gazetteer()`, `haversine_distance_mi()` — use directly for `dist_to_modal_facility` auxiliary variable
- `R/179_cbc_patient_year.R`: GEE fitting function (sections 5+) — copy the exact `geepack::geeglm()` call signature; do not alter the spec
- `R/180_cbc_missing_capture.R`: suppression helper, UF color palette, xlsx write pattern — reuse
- `R/181_cbc_prior_year.R`: script-generated memo pattern — follow for 183-MEMO.md

### Established Patterns
- `assert_file_exists()` (checkmate) before reading any pinned RDS — required by Phase 72 quality standards
- `source(…, local = new.env(parent = globalenv()))` execution pattern — all v3.9+ phases
- Dated output files (`output/xxx_<YYYYMMDD>.xlsx`) — consistent with 179/180/181

### Integration Points
- Reads Phase 179 dated RDS (`exposure_missing`, `far`, `triage`, `year_index`, `cbc_year`, `ID`)
- Reads R/169 RDS for `single_source_care_post`
- Reads R/122 RDS for encounter counts and modal facility ZIP (for auxiliary variable)
- Reads `data/reference/zcta_gazetteer_centroids.csv` for haversine auxiliary

</code_context>

<specifics>
## Specific Ideas

- **"Imputing patient-year would let one patient be near in one year and far in the next — statistically incoherent."** Patient-level imputation is the correct grain because the 614 missing patients lack a median post-anchor distance entirely.
- **Logged distance:** "PMM only uses values that actually occur in the observed data" — this is the key justification for PMM on log scale over normal-model imputation.
- **Complete-case reference numbers pinned:** OR = 0.834 (0.719–0.967), Phase 180 far-bound = 0.692, not-far-bound = 0.871 (0.751–1.009). These are the 20261015 run values.
- **Rubin's rules by hand:** cited to Rubin (1987). No mice::pool() wrapper — geeglm is not supported.
- **Outcome in imputation model:** including `prop_cbc_years` and `n_years_observed` is mandatory to avoid attenuation of the pooled OR toward 1. This is the key methodological point the ROADMAP candidate list omits.
- **ADI imputed jointly:** rather than dropped when patient ZIP is unknown (group a).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 183-mice-sensitivity-for-distance*
*Context gathered: 2026-10-15*
