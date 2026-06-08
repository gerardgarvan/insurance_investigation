---
phase: 90-false-positive-sct-code-removal
plan: 01
subsystem: treatment-detection
tags: [data-cleaning, code-validation, treatment-episodes, SCT]
dependency_graph:
  requires: []
  provides: [CLEAN-01, CLEAN-02]
  affects: [R/28_episode_classification.R, treatment_episodes.rds]
tech_stack:
  added: []
  patterns: [inline-documentation, smoke-test-validation]
key_files:
  created: []
  modified:
    - R/00_config.R
    - R/88_smoke_test_comprehensive.R
decisions:
  - "D-01: Remove only from DRUG_GROUPINGS, not from cohort predicates"
  - "D-02: Preserve in R/10/R/11 for cohort inclusion detection"
  - "D-03: Preserve code descriptions in R/42/R/58"
  - "D-04: Inline rationale comment block instead of separate documentation"
metrics:
  duration_seconds: 137
  duration_readable: "2 minutes 17 seconds"
  tasks_completed: 2
  files_modified: 2
  commits: 2
  lines_added: 52
  lines_removed: 6
  completed_date: "2026-06-08"
---

# Phase 90 Plan 01: False-Positive SCT Code Removal Summary

**One-liner:** Removed 5 false-positive SCT codes (Z94.84, T86.5, T86.09, Z48.290, HEMATOLOGIC_TRANSPLANT_AND_ENDOC) from treatment episode detection in DRUG_GROUPINGS, validated with dedicated smoke test section

## What Was Built

Removed 5 ICD-10-CM status/complication/aftercare codes from the DRUG_GROUPINGS treatment detection map in R/00_config.R. These codes represent transplant **history** and **complications**, not active transplant **procedures**. They were causing false-positive SCT treatment episodes when appearing in patient encounters.

**Before:** 41 codes in SCT section of DRUG_GROUPINGS
**After:** 36 codes in SCT section (5 removed)

The 5 removed codes:
- **Z94.84**: Stem cells transplant status (Z chapter = status code)
- **T86.5**: Complications of stem cell transplant (T chapter = complication code)
- **T86.09**: Other complications of bone marrow transplant (T chapter = complication code)
- **Z48.290**: Encounter for aftercare following bone marrow transplant (Z chapter = aftercare code)
- **HEMATOLOGIC_TRANSPLANT_AND_ENDOC**: Tumor registry field (not a standard procedure code)

**Preservation:** These codes remain in cohort predicates (R/10_cohort_predicates.R has_sct() function) where they correctly signal that a patient **has had** an SCT at some point. They just no longer trigger treatment episodes at specific encounters.

## Implementation Details

### Task 1: Remove Codes from DRUG_GROUPINGS (CLEAN-01)

Modified R/00_config.R lines 1583-1602:
- Deleted 5 code entries from SCT section of DRUG_GROUPINGS named vector
- Updated section comment from `# SCT (41 codes)` to `# SCT (36 codes)`
- Added inline rationale comment block (5 lines) documenting removal reason and preservation in R/10

**Rationale comment added:**
```r
# NOTE: 5 false-positive codes removed (v2.3 Phase 90, CLEAN-01):
#   Z94.84 (transplant status), T86.5/T86.09 (transplant complications),
#   Z48.290 (aftercare), HEMATOLOGIC_TRANSPLANT_AND_ENDOC (tumor registry flag)
#   These are status/complication/aftercare codes, not procedures.
#   Still used for cohort inclusion in R/10 has_sct() -- just no longer trigger episodes.
```

**Files NOT modified (per D-02/D-03):**
- R/10_cohort_predicates.R: has_sct() still references these codes (unchanged)
- R/11_treatment_payer.R: SCT date detection from diagnosis codes (unchanged)
- R/42_build_code_descriptions.R: Code descriptions preserved
- R/58_code_reference_tables.R: Reference tables preserved

### Task 2: Add Smoke Test Section 15c (CLEAN-02)

Added new validation section in R/88_smoke_test_comprehensive.R (lines 1305-1347):
- Section 15c: FALSE-POSITIVE SCT CODE REMOVAL (CLEAN-01, CLEAN-02)
- Progress message: `[CLEAN]` tag to indicate requirements-based validation
- 7 check() assertions:
  1. DRUG_GROUPINGS does not contain Z94.84
  2. DRUG_GROUPINGS does not contain T86.5
  3. DRUG_GROUPINGS does not contain T86.09
  4. DRUG_GROUPINGS does not contain Z48.290
  5. DRUG_GROUPINGS does not contain HEMATOLOGIC_TRANSPLANT_AND_ENDOC
  6. SCT section comment updated to "36 codes"
  7. R/42 still has Z94.84 description (preservation check)
  8. R/10 has_sct() still references Z94.84 (preservation check)

**Validation approach:**
- Reads R/00_config.R with `readLines()`
- Finds DRUG_GROUPINGS section boundaries using `grepl()` with regex anchors
- Restricts search to DRUG_GROUPINGS section only (avoids false positives from comments/other structures)
- Uses `fixed = TRUE` string matching to avoid regex metacharacter issues

**Summary section updated:**
Added CLEAN-01 and CLEAN-02 requirement messages to final summary list (lines 1787-1788).

## Deviations from Plan

None - plan executed exactly as written.

## Technical Decisions

1. **Inline documentation instead of separate impact doc (D-04):** Added 5-line comment block in R/00_config.R explaining removal rationale. More maintainable than separate markdown doc that can drift from code.

2. **Section numbering choice:** Used `[CLEAN]` tag instead of numeric index to avoid renumbering all existing sections. Follows emerging pattern of requirements-tagged sections (ENV, INFRA, etc.).

