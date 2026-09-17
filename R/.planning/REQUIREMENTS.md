# Requirements: v3.5 Encounter Distance (AM §4)

**Defined:** 2026-09-17
**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.
**Source:** `MILESTONE_encounter_distance.md` (AM §4 Distance domain spec, dated 2026-09-17)

## Milestone Goal

Implement the Analytic Manual §4 cleaning rules for patient-to-encounter distance exactly as written, resolve both Unresolved Issues (binary cutoff, histogram), and write results back into AM §4 so the domain is no longer blank or provisional. Exit criterion: a re-issued `encounter_distance_<date>.xlsx` from a real HiPerGator run, a histogram figure, a cutoff decision memo, and an updated AM §4 block — all reconciled to a single set of logged decisions in AM §3.

## v3.5 Requirements

### Distance Computation (DIST)

- [ ] **DIST-01**: Distance between patient ZIP5 and encounter facility ZIP5 is computed via `zipcodeR::zip_distance()`, reporting miles as primary with a km column alongside
- [ ] **DIST-02**: Any ZIP9 on the patient or facility side is reduced to ZIP5 before distance is computed
- [ ] **DIST-03**: An encounter with no patient ZIP (5 or 9 in address history) receives the temporally closest ZIP from the same patient's address history — nearest to the encounter date, either direction, tie → earlier address (D-03 resolved 2026-09-17); provenance recorded in `zip5_patient_source` ∈ {in_range_zip9, in_range_zip5, nearest_zip9, nearest_zip5} with a signed `days_offset` column
- [ ] **DIST-04**: Histogram of distance delivered in UF colors (encounter-level and patient-level, linear and log scale; 4 PNGs), plus a summary distribution table (n, mean, SD, median, IQR, p90, p95, p99, max — overall and stratified) and a `B_histogram_bins` sheet so figure and workbook cannot drift
- [ ] **DIST-05**: Binary `far_from_care` indicator implemented behind `CONFIG$distance_cutoff_mi` (default `NA` — indicator not emitted until set), accompanied by a data-driven cutoff recommendation memo (`docs/distance_cutoff_memo.md`) presenting distribution-based, literature-based, and sensitivity candidates for Amy/Erin to decide
- [ ] **DIST-06**: Every ambiguity resolved in this milestone is logged as a row in AM §3 (Variable and Phenotype Decision Log, D-01..D-06), and the AM §4 Distance block (Expected Structure, Observed Issues, Cleaning Rules, Unresolved Issues) is rewritten to match the code
- [ ] **DIST-07**: `R/122_encounter_distance.R` and `R/utils/utils_zip_calendar.R` are registered in `R/39_run_all_investigations.R`, `R/88_smoke_test_comprehensive.R`, and `R/SCRIPT_INDEX.md`; unit tests live under `tests/testthat/test-utils-zip-calendar.R`

## Future Requirements

- Drive-time or road-network distance (would need an external routing source — note as a possible follow-on in the cutoff memo)
- Facility ZIP imputation (D-04: missing facility ZIP is counted and reported under Observed Issues, not filled)
- Wiring `far_from_care` into the main modeling pipeline (waits on the team's cutoff decision — same pattern as the SES-linkage deferral in Phase 141)

## Out of Scope

- Drive-time / road-network distance — requires an external routing API; centroid great-circle distance via `zipcodeR` is the AM-specified method
- Facility ZIP imputation — D-04 resolved: count and report, do not fill
- `far_from_care` wired into downstream models — deferred until Amy/Erin set `distance_cutoff_mi`

## Traceability

| REQ-ID  | Phase | Plan(s) |
|---------|-------|---------|
| DIST-01 | 152   | 152-02  |
| DIST-02 | 152, 153 | 152-02, 153-01 |
| DIST-03 | 153   | 153-01, 153-02 |
| DIST-04 | 154   | 154-01, 154-02, 154-03 |
| DIST-05 | 155   | 155-01, 155-02, 155-03 |
| DIST-06 | 156   | 156-01, 156-02 |
| DIST-07 | 152, 156 | 152-02, 156-03, 156-05 |
