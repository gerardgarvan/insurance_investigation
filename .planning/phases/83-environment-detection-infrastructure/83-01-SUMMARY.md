---
phase: 83-environment-detection-infrastructure
plan: 01
subsystem: configuration
tags: [environment-detection, config, testing-infrastructure, cross-platform]
dependency_graph:
  requires: []
  provides: [IS_LOCAL, THREAD_COUNT, conditional-paths, auto-directory-creation]
  affects: [all-downstream-scripts]
tech_stack:
  added: []
  patterns: [environment-detection, conditional-config, auto-provisioning]
key_files:
  created:
    - path: R/00_config.R
      role: Environment detection and conditional CONFIG paths
      lines_added: 127
    - path: tests/fixtures/.gitkeep
      role: Git-tracked empty directory for local mode test data
  modified:
    - path: R/00_config.R
      role: Added SECTION 0 (environment detection) and SECTION 1b (auto-directory creation)
      before_sections: 8
      after_sections: 10
decisions:
  - decision: "IS_LOCAL flag set via OS detection (Windows=TRUE) with env var override"
    rationale: "Windows machines are only used for local dev in this project; Linux is HiPerGator production"
    alternatives: ["hostname detection", "manual config flag", "always require env var"]
    outcome: "Auto-detection minimizes config burden while env var enables Linux VM testing"
  - decision: "THREAD_COUNT as separate variable instead of inline in CONFIG$performance$num_threads"
    rationale: "CONFIG list needs constant value; THREAD_COUNT can be referenced before CONFIG definition"
    alternatives: ["duplicate if-else logic", "post-hoc CONFIG modification"]
    outcome: "Clean separation with single source of truth for thread count logic"
  - decision: "tempdir() for all local cache paths instead of repo-local temp/"
    rationale: "Avoids gitignore conflicts and R session cleanup automatically removes cache on exit"
    alternatives: ["./temp/ directory", "./.cache/ directory", "OS-specific temp paths"]
    outcome: "Ephemeral cache that never risks git commits, OS cleanup handles disk space"
  - decision: "Automatic directory creation at config source time"
    rationale: "Prevents first-run errors from missing output/cache directories, especially in tempdir() mode"
    alternatives: ["lazy creation in each script", "manual mkdir instructions", "error on missing dirs"]
    outcome: "Zero-config startup — directory structure materializes automatically"
metrics:
  duration_minutes: 2.5
  tasks_completed: 2
  files_created: 2
  files_modified: 1
  commits: 2
  lines_added: 127
  lines_removed: 23
  test_coverage: manual-verification-only
completed: 2026-06-04T03:22:55Z
---

# Phase 83 Plan 01: Environment Detection Infrastructure Summary

**Add environment auto-detection to R/00_config.R so the pipeline distinguishes between local Windows testing and HiPerGator Linux production, with conditional paths for data, cache, DuckDB, and thread count.**

## What Was Built

A zero-config environment detection system that automatically adapts the R pipeline to run on Windows developer machines or HiPerGator Linux production, with conditional paths for data directories, RDS cache, DuckDB files, and CPU thread allocation. No code changes or manual configuration required when switching environments.

## Commits

| Commit | Message | Files |
|--------|---------|-------|
| f52bc15 | feat(83-01): add environment detection and conditional paths to R/00_config.R | R/00_config.R |
| 18311ab | feat(83-01): create tests/fixtures/ directory for local mode test data | tests/fixtures/.gitkeep |

## Key Changes

### 1. SECTION 0: Environment Detection (R/00_config.R lines 33-76)

**IS_LOCAL flag:**
- Auto-detects Windows via `Sys.info()["sysname"] == "Windows"`
- Overridable via `R_TESTING_ENV=local` env var (enables Linux VM testing)
- Defaults to FALSE on Linux (production-safe)

**THREAD_COUNT variable:**
- Local: 1 thread (avoid contention on dev laptops)
- Production: reads `SLURM_CPUS_PER_TASK` env var, falls back to 16

**Startup logging:**
- Prints banner showing environment mode (LOCAL TESTING MODE or PRODUCTION MODE)
- Displays actual paths, thread count, and override status
- Visible in both RStudio console and SLURM job logs

### 2. Conditional CONFIG Paths (R/00_config.R lines 86-163)

All paths use if-else conditionals on `IS_LOCAL`:

**Local mode (Windows):**
- `data_dir`: `tests/fixtures/` (relative path)
- `project_dir`: `getwd()` (current working directory)
- `cache_dir`: `tempdir()/insurance_investigation_cache`
- `raw_dir`, `cohort_dir`, `outputs_dir`: subdirs under cache_dir
- `duckdb_dir`: `tempdir()/insurance_investigation_duckdb`
- `duckdb_path`: `pcornet_test.duckdb` (separate test database)
- `num_threads`: 1

**Production mode (HiPerGator Linux):**
- All existing paths unchanged (`/orange/`, `/blue/` mounts)
- `num_threads`: SLURM allocation or 16

