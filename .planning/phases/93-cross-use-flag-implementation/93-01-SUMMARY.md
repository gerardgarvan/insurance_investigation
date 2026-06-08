---
phase: 93-cross-use-flag-implementation
plan: 01
subsystem: treatment-episode-enrichment
tags: [temporal-context, immunotherapy-confidence, sct-conditioning, metadata-annotation]
dependency_graph:
  requires: [GANTT-06, GANTT-07]
  provides: [IMMU-01, IMMU-02]
  affects: [treatment_episodes.rds, gantt_episodes_v2.csv, gantt_detail_v2.csv]
tech_stack:
  added: []
  patterns: [any-positive aggregation, temporal windowing, defensive column fallbacks]
key_files:
  created: []
  modified:
    - R/00_config.R
    - R/28_episode_classification.R
    - R/52_gantt_v2_export.R
    - R/88_smoke_test_comprehensive.R
decisions:
  - decision: "QUESTIONABLE_IMMUNO_CODES as named vector in R/00_config.R"
    rationale: "Follows DRUG_GROUPINGS pattern; centralizes questionable code definitions"
    alternatives: ["xlsx lookup", "inline in R/28"]
    outcome: "Config vector chosen for consistency with existing patterns"
  - decision: "30-day temporal window for SCT conditioning context"
    rationale: "Standard pre-transplant conditioning window per clinical protocol"
    alternatives: ["14 days", "60 days"]
    outcome: "30 days chosen; SME validation pending"
  - decision: "is_sct_conditioning_context as boolean, not categorical"
    rationale: "Only 2 states (TRUE/FALSE for chemo, NA for others); simpler than 3-category"
    alternatives: ["categorical (yes/no/NA)"]
    outcome: "Boolean chosen for clarity"
  - decision: "days_to_nearest_sct as RDS-only column"
    rationale: "Diagnostic metadata; not needed for Gantt visualization"
    alternatives: ["Export to Gantt CSVs"]
    outcome: "RDS-only to avoid cluttering Gantt exports"
metrics:
  duration: "7 minutes"
  tasks_completed: 2
  files_modified: 4
  commits: 2
  lines_added: 314
  lines_deleted: 29
  completion_date: "2026-06-08"
---

# Phase 93 Plan 01: Cross-Use Flag Implementation Summary

**One-liner:** Temporal SCT conditioning context and immunotherapy confidence flags via QUESTIONABLE_IMMUNO_CODES (11 entries: 8 vitamin, 3 CAR-T) with RDS-only days_to_nearest_sct diagnostic column.

## Objective

Add temporal context logic for SCT conditioning and immunotherapy confidence flagging to the treatment episode pipeline. Annotate chemotherapy episodes within 30 days before SCT with a conditioning context flag, and flag 11 questionable immunotherapy codes (8 vitamin combos, 3 CAR-T) with a confidence column distinguishing their ambiguity type. These are metadata annotations — no reclassification of treatment_type.

## What Was Built

### 1. QUESTIONABLE_IMMUNO_CODES Configuration (R/00_config.R)

Added named vector mapping 11 codes to confidence flag reasons:
- **8 multivitamin codes** → `"questionable-vitamin"` (RxNorm CUIs: 891815, 891790, 1090823, 1313925, 1248142, 891716, 1090824, 891793)
- **3 CAR-T codes** → `"questionable-CAR-T vs immunotherapy"` (RxNorm 2479140 Lisocabtagene Maraleucel, ICD-10-PCS XW033C3/XW043C3)

Vector placed in Section 5c after DRUG_GROUPINGS, following established config pattern.

### 2. R/28 Episode Classification Enrichment

**New function:** `aggregate_immuno_confidence()` — mirrors `aggregate_cross_use_flag()` any-positive pattern. If ANY triggering code in the episode is questionable, the episode gets the flag.

**Phase 93 enrichment block (Step 5D):**

1. **SCT temporal context computation:**
   - Extract SCT episode start dates
   - Left join chemotherapy episodes to SCT dates (`relationship = "many-to-many"`)
   - Compute `days_to_sct = sct_start - episode_start`
   - Flag episodes with `days_to_sct >= 0 & days_to_sct <= 30` (inclusive 30-day window)
   - Aggregate to `is_sct_conditioning_context` boolean and `days_to_nearest_sct` integer

2. **Column derivation:**
   - `is_sct_conditioning_context`: `NA` for non-chemotherapy, `FALSE` if chemo but no nearby SCT, `TRUE` if within 30-day window
   - `days_to_nearest_sct`: RDS-only diagnostic column (NOT exported to Gantt CSVs)
   - `immuno_confidence`: Any-positive aggregation from QUESTIONABLE_IMMUNO_CODES

