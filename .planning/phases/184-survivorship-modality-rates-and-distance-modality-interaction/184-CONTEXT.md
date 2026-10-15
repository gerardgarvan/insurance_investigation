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
- **D-04:** Working correlation = `independence` with robust SEs. Each patient contributes many
  rows across modalities and years; `exchangeable` fits this structure poorly.

### Data structure
- **D-05:** One row per patient × modality × follow-up year. Outcome = count of distinct modality
  dates within that year. Offset = `log(person_years)` for that year.
- **D-06:** Cohort = Phase 179 pinned RDS (`cbc_patient_year_20261015.rds`), complete-case on
  exposure (exclude the 614 missing-exposure patients). `far` taken from the Phase 179 RDS.
  Primary analysis: years 2+ (matches Phase 179 primary). Secondary: all years.
- **D-07:** Modality eligibility: restrict each modality to the patients for whom it applies,
  per R/147/Phase 158–159 definitions (e.g., echo restricted to post-anthracycline patients).
  Do not include ineligible patients in a modality's rate denominator.
- **D-08:** Reference modality = CBC (ties back to Phase 179 as the anchor outcome).
- **D-09:** `year_index_cat` is included in the model to control for follow-up time trends
  (same construction as Phase 179).

### Covariates
- **D-10 (primary model terms):** `far + modality + far:modality + year_index_cat`. No additional
  adjustment. Matches the Phase 179 unadjusted specification.
- **D-11 (adjusted sensitivity):** Add `age_at_anchor + sex` from the same sources used in R/183.
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
- **D-16:** Before the modality model runs, fit the CBC-only Poisson GEE on the pinned Phase 179
  cohort and confirm the "Primary: years 2+" OR (and 95% CI) from the pinned Phase 179 workbook
  matches within 0.005, read by exact label. Script stops with an error if this check fails.
  Also assert patient-year row count and far/near patient split match Phase 179 exactly.

### Suppression
- **D-17:** Counts 1–10 displayed as "<11". Rates shown only when both numerator and denominator
  are ≥ 11. Applied to the Rate_Table tab and the Rates tab in the workbook.

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
- **D-21:** Memo: `184-MEMO.md` (in the phase directory or output/)

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
- Phase 179 workbook (exact label "Primary: years 2+"): most recent `output/cbc_patient_year_*.xlsx`

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
