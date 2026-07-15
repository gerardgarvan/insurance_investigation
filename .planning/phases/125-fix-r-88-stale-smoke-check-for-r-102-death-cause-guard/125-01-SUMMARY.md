---
phase: 125-fix-r-88-stale-smoke-check-for-r-102-death-cause-guard
plan: "01"
subsystem: smoke-test
tags: [smoke-test, R/88, R/102, death-cause, Phase-119-fix]
dependency_graph:
  requires: [R/102_death_cause_nhl_flag.R Phase 119 implementation]
  provides: [R/88 smoke test clean pass (0 failures) on Rscript-capable host]
  affects: [R/88_smoke_test_comprehensive.R Section 15o Check 6]
tech_stack:
  added: []
  patterns: [static grep assertions with single-quoted R strings for embedded double-quotes]
key_files:
  created: []
  modified:
    - R/88_smoke_test_comprehensive.R
decisions:
  - "Check 6 description changed from 'field-availability' to 'table-availability' to reflect Phase 119 reality"
  - "Runtime check (Rscript R/88 ... exit 0) deferred to HiPerGator — Rscript not available on Windows executor (see Runtime Acceptance Criterion below)"
metrics:
  duration_minutes: 5
  completed: "2026-07-15T14:30:14Z"
  tasks_completed: 1
  tasks_total: 1
  files_modified: 1
---

# Phase 125 Plan 01: Fix R/88 Stale Smoke Check for R/102 Death Cause Guard Summary

**One-liner:** Replace the stale `DEATH_CAUSE_CODE` + `death_cause_available` assertion in R/88 Section 15o Check 6 with the current Phase-119 guard (`get_pcornet_table("DEATH_CAUSE")` + `is.null(dc_tbl)`) so the comprehensive smoke test exits 0.

## Objective

Phase 119 migrated R/102 from a non-existent `DEATH.DEATH_CAUSE` column to the separate PCORnet CDM `DEATH_CAUSE` table. R/88 Check 6 (Section 15o) was never updated — it still asserted `DEATH_CAUSE_CODE` and `death_cause_available`, neither of which appear in live R/102 code post-Phase-119. This caused 1 of N checks to fail and `Rscript R/88` to exit 1 (SLURM-breaking).

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Rewrite Section 15o Check 6 to assert current DEATH_CAUSE table-availability guard | c95353e | R/88_smoke_test_comprehensive.R |

## Changes Made

**R/88_smoke_test_comprehensive.R — Section 15o Check 6 (lines 2164-2168):**

Old (stale — Phase 118 pattern, broken after Phase 119):
```r
  # Check 6: DEATH_CAUSE field-availability guard
  check("R/102 has DEATH_CAUSE field-availability guard",
        grepl("DEATH_CAUSE_CODE", r102_text) && grepl("death_cause_available", r102_text))
```

New (correct — matches current R/102 lines 144-145):
```r
  # Check 6: DEATH_CAUSE table-availability guard (Phase 119: R/102 reads the
  # DEATH_CAUSE table via get_pcornet_table + is.null(dc_tbl) guard, not the
  # non-existent DEATH.DEATH_CAUSE column / old death_cause_available flag)
  check("R/102 has DEATH_CAUSE table-availability guard",
        grepl('get_pcornet_table\\("DEATH_CAUSE"\\)', r102_text) && grepl("is.null\\(dc_tbl\\)", r102_text))
```

## Acceptance Criteria Verification

### Static (all verified on this executor)

| Criterion | Result |
|-----------|--------|
| `R/102 has DEATH_CAUSE table-availability guard` present in R/88 Section 15o | PASS — line 2167 |
| `get_pcornet_table\\("DEATH_CAUSE"\\)` present in Check 6 block | PASS — line 2168 |
| `is.null\\(dc_tbl\\)` present in Check 6 block | PASS — line 2168 |
| `death_cause_available` absent from Section 15o assertion (only in comment + R/35 section at line 1136) | PASS — no live assertion uses it |
| `DEATH_CAUSE_CODE` absent from entire R/88 | PASS — zero occurrences |
| Check description reads "table-availability" not "field-availability" | PASS |
| `git diff -- R/102_death_cause_nhl_flag.R` is empty | PASS — R/102 byte-for-byte unchanged |
| Total check count in Section 15o unchanged (14 checks, Check 6 is still 1 check) | PASS |

### Runtime Acceptance Criterion — TO BE RUN ON HIPERGATOR

**FLAG: Rscript is NOT available in this Windows executor environment.**

The criterion `Rscript R/88_smoke_test_comprehensive.R` exits 0 with `FAILED: 0/<total>` cannot be verified locally. All static grep criteria above are satisfied. This runtime check MUST be run on HiPerGator before Phase 125 is considered fully closed:

```bash
module load R/4.4.2
cd /path/to/project
Rscript R/88_smoke_test_comprehensive.R
echo "EXIT=$?"
```

Expected output: zero `FAIL:` lines and `FAILED: 0/<total>` banner, exit code 0.

## Deviations from Plan

None — plan executed exactly as written. The single-file constraint was honored; R/102 is unchanged.

## Known Stubs

None.

## Self-Check

- [x] `R/88_smoke_test_comprehensive.R` modified — file exists and was committed at c95353e
- [x] Commit c95353e exists in git log
- [x] R/102 unchanged (empty git diff)
- [x] Static grep criteria all pass

## Self-Check: PASSED