3. **Validation:**
   - Pre-join row count assertion (`pre_phase93_count`) prevents join explosion
   - Log conditioning context and confidence flag counts

**Updated artifacts:**
- Final select() extended to 25 columns (22 Phase 91 + 3 Phase 93)
- stopifnot() updated to validate new column names

### 3. R/52 Gantt v2 Export Schema Extension

**Defensive column fallbacks:**
- `is_sct_conditioning_context`: defaults to `NA` if column missing
- `immuno_confidence`: defaults to `NA_character_` if column missing
- Comment notes days_to_nearest_sct is RDS-only, not exported

**Extended selects (6 locations):**
1. `episodes_export` left join from episodes
2. `episodes_export` final select
3. `episodes_v2_cols` select
4. `detail_export` final select
5. Death pseudo-row episodes mutate + select (2 locations)
6. Death pseudo-row detail mutate + select (2 locations)
7. HL Diagnosis pseudo-row episodes mutate + select (2 locations)
8. HL Diagnosis pseudo-row detail mutate + select (2 locations)
9. Final column trim select for episodes
10. Final column trim select for detail

All add `is_sct_conditioning_context, immuno_confidence` after `sct_cross_use_flag`.

**Pseudo-rows:** Death and HL Diagnosis episodes/detail set both new columns to `NA` (not treatment episodes).

**Column counts updated:**
- `expected_ep_cols <- 22` (was 21)
- `expected_detail_cols <- 20` (was 19)

**Comment strings updated:**
- Death episodes: "all 26 v2 columns (Phase 93: +2)"
- Death detail: "all 24 v2 detail columns (Phase 93: +2)"
- HL Diagnosis episodes: "all 26 v2 columns (Phase 93: +2)"
- HL Diagnosis detail: "all 24 v2 detail columns (Phase 93: +2)"

### 4. R/88 Smoke Test Section 15f

**16 validation checks:**

**Static checks (12):**
1. QUESTIONABLE_IMMUNO_CODES exists in R/00_config.R (D-05)
2. QUESTIONABLE_IMMUNO_CODES has 11 entries (8 vitamin + 3 CAR-T) (D-08)
3. R/28 defines aggregate_immuno_confidence function
4. R/28 computes is_sct_conditioning_context
5. R/28 computes immuno_confidence
6. R/28 comment updated to 25 columns (Phase 93)
7. R/52 select() includes is_sct_conditioning_context (IMMU-01)
8. R/52 select() includes immuno_confidence (IMMU-02)
9. R/52 episodes expected column count is 22 (Phase 93)
10. R/52 detail expected column count is 20 (Phase 93)
11. R/52 has guard clause for is_sct_conditioning_context
12. R/52 has guard clause for immuno_confidence

**Runtime checks (4, if treatment_episodes.rds exists):**
13. is_sct_conditioning_context flag only on Chemotherapy episodes (D-02, D-13)
14. Non-chemotherapy episodes have NA for is_sct_conditioning_context (D-04)
15. immuno_confidence contains only valid values (D-10)
16. Each episode has exactly one row (mutual exclusivity preserved, D-13)

**Section 15e updates:**
- Check 6: Updated from "21" to "22 (Phase 93)"
- Check 7: Updated from "19" to "20 (Phase 93)"

**Final summary additions:**
- `IMMU-01: immuno_confidence column flags questionable immunotherapy codes (Phase 93)`
- `IMMU-02: Distinct flag values for vitamin combos vs CAR-T ambiguity (Phase 93)`

## Verification

**Manual acceptance criteria verification:**

