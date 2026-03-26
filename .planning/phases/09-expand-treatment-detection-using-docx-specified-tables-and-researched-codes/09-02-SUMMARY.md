---
phase: 09-expand-treatment-detection-using-docx-specified-tables-and-researched-codes
plan: 02
subsystem: cohort-predicates
tags:
  - treatment-detection
  - multi-source-expansion
  - aggregate-logging
dependency_graph:
  requires:
    - 09-01 (TREATMENT_CODES expansion in 00_config.R)
  provides:
    - Expanded has_chemo/radiation/sct() with 6+ sources per treatment type
    - Aggregate source contribution logging per treatment type
  affects:
    - R/04_build_cohort.R (treatment flags join — no changes needed, same columns)
    - R/10_treatment_payer.R (will use expanded detection for treatment-anchored payer in Plan 03)
tech_stack:
  added: []
  patterns:
    - Multi-source treatment flag detection (union of patient IDs)
    - Null-safe table access (if !is.null(pcornet$TABLE))
    - Aggregate source contribution logging (D-14)
key_files:
  created: []
  modified:
    - R/03_cohort_predicates.R
decisions:
  - what: Use RXNORM_CUI matching only for DISPENSING/MED_ADMIN (no NDC)
    why: Avoids SEER*Rx mapping file dependency; PCORnet CDM already normalizes to RXNORM_CUI
    alternatives_considered: NDC-based matching (rejected due to 100MB+ mapping file requirement)
  - what: DISPENSING/MED_ADMIN only for chemo (not radiation/SCT)
    why: Radiation and SCT are procedures, not drug dispensations; no RXNORM_CUI codes exist for these
    alternatives_considered: None (clinically inappropriate to match radiation/SCT on drug codes)
  - what: Aggregate source contribution logging (no per-patient tracking)
    why: Per D-14, log total patients per source without adding per-patient columns
    alternatives_considered: Per-patient source tracking (rejected as out of scope for this phase)
metrics:
  duration_minutes: 3
  tasks_completed: 2
  tasks_total: 2
  files_modified: 1
  commits: 2
  started: 2026-03-26T15:52:06Z
  completed: 2026-03-26T15:54:47Z
---

# Phase 09 Plan 02: Expand Treatment Detection with Docx-Specified Tables and Researched Codes

**One-liner:** Extended has_chemo/radiation/sct() to query 6+ data sources per treatment type (DIAGNOSIS, ENCOUNTER DRG, DISPENSING, MED_ADMIN, PROCEDURES revenue codes) with aggregate source contribution logging.

## What Was Built

Expanded the three treatment flag functions in `R/03_cohort_predicates.R` to detect treatment evidence from 4 new data source categories per treatment type:

### has_chemo() — 8 sources total
- **Existing sources (unchanged):** TUMOR_REGISTRY1/2/3 dates, PROCEDURES CPT/HCPCS/ICD codes, PRESCRIBING dates
- **NEW (Phase 9):**
  - DIAGNOSIS: Z51.11/Z51.12 (ICD-10), V58.11/V58.12 (ICD-9) for chemotherapy encounters
  - ENCOUNTER: DRGs 837-839, 846-848 for chemotherapy admissions
  - DISPENSING: RXNORM_CUI matching (reuses TREATMENT_CODES$chemo_rxnorm)
  - MED_ADMIN: RXNORM_CUI matching (reuses TREATMENT_CODES$chemo_rxnorm)
  - PROCEDURES: Revenue codes 0331/0332/0335 (PX_TYPE = "RE") for chemotherapy administration

### has_radiation() — 6 sources total
- **Existing sources (unchanged):** TUMOR_REGISTRY1/2/3 dates, PROCEDURES CPT/ICD codes
- **NEW (Phase 9):**
  - DIAGNOSIS: Z51.0 (ICD-10), V58.0 (ICD-9) for radiation therapy encounters
  - ENCOUNTER: DRG 849 for radiotherapy admissions
  - PROCEDURES: Revenue codes 0330/0333 (PX_TYPE = "RE") for radiation therapy

### has_sct() — 6 sources total
- **Existing sources (unchanged):** TUMOR_REGISTRY1 code, TUMOR_REGISTRY2/3 dates, PROCEDURES CPT/ICD codes
- **NEW (Phase 9):**
  - DIAGNOSIS: Z94.84/T86.5/T86.09/Z48.290/T86.0 (ICD-10 only) for transplant status/complications
  - ENCOUNTER: DRGs 014/016/017 for stem cell transplant admissions
  - PROCEDURES: Revenue codes 0362/0815 (PX_TYPE = "RE") for transplant procedures

