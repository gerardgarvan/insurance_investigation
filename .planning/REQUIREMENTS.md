# Requirements — v3.14 HL Treatment Detection Quality

**Milestone goal:** Validate pipeline treatment-capture sensitivity against the tumor registry, characterize confirmed-cohort patients with no captured treatment, close the MED_ADMIN name-based capture gap in R/26, and replace R/28 `regimen_label` with a date-level regimen + line-of-therapy engine covering all treatment types.

---

## Active Requirements

### TRVAL — Tumor-Registry Treatment Sensitivity (Phase 202)

- [x] **TRVAL-01**: Analyst can inspect the actual column names and content of TR1/TR2/TR3 first-course treatment fields (chemo, radiation, immunotherapy, transplant summary + dates) before any comparison code is written
- [x] **TRVAL-02**: Denominator = TR HL patients present in gantt_episodes_180 (≈600). For each, pipeline compares registry "treatment given" flag + first-course date vs Gantt capture and classifies as: captured (exact/±30 d/±90 d), not captured, or no treatment in registry. The 121 TR-HL patients outside the confirmed cohort are reported as a separate "not in pipeline" row, not included in the sensitivity denominator.
- [x] **TRVAL-03**: Sensitivity (% of TR-flagged treatments captured by pipeline) reported by treatment type (chemo, radiation, immunotherapy, transplant) with counts and date-difference distribution
- [x] **TRVAL-04**: Sensitivity stratified by SOURCE (partner site) and by diagnosis year (early vs late within study window)
- [x] **TRVAL-05**: Styled xlsx (KEY leftmost, A_sensitivity, B_date_diff, C_by_source, D_by_year, QC) with <11 suppression on all patient counts
- [x] **TRVAL-06**: Reverse direction (agreement / PPV-style): for pipeline-captured treatment episodes of each type, report what fraction have a matching registry record of that type — by treatment type
- [x] **TRVAL-07**: R/88 section for Phase 202: script exists, workbook KEY leftmost, expected sheets present, suppression applied

### NOTX — No-Treatment Characterization (Phase 203)

- [x] **NOTX-01**: For each no-treatment patient (≈3,246), whether first_hl_dx_date falls before the data window (enrollment start / first encounter)
- [x] **NOTX-02**: Count of encounters within ±90 days of first_hl_dx_date, reported for no-treatment patients
- [x] **NOTX-03**: No-treatment patients characterized by: single_source_care flag (R/169), SOURCE (partner site), payer category, far_from_care_100mi, age group at diagnosis, NLPHL vs cHL
- [x] **NOTX-04**: Registry treatment fields from Phase 202 joined for no-treatment patients (registry says treatment given but pipeline did not capture it)
- [x] **NOTX-05**: A "treatment observable" eligibility rule is proposed as a team decision item — the rule is not applied; output documents the proposed definition and counts affected patients
- [x] **NOTX-06**: Comparison group = 4,450 confirmed-cohort patients with ≥1 treatment episode; every NOTX characteristic (NOTX-01 through NOTX-04) is reported for both groups side by side
- [x] **NOTX-07**: Styled xlsx (KEY leftmost, A_profile, B_reasons_waterfall, C_by_source, D_candidate_rules, QC) with <11 suppression; R/88 section for Phase 203

### MCAP — MED_ADMIN Name-Based Capture (Phase 204)

- [ ] **MCAP-01**: R/26 adds name-based capture from RAW_MEDADMIN_MED_NAME alongside existing code-based capture, using DRUG_NAME_ALIASES canonicalization; source tagged as "MED_ADMIN_NAME"
- [ ] **MCAP-02**: Before/after counts per drug (minimum: rituximab, brentuximab, MTX) for administrations gained by name-based capture
- [ ] **MCAP-03**: All downstream scripts rerun: R/28→R/29→R/52 (90-day Gantt) and R/142 (180-day Gantt); unchanged columns match pre-Phase-204 values in a regression check on both outputs
- [ ] **MCAP-04**: R/88 checks added for name-based capture and regression guard; output/internal/ before/after RDS snapshots written
- [ ] **MCAP-05**: QC list of distinct RAW_MEDADMIN_MED_NAME strings newly matched per drug (with record/patient counts, suppressed to <11) for manual review of false positives (order text, non-HL formulations); script stops for review if any unexpected drug family appears

### REGL — Regimen + Line-of-Therapy Engine (Phase 205)

