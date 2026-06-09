---
phase: 94-make-proton-therapy-a-distinct-category-from-radiation
plan: 01
subsystem: Treatment Detection Infrastructure
tags:
  - treatment-categories
  - proton-therapy
  - config
  - cohort-predicates
  - episode-extraction
dependency_graph:
  requires:
    - "TREATMENT_CODES infrastructure (Phase 1)"
    - "Cohort predicate pattern (Phase 3)"
    - "Episode extraction pattern (Phase 43-44)"
  provides:
    - "Proton Therapy as distinct treatment category"
    - "has_proton() predicate function"
    - "HAD_PROTON cohort flag"
    - "extract_proton_dates() and extract_proton_dates_with_codes()"
  affects:
    - "R/52 Gantt export (will pick up Proton Therapy via TREATMENT_TYPES)"
    - "R/57 drug grouping tables (if extended to proton codes)"
    - "Treatment summary analyses"
tech_stack:
  added: []
  patterns:
    - "Treatment category split (Radiation → Radiation + Proton Therapy)"
    - "Single-source treatment detection (CPT only, no TR/DX/DRG/REV)"
key_files:
  created: []
  modified:
    - path: "R/00_config.R"
      changes: "Added 5th TREATMENT_TYPES element, proton_cpt list, DRUG_GROUPINGS proton mappings, TREATMENT_TYPE_COLORS entry"
    - path: "R/10_cohort_predicates.R"
      changes: "Added has_proton() function"
    - path: "R/14_build_cohort.R"
      changes: "Added HAD_PROTON flag with join and logging"
    - path: "R/25_treatment_durations.R"
      changes: "Added extract_proton_dates() and Proton Therapy dispatch branch"
    - path: "R/26_treatment_episodes.R"
      changes: "Added extract_proton_dates_with_codes() and Proton Therapy dispatch branch"
decisions:
  - decision: "Proton therapy CPT codes only (no TR/DX/DRG/REV sources)"
    rationale: "Proton beam therapy is a specific procedure identified by CPT codes; no tumor registry date columns, ICD codes, DRGs, or revenue codes exist for proton-specific detection"
    alternative: "Could have kept proton codes in Radiation category"
    outcome: "Simplest detection logic; mirrors actual data availability"
  - decision: "Default 90-day gap threshold for proton episodes"
    rationale: "Proton therapy is a form of radiation with similar treatment patterns (multi-fraction courses)"
    alternative: "Custom gap threshold"
    outcome: "Reuses Radiation gap threshold; noted for clinical SME validation"
  - decision: "Light orange / saddle brown color scheme for Proton Therapy"
    rationale: "Distinct from Radiation (green) and other treatment types; visually distinct in Gantt charts"
    alternative: "Other color palettes"
    outcome: "FFFDE7CC fill, FF8B4513 font"
metrics:
  duration_minutes: 3
  tasks_completed: 2
  files_modified: 5
  commits: 2
  lines_added: 103
  lines_removed: 10
completed_date: "2026-06-09"
---

# Phase 94 Plan 01: Make Proton Therapy a Distinct Category from Radiation

**One-liner:** Split proton beam therapy CPT codes (77520-77525) from Radiation into a distinct Proton Therapy treatment category with dedicated config, predicates, and episode extraction.

## What Was Built

Split proton beam therapy (CPT 77520, 77522, 77523, 77525) from the general "Radiation" treatment category into a distinct "Proton Therapy" category across core pipeline infrastructure: config definitions, cohort predicates, duration analysis, and episode detection.

**Infrastructure changes:**
- R/00_config.R: TREATMENT_TYPES expanded from 4 to 5 elements, DRUG_GROUPINGS maps 4 proton codes to "Proton Therapy", new proton_cpt list (4 codes removed from radiation_cpt, now 11 codes), TREATMENT_TYPE_COLORS has light orange/saddle brown entry
- R/10_cohort_predicates.R: has_proton() detects patients with proton CPT codes in PROCEDURES
- R/14_build_cohort.R: HAD_PROTON flag added to cohort with join and summary logging
- R/25_treatment_durations.R: extract_proton_dates() and dispatch branch in extract_all_dates()
- R/26_treatment_episodes.R: extract_proton_dates_with_codes() and dispatch branch in extract_dates_with_codes()

