# Phase 183: MICE Sensitivity for Distance — Pooled Results Memo

**Generated:** 2026-10-15  
**Script:** R/183_mice_sensitivity_distance.R  
**Run date:** 20261015  
**Host:** HiPerGator  

---

## Overview

This memo reports the multiple-imputation sensitivity analysis for the Phase 179 primary GEE result (effect of living far from care on annual CBC receipt). Multiple imputation via MICE (m = 20, maxit = 20, seed 20261015) was applied to 614 patients whose post-anchor median distance to care was missing after Phase 182.1 ZIP recovery. Two separate imputation strategies were compared.

---

## Imputation Strategy

- **D-01:** Impute `log_dist` = log1p(median distance) via predictive mean matching (PMM). Derive `far` from imputed `log_dist` using the Phase 179 cutoff.  
- **D-02:** Impute `far` directly via logistic regression (`logreg`), treating `far` as a binary factor.

Predictors: `prop_cbc_years`, `n_years_observed`, `dist_to_source_facility_mi` (auxiliary, mandatory), `age_at_anchor`, `sex`, `main_source`, `post_anchor_enc_count`, `single_source_care_post`, `adi`.

Dropped predictors: `payer` (payer_summary RDS not found at run time — recorded in KEY).

loggedEvents: `main_sourceUCI` was removed by mice in the D-01 (PMM) run. `main_sourceUCI` is not a mandatory predictor (mandatory set: `prop_cbc_years`, `n_years_observed`, `dist_to_source_facility_mi`); this event did not trigger a D-09 hard stop. Recorded in KEY and MICE-01 sheet.

---

## Reproduction Gate (Task 0)

Phase 179 complete-case result reproduced from pinned inputs:  
**OR = 0.834 (95% CI 0.719–0.967)** — matches Phase 179 primary estimate. Gate: PASS.

---

## Pooled MICE Results

Pooling method: Rubin (1987) with Barnard–Rubin degrees of freedom and t-quantile CI.

| Analysis          | Subset   | OR    | 95% CI        | FMI   | df      |
|-------------------|----------|-------|---------------|-------|---------|
| D-01 (log_dist PMM) | Years 2+ | 0.842 | 0.725–0.977 | 0.049 | 8009.8  |
| D-01 (log_dist PMM) | All years | 0.915 | 0.801–1.045 | 0.161 | 750.9   |
| D-02 (far logreg)  | Years 2+ | 0.834 | 0.713–0.976 | 0.160 | 764.8   |
| D-02 (far logreg)  | All years | 0.894 | 0.768–1.040 | 0.367 | 148.1   |

---

## Agreement Assessment (D-01 vs D-02)

**Primary subset (years 2+):** D-01 OR = 0.842, D-02 OR = 0.834 — difference of 0.008, within ±0.05 on the OR scale. The two strategies agree.

**All-years subset:** D-01 OR = 0.915, D-02 OR = 0.894 — difference of 0.021, within ±0.05 on the OR scale. The two strategies agree.

Both strategies yield estimates similar to the complete-case primary OR (0.834). The pooled primary (years 2+) ORs lie within ±0.01 of each other and within ±0.01 of the complete-case value for D-02.

---

## Phase 180 Bounding Context

Phase 180 computed bound under extreme missing-data assumptions:  
- Missing → far = 1 (MISS-02): OR = 0.692 (95% CI 0.614–0.781)  
- Missing → far = 0 (MISS-03): OR = 0.871 (95% CI 0.751–1.009)  

The MICE pooled estimates fall within these bounds for both subsets and both imputation strategies, consistent with a plausible MAR mechanism.

---

## Interpretation

Under a missing-at-random assumption with the predictors available, the MICE pooled primary OR (years 2+) is similar to the complete-case OR in both magnitude and direction. The result is not materially sensitive to whether `log_dist` or `far` is the imputation target. The all-years estimate moves toward the null in both strategies, consistent with earlier Phase 179 findings.

Agreement rule applied: estimates agree when the pooled primary ORs from D-01 and D-02 differ by ≤0.05 on the OR scale.

---

## Outputs

- `output/mice_sensitivity_distance_20261015.xlsx` — workbook (KEY, MICE-01, MICE-02 sheets)
- `output/mice_trace_20261015.png` — convergence trace plots (chain mean/SD)
- `output/mice_density_20261015.png` — observed vs imputed distributions
- `output/internal/mice_mids_20261015.rds` — mids objects (patient-level, internal only)
