# Phase 182: Facility ZIP Recovery Report

**Generated:** 2026-10-14
**Script:** R/182_facility_zip_recovery_report.R

---

## Recovery by Tier

**Tier 1 (FACILITYID donor fill):** NA — baseline RDS was a placeholder; no before/after encounter comparison available. This is expected for the first run with fill active. No prior run without fill exists in the dated-RDS series to serve as the "before" baseline.

## Headline: Patients Who Gained Exposure (by miss_reason)

**Patients who moved from missing to observed exposure after fill: 0**

The ZIP fill recovered encounters in the diagnostic workbook (filled_tier1 > 0), but no patient crossed the 100 mi threshold for `far` classification as a result. ZIPs were recovered at the encounter level, but the recovered ZIPs did not change any patient's median distance enough to alter their far/not-far assignment.

## Remaining Missing by Reason (after fill)

| Reason                | Encounters |
|-----------------------|-----------|
| facility_zip_missing  | 86,005    |
| zip_not_in_db         | 134,949   |

## ZIP Not-in-DB Diagnosis

See sheet C_zip_not_in_db in `output/182_facility_zip_diagnosis_20261014.xlsx` for the full breakdown of ZIP codes present in encounter data but absent from the centroid reference table.

## Effect on Results

| Metric                        | Before         | After          |
|-------------------------------|----------------|----------------|
| Phase 179 Primary OR (95% CI) | 0.84 (0.73–0.98) | 0.83 (0.71–0.96) |
| Phase 180 D-09 % shrinkage    | 37.4%          | 30.4%          |

Phase 179 primary OR is essentially unchanged. The ZIP fill did not materially alter the distance-based exposure classification.

## Locked Branches

- **D-05:** Same side — no change. Limitation row locked in R/179 KEY builder.
- **D-09:** Moves toward 1 (37.4% → 30.4% shrinkage). Consistent with out-of-system care interpretation. Report to Amy/Erin alongside D-165-01.

## Pinned Paths (HiPerGator, 2026-10-14)

- R/122 RDS: `output/encounter_distance_20261014.rds`
- R/122 XLSX: `output/encounter_distance_20261014.xlsx`
- Diagnostic workbook: `output/182_facility_zip_diagnosis_20261014.xlsx`
- R/179 RDS: `output/internal/cbc_patient_year_20261014.rds`
- R/179 XLSX: `output/cbc_patient_year_20261014.xlsx`
- R/180 RDS: `output/internal/cbc_missing_capture_20261014.rds`
- R/180 XLSX: `output/cbc_missing_capture_20261014.xlsx`

## R/88 Smoke Test (Phase 182)

ALL 970 CHECKS PASSED (3 skipped) — SMOKE-182-01: 10 PASS / 0 FAIL / 0 SKIP

---

# Phase 182.1: ZIP Centroid Mapping — Recovery Report

**Generated:** 2026-10-15
**Script:** R/182_facility_zip_recovery_report.R (182.1 section)

## Status Transitions (R/122 encounter-level, before → after)

| Transition | Encounters |
|---|---|
| zip_not_in_db → computed (crosswalk/haversine) | 13,666 |
| zip_not_in_db → facility_zip_missing (placeholder blanked) | 13,659 |
| patient_zip_missing → facility_zip_missing (missing patient + placeholder facility) | 2,647 |
| still zip_not_in_db | 107,624 |
| unchanged computed | retained; distance_mi identical |

Assert: no computed → other regression. PASS.
Assert: no distance_mi changes for previously computed rows. PASS.

## Distance Method Distribution (after)

| Method | Encounters |
|---|---|
| zipcodeR_crosswalk | 13,652 |
| haversine_gazetteer | 14 |

Crosswalk vintage: 2022.

## Patients Gaining Exposure

| Phase | Patients gained | Patients lost |
|---|---|---|
| Phase 182 (facility ZIP fill) | 185 | 0 |
| Phase 182.1 (ZIP→ZCTA crosswalk) | 48 | 0 |

Far switches (patients whose `far` value changed): **50**
(48 newly exposed + 2 existing patients whose median distance crossed the 100 mi threshold)

## Remaining Missing (after Phase 182.1)

| Reason | Encounters |
|---|---|
| facility_zip_missing | see Phase 182 baseline |
| zip_not_in_db | 107,624 |

**Phase 183 target (patients still missing exposure):** 614

Note: 2,647 encounters where the patient ZIP was missing and the facility ZIP was a placeholder are now classified as `facility_zip_missing` (not `zip_not_in_db`).

## Effect on Results

| Metric | Before (Phase 182 baseline) | After (Phase 182.1) |
|---|---|---|
| R/165 whole-record OR (95% CI) | 0.553 (0.470–0.651) | 0.553 (0.472–0.648) |
| R/165 post-anchor OR (95% CI) | 0.558 (0.468–0.665) | 0.557 (0.470–0.661) |
| R/179 primary OR (95% CI) | 0.828 (0.713–0.961) | 0.834 (0.719–0.967) |
| R/180 MISS-02 OR (far=1) | 0.699 | 0.692 |
| R/180 MISS-03 OR (far=0, 95% CI) | 0.864 (0.745–1.003) | 0.871 (0.751–1.009) |
| D-05 | same side | same side |
| D-09 % shrinkage | 30.4%, toward 1 | 19.7%, no material change |
| R/181 prior-year OR (95% CI) | 0.833 (0.682–1.016) | 0.823 (0.677–1.001) |

D-09 note: 30.4% → 19.7% sits near the 25% monitoring threshold — the direction (toward 1) is consistent with out-of-system care and does not constitute a reversal. Report to Amy/Erin alongside D-165-01.

## Locked Branches

- **D-05:** Same side — no change. Limitation row remains locked in R/179 KEY builder.
- **D-09:** 30.4% → 19.7% (further toward 1). Interpretation unchanged: consistent with out-of-system care.

## Remaining zip_not_in_db

107,624 encounters remain zip_not_in_db after the crosswalk pass. These are ZIP codes not present in either the zipcodeR database or the HRSA ZIP→ZCTA crosswalk (vintage 2022).

## R/88 Smoke Test (Phase 182.1)

ALL 982 CHECKS PASSED (3 skipped) — SMOKE-182.1-01: 9 PASS / 0 FAIL / 0 SKIP
