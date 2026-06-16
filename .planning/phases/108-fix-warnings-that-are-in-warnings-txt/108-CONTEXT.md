# Phase 108: Fix warnings that are in warnings.txt - Context

**Gathered:** 2026-06-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Resolve or suppress the 14 R warnings produced during a full pipeline run (captured in `warnings.txt`). Goal is a clean warnings() output — zero warnings on a successful run, with legitimate data conditions handled silently or promoted to informative messages.

</domain>

<decisions>
## Implementation Decisions

### Warning Triage Strategy
- **D-01:** 5 "DuckDB connection already open" warnings (warnings 3,4,6,9,10) — **suppress at source** by removing the `warning()` call from `open_pcornet_con()` in `R/utils/utils_duckdb.R`. Keep the existing silent close-and-reopen behavior.
- **D-02:** "Unresolved codes empty" warning (warning 7) — **suppress at source** by removing the `warning()` call from `to_tibble_safe()` in `R/utils/utils_dt.R` when result is empty. Return empty tibble silently.
- **D-03:** 815 `summarise()` warnings about `min()` returning `Inf` for all-NA groups (warning 11) — **fix at source** by creating a `min_or_na()` safe wrapper that returns `NA` instead of `Inf + warning` when all values are `NA`. Replace `min(col, na.rm = TRUE)` calls in `summarise()` across R/13, R/11, R/02 and related files.
- **D-04:** 3 "Date < 1900-01-01" warnings (warnings 8,12,13) — **coerce pre-1900 dates to NA** during ingest or harmonization. These are SAS epoch sentinels (1899-12-30), not real dates.
- **D-05:** "23 dates outside 1990-2030 range" warning (warning 5) — **widen the valid range** in `warn_date_range()` call in R/25 to accommodate tumor registry pre-2012 dates (e.g., 1960-2030).

### Connection Cleanup
- **D-06:** `open_pcornet_con()` connection pattern — **silent close/reopen only**. Remove the `warning()` call but keep the existing close-and-reopen behavior. No connection reuse or refactoring needed.

### Data Quality Gates
- **D-07:** LAB_RESULT_CM unicode ingest failure (warning 2) — **filename mismatch confirmed**. The actual file on disk is `LAB_RESULT_Mailhot_V1.csv`. Update the filename mapping in `R/00_config.R` (or wherever the ingest maps table names to filenames) so R/03 finds the correct file. If encoding issues persist after the filename fix, try latin1/windows-1252 fallback.
- **D-08:** PROVIDER table unavailable (warning 1) — **filename mismatch confirmed**. The actual file on disk is `PROVIDER_Mailhot_V1.csv`. Update the filename mapping so the pipeline finds the correct file.
- **D-09:** TABLE-2 rows >= TABLE-1 (warning 14) — **investigate and fix the root cause**. TABLE-2 (chemo-only encounters) should be a subset of TABLE-1 (all cancer encounters). Either the TABLE-2 filter is too broad or TABLE-1 is too narrow. Fix the logic error in R/36.

### Claude's Discretion
- Exact placement of the `min_or_na()` utility function (likely `R/utils/utils_assertions.R` or a new safe-math utility)
- Whether pre-1900 date coercion happens in R/03 ingest or R/02 harmonization
- Exact widened range for `warn_date_range()` (1960-2030 or similar)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Warning Sources
- `warnings.txt` — The complete list of 14 warnings to resolve (root of this phase)

### Core Files to Modify
- `R/utils/utils_duckdb.R` — `open_pcornet_con()` connection warning (lines 128-131)
- `R/utils/utils_dt.R` — `to_tibble_safe()` empty warning (lines 104-107)
- `R/utils/utils_assertions.R` — `warn_date_range()` function (lines 177-203)
- `R/03_duckdb_ingest.R` — LAB_RESULT_CM ingest error handling (lines 145-184), filename references
- `R/13_survivorship_encounters.R` — PROVIDER table check (lines 156-177), min() in summarise (lines 102, 131, 202, 236)
- `R/36_tableau_ready_tables.R` — TABLE-2 vs TABLE-1 validation (lines 361-365)

### Scripts with min() in summarise() to Fix
- `R/02_harmonize_payer.R` — min() calls (lines 238, 248)
- `R/11_treatment_payer.R` — 30+ min() calls in summarise()
- `R/13_survivorship_encounters.R` — min() calls (lines 102, 131, 202, 236)

### Configuration
- `R/00_config.R` — Data path configuration, table filename mappings

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `suppressWarnings()` pattern already used in R/14 (lines 406-408) for arithmetic operations — established pattern for targeted suppression
- `tryCatch()` error handling wrapper in R/03 (lines 145-184) — used for per-table ingest error recovery
- `warn_date_range()` in utils_assertions.R — parameterized range check, easy to adjust bounds

### Established Patterns
- Warning messages use `[R/XX WARNING]` prefix format consistently across the codebase
- Utility functions in `R/utils/` directory (utils_duckdb.R, utils_dt.R, utils_assertions.R)
- Defensive coding with `warning()` + graceful degradation preferred over hard stops

### Integration Points
- `open_pcornet_con()` is called from multiple scripts — change at source propagates everywhere
- `to_tibble_safe()` is used across multiple scripts — same propagation
- `min_or_na()` wrapper needs to be available to R/02, R/11, R/13 (add to utils)
- R/00_config.R defines table-to-filename mappings used by R/03 ingest

</code_context>

<specifics>
## Specific Ideas

- PROVIDER and LAB_RESULT_CM warnings are **confirmed filename mismatches**. Actual filenames: `PROVIDER_Mailhot_V1.csv` and `LAB_RESULT_Mailhot_V1.csv`. The pipeline's filename mappings need updating to match these.
- The 815 min() warnings are the highest priority noise reduction — a `min_or_na()` wrapper provides a clean, reusable solution.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 108-fix-warnings-that-are-in-warnings-txt*
*Context gathered: 2026-06-16*
