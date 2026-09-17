---
phase: 153-patient-zip-calendar-and-best-zip-selection
verified: 2026-09-17T00:00:00Z
status: passed
score: 14/14 must-haves verified
re_verification: false
---

# Phase 153: Patient ZIP Calendar and Best-ZIP Selection — Verification Report

**Phase Goal:** Build patient ZIP calendar and best-ZIP selection utilities, wire them into encounter distance script, and add test coverage.
**Verified:** 2026-09-17
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (Plans 01, 02, 03)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Every encounter's patient ZIP is the ZIP active on ADMIT_DATE, or the temporally nearest one when no period covers it | VERIFIED | `pick_best_zip()` inner-joins cal to enc, classifies in_range, and falls through to nearest with signed days_offset |
| 2 | Each picked patient ZIP carries a zip5_patient_source provenance label and a signed days_offset | VERIFIED | `transmute()` in pick_best_zip() produces both columns; four source labels present |
| 3 | ZIP9 reduced to ZIP5 before distance (DIST-02) | VERIFIED | `build_patient_zip_calendar()` derives zip5 from normalize_zip5 / substr(zip9,1,5); `compute_encounter_distance()` calls zip_distance on zip5_patient / zip5_facility |
| 4 | An in-range ZIP5 always beats an out-of-range ZIP9 (D-04 Zone 1 > Zone 2) | VERIFIED | D-04 two-zone arrange: `desc(in_range)` sorts Zone 1 before Zone 2 regardless of zip_len; Test 5 asserts this |
| 5 | get_zip9_at_date() in utils_address.R is unchanged; only SECTION 4 of R/122 replaced | VERIFIED | grep for `res_lookup <- get_zip9_at_date` returns 0 matches in R/122; normalize_zip9 not redefined in utils_zip_calendar.R |
| 6 | R/122 SECTION 4 uses build_patient_zip_calendar() + compute_encounter_distance() | VERIFIED | Both calls present in R/122 lines 246 and 257; source("R/utils/utils_zip_calendar.R") at line 60 |
| 7 | R/122 output carries zip5_patient_source, days_offset, n_candidates_in_range, and distance_status | VERIFIED | All four columns selected into enc_distance output (lines 516-521) |
| 8 | A completeness waterfall sheet reconciles row-for-row with distance_status counts | VERIFIED | stopifnot at line 672 asserts n_status_computed == n_distance_computed and four category counts sum to nrow(enc_distance); E_completeness sheet added via add_styled_sheet() |
| 9 | n_candidates_in_range > 1 count reported in QC | VERIFIED | Line 813: `n_candidates_gt1 <- sum(enc_distance$n_candidates_in_range > 1, na.rm = TRUE)`; added as a Metric row to qc_tbl |
| 10 | utils_zip_calendar.R registered in R/SCRIPT_INDEX.md | VERIFIED | Two matching lines found in SCRIPT_INDEX.md |
| 11 | Duplicate address periods collapse to one calendar row | VERIFIED | Test 1: `expect_equal(nrow(build_patient_zip_calendar(dup_addr)), 1L)` |
| 12 | Overlapping same-ZIP periods merge; D-05 tie-break correct; in-range ZIP5 beats out-of-range ZIP9; open period closes at study end; no-history yields patient_zip_missing; out-of-range nearest ignores ZIP tier | VERIFIED | Tests 2–8 in test-utils-zip-calendar.R with computed-value assertions |
| 13 | R/88 has a Phase 153 structural-check section (Section 15ai) | VERIFIED | Section 15ai at line 5338 with check_153 helper, p153_pass/p153_fail counters, 14 checks, SMOKE-153-01 footer |
| 14 | No redefinition of normalize_zip9/normalize_zip5/is_sentinel_zip5 in utils_zip_calendar.R | VERIFIED | grep returns 0 matches for `normalize_zip9 <- function` in utils_zip_calendar.R |

