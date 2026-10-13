# Requirements: v3.10 Distance Missingness & Script Fixes

## Milestone Goal

Find out whether encounters without a computed distance could bias the Phase 165 far-from-care (>100 mi) vs CBC association, and fix two small script issues first.

---

## v3.10 Requirements

### Script Fixes (Phase 178)

- [ ] **FIX-01**: `R/147_verify_vs_1006.R` guard — final `quit()` replaced with `if (!interactive()) quit(status = if (n_fail == 0) 0 else 1)`; "Confirmed-cohort N" and QC label lookups use exact-match (`==` or `fixed = TRUE`), not case-insensitive partial regex.
- [ ] **FIX-02**: R/122 workbook KEY note added — "Temporal ZIP match would fill 0 encounters (Phase 177). The patient_zip_missing encounters belong to patients with no ZIP9 (UNREACHABLE_NO_ZIP9) or no address history (not in R/121); no dated ZIP exists to fill them."

### Missing-Distance Bias Check (Phase 179)

- [ ] **MISS-01**: R/179_distance_missingness.R compares CBC rates between `distance_status` groups (computed vs patient_zip_missing; facility_zip_missing and zip_not_in_db reported separately) — encounter-level Rao-Scott (clustered on patient) and patient-level (any CBC); breakdown by R/121 triage group and by whether the patient has all vs some encounters missing.
- [ ] **MISS-02**: Bounding sensitivity analysis — Phase 165 association (patient-level Fisher and Rao-Scott) recomputed with all missing encounters assigned (a) far and (b) not far; both bounded ORs with CIs reported alongside the Phase 165 estimate.
- [ ] **MISS-03**: Decision rule applied before running — if both bounded ORs stay on the same side of 1 as the Phase 165 estimate → stated limitation added to Phase 165 output KEY; otherwise → flag to team (Amy/Erin) alongside D-165-01, no further analysis this milestone.

---

## Out of Scope

- New imputation tiers for patient_zip_missing encounters — Phase 177 confirmed zero fillable encounters
- Phase 156 AM write-back — dropped 2026-10-09 (registration covered by Phase 169)
- Phase 165 sensitivity sweep / PNG cutoff lines — superseded
- Any new R/88 section for R/179 (one-off script, not recurring)

---

## Traceability

| REQ-ID  | Phase | Plan(s) |
|---------|-------|---------|
| FIX-01  | 178   | TBD     |
| FIX-02  | 178   | TBD     |
| MISS-01 | 179   | TBD     |
| MISS-02 | 179   | TBD     |
| MISS-03 | 179   | TBD     |

---

## Carry-Forward Backlog (not in scope for v3.10)

- D-165-01: Amy/Erin confirmation of primary analysis method (patient-level Fisher vs Rao-Scott) — awaiting team
- Phase 168: Team review of NHL Gantt episode subsets
