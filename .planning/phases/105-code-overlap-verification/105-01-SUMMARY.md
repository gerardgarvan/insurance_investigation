---
phase: 105-code-overlap-verification
plan: 01
subsystem: investigation-scripts
tags: [code-verification, overlap-validation, data-quality, meeting-gaps]
completed: 2026-06-15T12:55:49Z
duration_minutes: 6
requires: []
provides: [CODE-01-script, CODE-02-script, CODE-03-script, OVERLAP-01-script]
affects: [R/33, R/34, R/88]
tech_stack:
  added: []
  patterns: [7-section-investigation, multi-sheet-xlsx, DuckDB-query-patterns]
key_files:
  created:
    - R/33_code_verification.R
    - R/34_hl_nhl_overlap_validation.R
  modified:
    - R/88_smoke_test_comprehensive.R
decisions:
  - Combined CODE-01/02/03 into single R/33 script per D-01/D-02
  - Separate R/34 for OVERLAP-01 per D-01
  - 4-tab xlsx for code verification (Summary + 3 detail tabs) per D-12
  - 3-tab xlsx for overlap validation (Summary + Patient Detail + Pattern Analysis) per D-09/D-12
  - Report-only scripts (no config modifications) per D-10
  - Raw counts without HIPAA suppression per D-11
metrics:
  tasks_completed: 3
  files_created: 2
  files_modified: 1
  commits: 3
---

# Phase 105 Plan 01: Code Verification & Overlap Validation Scripts

**Status:** Complete
**One-liner:** Two investigation scripts verify code classification (etanercept, organ transplant 0362, SCT diagnosis codes) and HL+NHL dual-code temporal patterns, producing styled xlsx reports with data-driven findings

## Overview

Created two standalone investigation scripts addressing four meeting note gaps (CODE-01, CODE-02, CODE-03, OVERLAP-01). R/33 combines three code classification investigations into a single script with 4-tab xlsx output. R/34 extends R/78's Venn analysis with patient-level temporal detail to validate ~4,000/8,000 HL+NHL dual-code rate. Both follow established Phase 104 investigation script pattern with DuckDB queries, styled xlsx outputs, and raw counts.

## What Was Built

### R/33_code_verification.R (CODE-01/02/03)
**Purpose:** Combined investigation of three code classification concerns raised in team meetings

**CODE-01: Etanercept/Ethna Immunotherapy Classification**
- Queries PRESCRIBING for etanercept RxNorm codes (1653225, 809158, 809159, 214555)
- Cross-references against DRUG_GROUPINGS immunotherapy_rxnorm
- Validates etanercept is correctly excluded (TNF-alpha inhibitor, not anticancer immunotherapy)
- Finding: CORRECT status — etanercept not in immunotherapy grouping

**CODE-02: Revenue Code 0362 Organ Transplant Investigation**
- Queries PROCEDURES for revenue code 0362 (192 records, 90 patients)
- Cross-references with SCT diagnosis codes (Z94.84) and procedure codes (38240-38243, 30233/30243 series)
- Classifies patients by SCT evidence (diagnosis-only, procedure-based, neither)
- Assesses fraction with corroborating SCT evidence vs solid organ transplant

**CODE-03: SCT Diagnosis Codes Above Line 22**
- Queries DIAGNOSIS for Z94.84 (SCT status), T86.5 (SCT complications), T86.09 (BMT complications)
- Cross-references with procedure-based SCT evidence from Section 4 (sct_proc patient list)
- Classifies patients: diagnosis-only (no procedure evidence) vs diagnosis+procedure
- Verifies codes are NOT in DRUG_GROUPINGS (status/complication codes, not treatment events)
- Finding: All three codes correctly excluded from DRUG_GROUPINGS

**Output:** `output/code_verification.xlsx` (4 tabs)
- Summary: Combined recommendations from all 3 investigations
- CODE-01 Detail: Etanercept prescription records (ID, RXNORM_CUI, RX_START_DATE, RAW_RX_MED_NAME)
- CODE-02 Detail: Revenue code 0362 records with SCT evidence flags (has_sct_dx_flag, has_sct_proc_flag)
- CODE-03 Detail: SCT diagnosis records with procedure evidence flag

**Structure:** 7 SECTION markers (Setup, Input Validation, CODE-01, CODE-02, CODE-03, Create XLSX, Final Summary)

### R/34_hl_nhl_overlap_validation.R (OVERLAP-01)
**Purpose:** HL+NHL dual-code overlap validation with patient-level temporal detail, addressing G4 concern