### Aggregate Source Contribution Logging
Per D-14, all three functions now log aggregate per-source patient counts:
```
[Treatment] has_chemo: 450 patients total
  Sources: TR=320, PX=180, RX=440, DX=23, DRG=8, DISP=12, MA=3, REV=5
```

This provides visibility into which data sources contribute most to treatment detection without per-patient overhead.

## What Changed

### File: R/03_cohort_predicates.R

**Function: has_chemo()**
- Added 5 new source blocks after existing PRESCRIBING block
- Added source counter variables (n_tr, n_px, n_rx, n_dx, n_drg, n_disp, n_ma, n_rev)
- Refactored existing TR blocks to track counts via named intermediate variables (tr1_chemo, tr2_chemo, tr3_chemo)
- Replaced single-line log with aggregate source logging (2 lines: total + per-source breakdown)
- Updated docstring to list all 9 sources

**Function: has_radiation()**
- Added 3 new source blocks after existing PROCEDURES block (DIAGNOSIS, ENCOUNTER DRG, PROCEDURES revenue)
- Added source counter variables (n_tr, n_px, n_dx, n_drg, n_rev)
- Refactored existing TR blocks to track counts
- Replaced single-line log with aggregate source logging
- Updated docstring to list all 6 sources
- **NOTE:** Does NOT reference DISPENSING or MED_ADMIN (radiation is not a drug)

**Function: has_sct()**
- Added 3 new source blocks after existing PROCEDURES block (DIAGNOSIS, ENCOUNTER DRG, PROCEDURES revenue)
- Added source counter variables (n_tr, n_px, n_dx, n_drg, n_rev)
- Refactored existing TR blocks to track counts (tr1_sct, tr_sct_from_loop)
- Replaced single-line log with aggregate source logging
- Updated docstring to list all 6 sources
- **NOTE:** Does NOT reference DISPENSING or MED_ADMIN (SCT is not a drug)

### Pattern Verification
- All new source blocks use null-safe `if (!is.null(pcornet$TABLE))` pattern
- All blocks use `distinct(ID)` before `pull(ID)` to avoid duplicate counting
- DISPENSING/MED_ADMIN only appear in has_chemo() (grep verified: lines 317, 318, 327, 328)
- All three functions have aggregate logging (grep verified: 3 "Sources:" lines)

## Deviations from Plan

None. Plan executed exactly as written. All acceptance criteria met.

## Verification Results

### Automated Verification (Task 1)
```bash
grep -c "chemo_dx_icd10\|chemo_drg\|chemo_revenue\|pcornet\$DISPENSING\|pcornet\$MED_ADMIN\|n_dx\|n_drg\|n_disp\|n_ma\|n_rev" R/03_cohort_predicates.R
# Result: 20 matches (expected: 10+)
```

### Automated Verification (Task 2)
```bash
grep -c "radiation_dx_icd10\|radiation_drg\|radiation_revenue\|sct_dx_icd10\|sct_drg\|sct_revenue" R/03_cohort_predicates.R
# Result: 10 matches (expected: 6+)
```

### Manual Verification
- [x] has_chemo() contains `DX %in% TREATMENT_CODES$chemo_dx_icd10`
- [x] has_chemo() contains `DX %in% TREATMENT_CODES$chemo_dx_icd9`
- [x] has_chemo() contains `DRG %in% TREATMENT_CODES$chemo_drg`
- [x] has_chemo() contains `RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm` for DISPENSING
- [x] has_chemo() contains `RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm` for MED_ADMIN
- [x] has_chemo() contains `PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue`
- [x] has_chemo() contains `Sources: TR=` aggregate logging line
- [x] has_radiation() contains `DX %in% TREATMENT_CODES$radiation_dx_icd10`
- [x] has_radiation() contains `DX %in% TREATMENT_CODES$radiation_dx_icd9`
- [x] has_radiation() contains `DRG %in% TREATMENT_CODES$radiation_drg`
- [x] has_radiation() contains `PX_TYPE == "RE" & PX %in% TREATMENT_CODES$radiation_revenue`
- [x] has_radiation() does NOT reference DISPENSING or MED_ADMIN
- [x] has_sct() contains `DX %in% TREATMENT_CODES$sct_dx_icd10`
- [x] has_sct() contains `DRG %in% TREATMENT_CODES$sct_drg`
- [x] has_sct() contains `PX_TYPE == "RE" & PX %in% TREATMENT_CODES$sct_revenue`
- [x] has_sct() does NOT reference DISPENSING or MED_ADMIN
- [x] All three functions contain `Sources:` aggregate logging lines

