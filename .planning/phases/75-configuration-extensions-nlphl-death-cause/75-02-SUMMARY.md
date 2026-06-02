---
phase: 75-configuration-extensions-nlphl-death-cause
plan: 02
type: execute
subsystem: testing
tags: [smoke-test, nlphl, death-cause, validation, regression-safety]
dependency_graph:
  requires: [ICD9_NLPHL_CODES, CANCER_SITE_MAP.C810, CANCER_SITE_MAP.C81, DEATH_CAUSE_MAP, classify_codes_hierarchical]
  provides: [smoke_test_nlphl_validation, smoke_test_death_cause_validation]
  affects: [R/88]
tech_stack:
  added: []
  patterns: [mutual-exclusivity-testing, structural-validation, code-level-classification]
key_files:
  created: []
  modified:
    - path: R/88_smoke_test_comprehensive.R
      lines_added: 122
      lines_removed: 19
      description: "Added SECTION 13 (NLPHL + DEATH_CAUSE_MAP validation, 11 checks), updated counters from /17 to /18, renamed SECTION 13 to SECTION 14"
decisions:
  - id: D-01
    summary: "Code-level classification testing (not patient-level)"
    rationale: "Smoke test validates classify_codes() function correctness, not cohort composition"
  - id: D-02
    summary: "Representative sample of 20 test codes (4+4+6+6)"
    rationale: "Covers NLPHL ICD-10, NLPHL ICD-9, classical ICD-10, classical ICD-9 across subcategories"
  - id: D-03
    summary: "Mutual exclusivity as sum check (not percentage)"
    rationale: "Exact count comparison catches silent failures (NLPHL + classical = total)"
  - id: D-04
    summary: "Major ICD-10 chapters as coverage proxy (5 codes)"
    rationale: "C81 (cancer), I25 (cardiac), J44 (respiratory), E11 (endocrine), G30 (neuro) span key mortality causes"
metrics:
  duration_seconds: 103
  duration_human: "1 minute 43 seconds"
  completed_date: "2026-06-02"
  tasks_completed: 1
  commits: 1
---

# Phase 75 Plan 02: Smoke Test Validation for NLPHL and Death Cause Summary

**One-liner:** Smoke test validates NLPHL mutual exclusivity (11 checks: 4-char prefix matching, ICD-9 exact match, mutual exclusivity sum) and DEATH_CAUSE_MAP structural integrity (30+ entries, UNK fallback, major chapter coverage)

## What Was Built

Extended R/88_smoke_test_comprehensive.R with a new test section validating Phase 75 configuration changes. Section 13 performs 11 structural checks ensuring classify_codes() correctly implements NLPHL breakout via hierarchical prefix matching and DEATH_CAUSE_MAP provides adequate coverage for mortality analysis.

**Key artifacts:**
- SECTION 13: NLPHL CLASSIFICATION & DEATH CAUSE VALIDATION (11 checks)
- Test coverage: 20 HL codes (4 NLPHL ICD-10, 4 NLPHL ICD-9, 6 classical ICD-10, 6 classical ICD-9)
- DEATH_CAUSE_MAP validation: entry count, UNK fallback, major chapter coverage
- Updated counters: all test groups from /17 to /18
- Version bump: v2.0 → v2.1

## How It Works

**NLPHL Mutual Exclusivity Testing (Checks 1-8):**
1. Define 20 test codes: 8 NLPHL codes + 12 classical HL codes across ICD-9 and ICD-10
2. Pass all codes through classify_codes() function
3. Verify NLPHL codes → "NLPHL" (checks 1-2)
4. Verify classical codes → "Hodgkin Lymphoma (non-NLPHL)" (checks 3-4)
5. Verify mutual exclusivity: NLPHL count + classical count = 20 (check 5)
6. Verify CANCER_SITE_MAP structure: C810 and C81 entries exist with correct values (checks 6-7)
7. Verify ICD9_NLPHL_CODES has 10 entries (check 8)

**DEATH_CAUSE_MAP Validation (Checks 9-11):**
1. Verify map exists and has >= 30 entries (Phase 75 added 167)
2. Verify UNK fallback exists (catches unmapped codes)
3. Verify 5 major ICD-10 chapters present (C81, I25, J44, E11, G30)

**Mutual Exclusivity Logic:**
- `all_hl_codes = [C810, C8100, C8105, C8109, 201.4, 201.40, 201.45, 201.48, C811, C8110, C812, C8120, C819, C8190, 201.0, 201.00, 201.5, 201.50, 201.9, 201.90]` (20 codes)
- `nlphl_count = 8` (from classify_codes)
- `classical_count = 12` (from classify_codes)
- `total = 20` (input length)
- Check passes if `nlphl_count + classical_count == total` (ensures no NA, no overlap, no missing)