**Score:** 14/14 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/utils/utils_zip_calendar.R` | build_patient_zip_calendar(), pick_best_zip(), compute_encounter_distance() | VERIFIED | 251 lines; all three functions defined; D-04 two-zone arrange; D-05 tie-break; four source/status labels each; no redefinition of utils_address.R helpers |
| `R/122_encounter_distance.R` | Wired compute_encounter_distance() + completeness waterfall sheet | VERIFIED | source() at line 60; SECTION 4 replaced; fan-out stopifnot at line 284; waterfall stopifnot at line 672; E_completeness sheet; provenance columns in output |
| `R/SCRIPT_INDEX.md` | utils_zip_calendar.R registration | VERIFIED | Entry present alongside utils_address.R |
| `tests/testthat/test-utils-zip-calendar.R` | Unit tests for all three functions | VERIFIED | 8 test_that blocks covering all milestone-listed cases; computed-value assertions; no HiPerGator data required |
| `R/88_smoke_test_comprehensive.R` | Section 15ai Phase 153 structural checks | VERIFIED | 14 grep/file-existence checks; p153_pass/p153_fail counters; SMOKE-153-01 footer line |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| R/utils/utils_zip_calendar.R | R/utils/utils_address.R | normalize_zip9 / is_sentinel_zip5 reuse (no redefinition) | VERIFIED | calls normalize_zip9, normalize_zip5, is_sentinel_zip5 without redefining them |
| pick_best_zip() | two-zone arrange | `desc(in_range), if_else(in_range,-zip_len,0L), abs(days_offset), desc(days_offset)` | VERIFIED | exact arrange call present at lines 166-170 |
| R/122_encounter_distance.R | R/utils/utils_zip_calendar.R | source() + SECTION 4 call | VERIFIED | `source("R/utils/utils_zip_calendar.R")` at line 60; build_patient_zip_calendar() at line 246; compute_encounter_distance() at line 257 |
| completeness waterfall sheet | distance_status counts | row-for-row reconciliation stopifnot | VERIFIED | stopifnot at lines 672-678 asserts all four status categories sum to nrow(enc_distance) |
| tests/testthat/test-utils-zip-calendar.R | R/utils/utils_zip_calendar.R | source via withr::with_dir() | VERIFIED | explicit source("R/utils/utils_zip_calendar.R") in test file; all three functions called |

---

### Data-Flow Trace (Level 4)

utils_zip_calendar.R functions are pure (no file I/O). R/122 is the runtime consumer; data flows verified statically:

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| R/122 SECTION 4 | dist_result | compute_encounter_distance(enc_for_dist, cal) | Yes — cal from vroom(LDS_ADDRESS_HISTORY), enc from encounters_raw | FLOWING |
| E_completeness sheet | completeness_tbl | sum() counts on enc_distance$distance_status / zip5_patient_source | Yes — derived from dist_result join | FLOWING |
| QC sheet | n_candidates_gt1, nearest days_offset distribution | enc_distance$n_candidates_in_range, enc_distance$days_offset | Yes — carried through from pick_best_zip() transmute | FLOWING |

---

### Behavioral Spot-Checks

Step 7b: SKIPPED for R/122 and R/88 (no runnable entry points without HiPerGator data). Unit test file exercises pure functions; Rscript unavailable in this Windows environment (deferred to HiPerGator run per plan acceptance criteria). Structural grep checks pass.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| DIST-02 | 153-01, 153-02 | ZIP9 reduced to ZIP5 before distance | SATISFIED | normalize_zip5 applied in build_patient_zip_calendar(); zip_distance() called on zip5 pairs |
| DIST-03 | 153-01, 153-02 | Bidirectional nearest-ZIP fill with provenance | SATISFIED | pick_best_zip() uses abs(days_offset) ranking in both directions; zip5_patient_source labels nearest_zip9/nearest_zip5 |
| DIST-07 | 153-02, 153-03 | Registration in SCRIPT_INDEX.md; R/88 structural checks; test coverage | SATISFIED | SCRIPT_INDEX.md entry present; R/88 Section 15ai 14 checks + SMOKE-153-01; 8-test test file |

---

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| None detected | — | — | — |

Checks run: no TODO/FIXME/placeholder comments in utils_zip_calendar.R; no empty return null / return {} stubs; no redefined helpers from utils_address.R; get_zip9_at_date() removed from SECTION 4; facility_zip_missing classified first in case_when (no imputation risk).

One minor observation (not a blocker): R/122 header comments at lines 12 and 29 still reference `get_zip9_at_date()` in the top-of-file description block. These are documentation comments, not executable code, and do not affect runtime behavior.

---

### Human Verification Required

#### 1. End-to-end distance computation on HiPerGator

**Test:** Run `Rscript R/122_encounter_distance.R` on HiPerGator with the live CSV data.
**Expected:** Workbook produced; E_completeness sheet shows waterfall values where n_facility_missing + n_patient_missing + n_zip_not_in_db + n_computed == nrow(enc_distance); stopifnots pass without error.
**Why human:** Requires HiPerGator data files and R environment; cannot execute locally.

#### 2. Testthat run on HiPerGator

**Test:** `Rscript -e "testthat::test_file('tests/testthat/test-utils-zip-calendar.R')"` from the project root.
**Expected:** 8 tests pass, 0 failures. Test 6 (patient_zip_missing via zipcodeR) passes if zipcodeR is installed, or is skipped cleanly.
**Why human:** Requires R with dplyr, zipcodeR, testthat, here, withr installed on HiPerGator.

#### 3. R/88 Section 15ai green run

**Test:** Run `Rscript R/88_smoke_test_comprehensive.R` on HiPerGator. Check Section 15ai output.
**Expected:** "Section 15ai: 14 PASS, 0 FAIL"
**Why human:** Requires HiPerGator R environment; grep-based checks are structurally verified here but need runtime confirmation.

---

### Gaps Summary

No gaps found. All 14 must-have truths verified against the actual codebase. All artifacts exist, are substantive, and are wired. Key links are connected. No anti-patterns blocking goal achievement.

---

_Verified: 2026-09-17_
_Verifier: Claude (gsd-verifier)_
