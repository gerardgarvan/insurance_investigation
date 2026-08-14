---
phase: 143-180-day-file-enrichment-parity-and-review-follow-ups
plan: 02
subsystem: episode-enrichment
tags: [parameterisation, 180-day, R/28, getOption, withr]
dependency_graph:
  requires: [143-01, 142-02]
  provides: [treatment_episodes_180_enriched.rds]
  affects: [R/28_episode_classification.R, R/39_run_all_investigations.R]
tech_stack:
  added: []
  patterns: [getOption-parameterisation-for-sourced-scripts, withr::with_options-scoped-options]
key_files:
  modified:
    - R/28_episode_classification.R
    - R/39_run_all_investigations.R
decisions:
  - R/39 wires 180-day enrichment call immediately after 90-day R/28 call via withr::with_options, guarded by a file.exists() check so a fresh clone without treatment_episodes_180.rds degrades gracefully rather than erroring
  - OUT_SUFFIX = "_180_enriched" (not "_180") so the overwrite guard is satisfied: treatment_episodes_180_enriched.rds != treatment_episodes_180.rds (Phase 142 unenriched output)
  - withr::with_options used in R/39 rather than manual options()/on.exit() so option restoration is guaranteed even on source() error
metrics:
  duration_minutes: ~15
  tasks_completed: 1
  tasks_pending: 1
  files_modified: 2
  completed_date: "2026-08-14"
---

# Phase 143 Plan 02: Parameterise R/28 for 180-day Enrichment Path — Summary

**One-liner:** R/28 now accepts EPISODES_RDS_PATH/DETAIL_RDS_PATH/OUT_SUFFIX via getOption() so the 180-day episodes file can be enriched without script duplication; R/39 wires the call via withr::with_options with an overwrite guard.

## Task Status

| Task | Name | Status | Commit |
|------|------|--------|--------|
| 0 | Confirm Phase 143 integrity checks ran | COMPLETE (pre-existing, human-verified) | — |
| 1 | Parameterise R/28 for 180-day path | COMPLETE | e8896cf |
| 2 | HiPerGator: run 90-day enrichment + verify, then run 180-day enrichment + check fill rates | PENDING — requires HiPerGator | — |

## Task 1 Details

### Changes Made

**R/28_episode_classification.R:**

1. Removed `OUTPUT_RDS` and `DETAIL_RDS` constants; replaced with three `getOption()`-based parameters immediately after source() calls:
   - `EPISODES_RDS_PATH` (default: `treatment_episodes.rds`)
   - `DETAIL_RDS_PATH` (default: `treatment_episode_detail.rds`)
   - `OUT_SUFFIX` (default: `""`)

2. Replaced all `readRDS(OUTPUT_RDS)` and `readRDS(DETAIL_RDS)` calls with the new parameterised equivalents. Updated `assert_rds_exists()` calls to use the same. Updated log messages to use `basename(EPISODES_RDS_PATH)` and `basename(DETAIL_RDS_PATH)`.

3. Replaced final `saveRDS(episodes, OUTPUT_RDS)` with an overwrite-guarded block:
   - `out_rds` constructed as `paste0("treatment_episodes", OUT_SUFFIX, ".rds")`
   - Guard: `stop()` if `nzchar(OUT_SUFFIX)` AND `normalizePath(out_rds) == normalizePath(EPISODES_RDS_PATH)` — prevents a suffix of `"_180"` from silently destroying the unenriched Phase 142 output
   - With `OUT_SUFFIX = ""` (the default), the guard is skipped entirely (`nzchar("")` is FALSE), so the 90-day path is bit-identical to before

**R/39_run_all_investigations.R:**

1. Added option reset immediately after `rm(list = ls())`:
   ```r
   options(p143_episodes_rds = NULL, p143_detail_rds = NULL, p143_out_suffix = NULL)
   ```
   Prevents stale interactive-session options from silently redirecting the 90-day enrichment to a 180-day file.

