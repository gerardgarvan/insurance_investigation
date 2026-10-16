# Phase 184: Survivorship Modality Rates and Distance × Modality Interaction - Context

**Gathered:** 2026-10-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Build `R/184_modality_rate_model.R`: produce per-modality surveillance rate tables (MODR-01) and
fit a count model with a `far × modality` interaction term (MODR-02). Reuses R/147/R/166
definitions and person-time; no re-derivation of the surveillance codeset or modality definitions.
Annual primary period; 6-month as sensitivity.

</domain>

<decisions>
## Implementation Decisions

### Distribution and primary model family
- **D-01:** Primary model = Poisson GEE with robust (sandwich) standard errors, clustered by
  patient ID. Robust SEs account for overdispersion without changing the model; this matches the
  Phase 179 approach and is decided in advance.
- **D-02:** Overdispersion is reported as a diagnostic only (Pearson χ²/df per modality), not used
  as a model-selection decision rule.
- **D-03:** Sensitivity = negative-binomial GEE (MASS::glm.nb or geepack equivalent). Results
  reported alongside primary in the Diagnostics tab.

### Working correlation structure
- **D-04:** Working correlation = `independence` with robust SEs, held in its own constant
  `MODR_CORSTR <- "independence"`. Do NOT use `CONFIG$distance_gee_corstr` (that is
  "exchangeable", the Phase 179 setting, used only in the reproduction gate).

### Data structure
- **D-05:** One row per patient × modality × follow-up year. Outcome = count of distinct modality
  dates within that year. Offset = `log(person_years)`.
- **D-05a:** Year window = Phase 179 convention: an event belongs to year k when
  `year_start < event_date <= year_end`.
- **D-05b:** The Phase 179 RDS has no person-time column. `person_years = as.numeric(year_end - year_start) / 365`
  (expected 1 for every row, since Phase 179 keeps only fully observed years); assert and report.
- **D-05c:** `far` is integer 0/1 in the Phase 179 RDS: the coefficient is `far`, interaction terms
  `far:modality<level>`. No `farTRUE` names.
- **D-06:** Cohort = Phase 179 pinned RDS (`cbc_patient_year_20261015.rds`), complete-case on
  exposure (exclude the 614 missing-exposure patients). `far` taken from the Phase 179 RDS.
  Primary analysis: years 2+ (matches Phase 179 primary). Secondary: all years.
- **D-07 (primary):** Eligibility = sex restriction only. Mammogram and Breast MRI →
  DEMOGRAPHIC.SEX = "F" only (data/reference/README.md line 285; R/147 line 83). All other
  modalities eligible for every complete-case patient. R/166 `survivorship_modality_rates_long`
  contains only patients who had a recorded event (not a denominator frame) and cannot be used
  as the expected eligible N; no R184_R166_XLSX comparison is made.
- **D-07a (sensitivity, Plan 02):** Echocardiogram and MUGA additionally restricted to
  anthracycline-exposed patients, defined exactly as the `echo_post_anthracycline` population
  in R/166 Plan 03 (R/167_anthracycline_echo.R; cite file:line; pin required input). Modality
  RRs for this restricted set reported alongside the primary results.
- **D-08:** Reference modality = "CBC (Phase 165 definition)". R/147 "Complete blood count"
  events are excluded — they disagreed with Phase 179 cbc_year (5,919 patient-years with
  cbc_year=1 had no R/166 CBC event; 3,959 in patients with no R/166 CBC events at all;
  median gap to nearest R/166 CBC event 539 days). Phase 165 events (build_cbc_events:
  WBC 6690-2 + Hgb 718-7 + PLT 777-3 same date, R/utils/utils_distance_cbc.R line 108)
  replace the R/166 CBC rows and must reproduce Phase 179 cbc_year exactly (D-16a).
- **D-16a:** CBC CHECK now compares Phase 165 CBC events (not R/166 "Complete blood count")
  with Phase 179 cbc_year. Should agree exactly; stop with 2×2 (sup()) if not.
- **D-29:** Model sample restricted to patient-years with year_end ≤ EXTRACT_DATE ("2025-09-15",
  R/00_config.R line 85) so all modalities are compared over the same coverage window. R/166
  event dates stop at 2025-03-29 (observed max), but the coverage boundary is defined from
  EXTRACT_DATE, not the observed max. Gate and D-16a CBC CHECK use the full Phase 179 years.
- **D-09:** `year_index_cat` built exactly as R/179 (years 1–4 and "5+"), copied verbatim.

### Covariates
- **D-10 (primary model terms):** `far + modality + far:modality + year_index_cat`. No additional
  adjustment. Matches the Phase 179 unadjusted specification.
