---
phase: 139-zip-stability-imputation-occurrence-counts
plan: 01
subsystem: data
tags: [r, dplyr, vroom, zip-normalization, address-history, pcornet]

# Dependency graph
requires:
  - phase: 137-zip9-temporal-lookup
    provides: normalize_zip9()/normalize_zip5()/normalize_zip5_raw() in R/utils/utils_address.R, get_zip9_at_date()
provides:
  - is_sentinel_zip5() utility function in R/utils/utils_address.R
  - R/115_zip_stability_counts.R (new investigation script) through Part A-05
  - addr_coal column contract (period_start_dt, period_end_dt, period_end_open, period_end_eff, zip9_norm, zip5_coalesced) reused by Plans 02/03/04
  - coalesce_zip5() single ZIP5-coalescing implementation in SECTION 1B, reusable by later plans
  - patient_stability tibble (n_distinct_zip9/zip5, n_zip9/zip5_transitions, n_plus4_only_transitions, obs_span_years, zip9_transitions_per_patient_year)
  - gap_days_summary object (median/p25/p75/min/max/deciles/histogram/dx-window reference)
affects: [139-02-validation-curve, 139-03-encounter-zip-classification, 139-04-xlsx-assembly-and-c02]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SECTION 1B testable-function prelude placed before the probe gate so sys.source() can capture pure functions even when the source CSV is absent"
    - "coalesce_zip5() as the single named ZIP5-coalescing implementation (raw column preferred, ZIP9-derived fallback), reused rather than re-derived by later plans"
    - "period_end_dt (NA-preserving) vs period_end_eff (sentineled) split so interval-matching consumers and exposure-span math never accidentally use the wrong one"
    - "Dual probe gate: CSV probe first (Windows-safe graceful quit), then DuckDB/ENCOUNTER connection bootstrap only reached after the CSV gate passes"

key-files:
  created:
    - R/115_zip_stability_counts.R
  modified:
    - R/utils/utils_address.R

key-decisions:
  - "is_sentinel_zip5() added as a new sibling function in utils_address.R; get_zip9_at_date() left byte-for-byte unchanged (verified via git diff)"
  - "ZIP5 coalescing implemented as exactly one function (coalesce_zip5(), in R/115's SECTION 1B), not inline and not inside utils_address.R -- satisfies 139-05-PATCH's single-implementation requirement"
  - "Script stops loudly (prints available columns, quits) if raw ADDRESS_ZIP5 is absent, rather than silently degrading to derived-from-ZIP9-only (FIX-04a)"
  - "period_end_dt keeps NA for open-ended records; period_end_eff (sentineled to 9999-12-31) is a separate follow-up column used only for interval-matching, not for exposure-span math (FIX-02)"
  - "Exposure-span math (A-04) uses period_end_eff capped at DATA_THROUGH (alias for ZIP_STUDY_PERIOD_MAX), not the far-future sentinel directly and not period_start_dt alone (FIX-04b)"
  - "Tie-break for spell ordering uses desc(period_end_eff), not period_end_dt, because dplyr::arrange() always sorts NA last regardless of direction"
  - "gap_days_summary includes deciles (quantile at 10%-90%) in addition to median/p25/p75/min/max/histogram, satisfying A-05's explicit requirement"
  - "Console headline stats report median and %zero-transition, never a mean (Pitfall 6)"

patterns-established:
  - "Pattern: SECTION 1B prelude for pure, testable functions defined before any probe gate in investigation scripts that will later gain a testthat file"

requirements-completed: [A-01, A-02, A-03, A-04, A-05]

# Metrics
duration: 25min
completed: 2026-08-05
---

# Phase 139 Plan 01: ZIP Stability Foundation Summary

