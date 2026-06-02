# Phase 72: Defensive Coding - Context

**Gathered:** 2026-06-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 72 adds checkmate assertions and input validation to the production pipeline scripts (decades 00-69). This covers file existence checks before data loads, data structure validation after critical loads/joins, column type checks for key identifiers, value range warnings for dates, and informative error messages using glue(). The phase does NOT modify existing tryCatch/stopifnot patterns, does NOT touch test scripts (80-87) or ad-hoc scripts (90-99), and does NOT change any pipeline behavior — it only adds fail-fast guards and warning diagnostics.

</domain>

<decisions>
## Implementation Decisions

### Validation Scope
- **D-01:** Assertions added to foundation (00-03), cohort (10-14), treatment (20-29), cancer (40-53), and payer/QA (60-69) scripts — approximately 40 production scripts.
- **D-02:** Test scripts (80-87) and ad-hoc scripts (90-99) are excluded from this phase. They are diagnostic/one-off and handle their own errors or run interactively.
- **D-03:** Output scripts (70-75) are excluded — they are visualization/report generators, not critical data pipeline steps.

### checkmate Integration
- **D-04:** Load checkmate once in R/00_config.R via `library(checkmate)`. Since every production script sources 00_config.R (directly or via chain), checkmate is available everywhere without per-script library() calls.
- **D-05:** Leave all ~30 existing tryCatch calls and 2 stopifnot calls (R/13, R/28) as-is. They serve different purposes (error recovery vs fail-fast). Add NEW checkmate assertions at script entry points and after critical loads/joins. No refactoring of working defensive code.
- **D-06:** Add checkmate to renv.lock via `renv::install("checkmate")` and `renv::snapshot()` for HiPerGator reproducibility.

### Assertion Depth
- **D-07:** Full validation: file/RDS existence + data frame structure + critical column presence + key identifier types + row-count sanity checks + date value range warnings.
- **D-08:** Column type checks for key identifiers only: PATID (character), ENCOUNTERID (character), date columns (Date class), numeric counts. Not all columns — only those that cause silent bugs when types are wrong.
- **D-09:** Date range validation uses 1990-2030 boundaries. Dates outside this range are flagged as warnings. Pre-2012 dates are legitimately present in tumor registry data (per existing historical_flag in R/26).
- **D-10:** Two severity levels — hard stops vs warnings:
  - **Hard stops (stop()):** File existence, data frame structure, required column presence, column type mismatches. These indicate the pipeline cannot proceed.
  - **Warnings (warning()):** Date range violations, unexpected row counts (e.g., zero rows after join, suspiciously large cartesian products). Pipeline continues but flags suspicious data.

### Error Message Style
- **D-11:** All messages follow the pattern: `[R/XX ACTION] What failed — expected vs actual — fix hint`. Uses glue() for interpolation. Examples:
  - Error: `[R/26 ERROR] Expected treatment_durations.rds at {path} -- run R/25_treatment_durations.R first`
  - Warning: `[R/26 WARNING] 15 dates outside 1990-2030 range in treatment_episodes`
- **D-12:** Warnings use the same glue() template as errors but with WARNING prefix instead of ERROR. Consistent format across all assertion messages.
- **D-13:** Create R/utils/utils_assertions.R with helper functions to reduce boilerplate:
  - `assert_rds_exists(path, script_name)` — checks file exists, fails with context + fix hint
  - `assert_df_valid(df, name, required_cols, script_name)` — checks data frame, columns, non-empty
  - `assert_col_types(df, type_spec, script_name)` — validates key column types
  - `warn_date_range(df, col, lo, hi, script_name)` — warns on out-of-range dates
  - `warn_row_count(df, name, min_expected, max_expected, script_name)` — warns on suspicious counts
  Auto-sourced by 00_config.R alongside other utils modules.

### Claude's Discretion
- Exact assertion placement within each script (after which specific load/join operations)
- Which specific columns constitute "key identifiers" in each table beyond PATID/ENCOUNTERID
- Row count thresholds for sanity checks (what counts as "suspiciously large" per join)
- Whether to batch assertions by script or by assertion type across plans
- Internal structure of utils_assertions.R helper functions
- Wave/plan decomposition strategy

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` — SAFE-01 (file existence validation), SAFE-02 (data structure validation), SAFE-03 (error messages with glue context)

### Script Inventory
- `R/SCRIPT_INDEX.md` — Canonical listing of all 67 numbered scripts + 8 utils + 8 archived. Identifies which scripts are in scope (decades 00-69).

### Configuration
- `R/00_config.R` — Foundation config where checkmate library() call will be added. Also the auto-sourcing mechanism for utils/ modules.
- `.lintr` — Current lintr configuration. New assertion code must pass lintr (150-char lines, magrittr pipe standard).

### Predecessor Phases
- `.planning/phases/71-linting-cleanup/71-CONTEXT.md` — Pipe standard (%>%), line length (150), disabled rules. New code must comply.
- `.planning/phases/70-automated-formatting/70-CONTEXT.md` — styler formatting applied. New code will need styler pass.

### Existing Defensive Patterns
- `R/10_cohort_predicates.R` — 18+ tryCatch patterns for DuckDB NULL-guards (DO NOT modify)
- `R/03_duckdb_ingest.R` — 6 tryCatch patterns for ingest error recovery (DO NOT modify)
- `R/13_survivorship_encounters.R` — stopifnot at line 64 (leave as-is)
- `R/28_episode_classification.R` — stopifnot at line 702 (leave as-is)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/utils/` directory with 8 existing modules — established pattern for adding utils_assertions.R
- `R/00_config.R` auto-sources all `R/utils/utils_*.R` files — new module will be picked up automatically
- `glue` package already loaded in most production scripts — available for error messages
- Existing tryCatch patterns in R/10, R/03, R/02, R/21, R/22, R/27 demonstrate the codebase's error handling style

### Established Patterns
- Scripts use `source("R/XX_name.R")` chains for dependency loading
- RDS caching at `/blue/erin.mobley-hl.bcu/clean/rds/` paths configured in CONFIG$rds_dir
- Header blocks follow Phase 69 `# ==============` box-style format
- Section headers use `# SECTION N: TITLE ----` format

### Integration Points
- `R/00_config.R` — add `library(checkmate)` call
- `R/utils/` — add `utils_assertions.R` module
- `renv.lock` — add checkmate dependency
- Each in-scope script (00-69) — add assertion calls at entry and after critical loads
- Smoke test (R/87) — should pass after all assertions added (no false positives on valid data)

</code_context>

<specifics>
## Specific Ideas

No specific requirements — standard defensive coding with decisions captured above.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 72-defensive-coding*
*Context gathered: 2026-06-02*
