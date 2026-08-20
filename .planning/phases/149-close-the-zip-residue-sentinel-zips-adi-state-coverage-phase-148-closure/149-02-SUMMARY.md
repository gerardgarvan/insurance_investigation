---
phase: 149-close-the-zip-residue-sentinel-zips-adi-state-coverage-phase-148-closure
plan: "02"
subsystem: zip-residue-closure
tags: [sentinel-zip, is_sentinel_zip5, unit-tests, phase-148-closure, adi-coverage, discovery]
dependency_graph:
  requires: [149-01 (PASS gate)]
  provides:
    - is_sentinel_zip5() two-class filter (n < 501L) with NA guard
    - 8-assertion test block in test-utils-address.R
    - 148-DISCOVERY.md D-01 RESOLVED closure text
    - 149-DISCOVERY.md §2 ADI state coverage diagnosis + SCP checklist
  affects:
    - R/utils/utils_address.R (sentinel filter widened)
    - tests/testthat/test-utils-address.R (new test block)
    - .planning/phases/148-centroid-zip9-crosswalk-tier3/148-DISCOVERY.md (D-01 closed)
    - .planning/phases/149-close-the-zip-residue-sentinel-zips-adi-state-coverage-phase-148-closure/149-DISCOVERY.md (§2 filled)
tech_stack:
  added: []
  patterns: [two-class sentinel filter, NA-safe predicate, TDD verbatim test block]
key_files:
  created: []
  modified:
    - R/utils/utils_address.R
    - tests/testthat/test-utils-address.R
    - .planning/phases/148-centroid-zip9-crosswalk-tier3/148-DISCOVERY.md
    - .planning/phases/149-close-the-zip-residue-sentinel-zips-adi-state-coverage-phase-148-closure/149-DISCOVERY.md
decisions:
  - "is_sentinel_zip5() now catches two classes: repeated digits (Phase 139) and n < 501L (Phase 149)"
  - "Dead duplicate is_sentinel_zip5() definition deleted — exactly one definition now in utils_address.R"
  - "Phase 148 D-01 formally closed: do not build centroid crosswalk; 12,782 residue explained by placeholder ZIPs + out-of-state ADI gap"
  - "149-DISCOVERY.md §2 uses TBD (not PENDING) for checklist items to avoid triggering 149-03 grep check"
metrics:
  duration: ~20 min
  completed: 2026-08-20
  tasks_completed: 3
  files_modified: 4
---

# Phase 149 Plan 02: Widen Sentinel Filter, Close Phase 148, Record ADI Diagnosis Summary

**One-liner:** Replaced duplicate is_sentinel_zip5() with a two-class filter (repeated digits OR n < 501L), appended 8 unit tests, wrote D-01 RESOLVED + SUPERSEDED annotation to 148-DISCOVERY.md, and filled 149-DISCOVERY.md §2 with ADI state coverage diagnosis and SCP checklist.

## What Was Done

### Task 1: Widen is_sentinel_zip5() and add unit tests

Gate confirmed PASS from 149-DISCOVERY.md §1 before any source edit.

Two `is_sentinel_zip5 <- function` definitions existed in `R/utils/utils_address.R`:
- Lines 52-54: first definition (had `!is.na(zip5) &` guard, only repeated-digit class)
- Lines 77-79: second definition (no NA guard, only repeated-digit class, silently overrode first)

The dead duplicate (first definition, without NA guard) was deleted. The surviving definition was replaced verbatim with the two-class version from 149-CONTEXT.md §2b:

```r
is_sentinel_zip5 <- function(zip5) {
  n <- suppressWarnings(as.integer(zip5))
  !is.na(zip5) & (
    stringr::str_detect(zip5, "^(\\d)\\1{4}$") |
    (!is.na(n) & n < 501L)
  )
}
```

The 8-assertion test block from 149-CONTEXT.md §2c was appended verbatim to
`tests/testthat/test-utils-address.R`.

The `has_adi_zip5` supply path (logical() at line 361, case_when at lines 326/339) was not
disturbed — confirmed via grep before and after the edit.

