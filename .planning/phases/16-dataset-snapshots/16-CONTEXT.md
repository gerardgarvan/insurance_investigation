# Phase 16: Dataset Snapshots - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Save cohort snapshots at each filter step, final outputs, and figure/table backing datasets as RDS files to `/blue/erin.mobley-hl.bcu/clean/rds/` subdirectories. Add a shared `save_output_data()` helper for consistent snapshot creation. This phase touches `04_build_cohort.R` (cohort snapshots), all 4 visualization scripts (backing data), and adds a new `utils_snapshot.R` utility file.

This phase does NOT modify the cache-check/load logic from Phase 15 or add any new analysis capabilities.

</domain>

<decisions>
## Implementation Decisions

### Snapshot Granularity
- **D-01:** Snapshot only the filter steps that change patient count: step 0 (initial population), step 1 (HL flag applied), step 2 (has enrollment), plus final cohort + attrition log. ~4-5 cohort RDS files total.
- **D-02:** Enrichment stages (payer join, treatment flags, surveillance, survivorship) do NOT get snapshots — they add columns but keep the same rows.
- **D-03:** Snapshot saving and attrition logging remain separate systems. `saveRDS()` calls are placed after existing `log_attrition()` lines. No combined wrapper.

### Helper Function Design
- **D-04:** `save_output_data(df, name)` lives in a new `R/utils_snapshot.R` file, sourced by `00_config.R` alongside other utils.
- **D-05:** Helper handles: path construction from name + subdirectory, `dir.create(recursive = TRUE)` if needed, `saveRDS()`, and console logging (`"Saved: {path} ({nrow} rows, {ncol} cols)"`). No metadata attributes beyond what saveRDS stores natively.

### Figure/Table Scope
- **D-06:** ALL visualization scripts get backing data snapshots: `05_visualize_waterfall.R`, `06_visualize_sankey.R`, `16_encounter_analysis.R`, and `11_generate_pptx.R`.
- **D-07:** For `11_generate_pptx.R`, save only the unique summary data frames that get rendered into tables (~5-8 data frames), not every slide table (some are the same data pivoted differently).
- **D-08:** For `16_encounter_analysis.R`, save backing data for all 7 figures and 2 summary tables (~9 data frames).

### Naming Conventions
- **D-09:** Cohort step snapshots use numbered + descriptive names: `cohort_00_initial_population.rds`, `cohort_01_hl_flag.rds`, `cohort_02_has_enrollment.rds`, `cohort_final.rds`, `attrition_log.rds`. Numbers match build order, names match attrition log step names.
- **D-10:** Figure/table backing data mirrors the output filename with `_data` suffix: `waterfall_attrition_data.rds`, `sankey_patient_flow_data.rds`, `encounters_per_person_by_payor_data.rds`, etc. Easy to trace which `.rds` backs which figure.

### Prior Decisions (carried forward from Phase 15)
- **D-11:** Use `.rds` format (not `.RData`). `readRDS()` returns a single named object. (Phase 15 D-05)
- **D-12:** Base cache directory: `/blue/erin.mobley-hl.bcu/clean/rds/`. Cohort snapshots go to `cohort/` subdirectory, figure/table backing data to `outputs/` subdirectory. (Phase 15 D-06, extended per SNAP-01/SNAP-03)

### Claude's Discretion
- Exact list of unique summary tables to snapshot from `11_generate_pptx.R` (determined by reading the script during planning)
- Console log formatting (separators, alignment, message wording)
- Whether `save_output_data()` takes a `subdir` parameter or has separate wrappers for cohort vs outputs
- Compression settings for `saveRDS()` (default `compress = TRUE` is fine)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Pipeline Code
- `R/04_build_cohort.R` -- Cohort filter chain with attrition logging. Add `saveRDS()` calls after filter steps (Sections 1-2) and at final assembly (Section 7/10).
- `R/00_config.R` -- CONFIG list with `cache` settings (lines 42-54). Add snapshot subdirectory paths here. Source new `utils_snapshot.R`.
- `R/01_load_pcornet.R` -- Existing `saveRDS()` cache pattern (line 529, 645). Reference for consistent style.

### Visualization Scripts (add backing data)
- `R/05_visualize_waterfall.R` -- Waterfall attrition chart. 1 ggsave (line 85).
- `R/06_visualize_sankey.R` -- Sankey/alluvial diagram. 1 ggsave (line 211).
- `R/16_encounter_analysis.R` -- Encounter analysis. 7 ggsaves + 2 write_csvs.
- `R/11_generate_pptx.R` -- PPTX generation with inline summary tables.

### Requirements
- `.planning/REQUIREMENTS.md` -- SNAP-01 through SNAP-05 (lines 124-128)

### Roadmap
- `.planning/ROADMAP.md` -- Phase 16 success criteria (lines 265-281)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `saveRDS(df, path, compress = TRUE)` pattern already established in `01_load_pcornet.R` (Phase 15 cache). Consistent style to follow.
- `CONFIG$cache$cache_dir` in `00_config.R` — base path for RDS storage. Phase 16 adds sibling subdirectory entries.
- `message(glue(...))` logging pattern used throughout all scripts. Snapshot logging should match.
- `dir.create(..., showWarnings = FALSE, recursive = TRUE)` pattern used in `04_build_cohort.R` line 487 for output dirs.

### Established Patterns
- Utils are sourced by `00_config.R` at the end: `source("R/utils_dates.R")`, `source("R/utils_attrition.R")`, `source("R/utils_icd.R")`. New `utils_snapshot.R` follows the same pattern.
- Attrition logging is a separate concern from data transformation: `log_attrition()` calls sit between pipeline steps. Snapshot `saveRDS()` calls follow the same placement pattern.

### Integration Points
- `R/00_config.R` — Add `CONFIG$cache$cohort_dir` and `CONFIG$cache$outputs_dir` entries. Source `utils_snapshot.R`.
- `R/04_build_cohort.R` — Add `saveRDS()` calls after steps 0, 1, 2 and at final assembly.
- `R/05_visualize_waterfall.R` — Add `save_output_data()` before `ggsave()`.
- `R/06_visualize_sankey.R` — Add `save_output_data()` before `ggsave()`.
- `R/16_encounter_analysis.R` — Add `save_output_data()` before each `ggsave()`/`write_csv()`.
- `R/11_generate_pptx.R` — Add `save_output_data()` for unique summary table data frames.

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- open to standard approaches within the decisions above.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope.

</deferred>

---

*Phase: 16-dataset-snapshots*
*Context gathered: 2026-04-03*
