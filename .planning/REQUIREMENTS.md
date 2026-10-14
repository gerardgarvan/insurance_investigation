# Requirements: v3.11 CBC Team Deliverable, Distance Completeness, Survivorship Modeling

## Milestone Goal

Deliver the CBC × distance prior-year analysis the team requested on 2026-10-13, recover missing-exposure patients via facility ZIP repair, add a MICE sensitivity analysis for remaining missing exposure, and model survivorship surveillance modality rates with a distance × modality interaction term.

---

## Active Requirements

### CBC Prior-Year Analysis (Phase 181)

- [x] **CBCP-01**: Analyst can produce a 2×2 table of CBC-in-prior-year (yes/no) × far-from-care (<100 mi / ≥100 mi) at the patient level, using the most recent fully observed follow-up year per patient from the Phase 179 RDS (`output/internal/cbc_patient_year_20261013.rds`), with a Pearson chi-squared test (Fisher if any expected count < 5), OR with 95% CI, CBC rates by group, missing-exposure count reported not tested, year_index distribution of the "prior year" reported, and primary analysis restricted to patients with year_index ≥ 2 (survivorship) with all-years secondary analysis.
- [x] **CBCP-02**: Analyst can share a one-page team memo (neutral language, markdown in the phase directory) covering: Phase 181 CBCP-01 result; Phase 165 encounter-level OR vs Phase 179 patient-year OR comparison; Phase 180 bounding results (noting that the not-far bound CI crosses 1); Phase 180 capture check (log-OR shrinks 37.4% under lab restriction, single-source split OR 0.754 vs 1.068 with which group is which stated); and open decisions D-15 and D-165-01.

### Facility ZIP Recovery (Phase 182)

- [x] **FZIP-01**: Analyst can diagnose the 581 missing-exposure patients in Phase 180 MISS-01 group (b) (facility_zip_missing / zip_not_in_db reasons) — identifying which facilities / ZIPs are missing, whether FACILITY_LOCATION or FACILITYID can be filled from other encounters at the same facility, and whether ZIPs can be added to the centroid table.
- [x] **FZIP-02**: Analyst can apply unambiguous fixes in R/122 (or its helpers only), re-run R/122 → R/179 → R/180, and produce a before/after report of patients/encounters recovered and how the primary OR and missingness breakdown change.

### Multiple-Imputation Sensitivity for Distance (Phase 183)

- [ ] **MICE-01**: Analyst can run multiple imputation (mice, m ≥ 20) of patient median distance or `far` for remaining missing-exposure patients after Phase 182, with predictors selected in the discuss phase (candidates: triage, SOURCE, single-source flag, age, sex, payer, ADI, encounter counts), and produce imputation model diagnostics (convergence, trace plots, density overlays).
- [ ] **MICE-02**: Analyst can refit the Phase 179 primary GEE in each imputed dataset, pool estimates with Rubin's rules, and produce a comparison table of pooled OR vs complete-case OR vs Phase 180 bounding ORs.

### Survivorship Modality Rates and Distance × Modality Interaction (Phase 184)

- [ ] **MODR-01**: Analyst can produce rates of each surveillance modality per patient-year (annual primary; 6-month as sensitivity), reusing R/147 / R/166 definitions and person-time, with suppression applied per HIPAA rules.
- [ ] **MODR-02**: Analyst can fit a count-per-patient-year model by modality (Poisson or negative-binomial GEE or GLMM, with log person-time offset, terms far × modality, clustered on patient ID), and report modality-specific rate ratios for far vs not-far with 95% CIs.

---

## Future Requirements (deferred)

- End-of-treatment date rules — pending Sharon's input
- Data-completeness check vs Medicaid claims (3.c.ii)
- Phase 168 NHL Gantt episode subsets team review
- D-15 primary analysis method (Phase 165 encounter-level vs Phase 179 patient-year) — awaiting Amy/Erin
- D-165-01 method confirmation (Rao-Scott vs patient-level Fisher) — awaiting Amy/Erin

---

## Out of Scope (v3.11)

- Changes to R/147 surveillance codeset or modality definitions — use existing R/147/R/166 output as-is in Phase 184
- Rerunning Phase 165 (encounter-level analysis) — Phase 181 is additive, not a replacement
- Publication-ready figure formatting — exploratory quality sufficient
- Forward-looking imputation for Phase 183 predictors not yet available in the dataset

---

## Traceability

| REQ-ID | Phase | Status |
|--------|-------|--------|
| CBCP-01 | 181 | Complete |
| CBCP-02 | 181 | Complete |
| FZIP-01 | 182 | Pending |
| FZIP-02 | 182 | Pending |
| MICE-01 | 183 | Pending |
| MICE-02 | 183 | Pending |
| MODR-01 | 184 | Pending |
| MODR-02 | 184 | Pending |

---

*Created: 2026-10-14 — v3.11 milestone kickoff.*
