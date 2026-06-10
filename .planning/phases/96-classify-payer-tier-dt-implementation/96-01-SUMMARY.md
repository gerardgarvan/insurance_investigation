---
phase: 96-classify-payer-tier-dt-implementation
plan: 01
subsystem: infra
tags: [data.table, fcase, keyed-joins, payer-classification, performance]

# Dependency graph
requires:
  - phase: 95-infrastructure-setup
    provides: "ensure_dt(), to_tibble_safe(), get_lookup_dt(), LOOKUP_TABLES_DT keyed tables"
provides:
  - "classify_payer_tier_dt() function in R/utils/utils_payer.R"
  - "R/96_validate_payer_dt.R parity validation script (41 checks)"
  - "tbl_lazy handling in ensure_dt() for DuckDB lazy table inputs"
affects: [97-r60-hot-path-migration, 98-remaining-lookup-optimization]

# Tech tracking
tech-stack:
  added: []
  patterns: ["fcase() for multi-branch conditionals in data.table context", "copy(ensure_dt()) reference semantics defense pattern", "keyed join update syntax X[Y, on=, col := i.col]", "unname() for comparing dplyr named-vector output vs data.table keyed-join output"]

key-files:
  created:
    - "R/96_validate_payer_dt.R"
  modified:
    - "R/utils/utils_payer.R"
    - "R/utils/utils_dt.R"

key-decisions:
  - "Return tibble (not data.table) for dplyr pipeline compatibility with R/60, R/61, R/62 callers"
  - "Use unname() in parity comparisons to handle names attribute difference between dplyr named-vector lookups and data.table keyed joins"
  - "Add tbl_lazy handling in ensure_dt() to support DuckDB lazy table inputs (nrow() returns NA on lazy tables)"
  - "Adjusted fixture codes: replaced 119/523 (not in AMC_PAYER_LOOKUP) with 11/511 (actual direct lookup codes) for proper code path coverage"

patterns-established:
  - "fcase() with default= for all multi-branch conditionals in data.table functions"
  - "copy(ensure_dt(df)) as first line of data.table utility functions for reference semantics defense"
  - "get_lookup_dt() keyed join pattern for AMC_PAYER_LOOKUP and TIER_MAPPING"
  - "unname() wrapper for identical() comparisons between dplyr and data.table outputs"

requirements-completed: [PAYER-01, PAYER-02]

# Metrics
duration: 15min
completed: 2026-06-10
---

# Phase 96 Plan 01: classify_payer_tier_dt() Implementation Summary

**data.table variant of classify_payer_tier() using fcase() and keyed joins, validated with 41-check parity script on fixture and production ENCOUNTER data**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-06-10T22:14:57Z
- **Completed:** 2026-06-10T22:30:00Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- Implemented classify_payer_tier_dt() (187 lines) alongside existing dplyr version in R/utils/utils_payer.R, using 8 fcase() calls, 2 keyed joins, copy() defense at entry, tibble return
- Created R/96_validate_payer_dt.R (313 lines) with 19-row fixture covering all edge cases and 41 validation checks across 9 sections
- Validated output parity on both fixture data (41/41 checks pass) and production ENCOUNTER data (1000 rows, all columns identical)
- Fixed ensure_dt() to handle DuckDB tbl_lazy inputs (nrow() returns NA on lazy tables)

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement classify_payer_tier_dt()** - `52d547a` (feat)
2. **Task 2: Create R/96_validate_payer_dt.R** - `041c574` (feat)
3. **Task 3: Verify parity validation on user environment** - User checkpoint (approved)
   - Fix: unname() in parity comparisons - `e39ff10` (fix, user-committed during checkpoint)
   - Fix: tbl_lazy handling in ensure_dt() - `48b7207` (fix, user-committed during checkpoint)

## Files Created/Modified
- `R/utils/utils_payer.R` - Added classify_payer_tier_dt() function (187 new lines, existing code unchanged)
- `R/96_validate_payer_dt.R` - Standalone parity validation script (313 lines, 41 checks)
- `R/utils/utils_dt.R` - Added tbl_lazy handling in ensure_dt() (+5 lines)

