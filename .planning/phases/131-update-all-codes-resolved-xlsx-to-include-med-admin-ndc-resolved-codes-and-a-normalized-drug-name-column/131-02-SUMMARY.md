---
phase: 131-update-all-codes-resolved-xlsx-to-include-med-admin-ndc-resolved-codes-and-a-normalized-drug-name-column
plan: 02
subsystem: data-pipeline
tags: [r, dplyr, duckdb, rxnorm, ndc, medication-detection]

# Dependency graph
requires:
  - phase: 122
    provides: "get_chemo_hits() with MED_ADMIN NDC (MEDADMIN_TYPE == 'ND') crosswalk resolution and normalize_ndc()/load_ndc_crosswalk() helpers in R/utils/utils_treatment.R"
provides:
  - "get_chemo_hits() additive return_source parameter tagging PRESCRIBING / MED_ADMIN (RX) / MED_ADMIN (NDC) / DISPENSING (NDC) rows"
  - "R/50's RXNORM aggregation now queries PRESCRIBING + MED_ADMIN (RX+ND) + DISPENSING generically for all 4 RXNORM vector categories, with source-agnostic de-duplication and dynamic per-code Source Table labels"
affects: [131-03, 131-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "get_chemo_hits(..., return_source = TRUE) as the standard way to get per-row source attribution across PRESCRIBING/MED_ADMIN/DISPENSING without touching the default 3-column contract"
    - "Separate distinct()-based de-duplication for count aggregation (ID, treatment_date, code) vs. source labeling (ID, treatment_date, code, source) to avoid conflating 'how many source paths matched' with 'how many distinct administrations occurred'"

key-files:
  created: []
  modified:
    - R/utils/utils_treatment.R
    - R/50_all_codes_resolved.R

key-decisions:
  - "Guarded the all-three-NULL edge case (all of PRESCRIBING/MED_ADMIN/DISPENSING missing) before the triggering_code -> code rename, since bind_rows(NULL, NULL, NULL) yields a 0-column tibble that would error on rename() -- not explicitly covered by the plan's interface note but required for correctness under the stated 'graceful degradation' requirement"

patterns-established:
  - "Additive-parameter pattern for shared utility functions (return_raw_name, return_source): new params default FALSE, drop their column when unset, guaranteeing byte-identical output for all existing callers"

requirements-completed: [MEDXLSX-03, MEDXLSX-04, MEDXLSX-05]

# Metrics
duration: 15min
completed: 2026-07-22
---

# Phase 131 Plan 02: RXNORM MED_ADMIN/DISPENSING NDC Generalization Summary

**Generalized R/50's chemo-only, PRESCRIBING/MED_ADMIN-RX-only RXNORM detection to all 4 RXNORM vector categories across PRESCRIBING + MED_ADMIN (RX and NDC-crosswalk) + DISPENSING, with per-code dynamic Source Table labeling and de-duplicated Records/Patients counts.**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-07-22
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments
- `get_chemo_hits()` gained an additive `return_source = FALSE` parameter that tags each matched row with `"PRESCRIBING"`, `"MED_ADMIN (RX)"`, `"MED_ADMIN (NDC)"`, or `"DISPENSING (NDC)"` — all 6 existing callers (R/10, R/11, R/25, R/26, R/76, R/109) remain byte-identical since none pass the new parameter.
- R/50's Section 3 RXNORM loop was rewritten to select all 4 RXNORM vectors generically (`filter(code_type == "RXNORM")`) and to call `get_chemo_hits()` for PRESCRIBING, MED_ADMIN, and DISPENSING (the last of which R/50 had never queried before), closing the "one remaining consumer" gap explicitly deferred at the end of Phase 122.
- Records/Patients counts are now computed from a source-agnostic de-duplication on `(ID, treatment_date, code)`, preventing inflation when the same administration is reachable via more than one path (e.g., both MED_ADMIN-RX and MED_ADMIN-ND).
- `all_codes_df$source_table` for RXNORM-vector codes now reflects the real per-code detected source (e.g., `"MED_ADMIN (NDC)"` alone for codes only reachable through the new NDC path, or `"MED_ADMIN (RX), PRESCRIBING"` for codes reachable through both) instead of the old static `"PRESCRIBING|MED_ADMIN"` string that every RXNORM row carried regardless of actual detection path. Non-RXNORM (PROCEDURES/ENCOUNTER) rows are completely unaffected.

**IMPORTANT — Records-column behavioral change:** Records-column values for existing single-source codes with multiple same-day rows will decrease relative to prior `all_codes_resolved.xlsx` runs, as a direct result of the `(ID, treatment_date, code)` de-duplication. This is intended (Pitfall 2 fix — the old loop counted raw joined rows with no `distinct()`, so a code with multiple same-day PRESCRIBING or MED_ADMIN rows for one patient was over-counted), not a regression. Because `all_codes_resolved.xlsx` is shared with collaborators, this visible number change should be flagged to them alongside the newly-surfaced NDC-only codes when the workbook is next regenerated on HiPerGator.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add additive return_source parameter to get_chemo_hits()** - `c885aa9` (feat)
2. **Task 2: Rewrite R/50 Section 3 RXNORM loop to use get_chemo_hits() across PRESCRIBING/MED_ADMIN/DISPENSING for all 4 vectors, with dedup** - `c241cbd` (feat)
3. **Task 3: Wire the dynamic per-code source_table into Section 4's all_codes_df assembly** - `0705199` (feat)

## Files Created/Modified
- `R/utils/utils_treatment.R` - `get_chemo_hits()` gains `return_source = FALSE` param; each branch (PRESCRIBING, DISPENSING, MED_ADMIN rx_hits/nd_hits) tags a `source` column before combining, dropped entirely when the param is unset.
- `R/50_all_codes_resolved.R` - Section 3's RXNORM loop rewritten to call `get_chemo_hits()` 3x per vector (PRESCRIBING/MED_ADMIN/DISPENSING) with `return_source = TRUE`, de-duplicate for counts vs. source labels separately, and populate `count_results$source_table`; Section 4's `vec_df` assembly renamed the static local var to `static_source_table`, joined in `dyn_source_table`, coalesced the two, and updated the intervening `select()` to preserve `source_table` through to the final `mutate()`.

## Decisions Made
- Added a guard (`if (nrow(raw_hits) > 0)`) around the `triggering_code -> code` rename in R/50's RXNORM loop before doing any of the plan's Step 4-7 logic. This wasn't explicitly spelled out in the plan/patch text, but `bind_rows(NULL, NULL, NULL)` (the case where PRESCRIBING, MED_ADMIN, and DISPENSING are all missing/unqueryable for a given run) produces a 0-column tibble, and `rename(code = triggering_code)` on that would error rather than degrade gracefully — which the interface block explicitly requires ("keep the same graceful-degradation posture as the code being replaced").

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Guarded the all-three-NULL edge case before the triggering_code -> code rename**
- **Found during:** Task 2 (R/50 Section 3 RXNORM loop rewrite)
- **Issue:** The plan's Task 2 step 4 says `bind_rows()` "drops [NULLs] transparently... the rename still applies to whatever columns survive," which holds when at least one of the three `get_chemo_hits()` calls returns non-NULL. If all three return NULL (e.g., in an environment where PRESCRIBING, MED_ADMIN, and DISPENSING are all absent), `bind_rows(NULL, NULL, NULL)` yields a 0-row/0-column tibble, and `rename(code = triggering_code)` on it throws "Can't rename columns that don't exist," breaking the loop instead of degrading gracefully as every other branch in this script does.
- **Fix:** Split the bind and rename into two steps — `raw_hits <- bind_rows(presc_hits, medadmin_hits, dispensing_hits)` followed by `if (nrow(raw_hits) > 0) { all_hits <- raw_hits %>% rename(code = triggering_code); ... }`. When all three sources are NULL/empty, the vector is skipped for that iteration (same `next`-like effect as the plan intended for empty `codes`), matching the script's existing graceful-degradation posture.
- **Files modified:** R/50_all_codes_resolved.R
- **Verification:** Structural review of the modified block; confirmed the guard preserves identical behavior to the plan's described logic whenever at least one source returns data (the common/expected case), and only changes behavior in the previously-unhandled all-NULL edge case.
- **Committed in:** c241cbd (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking-issue prevention)
**Impact on plan:** Purely defensive; no change to intended behavior when any of PRESCRIBING/MED_ADMIN/DISPENSING is queryable (the expected production case on HiPerGator). No scope creep.

## Issues Encountered
None. A transient `git status`/`git diff` inconsistency was observed for `R/00_config.R` early in the session (likely an OneDrive sync artifact) but resolved itself on retry and was unrelated to this plan's files — confirmed clean before and after this plan's commits.

## User Setup Required
None - no external service configuration required. This plan's changes are structural-only (dev environment lacks `duckdb`/`openxlsx2`/`here`, matching the project's established dual-environment convention); runtime confirmation of the regenerated `all_codes_resolved.xlsx` numbers happens on HiPerGator per the phase's later plans/verification.

## Next Phase Readiness
- R/50 now generically detects all 4 RXNORM-based treatment vector categories across PRESCRIBING/MED_ADMIN/DISPENSING with per-code source attribution, unblocking 131-03 (which builds on this to add the normalized drug-name column) and 131-04 (verification/regeneration).
- No blockers identified for 131-03/131-04.

---
*Phase: 131-update-all-codes-resolved-xlsx-to-include-med-admin-ndc-resolved-codes-and-a-normalized-drug-name-column*
*Completed: 2026-07-22*

## Self-Check: PASSED

- FOUND: .planning/phases/131-.../131-02-SUMMARY.md
- FOUND: c885aa9 (Task 1 commit)
- FOUND: c241cbd (Task 2 commit)
- FOUND: 0705199 (Task 3 commit)
