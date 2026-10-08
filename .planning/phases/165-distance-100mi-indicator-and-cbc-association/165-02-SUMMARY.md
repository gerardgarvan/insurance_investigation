# Phase 165 Plan 02 Summary

**Plan:** 165-02 — Distance CBC Association (Production)
**Completed:** 2026-10-08
**Status:** DONE

## What Was Built

| File | Purpose |
|------|---------|
| `R/165_distance_cbc_association.R` | Production analysis: Rao-Scott primary + adjusted sensitivity, both windows, five-sheet xlsx |
| `slurm/165_distance_cbc_association.sbatch` | SLURM wrapper (`module load R/4.5`, 64gb, 4hr) |
| `output/distance_cbc_association_20261008.xlsx` | Deliverable — KEY, A_crosstab, B_test, C_sensitivity, QC |

## Key Outcomes

- **Method (D-165-01):** Rao-Scott cluster-adjusted chi-square (encounter-level, clustered on patient ID)
- **Primary result (whole record):** OR = 0.553 [0.470, 0.651], F = 51.77, p = 6.8e-13, DEFF = 130
- **Primary result (post-anchor):** OR = 0.558 [0.468, 0.665], F = 43.33, p = 4.9e-11, DEFF = 130
- **Sensitivity:** Adjusted for rurality (ruca_category) + SOURCE; payer unavailable (no payer_summary RDS in output — noted in KEY and QC sheets)
- **Run time:** 2.9 min on HiPerGator compute node
- **Analysis set:** 1,725,592 encounters, 8,455 patients (whole); 1,341,955 / 8,397 (post-anchor)

## Decisions Made During Execution

- Payer covariate dropped from sensitivity formula when entirely NA (no payer_summary RDS found); noted in workbook KEY and C_sensitivity
- `get_hl_any_dx_ids()` called with no arguments (function takes none — fixed from plan spec)
- `pri$df` rendered as `paste(df, collapse="/")` to handle vector-length-2 F-test denominator df

## Commits

- `dc8f874` — feat(165-02): Task 2 — R/165 production script + sbatch wrapper
- `8bea961` — fix(165): call get_hl_any_dx_ids() with no arguments
- `67d9d8f` — fix(165): handle missing payer gracefully; fix pri$df vector
