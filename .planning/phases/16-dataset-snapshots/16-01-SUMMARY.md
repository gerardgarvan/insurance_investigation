---
phase: 16-dataset-snapshots
plan: 01
subsystem: cache-infrastructure
tags: [snapshot, rds, cache, cohort]
dependency_graph:
  requires: [SNAP-01, SNAP-02, SNAP-05]
  provides: [save_output_data-helper, cohort-snapshots, cache-subdirs]
  affects: [00_config, 01_load_pcornet, 04_build_cohort]
tech_stack:
  added: [utils_snapshot.R]
  patterns: [snapshot-helper, inline-saveRDS, directory-guards]
key_files:
  created: [R/utils_snapshot.R]
  modified: [R/00_config.R, R/01_load_pcornet.R, R/04_build_cohort.R]
decisions:
  - "Inline saveRDS() in 04_build_cohort.R instead of wrapping with save_output_data() for cohort snapshots (simpler, no function call overhead)"
  - "save_output_data() reserved for outputs/ subdir usage in Phase 17 visualization scripts"
  - "dir.create() guard only at step 0 since filter steps execute sequentially"
  - "CONFIG$cache structure: base cache_dir + raw_dir/cohort_dir/outputs_dir subdirs for clean separation"
metrics:
  duration_seconds: 180
  tasks_completed: 2
  files_created: 1
  files_modified: 3
  commits: 2
completed_date: 2026-04-03
---

# Phase 16 Plan 01: Snapshot Infrastructure Summary

**One-liner:** Created save_output_data() helper, restructured CONFIG cache with subdirectories, and added 5 inline RDS snapshots to cohort build pipeline.

## What Was Built

### Snapshot Helper (Task 1)

**R/utils_snapshot.R** — New snapshot utility providing `save_output_data(df, name, subdir = "outputs")` with:
- Input validation (df must be data.frame, subdir must be "cohort" or "outputs")
- Automatic directory creation with idempotent guard
- Path construction from CONFIG$cache$cache_dir + subdir
- Console logging: `Snapshot: {name}.rds ({nrow} rows, {ncol} cols)`
- Compression enabled via `compress = TRUE`

**CONFIG$cache restructure** — Extended cache configuration from single `cache_dir` to structured hierarchy:
```r
cache = list(
  cache_dir    = "/blue/erin.mobley-hl.bcu/clean/rds",      # Base (was .../raw)
  force_reload = FALSE,
  raw_dir      = "/blue/erin.mobley-hl.bcu/clean/rds/raw", # Phase 15: PCORnet tables
  cohort_dir   = "/blue/erin.mobley-hl.bcu/clean/rds/cohort", # Phase 16: filter steps
  outputs_dir  = "/blue/erin.mobley-hl.bcu/clean/rds/outputs" # Phase 16: viz backing data
)
```

**01_load_pcornet.R update** — Changed `cache_dir <- CONFIG$cache$cache_dir` to `cache_dir <- CONFIG$cache$raw_dir` to maintain Phase 15 functionality after cache_dir path change.

**00_config.R sourcing** — Added `source("R/utils_snapshot.R")` after utils_icd.R to auto-load snapshot helper.

### Cohort Snapshots (Task 2)

**R/04_build_cohort.R** — Added 5 inline `saveRDS()` calls at patient-count-changing steps:

1. **cohort_00_initial_population.rds** (after line 52) — Initial DEMOGRAPHIC population before any filters
2. **cohort_01_hl_flag.rds** (after line 105) — After HL_SOURCE and HL_VERIFIED flag join
3. **cohort_02_has_enrollment.rds** (after line 109) — After enrollment record filter (final filter step)
4. **cohort_final.rds** (after line 417) — Final assembled cohort with all enrichment columns
5. **attrition_log.rds** (after line 500) — Attrition log data frame for reproducible waterfall charts