- **D-11 (adjusted sensitivity):** Add `age_at_anchor + sex` from the same sources used in R/183
  (DuckDB DEMOGRAPHIC, read-only; anchor = min(year_start)). Sex factor built after the cohort join,
  categories < 11 patients merged into "Other/Unknown", `droplevels()`.
- **D-12:** `payer` excluded — no usable source was found in Phase 183; do not attempt to add it
  here.
- **D-13:** Variables that sit on the causal pathway between distance and testing (encounter counts,
  `single_source_care_post`) are excluded; including them would absorb the distance effect.

### Estimands
- **D-14 (primary):** Modality-specific rate ratio (far vs not-far) within each modality, read
  from the `far:modality` interaction terms on the exponentiated scale.
- **D-15 (global test):** Joint Wald test of all `far:modality` interaction terms, to show whether
  the distance effect differs across modalities.

### Reproduction gate (hard stop)
- **D-16:** Before the modality model runs, refit the Phase 179 model itself (logistic GEE on
  `cbc_year`, `run_gee()` copied verbatim from R/179, `CONFIG$distance_gee_corstr`) on the pinned
  Phase 179 RDS, years 2+, complete case. OR and both CI bounds must match the pinned Phase 179
  workbook "Primary: years 2+" (exact-label reader copied from R/183) within 0.005. Patient-year count
  and far/near patient counts printed and recorded (they define the cohort, no tolerance).
- **D-16a (long-frame check):** In the long frame, for CBC rows, `as.integer(count > 0)` must equal
  Phase 179 `cbc_year` for every patient-year. If not, stop and report the agreement table — it means
  the R/147/R/166 CBC event definition differs from the Phase 165/179 definition, which must be
  resolved before modelling.
- **D-16b:** Patient-years in the long CBC rows must equal the Phase 179 complete-case patient-years
  exactly (CBC applies to every patient).

### Suppression
- **D-17:** Counts 1–10 displayed as "<11" — events, eligible patients and person-years alike.
  Rates shown only when numerator and denominator are both ≥ 11. Applied to every count shown
  (Rates, QC, memo).

### Workbook structure
- **D-18:** Single workbook, UF colours, KEY leftmost. Tabs in order:
  1. **KEY** — run-date, cohort pin, model spec (formula, family, corstr, offset), suppression
     policy, modality eligibility notes.
  2. **Rates** — events, patient-years, and rate per patient-year, by modality × far × year-period
     (annual primary + 6-month sensitivity), with suppression applied.
  3. **Model_Results** — modality-specific RR (or OR) with 95% CI for far vs not-far.
  4. **Interaction** — joint Wald test stat and p-value, plus individual interaction term
     estimates (log-scale and exponentiated).
  5. **Diagnostics** — Pearson χ²/df per modality (Poisson primary), NB GEE comparison
     (key estimates alongside Poisson).
  6. **QC** — reproduction gate results (CBC model vs Phase 179 label), N eligible per
     modality, suppression audit (flag modalities where >50% of cells are suppressed).
- **D-19:** Script-generated memo `184-MEMO.md` analogous to Phases 181 and 183, summarising
  key findings, cohort pin, and model spec.

### Output file names
- **D-20:** Workbook: `output/modality_rate_model_<YYYYMMDD>.xlsx`
- **D-21:** Memo: `output/184-MEMO_<YYYYMMDD>.md`, copied unchanged to the phase folder at close-out.

### Sensitivity details
- **D-23 (6-month):** Each follow-up year is split into two half-years,
  `(year_start, year_start + 182.5]` and `(year_start + 182.5, year_end]`, each 0.5 person-years;
  events counted per half; same model with a half-year period factor. (Not a truncation to the first
  half of each year.)
- **D-24 (NB):** The same joint formula fitted with `MASS::glm.nb`, with cluster-robust SEs by
  patient (`sandwich::vcovCL(fit, cluster = ~ID)`). Modality-specific RRs and the joint Wald test
  computed from that covariance. If `sandwich` is not in renv, install + `renv::snapshot()` at the
  checkpoint.

### Pinning and names
- **D-25:** Pinned inputs (env override; path + pinned TRUE/FALSE in KEY; exist-check at start):
  `R184_P179_RDS` (output/internal/cbc_patient_year_20261015.rds),
  `R184_P179_XLSX` (output/cbc_patient_year_20261015.xlsx),
  `R184_EVENTS_RDS` (R/166 or R/147 dated modality events — path confirmed in Task 0),
  `R184_ELIG_RDS` (modality eligibility source — confirmed in Task 0),
  R/147 pointer file recorded as read.
