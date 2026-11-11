---
phase: 197
plan: "08"
name: mice-r183-convergence-diagnostic
status: complete
completed: 2026-11-11
duration_minutes: 15
tasks_completed: 5
tasks_total: 5
files_created: 2
files_modified: 1
key-decisions:
  - "D-197-NN: COLLAPSE_RARE_SOURCE defaults OFF; pending Gerard confirmation based on diagnostic output"
tags: [mice, convergence, diagnostic, main_source, R183]
key-files:
  created:
    - R/tools/mice_convergence_diagnostic.R
    - .planning/phases/197-phase-b-pipeline-hardening/197-MICE-CONVERGENCE.md
  modified:
    - R/183_mice_sensitivity_distance.R
dependency-graph:
  requires: []
  provides: [mice_convergence_diagnostic, collapse_rare_source_flag]
  affects: [R183]
tech-stack:
  added: []
  patterns: [env-var feature flag, Gelman-Rubin R-hat diagnostic]
---

# Phase 197 Plan 08: R/183 MICE Diagnostic Summary

**One-liner:** COLLAPSE_RARE_SOURCE env-var flag (default OFF) added to R/183; standalone Gelman-Rubin convergence diagnostic written to R/tools/.

## What Was Done

### Task 0 — Context probe

Grepped R/183 for `main_source`, `mice`, `loggedEvents`, `maxit`. Located:
- Config constants at lines 53-58
- `pat_mice$main_source` assembled and factored at line 488
- `SECTION 4` MICE calls starting at line 629
- `loggedEvents` printed at lines 672-685

### Task 1 — COLLAPSE_RARE_SOURCE flag in R/183

Added to config section (after MICE_SEED, line 56):

```r
COLLAPSE_RARE_SOURCE  <- as.logical(Sys.getenv("COLLAPSE_RARE_SOURCE", "FALSE"))
RARE_SOURCE_THRESHOLD <- as.integer(Sys.getenv("RARE_SOURCE_THRESHOLD", "30"))
```

Added new **Section 3b** (between Section 3 and Section 4) containing the collapse block.
When `COLLAPSE_RARE_SOURCE=FALSE` (default), logs level counts without modifying `pat_mice`.
When `TRUE`, calls `forcats::fct_collapse()` and logs the collapsed table.

D-197-NN comment cites evidence: 400 loggedEvents/model in 10/15 and 11/11 runs; "UCI" dropped every iteration.

### Task 2 — R/tools/mice_convergence_diagnostic.R

Created. Two analysis sections:

1. **main_source level counts** — reads `mice_input_patient_*.rds`, produces table with `flag` column marking levels with n < 30.
2. **R-hat convergence** — reads `mice_mids_*.rds`, iterates `chainMean` matrices, computes Gelman-Rubin-style R-hat at each iteration, finds first stable-below-1.1 iteration per imputed variable.

Writes `197-MICE-CONVERGENCE.md` to `.planning/phases/197-phase-b-pipeline-hardening/`.

Input discovery: env vars `MICE_DIAG_INPUT` / `MICE_DIAG_MIDS` take precedence, then `R183_MICE_INPUT_RDS` / `R183_MICE_MIDS_RDS`, then `list.files()` on `output/internal/` (last-found fallback with explicit error if none found).

### Task 3 — Placeholder 197-MICE-CONVERGENCE.md

Committed placeholder; will be overwritten when Gerard runs the diagnostic.

### Task 4 — HiPerGator run command

```
module load R/4.5; R --no-save
source("R/tools/mice_convergence_diagnostic.R", local = new.env(parent = globalenv()))
```

Expected output: table of main_source levels with n and flag column; R-hat table per imputed variable; confirmation line `[diag] Report written: ...197-MICE-CONVERGENCE.md`.

**Paste back:** the full `main_source level counts` table + the full convergence table + the final `[diag] Report written` line.

Using the 2026-11-11 mids files:
- `mice_input_patient_20261111.rds`
- `mice_mids_20261111.rds`

### Task 5 — Parse / brace-balance checks

Python brace-balance check: both files balanced at 0. No Rscript available locally (HiPerGator only).

## Commits

| Hash | Message |
|---|---|
| 6b5c754 | fix(197-08): COLLAPSE_RARE_SOURCE flag in R/183 (OFF); mice convergence diagnostic tool |

## Decisions Made

**D-197-NN: COLLAPSE_RARE_SOURCE defaults OFF**

The flag is wired and functional but will not activate until Gerard reviews the diagnostic output and confirms that collapsing "UCI" and other sub-30 levels is appropriate for the analysis. No MICE rerun is required; the decision point uses the existing 2026-11-11 mids file.

## Deviations from Plan

None — plan executed as written. The variable used in the collapse block is `pat_mice$main_source` (the name in context at that point in the script) rather than `mice_input$main_source` as written in the plan template; `pat_mice` is the actual object name throughout R/183.

## Known Stubs

- `.planning/phases/197-phase-b-pipeline-hardening/197-MICE-CONVERGENCE.md` is a placeholder; real content written by the diagnostic tool on HiPerGator.

## Self-Check: PASSED

- R/183_mice_sensitivity_distance.R: modified, committed in 6b5c754
- R/tools/mice_convergence_diagnostic.R: created, committed in 6b5c754
- .planning/phases/197-phase-b-pipeline-hardening/197-MICE-CONVERGENCE.md: created, committed in 6b5c754
- Brace balance: both files = 0