- [ ] **REGL-01**: A regimen dictionary exists in R/00_config.R covering: ABVD, AVD, BV+AVD, Nivo+AVD, BEACOPP/escBEACOPP, pediatric (ABVE-PC/OEPA-COPDAC/BV-AVEPC), NLPHL (R-CHOP/R-CVP/rituximab mono), salvage (ICE/GVD/IGEV/BV-bendamustine/BV-nivolumab/pembrolizumab/nivolumab mono), BV consolidation, Other
- [ ] **REGL-02**: Concurrency window for same-regimen drug co-occurrence is a named config constant (default ±7 days)
- [ ] **REGL-03**: Line-of-therapy counter assigned per patient: new line when a new non-maintenance drug class starts after a configurable gap or after SCT
- [ ] **REGL-04**: Engine operates on per-date administrations across Chemotherapy AND Immunotherapy treatment types (not limited to one treatment_type); SCT dates are used for the LOT rule; R/28 `regimen_label` and the Phase 201 relabel block in R/142 are both replaced
- [ ] **REGL-05**: Reconciliation table compares Phase 205 `regimen_label` values vs Phase 201 `abvd_class` values across all episodes
- [ ] **REGL-06**: Open team decisions logged in phase output: SME regimen list confirmation, gap length between lines, BV consolidation classification, NLPHL regimen handling
- [ ] **REGL-07**: Per-patient internal output (RDS + CSV in output/internal/): line-1 regimen, line-1 start date, number of lines, regimen per line
- [ ] **REGL-08**: Gantt schema change guarded by regression on all pre-Phase-205 columns; R/88 section for Phase 205; unit tests for regimen dictionary + LOT rule on synthetic patients

---

## Ground Rules (all phases)

- No change to cohort membership in any phase
- Phases 202 and 203 can run in parallel (no dependency between them)
- Phase 204 must precede Phase 205 (205 consumes updated treatment episodes)
- R/88 structural checks required in every phase
- Patient counts 1–10 → `"<11"` in every output
- KEY sheet leftmost in all xlsx workbooks
- UF colors: `#0021A5` (blue), `#FA4616` (orange)
- Runtime: HiPerGator interactive R/4.5; local edits first, sync to HiPerGator for pipeline runs

---

## Future Requirements (deferred)

- D-201-04: 121 TR-HL patients absent from confirmed_hl_cohort.rds — cohort-definition decision, not in scope for v3.14
- Application of "treatment observable" eligibility rule to cohort (dependent on team decision from NOTX-05)
- Multi-line therapy sequencing beyond LOT counter (requires episode boundary formalization)

---

## Out of Scope

- D-201-04 / any cohort-membership change — cohort is fixed for this milestone
- Applying the NOTX eligibility rule — proposed only, team decides
- Changing 7-day confirmation logic (cancer_summary_table gap criterion unchanged)
- Changes to payer classification, distance calculation, or survivorship logic
- Publication-ready figure formatting

---

## Traceability

| REQ-ID | Phase | Plan(s) | Status |
|--------|-------|---------|--------|
| TRVAL-01 | 202 | TBD | Pending |
| TRVAL-02 | 202 | TBD | Pending |
| TRVAL-03 | 202 | TBD | Pending |
| TRVAL-04 | 202 | TBD | Pending |
| TRVAL-05 | 202 | TBD | Pending |
| TRVAL-06 | 202 | TBD | Pending |
| TRVAL-07 | 202 | TBD | Pending |
| NOTX-01 | 203 | TBD | Pending |
| NOTX-02 | 203 | TBD | Pending |
| NOTX-03 | 203 | TBD | Pending |
| NOTX-04 | 203 | TBD | Pending |
| NOTX-05 | 203 | TBD | Pending |
| NOTX-06 | 203 | TBD | Pending |
| NOTX-07 | 203 | TBD | Pending |
| MCAP-01 | 204 | TBD | Pending |
| MCAP-02 | 204 | TBD | Pending |
| MCAP-03 | 204 | TBD | Pending |
| MCAP-04 | 204 | TBD | Pending |
| MCAP-05 | 204 | TBD | Pending |
| REGL-01 | 205 | TBD | Pending |
| REGL-02 | 205 | TBD | Pending |
| REGL-03 | 205 | TBD | Pending |
| REGL-04 | 205 | TBD | Pending |
| REGL-05 | 205 | TBD | Pending |
| REGL-06 | 205 | TBD | Pending |
| REGL-07 | 205 | TBD | Pending |
| REGL-08 | 205 | TBD | Pending |