2. Wired 180-day enrichment call immediately after the 90-day `run_script("R/28_episode_classification.R", results)` line:
   ```r
   if (file.exists(file.path(CONFIG$cache$outputs_dir, "treatment_episodes_180.rds"))) {
     withr::with_options(
       list(p143_episodes_rds = ..., p143_detail_rds = ..., p143_out_suffix = "_180_enriched"),
       source("R/28_episode_classification.R", local = new.env(parent = globalenv()))
     )
   } else {
     message("  [143] treatment_episodes_180.rds not found — skipping 180-day enrichment pass.")
   }
   ```
   The `file.exists()` guard ensures a fresh clone without the 180-day RDS degrades gracefully. The `withr::with_options` ensures option restoration even if `source()` errors partway.

### Decision: Wire it in (not "document as manual")

The plan offered two options. "Wire it in" was selected and implemented. Rationale: leaving it unstated reopens the same blank-column ticket for the next person, and the `file.exists()` guard makes the wired call safe for fresh clones.

### Acceptance Criteria Verified

- `grep "p143_episodes_rds\|p143_out_suffix" R/28_episode_classification.R` — 3 matches (getOption calls + stop() message)
- `grep "saveRDS" R/28_episode_classification.R` — exactly one saveRDS, writing to `out_rds`
- `grep "would overwrite the input RDS" R/28_episode_classification.R` — 1 match
- `grep "p143_episodes_rds = NULL" R/39_run_all_investigations.R` — 1 match
- Python balance check: parens=0, braces=0 — PASS
- `git diff --name-only` — only R/28 and R/39 modified (as intended)

## Task 2: Pending HiPerGator Verification

Task 2 requires running on HiPerGator. The orchestrator will handle this checkpoint. Steps required:

1. Archive current enriched file: `file.copy(treatment_episodes.rds → treatment_episodes_enriched_pre143.rds, overwrite = FALSE)`
2. Idempotency probe: confirm no `.x`/`.y` suffix columns present in the existing enriched file
3. Regenerate unenriched input via `source("R/26_treatment_episodes.R")`, then run `source("R/28_episode_classification.R")` with defaults
4. Verify 90-day output unchanged: `all.equal(new, pre143_snapshot)` must be TRUE
5. Run 180-day enrichment pass via the scoped options block from Task 2's `how-to-verify`
6. Check fill rates for all 6 enrichment columns in `treatment_episodes_180_enriched.rds` — must be > 0; episode_dx_* columns should be >= the 90-day benchmark rates from Task 0
7. Run `Rscript R/88_smoke_test.R` — must exit 0

**90-day benchmark fill rates (Task 0):**
- drug_group: 40.2%
- code_type: 67.2%
- source_table: 67.2%
- episode_dx_codes: 61.5%
- episode_dx_categories: 61.5%
- episode_dx_7day_confirmed: 61.2%

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] Added file.exists() guard to R/39 180-day wiring**
- **Found during:** Task 1 Step 5
- **Issue:** The plan's literal `withr::with_options(...)` block would error on a fresh clone where `treatment_episodes_180.rds` has not yet been produced by Phase 142 (R/142_gantt_180_export.R would not have run yet, or the researcher may only run R/39 on a subset of data)
- **Fix:** Wrapped the withr block in `if (file.exists(...))` with an informative skip message in the else branch
- **Files modified:** R/39_run_all_investigations.R

None beyond the above.

## Known Stubs

None — Task 1 is pure parameterisation/wiring code. No data-producing path runs until Task 2 (HiPerGator).

## Self-Check

Verified:
- `R/28_episode_classification.R` — modified, EPISODES_RDS_PATH/DETAIL_RDS_PATH/OUT_SUFFIX present, overwrite guard present, single saveRDS to out_rds
- `R/39_run_all_investigations.R` — modified, option reset present, withr::with_options 180-day block present
- Commit e8896cf — exists (`git log --oneline -1` confirms)

## Self-Check: PASSED
