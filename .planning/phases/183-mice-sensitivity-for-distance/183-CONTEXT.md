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
  - Complete-case OR — **read from the pinned Phase 179 workbook**, label `"Primary: years 2+"`. Stop with a clear error if the label is not found (same pattern as R/180–182). Do **not** hard-code numeric values.
  - Phase 180 lower bound — **read from the pinned Phase 180 workbook**, MISS-02 sheet, label for "all far" bound. Stop if label not found.
  - Phase 180 upper bound — **read from the pinned Phase 180 workbook**, MISS-03 sheet, label for "all not-far" bound. Stop if label not found.
  - Pooled MICE OR — primary (log-dist PMM, years 2+)
  - Pooled MICE OR — primary sensitivity (far logreg, years 2+)
  - Pooled MICE OR — all years (log-dist PMM)
- **D-14:** Counts 1–10 → `"<11"`. Percentages only when both counts ≥ 11. UF color palette.

### Input Pinning and Env Vars
- **D-15:** Four pinned inputs, each overridable via environment variable (default paths in parentheses):
  - `R183_P179_RDS` (default: `output/internal/cbc_patient_year_20261015.rds`) — Phase 179 patient-year RDS
  - `R183_P179_XLSX` (default: `output/cbc_patient_year_20261015.xlsx`) — Phase 179 workbook (source of complete-case OR)
  - `R183_P180_XLSX` (default: `output/cbc_missing_capture_20261015.xlsx`) — Phase 180 workbook (source of bounding ORs)
  - `R183_R122_RDS` (default: `output/encounter_distance_20261015.rds`) — R/122 encounter distance RDS (for encounter counts and modal facility ZIP)
  - All four paths are checked with `assert_file_exists()` at script startup. Whether each was the default or overridden via env var is recorded in the KEY sheet.

### Task 0 — Pre-Imputation Verification (Read-Only)
- **D-16:** Plan task 0 is a read-only confirmation step that must pass before any imputation runs:
  1. Read the pinned Phase 179 RDS; confirm column names for patient median distance, `far`, `SOURCE`, payer, ADI, and `single_source_care` are present (exact names to be confirmed against the actual RDS at run time).
  2. Fit a complete-case GEE on the pinned RDS using the exact Phase 179 primary specification (years 2+). Confirm the resulting OR reproduces `"Primary: years 2+"` from the Phase 179 workbook (within rounding). Stop with an explicit error message if it does not. Only proceed to imputation after task 0 passes.

### Privacy
- **D-17:** Patient-level imputed datasets (all m completed datasets) are written **only** to `output/internal/`. They are never written to `output/`, the workbook, the memo, or any `.planning/` file.
- No patient IDs or patient ZIPs appear in the workbook, memo, or any `.planning/` artifact. All counts 1–10 are shown as `"<11"` per the established suppression rule.

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
- **No hard-coded reference numbers:** complete-case OR and Phase 180 bounds are read at runtime from the pinned workbooks by exact label match (D-13). The 20261015 run values (0.834, 0.692, 0.871) are for human orientation only and must not appear in script code.
- **Rubin's rules by hand:** cited to Rubin (1987). No mice::pool() wrapper — geeglm is not supported.
- **Outcome in imputation model:** `prop_cbc_years` and `n_years_observed` are computed using the **same fully observed years as the Phase 179 GEE** (years 2+ for primary; all years for secondary). They must not include imputed rows. Including them is mandatory to avoid attenuation of the pooled OR toward 1 — this is the key methodological point the ROADMAP candidate list omits.
- **ADI imputed jointly:** rather than dropped when patient ZIP is unknown (group a).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 183-mice-sensitivity-for-distance*
*Context gathered: 2026-10-15*