**Added is_sentinel_zip5() to utils_address.R and created R/115_zip_stability_counts.R through Part A-05, computing per-patient ZIP9/ZIP5 transition counts, plus4-only transitions, exposure-denominator rates, and gap-time distributions (with deciles) from a single-source coalesce_zip5() ZIP5 implementation.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-08-05T17:56:47Z (approx, per STATE.md session start)
- **Completed:** 2026-08-05
- **Tasks:** 3 completed
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments
- `is_sentinel_zip5()` added to `R/utils/utils_address.R` as a new sibling function (00000/99999/any single-repeated-digit ZIP5 flagged as sentinel, NA passed through as NA), with `get_zip9_at_date()` left completely unmodified
- `R/115_zip_stability_counts.R` created with header, SECTION 1B pure-function prelude (`coalesce_zip5()`), dual probe gate (CSV then ENCOUNTER/DuckDB), and ZIP5-coalesced address load with sentinel/date filtering, each drop logged
- Part A-01/A-02/A-03/A-04/A-05 per-patient metrics computed: independent NA-dropped-then-deduped ZIP9/ZIP5 spell sequences, transitions, plus4-only transitions, exposure-denominator rate (period_end_eff capped at DATA_THROUGH, divide-by-zero guarded), and gap-time distribution (`gap_days_summary` with deciles)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add is_sentinel_zip5() to R/utils/utils_address.R** - `afba16a` (feat)
2. **Task 2: Create R/115_zip_stability_counts.R -- header, SECTION 1B prelude, dual probe gate, address load with ZIP5 coalescing, sentinel/date filtering** - `a7ea636` (feat)
3. **Task 3: Part A-01/A-02/A-03/A-04/A-05 -- spell dedup, transitions, exposure denominator, gap-time distribution** - `1fa3821` (feat)

**Plan metadata:** (this commit, following SUMMARY.md creation)

## Files Created/Modified
- `R/utils/utils_address.R` - Added `is_sentinel_zip5()` (sibling function) and updated the header Outputs comment; `get_zip9_at_date()` unchanged
- `R/115_zip_stability_counts.R` - New investigation script: header, SECTION 1B (`coalesce_zip5()`), SECTION 2 (constants + dual probe gate), SECTION 3 (address load, ZIP5 coalescing, sentinel/date filtering), SECTION 4 (spell dedup + transition metrics), SECTION 5 (exposure denominator), SECTION 6 (gap-time distribution + deciles), SECTION 7 (console headline stats)

## Decisions Made
See `key-decisions` in frontmatter above for the full list. Most consequential: the loud-stop-on-missing-ADDRESS_ZIP5 behavior (FIX-04a) and the period_end_dt/period_end_eff split (FIX-02), both mandated by 139-05-PATCH.md and implemented exactly as specified.

## Deviations from Plan

None - plan executed exactly as written. All 139-05-PATCH.md amendments (FIX-02, FIX-04a, FIX-04b, FIX-05) were already incorporated into the plan text itself and implemented as specified; no additional deviations were needed during execution.

## Issues Encountered

None. `Rscript` was not on PATH in the execution shell; resolved by invoking the full path to `Rscript.exe` under the installed R 4.4.1 distribution (`C:/Program Files/R/R-4.4.1/bin/Rscript.exe`) for all verification commands. This is an environment-discovery note, not a plan deviation -- no source files were changed as a result.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `addr_coal`'s column contract (period_start_dt, period_end_dt, period_end_open, period_end_eff, zip9_norm, zip5_coalesced) is established and ready for Plan 02 (validation curve), Plan 03 (encounter ZIP classification), and Plan 04 (xlsx assembly + C-02) to build on without re-deriving it
- `coalesce_zip5()` in SECTION 1B is the single reusable ZIP5-coalescing implementation; Plan 04's C-02 pre-filter comparison can call it directly against `addr_raw`
- `gap_days_summary` is assembled and named exactly as Plan 04's Task 2 expects
- `tests/testthat/test-115-validation-curve.R` (added in Plan 02) can `sys.source()` this file and capture SECTION 1B's pure functions even though the probe gate quits when run standalone without `LDS_ADDRESS_HISTORY` present
- No xlsx write yet by design -- deferred to Plan 04 once all sheets' data exists
- Runtime verification (loading the real CSV, opening DuckDB, computing metrics against real data) requires HiPerGator; only structural/parse-level verification was possible in this Windows environment, consistent with the plan's stated scope

---
*Phase: 139-zip-stability-imputation-occurrence-counts*
*Completed: 2026-08-05*

## Self-Check: PASSED

- FOUND: R/utils/utils_address.R
- FOUND: R/115_zip_stability_counts.R
- FOUND commit: afba16a
- FOUND commit: a7ea636
- FOUND commit: 1fa3821