## Decisions Made
- **Return tibble:** classify_payer_tier_dt() returns tibble (not data.table) for compatibility with R/60, R/61, R/62 which use dplyr pipelines downstream
- **Fixture code adjustment:** Replaced "119" and "523" (not in AMC_PAYER_LOOKUP) with "11" (Medicare) and "511" (Private) to properly test direct AMC lookup code path alongside prefix fallback
- **unname() for parity:** dplyr's named-vector lookup (AMC_PAYER_LOOKUP[effective_payer]) preserves names attribute; data.table keyed joins produce unnamed vectors. Values are identical but identical() checks attributes. unname() resolves this.
- **tbl_lazy guard:** DuckDB lazy tables return NA from nrow(), causing ensure_dt() to error. Added inherits(df, "tbl_lazy") check with dplyr::collect() before conversion.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixture codes not in AMC_PAYER_LOOKUP**
- **Found during:** Task 2 (fixture construction)
- **Issue:** Plan specified "119" and "523" as "Direct AMC lookup" codes, but they are not in AMC_PAYER_LOOKUP (would fall through to prefix fallback, not testing direct lookup)
- **Fix:** Replaced with "11" (Medicare, in lookup) and "511" (Private, in lookup) per plan's own instruction to adjust codes
- **Files modified:** R/96_validate_payer_dt.R
- **Verification:** Fixture now properly exercises both direct lookup AND prefix fallback code paths
- **Committed in:** 041c574 (Task 2 commit)

**2. [Rule 1 - Bug] Names attribute mismatch in parity comparison**
- **Found during:** Task 3 (user checkpoint)
- **Issue:** dplyr's AMC_PAYER_LOOKUP[effective_payer] and unlist(TIER_MAPPING[tier]) produce named vectors; data.table keyed joins produce unnamed vectors. identical() fails due to attribute difference despite identical values.
- **Fix:** Added unname() wrapper around dplyr column references in parity comparisons
- **Files modified:** R/96_validate_payer_dt.R
- **Committed in:** e39ff10 (user-committed during checkpoint)

**3. [Rule 3 - Blocking] DuckDB lazy table causes ensure_dt() error**
- **Found during:** Task 3 (user checkpoint, production data test)
- **Issue:** get_pcornet_table() returns tbl_lazy objects from DuckDB. nrow() on a lazy table returns NA, causing `if (nrow(df) == 0)` to error with "missing value where TRUE/FALSE needed"
- **Fix:** Added inherits(df, "tbl_lazy") check at top of ensure_dt() to collect() before proceeding
- **Files modified:** R/utils/utils_dt.R
- **Committed in:** 48b7207 (user-committed during checkpoint)

---

**Total deviations:** 3 auto-fixed (2 bugs, 1 blocking)
**Impact on plan:** All fixes necessary for correctness. No scope creep. The unname() and tbl_lazy fixes were discovered during user verification on production data -- exactly the scenario the checkpoint was designed to catch.

## Issues Encountered
- Names attribute difference between dplyr named-vector lookups and data.table keyed joins was not anticipated in the plan. This is a systematic difference that Phase 97-98 should be aware of when comparing outputs.
- DuckDB lazy table handling was not covered by Phase 95 infrastructure (fixture-only testing). Production data exposed the gap.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None. All functionality is fully wired and validated.

## Next Phase Readiness
- classify_payer_tier_dt() is validated and ready for Phase 97 (R/60 hot-path migration)
- ensure_dt() now handles DuckDB lazy tables, removing a blocker for Phase 97-98 production use
- unname() pattern documented for future parity comparisons in Phase 97-98 validation scripts
- No existing callers (R/60, R/61, R/62) were modified -- they continue using classify_payer_tier() until their own migration phases

## Self-Check: PASSED

- [x] R/utils/utils_payer.R exists and contains classify_payer_tier_dt
- [x] R/96_validate_payer_dt.R exists and contains 41 checks
- [x] R/utils/utils_dt.R exists with tbl_lazy handling
- [x] 96-01-SUMMARY.md created
- [x] Commit 52d547a found (Task 1)
- [x] Commit 041c574 found (Task 2)
- [x] Commit e39ff10 found (checkpoint fix: unname)
- [x] Commit 48b7207 found (checkpoint fix: tbl_lazy)

---
*Phase: 96-classify-payer-tier-dt-implementation*
*Completed: 2026-06-10*