### Success Criteria Met
- [x] has_chemo() detects from 8 sources (3 TR + PROCEDURES + PRESCRIBING + DIAGNOSIS + ENCOUNTER DRG + DISPENSING + MED_ADMIN + revenue codes)
- [x] has_radiation() detects from 6 sources (3 TR + PROCEDURES + DIAGNOSIS + ENCOUNTER DRG + revenue codes)
- [x] has_sct() detects from 6 sources (3 TR + PROCEDURES + DIAGNOSIS + ENCOUNTER DRG + revenue codes)
- [x] All 3 functions log aggregate per-source patient counts per D-14
- [x] All new source blocks use null-safe `if (!is.null(pcornet$TABLE))` pattern
- [x] DISPENSING/MED_ADMIN only used for chemo (RXNORM_CUI matching per D-12), not radiation/SCT

## Known Stubs

None. This plan does not introduce stubs. All code lists consumed from Plan 01 (09-01-SUMMARY.md), which populated TREATMENT_CODES with researched codes.

## Implementation Notes

### Code Quality
- Functions are self-contained: no external state dependencies beyond pcornet$ tables and TREATMENT_CODES
- Consistent null-safety pattern across all table accesses
- Clear separation between existing sources and Phase 9 additions (comment header: "--- Phase 9: Expanded treatment detection sources ---")
- Aggregate logging provides operational visibility without per-patient overhead

### Integration Points
- **Upstream dependency:** Plan 01 (09-01) must complete first to populate TREATMENT_CODES with new code vectors
- **Downstream impact:** Plan 03 will extend 10_treatment_payer.R to extract dates from these new sources for treatment-anchored payer computation
- **No breaking changes:** Same function signatures (returns tibble(ID, HAD_*)), same output schema → 04_build_cohort.R requires no changes

### Performance Considerations
- New sources are checked in order of expected prevalence: DIAGNOSIS (common), ENCOUNTER DRG (moderate), DISPENSING/MED_ADMIN (sparse), revenue codes (sparse)
- Null-safe checks prevent unnecessary computation if tables not loaded
- distinct(ID) before pull(ID) avoids duplicate counting if patients have multiple qualifying records

### Testing Strategy
When pipeline runs on HiPerGator:
1. Check aggregate logging output: do new sources contribute non-zero counts?
2. Compare total patients before/after expansion: expect increase (more sensitive detection)
3. If zero matches for DISPENSING/MED_ADMIN: check table population (these are optional PCORnet tables)
4. If zero matches for revenue codes: check if PROCEDURES has PX_TYPE = "RE" rows (uncommon in PCORnet)

## What's Next

**Plan 03 (next in phase):** Extend compute_payer_at_chemo/radiation/sct() in 10_treatment_payer.R to extract dates from the 4 new source categories added in this plan. This will increase the number of patients with PAYER_AT_CHEMO/RADIATION/SCT values (better anchor date coverage = more payer assignments).

**Blocked by:** None (this plan is complete)

**Blocks:** Plan 03 (must wait for this plan's expanded detection functions)

## Self-Check: PASSED

### Files Created
(None expected)

### Files Modified
- [x] R/03_cohort_predicates.R exists
  ```bash
  [ -f "C:\Users\Owner\Documents\insurance_investigation\R\03_cohort_predicates.R" ] && echo "FOUND"
  # Result: FOUND
  ```

### Commits Exist
- [x] Task 1 commit f1eb490 exists
  ```bash
  git log --oneline --all | grep -q "f1eb490" && echo "FOUND: f1eb490"
  # Result: FOUND: f1eb490
  ```
- [x] Task 2 commit 16e5eee exists
  ```bash
  git log --oneline --all | grep -q "16e5eee" && echo "FOUND: 16e5eee"
  # Result: FOUND: 16e5eee
  ```

All planned artifacts created. All commits verified.
