---
phase: 165-distance-100mi-indicator-and-cbc-association
plan: "01"
subsystem: analysis
tags: [distance, cbc, statistical-methods, rao-scott, survey, geepack, prototype]
dependency_graph:
  requires:
    - R/122 output (enc_distance RDS)
    - R/147 pattern (CBC LOINCs, anchor date logic)
    - DuckDB (LAB_RESULT_CM, ENCOUNTER)
    - utils_treatment.R (get_hl_any_dx_ids)
  provides:
    - R/utils/utils_distance_cbc.R (shared helpers for R/163 and R/165)
    - R/163_distance_cbc_methods_prototype.R
    - CONFIG$far_from_care_cutoff_mi (single cutoff source)
    - CONFIG$distance_assoc_method = "rao_scott" (D-165-01 recorded)
    - enc_far_from_care.rds (ACC-01)
    - 165-METHODS.md (decision document for D-165-01)
  affects:
    - Plan 02 (R/165 production script — now unblocked; method = rao_scott)
tech_stack:
  added:
    - survey (cluster-adjusted chi-square; Rao-Scott F; svyglm)
    - geepack (installed; GEE skipped at runtime — infeasible at 1.7M rows)
  patterns:
    - CONFIG key as single numeric source (CONFIG$far_from_care_cutoff_mi)
    - Non-equi date-range join for CBC-in-encounter (left_join + filter)
    - tryCatch GEE fallback (exchangeable -> independence)
    - DEFF as explicit output column for method-selection evidence
key_files:
  created:
    - .planning/phases/165-distance-100mi-indicator-and-cbc-association/165-DISCOVERY.md
    - R/utils/utils_distance_cbc.R
    - R/163_distance_cbc_methods_prototype.R
    - slurm/163_distance_cbc_methods_prototype.sbatch
    - .planning/phases/165-distance-100mi-indicator-and-cbc-association/165-METHODS.md
  modified:
    - R/00_config.R (Phase 165 keys; CONFIG$distance_assoc_method set to "rao_scott" per D-165-01)
    - .planning/phases/165-distance-100mi-indicator-and-cbc-association/165-CONTEXT.md (D-165-01 recorded)
decisions:
  - "D-165-01: rao_scott (C2 Rao-Scott encounter-level) selected as primary; C4 patient Fisher as sensitivity"
  - "R/163 is prototype (R/164 taken by dox baseline); Plan 02 production = R/165"
  - "build_cbc_events() re-derives from DuckDB: R/147 saves post-anchor-only wide table (D-06a)"
  - "CBC date priority: RESULT_DATE > SPECIMEN_DATE > LAB_ORDER_DATE (matches R/147 line 183)"
  - "DEFF=130 in both windows; GEE skipped (1.7M rows infeasible in SLURM budget)"
  - "suppress_small_vec() returns NA_integer_; suppress_display() returns '<11' string"
metrics:
  duration: "1 day (2026-10-08)"
  completed_date: "2026-10-08"
  tasks_completed: 7
  tasks_total: 7
  files_created: 5
  files_modified: 3
---

# Phase 165 Plan 01: Distance >100 mi Indicator and CBC Association Methods Prototype — Summary

**One-liner:** Prototype (R/163) ran all four candidate tests x two windows on 1.7M real encounters; DEFF=130 drove the method choice (D-165-01: Rao-Scott primary, patient Fisher sensitivity); 165-METHODS.md delivered with numeric evidence.

## Completed Tasks

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Read-only discovery | 9c99239 | 165-DISCOVERY.md |
| 2 | Install survey + geepack on HiPerGator | (renv.lock) | renv.lock |
| 3 | CONFIG keys + utils_distance_cbc.R | 9c8b601 | R/00_config.R, R/utils/utils_distance_cbc.R |
| 4 | R/163 prototype + sbatch wrapper | 1aabefe | R/163_distance_cbc_methods_prototype.R, slurm/163_*.sbatch |
| 5 | Run prototype on HiPerGator | (log) | enc_far_from_care.rds written |
| 6 | Write 165-METHODS.md from prototype log | a9975b7 | 165-METHODS.md |
| 7 | Review memo; record D-165-01 | adc83f0 | R/00_config.R, 165-CONTEXT.md, 165-METHODS.md |