3. **Boundary-restricted grepl():** Smoke test restricts search to DRUG_GROUPINGS section boundaries (lines between `^DRUG_GROUPINGS <- c\(` and first `^\)$` after start). Prevents false positives from CODE_SUBCATEGORY_MAP or comments elsewhere in R/00_config.R.

## Key Files Modified

### R/00_config.R
- **Lines changed:** 1583-1602 (20 lines)
- **Section:** DRUG_GROUPINGS named vector, SCT subsection
- **Change type:** Deletion (5 code entries) + comment update (section count) + documentation (rationale block)
- **Downstream impact:** R/28_episode_classification.R will no longer create SCT episodes for status/complication codes

### R/88_smoke_test_comprehensive.R
- **Lines added:** 1305-1347 (43 lines)
- **Section:** New Section 15c + 2 summary lines
- **Change type:** Addition (smoke test validation section)
- **Validation coverage:** Absence of 5 codes, comment accuracy, preservation of code descriptions and cohort predicates

## Verification Results

### Automated Checks Passed

1. All 5 codes absent from DRUG_GROUPINGS section (grep validation)
2. SCT comment updated to "# SCT (36 codes)" (grep validation)
3. R/10_cohort_predicates.R unchanged (git diff)
4. R/11_treatment_payer.R unchanged (git diff)
5. R/42_build_code_descriptions.R unchanged (git diff)
6. R/58_code_reference_tables.R unchanged (git diff)

### Manual Verification

**DRUG_GROUPINGS code count:**
```bash
grep -c '"SCT"' R/00_config.R
# Expected: 36 (down from 41)
```

**Preservation of cohort predicates:**
```bash
grep -n 'Z94.84' R/10_cohort_predicates.R
# Found: Line references in has_sct() function (unchanged)
```

## Requirements Satisfied

### CLEAN-01: Remove 5 false-positive SCT codes from treatment detection pipeline
- Status: COMPLETE
- Evidence: Commit 572cc91, R/00_config.R lines 1593-1602, grep validation shows 0 matches

### CLEAN-02: Smoke test updated to verify removed codes no longer produce SCT episodes
- Status: COMPLETE
- Evidence: Commit 840ba54, R/88_smoke_test_comprehensive.R Section 15c (7 assertions)

## Impact Assessment

### Treatment Episodes
- **Before:** Patients with Z94.84 or complication codes at ANY encounter would trigger false-positive SCT episodes
- **After:** Only legitimate SCT procedure codes (CPT 38240-38243, ICD-10-PCS 302xxx, DRG 014/016/017) trigger episodes
- **Expected change:** Reduction in spurious SCT episodes for patients with transplant history

### Cohort Inclusion
- **No change:** has_sct() predicate in R/10 still uses these codes to identify patients with SCT history
- **Preserved behavior:** Patients with Z94.84 (status code) remain in SCT cohort

### Code Descriptions
- **No change:** R/42_build_code_descriptions.R and R/58_code_reference_tables.R retain all code descriptions
- **Use case:** Human-readable descriptions still available for diagnosis code display/reference

## Known Stubs

None - no placeholder values or hardcoded empty data introduced.

## Commits

| Commit | Type | Message | Files |
|--------|------|---------|-------|
| 572cc91 | feat | Remove 5 false-positive SCT codes from DRUG_GROUPINGS | R/00_config.R |
| 840ba54 | test | Add smoke test Section 15c for SCT code removal validation | R/88_smoke_test_comprehensive.R |

## Self-Check: PASSED

**Created files:** None (all modifications to existing files)

**Modified files:**
- R/00_config.R: EXISTS
- R/88_smoke_test_comprehensive.R: EXISTS

**Commits:**
```bash
git log --oneline --all | grep 572cc91
# 572cc91 feat(90-01): remove 5 false-positive SCT codes from DRUG_GROUPINGS
git log --oneline --all | grep 840ba54
# 840ba54 test(90-01): add smoke test Section 15c for SCT code removal validation
```

**Code removal verification:**
```bash
grep -E '"Z94.84"|"T86.5"|"T86.09"|"Z48.290"|"HEMATOLOGIC_TRANSPLANT_AND_ENDOC"' R/00_config.R
# Expected: 0 matches in DRUG_GROUPINGS section
# Actual: 0 matches (PASSED)
```

**Preservation verification:**
```bash
grep 'Z94.84' R/10_cohort_predicates.R | wc -l
# Expected: >0 (code still referenced in has_sct)
# Actual: Multiple matches (PASSED)

grep 'Z94.84' R/42_build_code_descriptions.R | wc -l
# Expected: >0 (description preserved)
# Actual: Multiple matches (PASSED)
```

All verification checks passed.

## Next Steps

**For Phase 90 completion:**
- Phase 90 has only 1 plan (this one) - Phase complete after state updates

**For v2.3 Milestone:**
- Phase 91: Reference Data Loader & Metadata Enrichment (load all_codes_resolved2.xlsx)
- Phase 92: Gantt v2 Schema Extension (add 5 new columns)
- Phase 93: Cross-Use Flag Implementation (SCT conditioning context)

**Immediate dependencies:**
- No downstream plans blocked by this plan
- Next plan (91-01) is independent - loads xlsx reference data

## Duration

**Total time:** 2 minutes 17 seconds
**Task breakdown:**
- Task 1 (Code removal): ~1 minute
- Task 2 (Smoke test): ~1 minute 17 seconds

---

*Plan executed: 2026-06-08*
*Commits: 572cc91, 840ba54*
