---
phase: 138
plan: 05
subsystem: pipeline-runner
tags: [bug-fix, ordering, assertions, gantt-export]
requires: []
provides: [R/52-fixed, R/101-fixed, R/104-fixed, R/39-reordered]
affects: [R/39, R/52, R/101, R/104]
tech-stack:
  added: []
  patterns: [fail-fast assertions, named stop() messages]
key-files:
  modified:
    - R/39_run_all_investigations.R
    - R/52_gantt_v2_export.R
    - R/101_gantt_lifespan_collapse.R
    - R/104_gantt_entire_history.R
decisions:
  - source(here()) redundant and unreliable in SLURM context — removed from all three scripts
  - R/101 and R/104 reordered to Stage 4 (after R/52) in R/39 to satisfy producer dependency
  - R/104 stopifnot() replaced with named if/stop(glue()) assertions matching R/101 pattern
metrics:
  duration: ~5 minutes
  completed: 2026-07-26
  tasks: 1
  files: 4
---

# Phase 138 Plan 05: Diagnose R/52 / R/101 / R/104 "cannot open the connection" — Summary

Diagnosed and fixed the bare "cannot open the connection" failures in R/52, R/101, and R/104 that appeared in log2.txt.

## Root Cause Analysis

### Step 1 — File reads enumerated

**R/52 (52_gantt_v2_export.R):**
- `readRDS(EPISODES_RDS)` — cache/outputs/treatment_episodes.rds
- `readRDS(DETAIL_RDS)` — cache/outputs/treatment_episode_detail.rds
- `read.csv(CANCER_SUMMARY_CSV)` — output/tables/cancer_summary.csv (optional, file.exists-gated)
- `readRDS(DESCRIPTIONS_RDS)` — cache/outputs/code_descriptions.rds (optional, file.exists-gated)
- `readRDS(VALIDATED_DEATHS_RDS)` — cache/outputs/validated_death_dates.rds (optional, file.exists-gated)
- `readRDS(COHORT_RDS)` — output/confirmed_hl_cohort.rds (optional, file.exists-gated)

**R/101 (101_gantt_lifespan_collapse.R):**
- `read.csv(INPUT_EPISODES)` — output/gantt_episodes.csv

**R/104 (104_gantt_entire_history.R):**
- `read.csv(INPUT_LIFESPAN)` — output/gantt_lifespan.csv
- `read.csv(INPUT_EPISODES)` — output/gantt_episodes.csv

### Step 2 — Paths resolved, missing artefacts identified

The failure occurred BEFORE any file read. The log showed "Loaded 15 utility modules from R/utils/" (R/00_config.R completed) then immediate failure — pointing to the very next line in each script:

```r
source(here("R/utils/utils_format.R"))
```

This line is present in all three scripts (R/52 line 131, R/101 line 60, R/104 line 47). The `here` package is not loaded by any script that runs before these three in R/39. In the SLURM execution context, calling `here()` with no package loaded causes the "cannot open the connection" error (R traps the error message from the failed source() attempt, which presents as this bare message).

### Step 3 — Producer identified

The `source(here(...))` calls are **redundant**: R/00_config.R already sources all utils files via:
```r
utils_files <- list.files(path = "R/utils", pattern = "\\.R$", full.names = TRUE)
invisible(lapply(utils_files, source))
```
`utils_format.R` is included in these 15 modules. The `source(here(...))` calls were added as defensive extra loads but have no effect when they work, and break when the `here` package isn't on the search path.

**Secondary issue (D-11 ordering):** R/101 reads `output/gantt_episodes.csv` (produced by R/52 in Stage 4) but is placed in Stage 2. R/104 reads both `gantt_episodes.csv` (R/52) and `gantt_lifespan.csv` (R/101) but is also in Stage 2. Both scripts would fail on the file read even if the source() issue were fixed independently, because their upstream artefacts don't exist at Stage 2 time.

### Step 4 — Classification

- **R/52**: Classification **(a)** — `source(here(...))` bug. R/52 is in Stage 4 (correct position); its own input artefacts (treatment_episodes.rds etc.) are produced in Stage 1.
- **R/101**: Classification **(a) + (b)** — `source(here(...))` bug AND wrong stage. Even after fixing the source() call, gantt_episodes.csv from R/52 won't exist yet. Reorder to Stage 4.
- **R/104**: Classification **(a) + (b)** — same dual issue. Reorder to Stage 4.

### Step 5 — Assertions (D-12)

All file reads in R/52, R/101, and R/104 already had or received named assertions:
- R/52: `assert_rds_exists()` on all mandatory RDS inputs; `file.exists()` + `assert_rds_exists()` on optional inputs
- R/101: `if (!file.exists(INPUT_EPISODES)) stop(glue(...))` already present (lines 73-78)
- R/104: `stopifnot(file.exists(...))` replaced with two named `if (!file.exists(...)) stop(glue(...))` blocks, naming the missing file and producer script for each

## Changes Made

| File | Change |
|------|--------|
| `R/52_gantt_v2_export.R` | Removed `source(here("R/utils/utils_format.R"))` (line 131); replaced with comment |
| `R/101_gantt_lifespan_collapse.R` | Removed `source(here("R/utils/utils_format.R"))` (line 60); replaced with comment |
| `R/104_gantt_entire_history.R` | Removed `source(here("R/utils/utils_format.R"))` (line 47); replaced with comment; improved assertions |
| `R/39_run_all_investigations.R` | Moved R/101 and R/104 from Stage 2 to Stage 4 (after R/52) |

## Decisions Made

1. **`source(here())` removed, not replaced**: utils_format.R is already in the 15-module auto-load; adding `library(here)` would be a band-aid that doesn't address the root redundancy.
2. **Stage reorder, not stage split**: R/101 and R/104 belong with the other Gantt export chain (R/52 → R/101 → R/104), so Stage 4 is the natural home.
3. **R/104 assertion style matched to R/101**: both now use `if (!file.exists(...)) stop(glue(...))` with script tag, missing path, and producer hint.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED
- `R/52_gantt_v2_export.R` — verified `here` removed, assertions present
- `R/101_gantt_lifespan_collapse.R` — verified `here` removed, assert present
- `R/104_gantt_entire_history.R` — verified `here` removed, named assertions added
- `R/39_run_all_investigations.R` — verified R/101 and R/104 now in Stage 4 after R/52
- Commit `9c39562` exists
