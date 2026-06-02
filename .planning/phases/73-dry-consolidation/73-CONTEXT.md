# Phase 73: DRY Consolidation - Context

**Gathered:** 2026-06-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 73 consolidates duplicated lookup tables to R/00_config.R (DRY-01) and extracts repeated code patterns into shared utility functions in R/utils/ (DRY-02). Five targets are in scope: PREFIX_MAP consolidation (11 files), TIER_MAPPING consolidation (3 files), classify_codes() extraction (10 files), payer tier classification extraction (3 files), and file I/O helper creation (56 files). This phase does NOT modify pipeline behavior, add new features, or change any outputs — it only eliminates duplication while preserving identical behavior.

</domain>

<decisions>
## Implementation Decisions

### Consolidation Scope (DRY-01 + DRY-02)
- **D-01:** All five duplication targets are in scope: PREFIX_MAP, TIER_MAPPING, classify_codes(), payer tier logic, and file I/O helpers. No targets deferred.
- **D-02:** PREFIX_MAP (324-entry cancer site classification table) moves to R/00_config.R as `CANCER_SITE_MAP`. Currently duplicated in 11 files (~2,860 lines): R/28, R/40, R/43, R/44, R/45, R/46, R/47, R/48, R/49, R/51, R/52.
- **D-03:** TIER_MAPPING (8-item payer hierarchy) moves to R/00_config.R under existing payer config section. Currently in R/60, R/61, R/62.
- **D-04:** Old copies of PREFIX_MAP and TIER_MAPPING deleted in same commit as consolidation (per success criteria #4).

### Utility Organization (DRY-02)
- **D-05:** `classify_codes()` function moves to new `R/utils/utils_cancer.R`. Dedicated file for cancer-specific utilities, matching domain separation of existing utils_payer.R and utils_treatment.R.
- **D-06:** Payer tier classification logic extracted to existing `R/utils/utils_payer.R` (which already has is_missing_payer(), CODE_TO_TIER(), field_match()). Keeps all payer logic in one place.
- **D-07:** File I/O helper (`build_output_path()`) added to existing `R/utils/utils_snapshot.R` (which already has save_output_data()). Groups all output-related helpers together.

### Payer Logic Extraction
- **D-08:** Full row-level classification extracted as single `classify_payer_tier(df)` function. Covers the entire mutate chain: effective_payer resolution, dual_eligible flag, payer_category mapping, and tier assignment. Each of R/60, R/61, R/62 calls it once. Scripts retain their own grouping/summarization logic (same-day vs encounter-level vs date-level).

### File I/O Helper
- **D-09:** `build_output_path(subdir, filename)` returns the full path AND auto-creates parent directories. One call replaces two lines (file.path + dir.create). Applied across the 56 files that use the repeated pattern.

### Claude's Discretion
- Internal structure of CANCER_SITE_MAP in R/00_config.R (section placement, naming convention)
- How classify_payer_tier() handles minor differences between R/60, R/61, R/62 (parameters vs conditional logic)
- Wave/plan decomposition strategy and execution order
- Which of the 56 file I/O sites to convert in Phase 73 vs leave as low-priority cleanup
- Smoke test validation approach for constants and utility functions

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` -- DRY-01 (consolidate lookup tables), DRY-02 (extract repeated patterns)

### Script Inventory
- `R/SCRIPT_INDEX.md` -- Canonical listing of all 67 numbered scripts + utils + archived

### Configuration and Utilities
- `R/00_config.R` -- Foundation config where CANCER_SITE_MAP and TIER_MAPPING will be added. Auto-sources R/utils/*.R modules. Already contains ICD_CODES, PAYER_MAPPING, AMC_PAYER_LOOKUP, TREATMENT_CODES, ANALYSIS_PARAMS.
- `R/utils/utils_payer.R` -- Existing payer utilities (is_missing_payer, CODE_TO_TIER, field_match). Will receive classify_payer_tier().
- `R/utils/utils_snapshot.R` -- Existing output helpers (save_output_data). Will receive build_output_path().

### Duplication Targets (read to understand current state)
- `R/28_episode_classification.R` -- PREFIX_MAP + classify_codes() at line ~98
- `R/40_cancer_site_frequency.R` -- PREFIX_MAP + classify_codes() at line ~64
- `R/43_cancer_site_confirmation.R` -- PREFIX_MAP + classify_codes() at line ~50
- `R/44_cancer_site_confirmation_7day.R` -- PREFIX_MAP + classify_codes() at line ~50
- `R/45_cancer_summary.R` -- PREFIX_MAP + classify_codes() at line ~62
- `R/46_cancer_summary_table.R` -- PREFIX_MAP + classify_codes() at line ~59
- `R/47_cancer_summary_refined.R` -- PREFIX_MAP + classify_codes() at line ~81
- `R/48_cancer_summary_post_hl.R` -- PREFIX_MAP + classify_codes() at line ~81
- `R/49_cancer_summary_pre_post.R` -- PREFIX_MAP + classify_codes() at line ~73
- `R/51_gantt_data_export.R` -- PREFIX_MAP + classify_codes() at line ~108
- `R/52_gantt_v2_export.R` -- PREFIX_MAP + classify_codes()
- `R/60_tiered_same_day_payer.R` -- TIER_MAPPING + payer classification logic at line ~71
- `R/61_tiered_encounter_level.R` -- TIER_MAPPING + payer classification logic
- `R/62_tiered_date_level.R` -- TIER_MAPPING + payer classification logic

### Predecessor Phases
- `.planning/phases/72-defensive-coding/72-CONTEXT.md` -- Assertion patterns, utils_assertions.R. New code must follow same patterns.
- `.planning/phases/71-linting-cleanup/71-CONTEXT.md` -- Pipe standard (%>%), line length (150), disabled linter rules.
- `.planning/phases/70-automated-formatting/70-CONTEXT.md` -- styler formatting. New code needs styler pass.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/utils/` directory with 9 modules -- established pattern for adding utils_cancer.R
- `R/00_config.R` auto-sources all `R/utils/utils_*.R` files -- new module picked up automatically
- `utils_payer.R` already has 3 payer utility functions -- natural home for classify_payer_tier()
- `utils_snapshot.R` already has save_output_data() -- natural home for build_output_path()

### Established Patterns
- Constants in R/00_config.R use named lists/vectors: ICD_CODES, PAYER_MAPPING, AMC_PAYER_LOOKUP, TREATMENT_CODES
- Utility functions follow `function_name <- function(params)` style with roxygen-lite comments
- Scripts use `source("R/00_config.R")` or are in the source chain, so all config + utils available
- New utility modules auto-discovered by `R/00_config.R` glob pattern on `R/utils/utils_*.R`

### Integration Points
- `R/00_config.R` -- add CANCER_SITE_MAP and TIER_MAPPING constants
- `R/utils/utils_cancer.R` -- new file with classify_codes()
- `R/utils/utils_payer.R` -- add classify_payer_tier() function
- `R/utils/utils_snapshot.R` -- add build_output_path() function
- 11 cancer scripts -- remove PREFIX_MAP + classify_codes(), replace with centralized references
- 3 payer scripts -- remove TIER_MAPPING + classification chain, replace with classify_payer_tier() call
- 56 output scripts -- replace dir.create + file.path with build_output_path()
- `R/87_smoke_test.R` -- validate no duplicate constant definitions remain

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- standard DRY consolidation with decisions captured above.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 73-dry-consolidation*
*Context gathered: 2026-06-02*
