---
phase: 09-expand-treatment-detection-using-docx-specified-tables-and-researched-codes
plan: 01
subsystem: Configuration & Data Loading
tags:
  - treatment-codes
  - table-loading
  - pcornet-cdm
  - dispensing
  - med-admin
dependency_graph:
  requires:
    - 00_config.R (TREATMENT_CODES list)
    - 01_load_pcornet.R (table loading infrastructure)
  provides:
    - TREATMENT_CODES with 11 new code list vectors (DRG, revenue, diagnosis)
    - DISPENSING and MED_ADMIN table loading specs
    - Expanded PCORNET_TABLES vector (11 tables)
  affects:
    - 03_cohort_predicates.R (will consume new code lists in has_*() functions)
    - 10_treatment_payer.R (will use new tables for treatment date anchoring)
tech_stack:
  added:
    - PCORnet CDM v7.0 DISPENSING table (15 columns)
    - PCORnet CDM v7.0 MED_ADMIN table (12 columns)
  patterns:
    - Code list vectors in CONFIG list
    - col_types specifications for PCORnet tables
    - Null-safe table loading (warn and skip if CSV missing)
key_files:
  created: []
  modified:
    - R/00_config.R (64 insertions, 2 deletions)
    - R/01_load_pcornet.R (57 insertions, 5 deletions)
decisions:
  - "Add 11 new code list vectors (not extend existing): Keeps treatment types distinct and queryable"
  - "RXNORM_CUI-only matching for DISPENSING/MED_ADMIN: Avoids NDC complexity (50+ codes per drug)"
  - "Include both ICD-9 and ICD-10 diagnosis codes: Cohort spans 2012-2025 (pre/post Oct 2015 ICD-10 transition)"
  - "Omit DRG 015 from sct_drg: Code deleted FY2012, replaced by 016/017"
  - "Expand chemo_icd9 to include 99.28: Immunotherapy injection/infusion (D-07)"
metrics:
  duration_seconds: 151
  completed: 2026-03-26
---

# Phase 09 Plan 01: Add Expanded Treatment Code Lists and New Table Loading Summary

**One-liner:** Added 11 new treatment code list vectors (DRG, revenue, diagnosis codes for chemo/radiation/SCT) to TREATMENT_CODES and enabled DISPENSING/MED_ADMIN table loading with full col_types specifications.

## What Was Built

### Task 1: Expanded TREATMENT_CODES in 00_config.R
Added 11 new code list vectors to the TREATMENT_CODES list:

**Diagnosis-based evidence (5 vectors):**
- `chemo_dx_icd10`: Z51.11, Z51.12 (encounter for chemo/immunotherapy)
- `chemo_dx_icd9`: V58.11, V58.12 (legacy pre-2015 codes)
- `radiation_dx_icd10`: Z51.0 (encounter for radiation therapy)
- `radiation_dx_icd9`: V58.0 (legacy pre-2015 code)
- `sct_dx_icd10`: Z94.84, T86.5, T86.09, Z48.290, T86.0 (transplant status/complications/aftercare)

**DRG-based evidence (3 vectors):**
- `chemo_drg`: 837-839 (chemo w/o acute leukemia), 846-848 (chemo w/ hematologic malignancy)
- `radiation_drg`: 849 (radiotherapy)
- `sct_drg`: 014 (allogeneic), 016 (autologous w/ CC/MCC), 017 (autologous w/o CC/MCC)
  - Note: Omitted DRG 015 (deleted FY2012, split into 016/017)

**Revenue code evidence (3 vectors):**
- `chemo_revenue`: 0331 (injected), 0332 (oral), 0335 (IV push)
- `radiation_revenue`: 0330 (general), 0333 (radiation therapy)
- `sct_revenue`: 0362 (organ transplant - other than kidney), 0815 (allogeneic stem cell acquisition)

**Also expanded:**
- `chemo_icd9`: Added 99.28 (immunotherapy injection/infusion per D-07)

**Updated header comment** to reflect new table sources: PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, DIAGNOSIS, ENCOUNTER.

### Task 2: DISPENSING and MED_ADMIN table loading in 01_load_pcornet.R
Added two new PCORnet CDM table specifications:

**DISPENSING_SPEC (15 columns):**
- Key columns: RXNORM_CUI (chemo matching), DISPENSE_DATE (treatment date anchoring)
- Includes: DISPENSINGID, PRESCRIBINGID, ID, NDC, DISPENSE_SUP, DISPENSE_AMT, DISPENSE_DOSE_DISP, DISPENSE_DOSE_DISP_UNIT, DISPENSE_ROUTE, RAW_NDC, DISPENSE_SOURCE, RAW_DISPENSE_MED_NAME, SOURCE
- All ID/code columns character type; dates parsed via parse_pcornet_date()

**MED_ADMIN_SPEC (12 columns):**
- Key columns: RXNORM_CUI (chemo matching), MEDADMIN_START_DATE (treatment date anchoring)
- Includes: MEDADMINID, ID, ENCOUNTERID, PRESCRIBINGID, MEDADMIN_CODE, MEDADMIN_TYPE, MEDADMIN_STOP_DATE, MEDADMIN_ROUTE, RAW_MEDADMIN_MED_NAME, SOURCE
- All ID/code columns character type; dates parsed via parse_pcornet_date()

