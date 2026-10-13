# Phase 180: Missing-Exposure Bias Check and CBC Capture Check — Context

**Gathered:** 2026-10-13
**Status:** Ready for planning
**Depends on:** Phase 179 (`output/internal/cbc_patient_year_<date>.rds`)

<domain>
## Phase Boundary

Build `R/180_cbc_missing_capture.R`: read-only checks on the Phase 179 patient-year analysis.
(1) Could patients with missing exposure bias the Phase 179 OR? (2) Does the far → lower CBC
association reflect CBCs done outside our system (non-capture) rather than not done?

Study hypothesis: far patients obtain CBCs outside our system, so "no CBC" can mean "not captured".
</domain>

<decisions>
## Implementation Decisions

### Inputs
- **D-01:** Phase 179 patient-year RDS pinned to `cbc_patient_year_20261013.rds` (env-var override
  `R180_P179_RDS`; record in KEY). The recomputed primary OR must reproduce Phase 179
  (0.84, 95% CI 0.73–0.98, rounded) or the script stops. Use the Phase 179 primary specification throughout: years 2+, GEE logistic
  `cbc_year ~ far + year_index_cat`, `id = ID`, `corstr = CONFIG$distance_gee_corstr`. Repeat for
  all years as secondary.

### MISS-01 — missing exposure
- **D-02:** Missing-exposure patients = `exposure_missing == TRUE` (no computed-distance post-anchor
  encounter). Break down by reason, exactly one group per patient (asserted):
  (c) **no post-anchor encounter in the ENCOUNTER table** (checked first);
  (a) post-anchor encounters in enc_distance, all `patient_zip_missing`;
  (b) only `facility_zip_missing` / `zip_not_in_db`;
  (d) mixed (a)+(b) reasons; (e) `computed` status but no distance value;
  (f) post-anchor ENCOUNTER rows but none in enc_distance.
  Also by R/121 triage group (incl. "not in R/121").
- **D-03:** Report patients, patient-years and CBC-year rate per group vs the observed-exposure
  group. Group (c) is flagged in KEY as directly relevant to capture (no in-system contact after
  anchor).

### MISS-02 / MISS-03 — bounding
- **D-04:** Refit the Phase 179 primary model with all missing-exposure patients assigned
  (i) far, (ii) not far. Report both ORs with 95% CIs beside the Phase 179 estimate.
- **D-05 (locked):** both bounded ORs on the same side of 1 as Phase 179 → add a stated limitation
  row to the Phase 179 KEY builder (lands on next R/179 run). Either crosses 1 → flag to Amy/Erin
  with D-165-01; no further analysis this milestone. KEY records the branch and the numbers.

### MISS-04 — capture
- **D-06:** Per patient-year flags, same interval as the outcome:
  (a) `any_lab_year` — ≥1 LAB_RESULT_CM result with LOINC **not** in the CBC set and **not** in
  the hematology list {6690-2, 718-7, 777-3, 4544-3, 789-8, 787-2, 785-6, 786-4, 788-0, 770-8,
  26499-4, 731-0, 58410-2, 57021-8, 57782-5}; date = coalesce(RESULT_DATE, SPECIMEN_DATE,
  LAB_ORDER_DATE); SQL push-down.
  (b) `any_enc_year` — ≥1 in-system encounter (any ENC_TYPE) in the year.
- **D-07 Descriptive first:** far vs not far proportion of patient-years with (a) and (b).
- **D-08:** Refit the primary model within (a)-years **[primary restriction]** and within
  (b)-years [secondary]; and stratified by Phase 167 `single_source_care_post` (R/169 RDS).
- **D-09 (locked):** compare the restricted OR with the Phase 179 primary OR on the log scale:
  change = 1 − log(OR_restricted) / log(OR_179).
  - change ≥ +25% (log-OR shrinks by at least a quarter) → "moves toward 1: consistent with
    out-of-system care (non-capture)"
  - change between −25% and +25% → "no material change: consistent with a true difference in CBC
    receipt"
  - change ≤ −25% (log-OR grows by at least a quarter) → "moves away from 1: consistent with a true
    difference in CBC receipt"
  The label is decided by the PRIMARY restriction; the secondary restriction and each
  single_source_care_post stratum get the same rule applied and are reported alongside. Always
  report the percentage change and CIs. Report only; goes to Amy/Erin with D-165-01.
- **D-10 Caveat check:** report value counts of LAB_RESULT_CM source fields (e.g. LAB_RESULT_SOURCE,
  RESULT_LOC). These describe how a result was captured, not whether it came from an outside
  facility; unless a field explicitly identifies external results, KEY states "external origin of
  lab results could not be determined from available fields" (absence is not evidence of none).

### Outputs and execution
- **D-11:** Workbook `output/cbc_missing_capture_<YYYYMMDD>.xlsx`: KEY leftmost (inputs, branches
  taken for D-05 and D-09 with numbers), MISS-01, MISS-02/03, MISS-04 sheets. Counts 1–10 → "<11";
  percentages only when both counts ≥11; UF colors. Patient-year flags to
  `output/internal/cbc_missing_capture_<YYYYMMDD>.rds`.
- **D-12:** Interactive R on HiPerGator from the repo root (`module load R/4.5`;
  `source(..., local = new.env(parent = globalenv()))`); no SLURM, no Rscript; local checks grep
  only. Register in R/39 (one-off) and SCRIPT_INDEX; no R/88 section.
</decisions>

<canonical_refs>
- Phase 179 CONTEXT and RDS
- `R/179_cbc_patient_year.R` — model specification and KEY builder (D-05 limitation row)
- `R/169_single_source_care.R` RDS — `single_source_care_post`
- `R/121_zip_problem_inventory.R` RDS — `triage`
- `R/122_encounter_distance.R` — `distance_status`
</canonical_refs>