**Placement strategy:**
- Snapshots placed IMMEDIATELY after corresponding `log_attrition()` calls (filter steps 0-2)
- Final cohort snapshot placed after `hl_cohort <- cohort %>% select(...)` block completes
- Attrition log snapshot placed after `print(attrition_log)` in Section 9
- NO snapshots in Sections 3-6.8 (enrichment stages add columns, don't change patient count)

**Directory creation:**
- `dir.create(CONFIG$cache$cohort_dir, recursive = TRUE, showWarnings = FALSE)` guard at step 0 only
- Subsequent snapshots assume directory exists (sequential execution)

## Deviations from Plan

None — plan executed exactly as written.

## Testing & Verification

**Automated verification (passing):**
```bash
grep -c "cohort_00_initial_population" R/04_build_cohort.R  # 2 (comment + saveRDS)
grep -c "cohort_01_hl_flag" R/04_build_cohort.R             # 2
grep -c "cohort_02_has_enrollment" R/04_build_cohort.R      # 2
grep -c "cohort_final.rds" R/04_build_cohort.R              # 2
grep -c "attrition_log.rds" R/04_build_cohort.R             # 2
grep -c "saveRDS" R/04_build_cohort.R                       # 5 (total snapshots)
```

**Manual verification (checklist):**
- [x] utils_snapshot.R contains `save_output_data <- function(df, name, subdir = "outputs")`
- [x] save_output_data validates `!subdir %in% c("cohort", "outputs")`
- [x] 00_config.R contains `cache_dir = "/blue/erin.mobley-hl.bcu/clean/rds"` (base path)
- [x] 00_config.R contains `raw_dir`, `cohort_dir`, `outputs_dir` entries
- [x] 00_config.R contains GITIGNORED warnings for cache directories
- [x] 00_config.R sources utils_snapshot.R
- [x] 01_load_pcornet.R references `CONFIG$cache$raw_dir` (not cache_dir)
- [x] 04_build_cohort.R has 5 saveRDS calls at correct locations
- [x] Each saveRDS uses `file.path(CONFIG$cache$cohort_dir, "{name}.rds")`
- [x] Each saveRDS has `compress = TRUE`
- [x] dir.create guard appears exactly once (step 0)

## Known Stubs

None — this plan only creates infrastructure (helper function and snapshot calls). No data wiring or UI components.

## Files Created

| File | Lines | Purpose |
|------|-------|---------|
| R/utils_snapshot.R | 59 | Snapshot helper function with validation and logging |

## Files Modified

| File | Changes | Reason |
|------|---------|--------|
| R/00_config.R | +9 lines | Restructured cache config with subdirs, sourced utils_snapshot.R |
| R/01_load_pcornet.R | 1 line | Updated cache_dir reference to raw_dir |
| R/04_build_cohort.R | +24 lines | Added 5 inline saveRDS calls for filter steps and final cohort |

## Key Technical Decisions

**D-01: Inline saveRDS vs save_output_data wrapper**
- **Decision:** Use inline `saveRDS()` in 04_build_cohort.R for cohort snapshots
- **Rationale:** Simpler, no function call overhead, snapshots happen in existing filter chain flow
- **save_output_data usage:** Reserved for Phase 17 visualization scripts where consistent naming/logging needed across multiple output files

**D-02: Directory creation strategy**
- **Decision:** Single idempotent `dir.create()` guard at step 0
- **Rationale:** Filter steps execute sequentially; directory guaranteed to exist after step 0
- **Alternative rejected:** dir.create() before each saveRDS (redundant, clutters code)

**D-03: Cache structure design**
- **Decision:** Restructure CONFIG$cache from flat to hierarchical with base + subdirs
- **Rationale:** Separates raw table cache, cohort snapshots, and viz outputs for clarity
- **Migration path:** Updated 01_load_pcornet.R to use `raw_dir` to preserve Phase 15 behavior

## Commits

| Hash | Message | Files |
|------|---------|-------|
| d4fc273 | feat(16-01): create snapshot utility and extend CONFIG cache | R/utils_snapshot.R, R/00_config.R, R/01_load_pcornet.R |
| b550ba9 | feat(16-01): add cohort filter step snapshots to build pipeline | R/04_build_cohort.R |

## Self-Check: PASSED

**Created files exist:**
```bash
[ -f "R/utils_snapshot.R" ] && echo "FOUND: R/utils_snapshot.R"
# FOUND: R/utils_snapshot.R
```

**Commits exist:**
```bash
git log --oneline --all | grep -q "d4fc273" && echo "FOUND: d4fc273"
# FOUND: d4fc273
git log --oneline --all | grep -q "b550ba9" && echo "FOUND: b550ba9"
# FOUND: b550ba9
```

**Modified files verify:**
- R/00_config.R contains cohort_dir, outputs_dir, raw_dir, and sources utils_snapshot.R
- R/01_load_pcornet.R references CONFIG$cache$raw_dir
- R/04_build_cohort.R contains all 5 snapshots with correct paths

## Impact Analysis

**Downstream effects:**
- Phase 17 visualization scripts can now use `save_output_data()` for figure backing datasets
- Cohort snapshots enable debugging filter chain issues without re-running full pipeline
- Cache directory structure supports future expansion (e.g., intermediate/ for staging data)

**Compatibility:**
- Phase 15 cache logic unaffected (01_load_pcornet.R updated to use raw_dir)
- No changes to existing function signatures or attrition logging behavior
- Snapshot calls are fire-and-forget (no return values used downstream)

## Next Steps

**Plan 16-02: Output Backing Datasets**
- Add `save_output_data()` calls to 15_pptx_builder.R and 16_encounter_analysis.R
- Save table builder output data frames (waterfall, sankey, encounter histograms)
- Verify figure reproducibility from backing .rds files

---

*Completed: 2026-04-03 | Duration: 180 seconds (3 minutes) | Commits: 2*