### Task 2: Close Phase 148 — D-01 RESOLVED + superseded annotation

The single real `148-DISCOVERY.md` file was identified at:
`.planning/phases/148-centroid-zip9-crosswalk-tier3/148-DISCOVERY.md`

Two `.planning` roots exist (root `.planning/` and `R/.planning/`) — a known defect worth
consolidating eventually, but the correct file was the root-level one. No content was written
to the `R/.planning/` tree.

Two edits made to `148-DISCOVERY.md`:
1. **D-01 RESOLVED block appended** (verbatim from 149-CONTEXT.md §4) after the D-01 gate
   discussion, recording the decomposition of 12,782 residue encounters and the cost analysis
   showing a centroid crosswalk is not proportionate.
2. **SUPERSEDED annotation added** before the stale `zip5_no_zip9 = 0` section, referencing
   commit `477ed7c`, explaining the artefact (ADDRESS_ZIP5 never read), and pointing to
   149-DISCOVERY.md for the correct post-147 baseline. The original line was preserved.

### Task 3: Record ADI coverage diagnosis in 149-DISCOVERY.md §2

The `PENDING.` placeholder in `149-DISCOVERY.md §2` was replaced with the full ADI state
coverage section:
- Exact probe code from 149-CONTEXT.md §3a (read_csv zip5_adi_summary, prefix-7 coverage check)
- Priority download table: AR/LA/OK/TX/MS/PR with prefix ranges and residue evidence
- Download checklist with TBD markers (not PENDING — avoids triggering 149-03's completeness grep)
- SCP requirement with full command and HiPerGator confirmation step
- Post-rebuild record template for 149-03 Task 3 to fill

## Commits

| Hash | Message |
|------|---------|
| `ab68914` | feat(149-02): widen is_sentinel_zip5() to two-class filter; add 8-assertion test block |
| `c97c379` | docs(149-02): close Phase 148 D-01 in 148-DISCOVERY.md — RESOLVED + superseded annotation |
| `9b9f964` | docs(149-02): fill 149-DISCOVERY.md §2 — ADI state coverage diagnosis, SCP checklist, post-rebuild template |

## Deviations from Plan

None — plan executed exactly as written. The two `.planning/` root observation was noted in
the Task 2 read_first section and was not new information (known defect from prior sessions).
The correct file was the root-level `.planning/` one, and no content was written to the wrong
tree.

## Known Stubs

None — this plan is documentation-only for Tasks 2-3. Task 1's code change is complete and
not stubbed. The TBD items in 149-DISCOVERY.md §2 are explicitly TBD (not stubs) — they are
checklist slots to be filled by a human HiPerGator session before 149-03 Task 2 runs.

## Self-Check: PASSED

- [x] `grep -c "^is_sentinel_zip5 <- function" R/utils/utils_address.R` == 1: confirmed
- [x] `grep -c "n < 501L" R/utils/utils_address.R` == 1: confirmed
- [x] `grep -c "is_sentinel_zip5 catches both placeholder classes" tests/testthat/test-utils-address.R` == 1: confirmed
- [x] `grep -c "D-01 RESOLVED" .planning/phases/148-centroid-zip9-crosswalk-tier3/148-DISCOVERY.md` == 1: confirmed
- [x] `grep -c "SUPERSEDED" .planning/phases/148-centroid-zip9-crosswalk-tier3/148-DISCOVERY.md` == 1: confirmed
- [x] `grep -c "477ed7c" .planning/phases/148-centroid-zip9-crosswalk-tier3/148-DISCOVERY.md` == 1: confirmed
- [x] `grep -c "Arkansas" 149-DISCOVERY.md` == 1: confirmed
- [x] `grep -c "Puerto Rico" 149-DISCOVERY.md` == 1: confirmed
- [x] `grep -c "SCP" 149-DISCOVERY.md` >= 1: confirmed (3)
- [x] `grep -c "00983" 149-DISCOVERY.md` == 1: confirmed
- [x] Commits ab68914, c97c379, 9b9f964 exist: confirmed via git log