All path construction uses `file.path()` — no hardcoded `/` or `\` separators (INFRA-01 compliance).

### 3. SECTION 1b: Automatic Directory Creation (R/00_config.R lines 165-191)

Creates 11 directories at config source time if they don't exist:
- `output/` (and 5 subdirs: figures, tables, cohort, diagnostics, logs)
- All cache directories (cache_dir, raw_dir, cohort_dir, outputs_dir, duckdb_dir)

**Why automatic:** Prevents "cannot open file" errors on first run, especially critical for tempdir() paths that don't pre-exist as subdirectories.

**Implementation:** Loop with `dir.create(recursive = TRUE, showWarnings = FALSE)` — idempotent, silent if dirs already exist.

### 4. tests/fixtures/ Directory Structure

- Created `tests/` and `tests/fixtures/` directories
- Added empty `.gitkeep` file to track directory in git
- This is where `CONFIG$data_dir` points in local mode
- Phase 84 will populate with hand-crafted test fixture CSVs

## Technical Details

### Environment Detection Logic

```r
IS_LOCAL <- if (Sys.getenv("R_TESTING_ENV") != "") {
  Sys.getenv("R_TESTING_ENV") == "local"
} else {
  Sys.info()["sysname"] == "Windows"
}
```

**Priority:** Env var override > OS detection
**Safety:** Unset env var on Linux = FALSE (production default)

### Path Construction Pattern

```r
data_dir = if (IS_LOCAL) {
  file.path("tests", "fixtures")
} else {
  "/orange/erin.mobley-hl.bcu/Mailhot_V1_20250915"
}
```

All 8 conditional paths follow this pattern. No code duplication, single if-else per path.

### Cross-Platform Compatibility

- `file.path()` for all path construction (handles `/` vs `\` automatically)
- `tempdir()` returns OS-appropriate temp directory (Windows: `C:\Users\...\AppData\Local\Temp\RtmpXXXXXX`, Linux: `/tmp/RtmpXXXXXX`)
- `getwd()` for local project_dir (works with both drive letters and Unix paths)
- No assumptions about path separators, drive letters, or temp locations

## Verification

**Manual verification required** (Rscript not available in CI environment):

```r
# On Windows (auto-detected):
source("R/00_config.R")
stopifnot(IS_LOCAL == TRUE)
stopifnot(grepl("fixtures", CONFIG$data_dir))
stopifnot(grepl("tempdir", CONFIG$cache$duckdb_path))
stopifnot(CONFIG$performance$num_threads == 1)

# On Linux without env var (production default):
source("R/00_config.R")
stopifnot(IS_LOCAL == FALSE)
stopifnot(grepl("/orange/", CONFIG$data_dir))
stopifnot(grepl("/blue/", CONFIG$cache$duckdb_path))
stopifnot(CONFIG$performance$num_threads >= 1)

# On Linux with override:
Sys.setenv(R_TESTING_ENV = "local")
source("R/00_config.R")
stopifnot(IS_LOCAL == TRUE)
```

**Automated checks performed:**
- Git commit successful (both tasks committed)
- File existence verified: `tests/fixtures/.gitkeep` created
- Path construction audit: All `file.path()` usage confirmed, no hardcoded separators found

## Deviations from Plan

None. Plan executed exactly as specified.

## Known Stubs

None. This is pure configuration infrastructure with no UI or data rendering.

## Requirements Satisfied

- ENV-01: Cross-platform path handling via file.path()
- ENV-02: OS detection via Sys.info()["sysname"]
- ENV-03: Environment variable override via R_TESTING_ENV
- ENV-04: Conditional config (IS_LOCAL flag with if-else paths)
- ENV-05: Startup logging (environment mode banner)
- ENV-06: Safe defaults (production on Linux unless overridden)
- INFRA-01: All path construction uses file.path()
- INFRA-03: Auto-provisioning (directory creation at startup)

## Impact on Downstream Work

**Phase 84 (Test Fixture Generation):**
- Can now populate `tests/fixtures/` directory
- Local mode will automatically use test data
- DuckDB ingest will target separate test database

**Phase 85 (Local Smoke Test Adaptation):**
- R/88 smoke test can now run locally against fixtures
- No code changes needed — config auto-adapts
- Verification: source R/00_config.R shows IS_LOCAL=TRUE

**Phase 86 (Local Testing Documentation):**
- Environment detection is transparent — minimal docs needed
- Only need to document: git clone, open RStudio, source config works

**All existing scripts:**
- No changes required — CONFIG paths automatically adapt
- Backward compatible: production behavior unchanged on Linux
- PCORNET_PATHS automatically points to correct data_dir

## Next Steps

1. Phase 84: Generate targeted test fixture CSVs (~20 patients with clinical edge cases)
2. Verify DuckDB ingest works with fixture CSVs in local mode
3. Adapt R/88 smoke test to run against test database
4. Document local testing workflow

## Self-Check

**Files created:**
- `R/00_config.R` (modified, +127 lines): ✓ EXISTS
- `tests/fixtures/.gitkeep`: ✓ EXISTS

**Commits:**
- f52bc15: ✓ FOUND in git log
- 18311ab: ✓ FOUND in git log

**Key patterns:**
- IS_LOCAL flag: ✓ FOUND in R/00_config.R
- THREAD_COUNT variable: ✓ FOUND in R/00_config.R
- Conditional data_dir: ✓ FOUND in R/00_config.R
- tempdir() usage: ✓ FOUND in R/00_config.R
- SECTION 1b directory creation: ✓ FOUND in R/00_config.R
- SECTION 8 unchanged: ✓ FOUND in R/00_config.R

## Self-Check: PASSED

All files created, all commits exist, all patterns implemented as specified.