**Infrastructure updates:**
- Updated PCORNET_TABLES vector in 00_config.R to 11 tables (added DISPENSING, MED_ADMIN)
- Updated TABLE_SPECS lookup in 01_load_pcornet.R to map new tables
- Updated file headers to reflect "11 primary tables" (was "9 primary tables")
- Null-safe loading via existing load_pcornet_table() function (warns and skips if CSV missing)

## Deviations from Plan

None - plan executed exactly as written. All 11 code list vectors added with decision IDs (D-07, D-09, D-10, D-11) documented in comments. Both new table specs follow PCORnet CDM v7.0 column definitions from research.

## Commits

| Task | Commit | Files Modified | Description |
|------|--------|----------------|-------------|
| 1 | `606cb08` | R/00_config.R | Expand TREATMENT_CODES with 11 new code list vectors (diagnosis, DRG, revenue) |
| 2 | `8b896ed` | R/00_config.R, R/01_load_pcornet.R | Add DISPENSING and MED_ADMIN table loading with full col_types |

## Self-Check: PASSED

**Files verified:**
```bash
[ -f "C:\Users\Owner\Documents\insurance_investigation\R\00_config.R" ] && echo "FOUND: R/00_config.R" || echo "MISSING: R/00_config.R"
# FOUND: R/00_config.R

[ -f "C:\Users\Owner\Documents\insurance_investigation\R\01_load_pcornet.R" ] && echo "FOUND: R/01_load_pcornet.R" || echo "MISSING: R/01_load_pcornet.R"
# FOUND: R/01_load_pcornet.R
```

**Commits verified:**
```bash
git log --oneline --all | grep -q "606cb08" && echo "FOUND: 606cb08" || echo "MISSING: 606cb08"
# FOUND: 606cb08

git log --oneline --all | grep -q "8b896ed" && echo "FOUND: 8b896ed" || echo "MISSING: 8b896ed"
# FOUND: 8b896ed
```

**Code list count verified:**
```bash
grep -c "chemo_drg\|radiation_drg\|sct_drg\|chemo_revenue\|radiation_revenue\|sct_revenue\|chemo_dx_icd10\|chemo_dx_icd9\|radiation_dx_icd10\|radiation_dx_icd9\|sct_dx_icd10" R/00_config.R
# 11 (one definition per new vector)
```

**Table spec count verified:**
```bash
grep -c "DISPENSING_SPEC\|MED_ADMIN_SPEC" R/01_load_pcornet.R
# 8 (2 specs + 2 references in TABLE_SPECS + comments)
```

All acceptance criteria met.

## Known Stubs

None - this plan only adds configuration data and table loading infrastructure. No UI rendering, placeholder data, or stub logic introduced.

## Next Steps

Plans 02 and 03 will consume these new code lists and tables:
- **Plan 02:** Extend has_chemo/radiation/sct() functions in 03_cohort_predicates.R to query DIAGNOSIS, ENCOUNTER DRG, DISPENSING, MED_ADMIN, and PROCEDURES revenue codes
- **Plan 03:** Extend compute_payer_at_*() functions in 10_treatment_payer.R to extract dates from new sources for treatment-anchored payer computation

## Technical Notes

### RXNORM_CUI vs NDC Matching (D-12)
DISPENSING and MED_ADMIN specs include both NDC and RXNORM_CUI columns, but only RXNORM_CUI will be used for chemo matching. Rationale:
- NDC codes are product-specific (50+ codes per drug: brand, generic, package sizes)
- RXNORM_CUI codes are ingredient-level (1 code per drug: doxorubicin = 3639)
- Avoids need for SEER*Rx NDC-to-category mapping file (100MB+, quarterly updates)
- PCORnet CDM already normalizes drugs to RXNORM_CUI in all medication tables

### ICD-9 vs ICD-10 Code Coverage
All diagnosis and procedure code lists include both ICD-9 and ICD-10 versions to capture records across the ICD-10 transition (October 1, 2015). Hodgkin Lymphoma cohort spans 2012-2025, so pre-2015 records require ICD-9 codes.

### DRG Code Stability
MS-DRG definitions change annually (FY2026 is version 43.0). Key changes:
- DRG 015 (autologous BMT) deleted October 1, 2011 → split into 016 (w/ CC/MCC) and 017 (w/o CC/MCC)
- Chemo DRGs 837-839 (w/o acute leukemia) and 846-848 (w/ hematologic malignancy) stable since FY2008
- Radiation DRG 849 stable since FY2008
- Re-verify DRG codes annually if cohort extends beyond 2026

### Revenue Code Changes
Revenue codes (UB-04) change infrequently:
- 0815 (allogeneic stem cell acquisition) added January 1, 2017
- 033X series (chemo/radiation) stable since 2000s
- No upcoming changes documented as of March 2026

## Duration
151 seconds (~2.5 minutes)