✓ R/00_config.R contains `QUESTIONABLE_IMMUNO_CODES <- c(` with exactly 11 entries
✓ R/00_config.R contains `"891815" = "questionable-vitamin"` (first vitamin code)
✓ R/00_config.R contains `"XW043C3" = "questionable-CAR-T vs immunotherapy"` (last CAR-T code)
✓ R/28 contains `aggregate_immuno_confidence <- function(codes_str, lookup_vec)`
✓ R/28 contains `is_sct_conditioning_context` in the Phase 93 enrichment block
✓ R/28 contains `days_to_nearest_sct` computation with `as.integer(min(days_to_sct[days_to_sct >= 0]`
✓ R/28 contains `left_join(sct_dates, by = "patient_id", relationship = "many-to-many")`
✓ R/28 contains `days_to_sct >= 0 & days_to_sct <= 30` (inclusive 30-day window per D-01)
✓ R/28 contains `treatment_type != "Chemotherapy" ~ NA` for conditioning flag (D-04)
✓ R/28 final select() includes `is_sct_conditioning_context, days_to_nearest_sct, immuno_confidence`
✓ R/28 stopifnot includes `"is_sct_conditioning_context"` and `"immuno_confidence"`
✓ R/28 comment says "25 columns per Phase 93" (22 Phase 91 + 3 new)
✓ R/28 contains `pre_phase93_count` row count validation after temporal join
✓ R/52 contains `expected_ep_cols <- 22` (was 21)
✓ R/52 contains `expected_detail_cols <- 20` (was 19)
✓ R/52 contains `!"is_sct_conditioning_context" %in% names` defensive fallback
✓ R/52 contains `!"immuno_confidence" %in% names` defensive fallback
✓ R/52 death_episodes mutate contains `is_sct_conditioning_context = NA`
✓ R/52 death_episodes mutate contains `immuno_confidence = NA_character_`
✓ R/52 hl_dx_episodes mutate contains `is_sct_conditioning_context = NA`
✓ R/52 hl_dx_episodes mutate contains `immuno_confidence = NA_character_`
✓ R/52 final episodes_export select() ends with `is_sct_conditioning_context, immuno_confidence`
✓ R/52 final detail_export select() ends with `is_sct_conditioning_context, immuno_confidence`
✓ R/88 contains `SECTION 15f: PHASE 93 CROSS-USE FLAG VALIDATION`
✓ R/88 contains `QUESTIONABLE_IMMUNO_CODES` check (Check 1)
✓ R/88 contains `length(QUESTIONABLE_IMMUNO_CODES) == 11` (Check 2)
✓ R/88 contains `expected_ep_cols <- 22` in Section 15f Check 9
✓ R/88 contains `expected_detail_cols <- 20` in Section 15f Check 10
✓ R/88 Section 15e checks updated to expect 22/20 (not 21/19)
✓ R/88 final summary contains `IMMU-01` and `IMMU-02` lines

**Automated verification:** Smoke test cannot run locally (Rscript not available), but all static checks verified via grep.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all columns are fully wired. `is_sct_conditioning_context` and `immuno_confidence` are metadata annotations derived from existing data; no data sources missing.

## Commits

1. **57bd224**: `feat(93-01): add QUESTIONABLE_IMMUNO_CODES config and enrich R/28 with temporal context + confidence columns` (Task 1)
   - Files: R/00_config.R, R/28_episode_classification.R
   - Added: QUESTIONABLE_IMMUNO_CODES vector (11 entries), aggregate_immuno_confidence() function, Phase 93 enrichment block, 3 new columns in final select, stopifnot update

2. **d2eaa4d**: `feat(93-01): extend Gantt v2 export schema and add smoke test Section 15f` (Task 2)
   - Files: R/52_gantt_v2_export.R, R/88_smoke_test_comprehensive.R
   - Added: Defensive fallbacks, 2 new columns in 10 select locations, updated column counts (22/20), smoke test Section 15f with 16 checks, updated Section 15e checks 6-7

## Self-Check: PASSED

**Files created:** 0 (none)

**Files modified:** 4
- [x] R/00_config.R exists
- [x] R/28_episode_classification.R exists
- [x] R/52_gantt_v2_export.R exists
- [x] R/88_smoke_test_comprehensive.R exists

**Commits:** 2
- [x] 57bd224 exists
- [x] d2eaa4d exists

All artifacts verified present. All acceptance criteria met.

## Next Steps

1. **Run R/28 on HiPerGator** to generate updated treatment_episodes.rds with 25 columns
2. **Run R/52 on HiPerGator** to generate Gantt v2 CSVs with 22/20-column schemas
3. **Run R/88 smoke test on HiPerGator** to validate runtime checks (13-16 in Section 15f)
4. **Review SCT conditioning flags** — validate 30-day window with clinical SME
5. **Review CAR-T classification** — determine if 3 CAR-T codes should remain flagged as "questionable" or be reclassified

## Implementation Notes

- **Treatment type mutual exclusivity preserved:** No reclassification (D-13). Flags are annotations only.
- **Temporal context computation:** many-to-many join explicitly specified to avoid cartesian product warnings
- **Backward compatibility:** Defensive fallbacks ensure R/52 runs even if Phase 93 R/28 not yet executed
- **RDS-only column:** `days_to_nearest_sct` diagnostic metadata not exported to Gantt CSVs to avoid clutter
- **Any-positive aggregation:** Follows established `aggregate_cross_use_flag()` pattern; first matching flag wins
- **HIPAA compliance:** No patient-level data in SUMMARY; only counts logged in R/28 messages

---

**Phase 93 Plan 01 execution complete. IMMU-01 and IMMU-02 requirements satisfied.**
