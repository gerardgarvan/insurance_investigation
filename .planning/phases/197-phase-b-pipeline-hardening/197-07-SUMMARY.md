---
phase: 197
plan: "07"
name: small-fixes-fingerprint-r02-sort
status: complete
completed: 2026-11-11
duration_min: 10
tasks_completed: 4
files_modified: 2
key-files:
  modified:
    - R/tools/check_cohort_fingerprint.R
    - R/02_harmonize_payer.R
decisions: []
tags: [fingerprint, sort, path-fix, byte-identity]
---

# Phase 197 Plan 07: Small Fixes — Fingerprint Path and R/02 Sort

## One-liner

Fixed `check_cohort_fingerprint.R` to find `cohort_final.rds` in `cohort/` adjacent to `cache/outputs/`; added `arrange(ID)` before `write_csv` in `R/02_harmonize_payer.R` for byte-identical reruns.

## Commits

| Task | Commit  | Description                                                |
|------|---------|------------------------------------------------------------|
| 1+2  | c4a2620 | fix(197-07): cohort path in fingerprint tool; R/02 sort by ID |

## Changes

### Task 1 — check_cohort_fingerprint.R path fix

`COHORT_RDS` was `here("output", "cohort_final.rds")`. Replaced with:

```r
# cohort/ sits adjacent to cache/outputs/; not under output/ root
cohort_path <- file.path(dirname(CONFIG$cache$outputs_dir), "cohort", "cohort_final.rds")
COHORT_RDS  <- cohort_path
```

On HiPerGator `CONFIG$cache$outputs_dir` = `/blue/erin.mobley-hl.bcu/clean/rds/outputs`,
so the resolved path is `/blue/erin.mobley-hl.bcu/clean/rds/cohort/cohort_final.rds`.

Also added:
```r
message("[fingerprint] Comparing against pre-phaseA baseline: ", baseline_path)
```

### Task 2 — R/02_harmonize_payer.R sort before write

Added one line immediately before `write_csv(payer_summary, output_path)`:
```r
# Sort by ID for byte-identical reruns
payer_summary <- arrange(payer_summary, ID)
```

No filter logic or column derivations changed.

### Task 3 — HiPerGator verification command (document only)

To confirm PASS against the pre-phaseA baseline:

```
# On HiPerGator compute node:
module load R/4.5
R --no-save

source("R/00_config.R", local = new.env(parent = globalenv()))
source("R/tools/check_cohort_fingerprint.R", local = new.env(parent = globalenv()))
```

Expected output lines to paste back:
```
[fingerprint] Comparing against pre-phaseA baseline: .../pre_phaseA_20261111_0852/cohort_final_fingerprint.rds
cohort_final fingerprint check: PASS
  n_rows: OK
  n_unique_id: OK
  sorted_id_md5: OK
  columns: OK
```

If any line shows `MISMATCH`, paste the full block including the `Expected:` and `Got:` lines.

### Task 4 — Parse checks

Brace-balance check (Python) returned 0 for both files. No structural syntax issues.

## Deviations from Plan

**1. [Rule 1 - Bug] R/02 filename differs from plan**

- **Found during:** Task 0 grep
- **Issue:** Plan named the file `R/02_load_encounter_payer.R`; actual file is `R/02_harmonize_payer.R`.
- **Fix:** Applied sort fix to `R/02_harmonize_payer.R` (the correct file). No functional change.

**2. [Rule 3 - Blocking] No local Rscript per CLAUDE.md**

- **Issue:** Task 4 specifies `Rscript -e 'invisible(parse(...))'`, which cannot run on Windows.
- **Fix:** Used Python brace-balance check instead; both files returned 0. HiPerGator parse is covered by Task 3 verification step.

## Known Stubs

None.

## Self-Check: PASSED

- R/tools/check_cohort_fingerprint.R — modified, committed c4a2620
- R/02_harmonize_payer.R — modified, committed c4a2620
- Both files brace-balanced (0)