## Key Findings from Prototype

**Analysis set:** 1,725,592 encounters (8,455 patients) with computed distance and known anchor date; 285,125 (16.5%) far from care (>100 mi); 219,287 (12.7%) with CBC in encounter.

**Cluster structure (whole record):** min=1, Q1=25, median=87, Q3=232, p95=728, max=8,752, mean=204 encounters per patient.

**DEFF = 130 in both windows.** Effective encounter-level sample size ~13,300. Naive chi-square SE is ~11x too small. Encounter-level analysis requires full clustering adjustment.

**Results summary:**

| Window | Method | OR | 95% CI | DEFF | p |
|--------|--------|----|--------|------|---|
| Whole | C2 Rao-Scott | 0.553 | [0.470, 0.651] | 130.1 | 6.8e-13 |
| Whole | C4 patient Fisher | 0.586 | [0.535, 0.641] | — | <2e-16 |
| Post-anchor | C2 Rao-Scott | 0.558 | [0.468, 0.665] | 130.3 | 4.9e-11 |
| Post-anchor | C4 patient Fisher | 0.659 | [0.604, 0.719] | — | <2e-16 |

Direction consistent: far-from-care encounters are negatively associated with CBC receipt (OR < 1 in all cells, both methods, both windows).

C1 (naive Pearson): OR undefined at 1.7M rows (integer overflow); excluded.
C3 (GEE): Skipped — computationally infeasible within SLURM time budget at max cluster size 8,752.

## Decision Recorded — D-165-01

**Primary method:** C2 Rao-Scott encounter-level (clustered on patient ID)
**Sensitivity:** C4 patient-level Fisher exact
**CONFIG$distance_assoc_method:** `"rao_scott"`

Rationale: DEFF=130 is large enough that ignoring clustering is not defensible. Rao-Scott properly adjusts at the encounter level. Patient-level Fisher provides a clustering-free cross-check that agrees in direction and approximate magnitude.

## Deviations from Plan

**1. [Rule 1 - Bug] Removed erroneous dplyr::join_by block in build_enc_analysis()**
- **Found during:** Task 3 / Task 5 prototype run
- **Issue:** Plan pseudo-code showed a join_by(between(...)) with a self-referential column expression that errored on execution
- **Fix:** Replaced with left_join on ID + filter on date range + group_by summarise; semantics identical, no fan-out
- **Commits:** 556f00c, 1d2d61d

**2. [Rule 3 - Blocking] Output path fix for enc_distance lookup**
- **Found during:** Task 5 prototype run
- **Issue:** R/163 looked in CONFIG$cache$outputs_dir but file was in CONFIG$output_dir
- **Fix:** Corrected path in Section 1b (commit 9c32085)

**3. [Rule 1 - Runtime] C3 GEE skipped; corstr auto-overridden to independence**
- **Found during:** Task 5 (Section 3 log)
- **Issue:** Max cluster = 8,752; GEE projected to exceed 8-hour SLURM allocation
- **Fix:** SKIP_GEE flag added (commit 1d2d61d); documented in 165-METHODS.md; does not affect D-165-01

## Known Stubs

None. All functions are complete. enc_far_from_care.rds written on HiPerGator. 165-METHODS.md contains real numbers with no placeholders. D-165-01 is recorded.

## Self-Check: PASSED

Files exist: 165-DISCOVERY.md, R/utils/utils_distance_cbc.R, R/163_distance_cbc_methods_prototype.R, slurm/163_distance_cbc_methods_prototype.sbatch, 165-METHODS.md.

Commits present: 9c99239, 9c8b601, 1aabefe, a9975b7, adc83f0.

R/122_encounter_distance.R: unchanged throughout.
Literal 100 cutoff: absent from R/163 and utils_distance_cbc.R.
module load R/4.4.2: absent from all new files.
statistic = "F": present in R/163.
CONFIG$distance_assoc_method: set to "rao_scott" (commit adc83f0).