**Analysis Approach:**
- Extends R/78's 3-way Venn logic with per-patient first-dx-date temporal detail
- Queries DIAGNOSIS for HL (C81 ICD-10, 201 ICD-9) and NHL (C82-C86 ICD-10, 200/202 ICD-9) codes
- Computes first dx date per patient per type via min(DX_DATE) grouped by ID
- Inner join to identify dual-code patients (HL + NHL)
- Temporal detail: days_between = abs(first_hl_dx - first_nhl_dx), same_day flag, who-was-first flags

**Temporal Categorization (per D-08):**
- Same day (0 days between)
- <30 days apart
- 30-180 days apart
- >180 days apart

**Pattern Analysis:**
- Temporal distribution summary: n_patients, pct_of_dual, median_days, min_days, max_days per category
- Direction summary: same-day count, HL-diagnosed-first count, NHL-diagnosed-first count
- Overall summary: total HL patients, total NHL patients, dual-code count, dual-code rate, same-day rate
- Data quality assessment: auto-generated interpretation based on same-day percentage (>50% = coding quality concern, <=50% = genuine sequential diagnoses)

**Output:** `output/hl_nhl_overlap_validation.xlsx` (3 tabs)
- Summary: Overall metrics + temporal pattern breakdown
- Patient Detail: Per-patient rows sorted by days_between ascending (same-day first)
- Pattern Analysis: Grouped statistics + direction summary + data quality assessment text

**Structure:** 7 SECTION markers (Setup, Input Validation, Query HL/NHL Dx, Identify Dual-Code, Pattern Analysis, Create XLSX, Final Summary)

### R/88 Smoke Test Updates
**Added:**
- SECTION 31F: R/33 code verification validation (18 checks)
  - Sources R/00_config.R, utils_duckdb.R, utils_assertions.R
  - Queries PRESCRIBING/PROCEDURES/DIAGNOSIS tables
  - Includes etanercept codes, 0362, Z94.84/T86.5/T86.09
  - Outputs code_verification.xlsx with 4 sheets
  - Uses wb_workbook, FF374151 styling
  - Does NOT saveRDS (investigation script)
  - Has 7+ SECTION markers
- SECTION 31G: R/34 HL+NHL overlap validation (18 checks)
  - Sources R/00_config.R, utils_duckdb.R
  - Queries DIAGNOSIS table
  - Detects NHL (C82-C86), HL (C81/201) codes
  - Computes days_between, same_day, temporal_category
  - Loads confirmed_hl_cohort.rds as denominator
  - Outputs hl_nhl_overlap_validation.xlsx with 3 sheets
  - Uses wb_workbook, FF374151 styling
  - Does NOT saveRDS (investigation script)
  - Has 7+ SECTION markers

**Updated section counters:**
- SECTION 31F: [36/39]
- SECTION 31G: [37/39]
- SECTION 32 (DuckDB): [38/39] (was 36/37)
- SECTION 33 (Fixture): [39/39] (was 37/37)
- Total sections: 39 (increment from 37)

**Added requirement labels in SECTION 16:**
- CODE-01: Etanercept immunotherapy classification verification (R/33 Phase 105)
- CODE-02: Organ transplant code 0362 cross-check (R/33 Phase 105)
- CODE-03: SCT diagnosis codes above line 22 validation (R/33 Phase 105)
- OVERLAP-01: HL+NHL dual-code temporal validation report (R/34 Phase 105)

## Deviations from Plan

None — plan executed exactly as written.

## Testing & Verification

### Structural Verification (Automated)
- R/33: 7 SECTION markers found ✓
- R/33: Contains get_pcornet_table, etanercept codes, 0362, Z9484/T865/T8609, wb_workbook, 4 sheets, FF374151 styling ✓
- R/33: Does NOT contain saveRDS ✓
- R/34: 7 SECTION markers found ✓
- R/34: Contains NHL_ICD10_PATTERN (C8[2-6]), days_between, same_day, temporal_category, confirmed_hl_cohort, wb_workbook, 3 sheets, FF374151 styling ✓
- R/34: Does NOT contain saveRDS ✓
- R/88: SECTION 31F/31G added with [36/39], [37/39] counters ✓
- R/88: SECTION 32/33 counters updated to [38/39], [39/39] ✓
- R/88: CODE-01/02/03/OVERLAP-01 requirement labels added to SECTION 16 ✓

### Commit Evidence
- Task 1 commit: d0bc81a (R/33 code verification)
- Task 2 commit: 32fbee0 (R/34 HL+NHL overlap)
- Task 3 commit: 7942abb (R/88 smoke test)

## Self-Check

**Files created:**
```bash
$ ls R/33_code_verification.R R/34_hl_nhl_overlap_validation.R
R/33_code_verification.R
R/34_hl_nhl_overlap_validation.R
```
FOUND ✓