## Verification

**Manual verification (R not available on local machine):**
- ✓ 18 occurrences of `/18]` (all counters updated)
- ✓ 0 occurrences of `/17]` (all old counters replaced)
- ✓ SECTION 13: NLPHL CLASSIFICATION exists
- ✓ SECTION 14: SUMMARY exists (renamed from SECTION 13)
- ✓ classify_codes(nlphl_icd10) test exists
- ✓ 13 occurrences of DEATH_CAUSE_MAP (sufficient coverage)
- ✓ UNK check exists
- ✓ All 11 check() calls present in Section 13
- ✓ Validated requirements updated with CANCER-01 and DEATH-01/02

**Expected behavior (will be validated on HiPerGator):**
- All 11 new checks should PASS
- No FAIL lines in smoke test output
- Exit code 0 (all checks pass)
- Output contains "PASS: ICD-10 C81.0x codes classify as 'NLPHL'"
- Output contains "PASS: Mutual exclusivity: NLPHL (8) + classical (12) = total (20)"
- Output contains "PASS: DEATH_CAUSE_MAP has >= 30 entries (found 167)"

## Deviations from Plan

None — plan executed exactly as written.

## Commits

| Hash | Message | Files |
|------|---------|-------|
| 2c3d025 | feat(75-02): add NLPHL and DEATH_CAUSE_MAP validation to smoke test | R/88_smoke_test_comprehensive.R |

## Known Stubs

None — validation logic is fully implemented. Smoke test will run on HiPerGator during next pipeline execution to confirm all checks pass.

## Downstream Impact

**Immediate (Phase 75 only):**
- Smoke test now validates Phase 75 configuration changes
- Any future changes to CANCER_SITE_MAP or classify_codes() that break NLPHL mutual exclusivity will be caught immediately
- DEATH_CAUSE_MAP structure is validated before Phase 78 consumption

**Regression safety:**
- If a developer accidentally removes C810 from CANCER_SITE_MAP, smoke test will fail (check 6)
- If classify_codes() hierarchical logic breaks, mutual exclusivity check will fail (check 5)
- If DEATH_CAUSE_MAP is deleted, check 9 will fail
- If UNK fallback is removed, check 10 will fail

**Future phases:**
- Phase 77: Cancer analysis scripts will use classify_codes() with confidence that NLPHL breakout is structurally valid
- Phase 78: Death cause profiling scripts will use DEATH_CAUSE_MAP with confidence that coverage is adequate
- Phase 79: Gantt chart will show NLPHL as distinct category, validated by smoke test

## Test Coverage

**NLPHL Classification:**
- ICD-10 NLPHL subcategories: C810, C8100, C8105, C8109 (4/10 possible codes)
- ICD-9 NLPHL codes: 201.4, 201.40, 201.45, 201.48 (4/10 possible codes)
- ICD-10 classical HL: C811, C8110, C812, C8120, C819, C8190 (6 codes across 3 subcategories)
- ICD-9 classical HL: 201.0, 201.00, 201.5, 201.50, 201.9, 201.90 (6 codes across 5 subcategories)
- **Total test codes:** 20 (covers both ICD versions, both HL subtypes, multiple subcategories)

**DEATH_CAUSE_MAP Coverage:**
- Entry count: >= 30 (actual: 167)
- UNK fallback: present
- Major chapters: 5 (cancer, cardiac, respiratory, endocrine, neurological)
- **Coverage:** Sufficient for Phase 78 mortality analysis

## Self-Check: PASSED

**Files created/modified exist:**
- ✓ R/88_smoke_test_comprehensive.R exists and contains SECTION 13
- ✓ R/88_smoke_test_comprehensive.R contains all 11 new check() calls
- ✓ R/88_smoke_test_comprehensive.R contains updated counters (/18)
- ✓ R/88_smoke_test_comprehensive.R contains SECTION 14: SUMMARY (renamed)

**Commits exist:**
- ✓ 2c3d025 exists in git log

**Structure validation:**
- ✓ Version updated to v2.1 (verified via grep)
- ✓ All counters updated from /17 to /18 (18 occurrences of /18, 0 of /17)
- ✓ SECTION 13 contains classify_codes() calls (verified via grep)
- ✓ SECTION 13 contains DEATH_CAUSE_MAP validation (13 occurrences)
- ✓ Validated requirements list includes CANCER-01 and DEATH-01/02 (verified via grep)