- **D-26:** Task 0 (read-only, local grep of the writing scripts) records exact column names,
  modality labels (incl. the CBC label), eligibility flag, CBC event definition used by R/147/R/166,
  and the Phase 179 workbook sheet/label column, before code is written. Held as constants; missing
  names stop the run with the available names printed.

### Execution
- **D-27:** Interactive R on HiPerGator (`module load R/4.5`; `source(f, local = new.env(parent = globalenv()))`).
  No SLURM, no Rscript; local checks are grep only. UF colours #0021A5 / #FA4616.
- **D-28:** Two plans. 01 = Task 0, pins, gate, long frame, checkpoint. 02 = rates, models,
  workbook, memo, registration (R/39, SCRIPT_INDEX), R/88 rerun, close-out.

### Script number
- **D-22:** `R/184_modality_rate_model.R` (next available sequential number; depends on R/147,
  R/166, and the Phase 179 pinned RDS).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Roadmap and requirements
- `.planning/ROADMAP.md` §Phase 184 — goal, design constraints, success criteria, dependency on Phase 181
- `.planning/REQUIREMENTS.md` §MODR-01, MODR-02 — acceptance criteria

### Prior phase contexts (locked decisions)
- `.planning/phases/180-cbc-per-patient-year/180-CONTEXT.md` — missing-exposure bounding approach
- `.planning/phases/183-mice-sensitivity-for-distance/183-CONTEXT.md` — D-11 (Rubin pool), D-14 (comparison table pattern), predictor sources (age, sex)

### Key scripts to reuse patterns from
- `R/147_surveillance_modality_frequency.R` — modality definitions and eligibility; codeset
- `R/166_survivorship_modality_rates.R` — person-time derivation (`compute_modality_rates()`), R/147 pin pointer
- `R/179_cbc_patient_year.R` — GEE spec, `year_index_cat` construction, `arrange(ID, year_index)`, robust SE pattern, exact-label reader
- `R/183_mice_sensitivity_distance.R` — memo generation pattern, workbook structure, exact-label reader

### Configuration
- `R/00_config.R` — `CONFIG$far_from_care_cutoff_mi`, `CONFIG$distance_gee_corstr`, UF colour palette

### Pinned data
- Phase 179 RDS: `output/internal/cbc_patient_year_20261015.rds` (cohort pin; env-var override `R184_P179_RDS`)
- Phase 179 workbook (exact label "Primary: years 2+"): pinned `output/cbc_patient_year_20261015.xlsx` (`R184_P179_XLSX`)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `compute_modality_rates()` in `R/utils/utils_surveillance_rates.R` (auto-sourced via R/00_config.R) — already computes per-patient modality rates; Phase 184 extends this to patient-year grain
- `R/166_survivorship_modality_rates.R` §SECTION 1 — R/147 pin pointer and loading pattern (reuse verbatim)
- `R/179_cbc_patient_year.R` — `run_gee()` helper, exact-label workbook reader, `year_index_cat` factor construction; copy these patterns into R/184
- `R/183_mice_sensitivity_distance.R` — memo generation (`writeLines` to `184-MEMO.md`), KEY builder pattern

### Established Patterns
- Exact-label reader: read Phase 179 workbook by label string, stop if label not found (see R/180, R/183)
- Robust GEE via `geepack::geeglm()` with `std.err = "san.se"`, `id = as.integer(ID)`, `data = arrange(data, ID, year_index)`
- Pearson χ²/df: `sum(residuals(fit, "pearson")^2) / fit$df.residual`
- NB sensitivity: `MASS::glm.nb()` (patient-level) or `geeNB` equivalent if available
- UF colour palette and KEY-leftmost workbook construction: `openxlsx` with `addStyle`

### Integration Points
- Reads Phase 179 pinned RDS (patient-year with `far`, `cbc_year`, `year_index`, person-time)
- Reads R/147 pin pointer at `output/logs/147_verify_last_pass.txt` to get modality eligibility RDS
- Writes to `output/` (workbook) and phase dir (memo)

</code_context>

<specifics>
## Specific Ideas

- The model structure is a long-format Poisson GEE with an offset, one row per patient × modality × year. This is the count-data analogue of the Phase 179 binary GEE.
- The CBC reproduction gate (D-16) is the Phase 179 / Phase 183 "Task 0" pattern adapted for a count outcome: confirm row counts and far/near split exactly; confirm OR within 0.005.
- Modality eligibility restrictions (D-07) are important to get right — diluting denominator with ineligible patients produces misleading rates for modalities like echo.
- The global Wald test (D-15) gives the team a single headline result ("does distance matter differently across modalities?") before presenting modality-specific RRs.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 184-survivorship-modality-rates-and-distance-modality-interaction*
*Context gathered: 2026-10-15*
