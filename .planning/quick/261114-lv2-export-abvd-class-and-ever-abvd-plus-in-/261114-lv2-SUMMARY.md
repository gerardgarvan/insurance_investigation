---
phase: 261114-lv2
plan: 01
type: quick
tags: [abvd, gantt, export, phase-201b]
key_files:
  modified:
    - R/utils/utils_cancer.R
    - R/142_gantt_180_export.R
    - R/88_smoke_test_comprehensive.R
    - R/SCRIPT_INDEX.md
    - tests/testthat/test-201-abvd-tr-flags.R
decisions:
  - "ABVD_PLUS broadened: three-core (Dox+Vin+Dac) + extra non-BV/Nivo drug = ABVD_PLUS regardless of Bleomycin presence"
  - "BV+AVD and Nivo+AVD remain NA (has_excl guard unchanged)"
  - "ABVD+BV now returns NA instead of ABVD_PLUS (corrected: has_excl=TRUE path)"
metrics:
  completed_date: "2026-11-14"
  tasks: 3
  files_modified: 5
---

# Phase 261114-lv2 Summary

**One-liner:** gantt_episodes_180.csv extended to 32 columns with abvd_class (col 31, Chemotherapy rows only) and ever_abvd_plus (col 32, patient-level flag); ABVD_PLUS broadened to cover AVD+extra non-excluded agent.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Broaden classify_abvd_episode() ABVD_PLUS logic; add T-NEW-1..4 | 195843c |
| 2 | Add abvd_class (col 31) and ever_abvd_plus (col 32) to R/142 export | ccd92e2 |
| 3 | Update R/88 Section 15bd for 32-col file; add 7 new checks + 2 unit checks | 6776442 |

## Key Changes

**R/utils/utils_cancer.R** — classify_abvd_episode() ABVD_PLUS logic:
- Old: `all_four → ABVD_PLUS` (covered ABVD+extra only; BV+ABVD incorrectly returned ABVD_PLUS)
- New three-branch structure:
  - `all_four + !has_excl + n_fam <= 4` → "ABVD"
  - `all_four + !has_excl + n_fam > 4` → "ABVD_PLUS"
  - `all_four + has_excl` → NA
  - `three-core + !has_excl + n_fam <= 3` → "AVD"
  - `three-core + !has_excl + n_fam > 3` → "ABVD_PLUS" (broadened; Bleo optional)

**R/142_gantt_180_export.R:**
- EPISODES_SCHEMA: 30 → 32 columns
- Section 4C4: ever_abvd_plus computed via group_by any(abvd_class == "ABVD_PLUS")
- Two new stopifnot guards for ever_abvd_plus
- select() trimmer: abvd_class and ever_abvd_plus at cols 31-32
- PRE201B regression block: saves 30-col baseline, verifies cols 1-30 unchanged post-run

**R/88 Section 15bd:**
- [c1]: 30 → 32 columns
- New: [c6] abvd_class@31, [c7] ever_abvd_plus@32
- New: [d3] abvd_class value set, [d4] ever_abvd_plus TRUE/FALSE only
- New: [e5] ever_abvd_plus constant within patient, [e6] consistency with abvd_class
- New: [a5b] AVD+Rituximab unit check, [a5c] BV+AVD regression unit check

## Deviations from Plan

None — plan executed exactly as written.

## Verification Results

- `tools/rcheck.sh parse` (all 4 files): 0 failures
- `tools/rcheck.sh test 201-abvd`: 13 tests, 0 failures, 0 errors
- T-NEW-1 (AVD+Rituximab → ABVD_PLUS): PASS
- T-NEW-2 (BV+AVD → NA): PASS
- T-NEW-3 (Nivo+AVD → NA): PASS
- T-NEW-4 (ABVD+BV → NA): PASS

## HiPerGator Steps for Gerard

```r
module load R/4.5
R --no-save
# Optional: set env var before sourcing to run PRE201B regression
Sys.setenv(RUN_PRE201B_REGRESSION = "TRUE")
source("R/142_gantt_180_export.R", local = new.env(parent = globalenv()))
source("R/88_smoke_test_comprehensive.R", local = new.env(parent = globalenv()))
```

Paste back: 15bd tally line (`ABVD-TR-201: N PASS / N FAIL / N SKIP`), overall FAIL delta from Section 16, and nrow/ncol line from R/142.

## Self-Check

- R/utils/utils_cancer.R: modified (confirmed by parse OK)
- R/142_gantt_180_export.R: modified (confirmed by parse OK)
- R/88_smoke_test_comprehensive.R: modified (confirmed by parse OK)
- tests/testthat/test-201-abvd-tr-flags.R: modified (confirmed by test pass)
- Commits: 195843c, ccd92e2, 6776442 (all on main branch)

## Self-Check: PASSED