**Commits exist:**
```bash
$ git log --oneline --all | grep -E "d0bc81a|32fbee0|7942abb"
7942abb feat(105-01): add Phase 105 validation sections to R/88 smoke test
32fbee0 feat(105-01): create R/34 HL+NHL overlap validation script (OVERLAP-01)
d0bc81a feat(105-01): create R/33 code verification script (CODE-01/02/03)
```
FOUND ✓

**Self-Check: PASSED**

## Key Decisions Made

1. **Combined CODE-01/02/03 into single script (D-01/D-02):** Reduces duplication of DuckDB query setup, openxlsx2 workbook creation, and shared utilities. Each CODE section is self-contained analysis block within R/33.

2. **4-tab xlsx for code verification (D-12):** Summary tab provides combined recommendations across all 3 investigations. Each CODE gets dedicated detail tab with patient-level data for clinical review.

3. **3-tab xlsx for overlap validation (D-09/D-12):** Summary tab (overall metrics + temporal breakdown), Patient Detail tab (per-patient sorted by days_between), Pattern Analysis tab (grouped statistics + data quality assessment).

4. **Temporal categorization thresholds (D-08):** Same-day (0d), <30d, 30-180d, >180d. Thresholds chosen to distinguish same-encounter coding (0d), acute sequential diagnoses (<30d), subacute evolution (30-180d), and chronic/distinct malignancies (>180d).

5. **Data quality assessment auto-interpretation:** If same_day_pct > 50%, report coding quality concern. Otherwise, report genuine sequential diagnoses. Addresses Erin's skepticism about ~4,000/8,000 dual-code rate directly.

6. **Report-only, no config modifications (D-10):** Both scripts document findings and recommendations in xlsx summary tabs and console output. Config changes (if needed) would be separate follow-up phase.

7. **Raw counts without HIPAA suppression (D-11):** Manual suppression before sharing (v3.1/v3.2 convention for internal investigation scripts).

## Known Stubs

None. Both scripts are complete investigations producing final xlsx outputs. No data wiring deferred.

## Follow-Up Work

### Potential Config Changes (Out of Scope for Phase 105)
If CODE-01/02/03 findings reveal classification errors:
- Remove codes from DRUG_GROUPINGS if incorrectly included
- Add codes to DRUG_GROUPINGS if incorrectly excluded
- Update QUESTIONABLE_IMMUNO_CODES if new edge cases discovered

### OVERLAP-01 Findings Interpretation (Out of Scope for Phase 105)
Phase 105 produces the data. Interpretation and action (e.g., exclude same-day dual codes from cohort, flag for manual review) deferred to team discussion after xlsx review.

### Future Integration
- R/33 and R/34 are standalone investigation scripts (no upstream dependencies)
- Both could be re-run on updated DuckDB data to track trends over time
- Pattern analysis from R/34 could inform cohort exclusion criteria in future phases

## Requirements Completed

- [x] CODE-01: Etanercept immunotherapy classification investigation (R/33 Section 3)
- [x] CODE-02: Organ transplant code 0362 cross-check (R/33 Section 4)
- [x] CODE-03: SCT diagnosis codes above line 22 validation (R/33 Section 5)
- [x] OVERLAP-01: HL+NHL dual-code temporal validation report (R/34)

## Technical Notes

### Pitfall Guards Implemented
- **Pitfall 1 (RxNorm string types):** Always quote RxNorm codes in queries: `c("1653225", "809158", "809159", "214555")`
- **Pitfall 2 (ICD normalization):** Normalize both sides: `toupper(str_remove_all(DX, "\\."))` for consistent matching
- **Pitfall 3 (Temporal symmetry):** Use `abs(first_hl_dx - first_nhl_dx)` for symmetric days_between calculation
- **Pitfall 5 (Lazy evaluation):** Always call `collect()` after DuckDB filter/select chains

### Code Reuse
- R/78 NHL_ICD10_PATTERN, NHL_ICD9_PATTERN, HL code detection logic reused in R/34
- R/31/R/32 7-section investigation script structure, styled xlsx pattern (FF374151/FFFFFFFF headers)
- R/00_config.R DRUG_GROUPINGS access patterns, get_pcornet_table() from utils_duckdb.R

### Performance Notes
- R/33 queries 3 tables sequentially (PRESCRIBING, PROCEDURES, DIAGNOSIS) — no parallelization needed
- R/34 queries DIAGNOSIS twice (HL codes, NHL codes) — lazy evaluation defers work until collect()
- Both scripts suitable for interactive execution on HiPerGator (no SLURM job needed)

---

**Phase:** 105-code-overlap-verification
**Plan:** 01
**Summary created:** 2026-06-15
**Execution time:** 6 minutes
