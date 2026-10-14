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

## R/88 Smoke Test

ALL 970 CHECKS PASSED (3 skipped) — SMOKE-182-01: 10 PASS / 0 FAIL / 0 SKIP
