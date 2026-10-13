# Phase 179: CBC Within Each Follow-Up Year (Patient-Year Re-specification of Phase 165) — Context

**Gathered:** 2026-10-13
**Status:** Ready for planning
**Supersedes:** the encounter-level 179-CONTEXT (archived as 179-CONTEXT-superseded.md)

<domain>
## Phase Boundary

Build `R/179_cbc_patient_year.R`: a read-only, one-off analysis of whether patients who live far from
where they receive care (>100 mi) are less likely to have a CBC in each follow-up year after HL
diagnosis. This re-specifies the Phase 165 question at the patient-year level. Phase 165 itself is
not changed except for a relabel (D-14).

Missing-exposure bias and CBC capture checks are Phase 180, which consumes this phase's
patient-year RDS.
</domain>

<decisions>
## Implementation Decisions

### Unit and follow-up
- **D-01 Unit:** patient-year after `hl_anchor_date`. Year k = (anchor + 365·(k−1), anchor + 365·k],
  half-open, anchor day = pre (same convention as Phases 165/166/167). Keep `year_index` (k).
- **D-02 Anchor source:** R/147 anchor RDS (D-167-04 pattern), not Phase 165 output.
- **D-03 Universe:** every cohort patient with a known `hl_anchor_date`, including patient-years
  with **no in-system encounters**. Do not restrict to patients or years with encounters — years
  without contact are where out-of-system care would show up.
- **D-04 Fully observed years only:** a patient-year counts only if its end date ≤ the CDM data
  cutoff and the patient was alive at its end (DEATH table if present; record the source). Do
  **not** define follow-up from last in-system contact (that conditions on capture). Partial final
  years are excluded. Record the cutoff date and source in KEY.

### Outcome
- **D-05 Primary:** `cbc_year = 1` if ≥1 CBC event from `build_cbc_events()` (LOINCs 6690-2,
  718-7, 777-3 all on the same date; date = coalesce(RESULT_DATE, SPECIMEN_DATE, LAB_ORDER_DATE))
  falls in the year interval. Call the function as-is; do not redefine.
- **D-06 Sensitivity (broad hematology):** ≥1 result in the year for any LOINC in
  {6690-2, 718-7, 777-3, 4544-3, 789-8, 787-2, 785-6, 786-4, 788-0, 770-8, 26499-4, 731-0,
  58410-2, 57021-8, 57782-5} (no same-date requirement). Same date priority. SQL push-down like
  `build_cbc_events()`.

### Exposure
- **D-07 Primary:** patient-level **median** of `distance_mi` over the patient's post-anchor
  encounters (`ADMIT_DATE > hl_anchor_date`) with `distance_status == "computed"` in the R/122
  `enc_distance` RDS (the same file Phase 165 used). One value per patient, applied to all of that
  patient's patient-years. `far = median > CONFIG$far_from_care_cutoff_mi` (100).
- **D-08 Missing exposure:** patients with no computed-distance post-anchor encounter have missing
  exposure; excluded from Phase 179 estimates, counted in KEY, and carried in the RDS with
  `exposure_missing = TRUE` for Phase 180.
- **D-09 Sensitivity (per-year median):** median over that year's computed-distance encounters;
  years with none are excluded from this sensitivity only. Report the number of patient-years and
  patients dropped.
- **D-10 Descriptives:** distribution of the patient median (quantiles), and n patients far / not far.

### Analysis
- **D-11 Model:** GEE logistic (`geepack::geeglm`, family binomial, `id = ID`,
  `corstr = CONFIG$distance_gee_corstr`), `cbc_year ~ far + year_index_cat`, with year index
  categorical, capped at "5+". OR for `far` with robust 95% CI.
- **D-12 Year 1:** year 1 overlaps primary treatment (CBCs near-universal). **Primary estimate =
  years 2+** (survivorship surveillance). Secondary = all years. Year 1 reported on its own as a
  descriptive 2×2.
- **D-13 Descriptives per year index:** patient-years, CBC rate far vs not far, crude OR, all
  suppressed per D-16. If the GEE fails to converge, report crude pooled OR and the warning; do
  not switch method silently.

### Phase 165 relabel
- **D-14:** In R/165's KEY builder, label the analysis as **encounter-level ("CBC drawn during the
  encounter")** and add a row pointing to Phase 179 as the patient-year analysis. Lands on the next
  R/165 run; do not edit existing workbooks by hand.

### Team item
- **D-15:** Which analysis is primary — Phase 165 (encounter-level) or Phase 179 (patient-year) — is
  for Amy/Erin, together with D-165-01. Record in STATE; this phase reports both side by side in
  KEY (Phase 165 numbers cited from `output/distance_cbc_association_20261008.xlsx`).

### Outputs and execution
- **D-16:** Workbook `output/cbc_patient_year_<YYYYMMDD>.xlsx`: KEY leftmost (inputs and
  whether pinned, cutoff date, death source, exposure definition, primary/secondary/sensitivity
  ORs, D-15 note), then descriptives, per-year table, model results. Counts 1–10 → "<11"
  (`suppress_small_vec` / project helper; percentages shown only when numerator and denominator
  are both ≥11). UF colors.
- **D-17:** `output/internal/cbc_patient_year_<YYYYMMDD>.rds`: one row per patient-year with ID,
  year_index, interval dates, cbc_year, cbc_year_broad, median_distance, far, far_year_median,
  exposure_missing, triage (R/121, NA → "not in R/121"). Phase 180 reads this.
- **D-18:** Interactive R on HiPerGator from the repo root: `module load R/4.5`;
  `source("R/179_cbc_patient_year.R", local = new.env(parent = globalenv()))`. No SLURM, no Rscript.
  Local checks are grep only.
- **D-19:** Register in R/39 (one-off) and SCRIPT_INDEX. No R/88 section.

### Claude's Discretion
- Sheet names and column order.
- How to obtain the CDM data cutoff (CONFIG constant vs max date in a CDM table) — choose the
  documented project source, record it in KEY.
</decisions>

<canonical_refs>
- `R/utils/utils_distance_cbc.R` — `build_cbc_events()`; GEE conventions from Phase 165
- `R/165_distance_cbc_association.R` — R/122 RDS used, CONFIG usage, KEY builder (D-14)
- `R/122_encounter_distance.R` — `enc_distance` schema, `distance_status`
- R/147 anchor RDS — `hl_anchor_date`
- `R/121_zip_problem_inventory.R` RDS — `triage` (via the R/177 loading pattern)
- `R/166_survivorship_modality_rates.R` — half-open year interval convention
- `R/00_config.R` — `far_from_care_cutoff_mi`, `distance_gee_corstr`, date bounds
- `.planning/phases/165-*/165-CONTEXT.md` — D-165-01 and window conventions
</canonical_refs>

<deferred>
- Missing-exposure bias check and CBC capture check → Phase 180.
- Primary-analysis choice (165 vs 179) → Amy/Erin with D-165-01.
</deferred>