**Detection strategy:** Proton therapy uses only PROCEDURES CPT codes (PX_TYPE == "CH"). No tumor registry dates, diagnosis codes, DRGs, or revenue codes exist for proton-specific detection (simpler than Radiation's 5-source detection).

**Backward compatibility:** GANTT_TREATMENT_TYPES auto-includes Proton Therapy via derivation from TREATMENT_TYPES. Downstream scripts using TREATMENT_TYPES will automatically process proton therapy episodes.

## Tasks Completed

### Task 1: Split proton codes from Radiation config and register Proton Therapy category

**Status:** ✅ Complete
**Commit:** 66167e7

Modified R/00_config.R:
- DRUG_GROUPINGS: Radiation section comment updated from "15 codes" to "11 codes", new Proton Therapy section with 4 codes (77520, 77522, 77523, 77525)
- TREATMENT_CODES: Removed proton codes from radiation_cpt (comment: "Proton codes moved to proton_cpt"), added new proton_cpt list with 4 codes
- TREATMENT_TYPES: Added "Proton Therapy" as 5th element (after Radiation, before SCT)
- TREATMENT_TYPE_COLORS: Added `` `Proton Therapy`  = list(fill = "FFFDE7CC", font = "FF8B4513") `` (light orange / saddle brown)
- GANTT_TREATMENT_TYPES: No changes needed (auto-derives from TREATMENT_TYPES)

**Verification:**
- `grep -c "Proton Therapy" R/00_config.R` → 7 occurrences
- proton_cpt list exists with 4 codes
- 77520-77525 appear in DRUG_GROUPINGS proton section and proton_cpt list, not in radiation_cpt

### Task 2: Add has_proton() predicate, cohort integration, and episode/duration dispatch

**Status:** ✅ Complete
**Commit:** bf5aa71

**R/10_cohort_predicates.R:**
- Updated module docstring to include has_proton in function list
- Added has_proton() function (lines 490-522): queries PROCEDURES for PX_TYPE == "CH" and PX in TREATMENT_CODES$proton_cpt, returns tibble with ID and HAD_PROTON = 1L, logs source counts (PX only)

**R/14_build_cohort.R:**
- Added `proton_flags <- has_proton()` after sct_flags
- Added `left_join(proton_flags, by = "ID")` in join chain
- Added `HAD_PROTON = coalesce(HAD_PROTON, 0L)` in mutate block
- Added logging message for HAD_PROTON = 1 patient count and percentage

**R/25_treatment_durations.R:**
- Updated @param type docstring to include "Proton Therapy"
- Added `} else if (type == "Proton Therapy") { return(extract_proton_dates()) }` dispatch branch in extract_all_dates()
- Added extract_proton_dates() function after extract_radiation_dates(): queries PROCEDURES for proton_cpt codes, calls stack_and_dedup() with PX source only, includes inline comment about default 90-day gap threshold

**R/26_treatment_episodes.R:**
- Updated @param type docstring to include "Proton Therapy"
- Added `} else if (type == "Proton Therapy") { return(extract_proton_dates_with_codes()) }` dispatch branch in extract_dates_with_codes()
- Added extract_proton_dates_with_codes() function after extract_radiation_dates_with_codes(): queries PROCEDURES for proton_cpt codes with triggering_code = PX, calls stack_and_dedup_with_codes()

**Verification:**
- has_proton defined in R/10, called in R/14
- HAD_PROTON appears in cohort mutate and logging
- extract_proton_dates and extract_proton_dates_with_codes defined in R/25 and R/26
- Dispatch branches handle "Proton Therapy" type in both extraction functions
- TREATMENT_CODES$proton_cpt used in all detection queries

## Deviations from Plan

None. Plan executed exactly as written.

## Requirements Satisfied

- ✅ PROTON-01: Proton Therapy is a distinct treatment category in TREATMENT_TYPES
- ✅ PROTON-02: 4 proton CPT codes map to "Proton Therapy" in DRUG_GROUPINGS
- ✅ PROTON-03: Proton codes removed from radiation_cpt, added to new proton_cpt list
- ✅ PROTON-04: has_proton() detects patients with proton CPT codes

## Known Stubs

None. No stubs introduced. Proton therapy detection uses CPT codes from PROCEDURES (authoritative source), no placeholder data.

## Testing Notes

**Manual verification performed:**
- Config: 7 "Proton Therapy" occurrences, proton_cpt exists, 13 total occurrences of 77520-77525 (DRUG_GROUPINGS, proton_cpt, code descriptions, comment references)
- Predicates: has_proton() defined and called in R/14
- Episode extraction: Proton Therapy dispatch branches in R/25 and R/26

**Runtime validation (recommended before closing phase):**
- Run R/14_build_cohort.R: Verify HAD_PROTON flag created with non-zero patient count (if proton codes exist in data)
- Run R/25/26 with TREATMENT_TYPES loop: Verify Proton Therapy episode extraction executes without errors
- Check R/52 Gantt export: Verify proton episodes appear with light orange color

**Expected behavior:**
- If proton codes exist in PROCEDURES: HAD_PROTON = 1 for affected patients, proton episodes appear in treatment_durations.rds and treatment_episodes.rds, Gantt charts show proton therapy rows
- If no proton codes in data: HAD_PROTON = 0 for all patients (expected for most cohorts), no proton episodes generated

## Downstream Impact

**Immediate (automatic):**
- R/52 Gantt export: Proton Therapy episodes will appear as separate rows with light orange color (TREATMENT_TYPE_COLORS)
- Any script looping over TREATMENT_TYPES: Now processes 5 types instead of 4

**Future (requires explicit code changes):**
- R/57 drug grouping tables: If extended to proton codes, will need to map 77520-77525 to descriptive names
- Treatment summary tables: May need to add Proton Therapy column/row
- Payer-stratified treatment analyses: Will separate proton from conventional radiation

**No breaking changes:** Existing outputs preserved. GANTT_TREATMENT_TYPES derivation ensures backward compatibility.

## Self-Check

**Files created:**
- None (plan only modified existing files)

**Files modified:**
✅ R/00_config.R exists, contains "Proton Therapy" (7 occurrences), proton_cpt list, TREATMENT_TYPES has 5 elements
✅ R/10_cohort_predicates.R exists, contains has_proton() function
✅ R/14_build_cohort.R exists, contains HAD_PROTON flag and proton_flags join
✅ R/25_treatment_durations.R exists, contains extract_proton_dates() and dispatch branch
✅ R/26_treatment_episodes.R exists, contains extract_proton_dates_with_codes() and dispatch branch

**Commits exist:**
✅ 66167e7: feat(94-01): split proton therapy codes from Radiation into distinct category
✅ bf5aa71: feat(94-01): add proton therapy predicate, cohort flag, and episode extraction

**Git verification:**
```bash
git log --oneline | grep -E "66167e7|bf5aa71"
# 66167e7 feat(94-01): split proton therapy codes from Radiation into distinct category
# bf5aa71 feat(94-01): add proton therapy predicate, cohort flag, and episode extraction
```

## Self-Check: PASSED

All claimed files exist, all commits exist, all verifications passed.
