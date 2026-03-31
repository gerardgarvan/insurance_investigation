---
phase: 10-incorporate-variabledetails-xlsx-surveillance-strategy-and-treatment-variable-documentation-docx-variables-into-pipeline-then-regenerate-treatment-variable-documentation-docx
plan: "01"
subsystem: config
tags: [pcornet, r-pipeline, surveillance, labs, survivorship, provider-specialty, nucc, loinc, cpt, icd10pcs]

# Dependency graph
requires:
  - phase: 09-expand-treatment-detection-using-docx-specified-tables-and-researched-codes
    provides: TREATMENT_CODES pattern in 00_config.R, DISPENSING/MED_ADMIN table specs
provides:
  - "SURVEILLANCE_CODES list with 9 modalities (mammogram, breast MRI, echo, stress test, ECG, MUGA, PFT, TSH, CBC) in 00_config.R"
  - "LAB_CODES list with 10 lab types (CPT + LOINC codes) in 00_config.R"
  - "SURVIVORSHIP_CODES list with ICD-9/ICD-10 personal history codes in 00_config.R"
  - "PROVIDER_SPECIALTIES list with 6 NUCC oncology taxonomy codes in 00_config.R"
  - "LAB_RESULT_CM table spec (col_types) in 01_load_pcornet.R"
  - "PROVIDER table spec (col_types) in 01_load_pcornet.R"
  - "Expanded TREATMENT_CODES: sct_hcpcs, additional sct_icd10pcs, cart_icd10pcs_prefixes"
affects: [13_surveillance, 14_survivorship_encounters, downstream detection scripts]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Named list with _cpt/_hcpcs/_loinc/_icd10pcs suffixes per code type per modality (follows TREATMENT_CODES pattern)"
    - "PCORNET_TABLES vector drives automatic path building via PCORNET_PATHS"
    - "Phase 10 diagnostic logging block after loading for PROVIDER specialty validation"

key-files:
  created: []
  modified:
    - "R/00_config.R"
    - "R/01_load_pcornet.R"

key-decisions:
  - "All surveillance/lab codes transcribed directly from VariableDetails.xlsx, not from RESEARCH.md examples (which are illustrative)"
  - "LAB_CODES duplicates TSH/CBC LOINC from SURVEILLANCE_CODES for convenience in lab-specific queries"
  - "platelets_loinc includes APRI Index and PDF derived values as they appear in the Labs sheet"
  - "sct_icd10pcs expanded to include open approach (30230x/30240x), allogeneic related/unrelated (G2/G3/U2/U3/X2/X3/Y2/Y3), Omidubicel new-tech (XW133C8/XW143C8), and embryonic (AZ) codes from VariableDetails.xlsx"
  - "CAR T-cell codes stored as cart_icd10pcs_prefixes (prefix-match pattern, consistent with existing radiation_icd10pcs_prefixes)"
  - "PCORNET_TABLES updated in 00_config.R (source of truth); TABLE_SPECS updated in 01_load_pcornet.R"

patterns-established:
  - "Phase-annotated additions: new Phase 10 entries labeled with # Phase 10 comments for traceability"
  - "Diagnostic logging after load block validates data quality before downstream scripts run"

requirements-completed: [SURV-01, SVENC-01]

# Metrics
duration: 25min
completed: 2026-03-31
---

# Phase 10 Plan 01: Foundation Config and Table Loading Summary

**SURVEILLANCE_CODES (9 modalities), LAB_CODES (10 types), SURVIVORSHIP_CODES, and PROVIDER_SPECIALTIES added to 00_config.R with codes from VariableDetails.xlsx; LAB_RESULT_CM and PROVIDER table specs added to 01_load_pcornet.R**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-03-31T15:55:19Z
- **Completed:** 2026-03-31T16:20:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Transcribed all surveillance codes from VariableDetails.xlsx "Surveillance Strategy" sheet into SURVEILLANCE_CODES named list covering 9 modalities with CPT, HCPCS, ICD-10-PCS, LOINC, and ICD-10 screening Z codes
- Transcribed lab codes from "Labs" sheet into LAB_CODES with CPT and LOINC for CRP, ALT, AST, ALP, GGT, bilirubin, platelets, FOBT plus TSH/CBC LOINC duplicated for lab query convenience
- Added SURVIVORSHIP_CODES (ICD-9 V87.41/V87.42/V87.43/V87.46/V15.3 and ICD-10 Z92.21/Z92.22/Z92.23/Z92.25/Z92.3) and PROVIDER_SPECIALTIES (6 NUCC oncology taxonomy codes)
- Added LAB_RESULT_CM_SPEC and PROVIDER_SPEC to 01_load_pcornet.R with proper col_types, both added to PCORNET_TABLES and TABLE_SPECS
- Added Phase 10 diagnostic logging: PROVIDER_SPECIALTY_PRIM distinct values and LAB_LOINC null rate

## Task Commits

Each task was committed atomically:

1. **Task 1: Populate config code lists in 00_config.R** - `a0929bf` (feat)
2. **Task 2: Add LAB_RESULT_CM and PROVIDER table specs to 01_load_pcornet.R** - `1753550` (feat)

**Plan metadata:** (final docs commit — see below)

## Files Created/Modified

- `R/00_config.R` - Added SURVEILLANCE_CODES, LAB_CODES, SURVIVORSHIP_CODES, PROVIDER_SPECIALTIES sections (355 lines net); expanded TREATMENT_CODES with sct_hcpcs, additional sct_icd10pcs, cart_icd10pcs_prefixes; updated PCORNET_TABLES to include LAB_RESULT_CM and PROVIDER
- `R/01_load_pcornet.R` - Added LAB_RESULT_CM_SPEC (23 columns), PROVIDER_SPEC (7 columns), both in TABLE_SPECS; diagnostic logging block; updated header to reflect 13-table load set

## Decisions Made

- Transcribed codes directly from VariableDetails.xlsx rather than RESEARCH.md illustrative examples (plan directive)
- HCPCS code "224576" for TSH included in tsh_hcpcs as it appeared in Surveillance Strategy sheet, even though it is a Medicare clinical lab code rather than a standard HCPCS J-code
- LAB_CODES.platelets_loinc includes APRI Index (86465-2) and PDF (80563-0) as derived values since they appeared in the Labs sheet alongside the primary platelets LOINC (777-3)
- PCORNET_TABLES maintained in 00_config.R (source of truth) per existing pattern; PCORNET_PATHS auto-builds from it via setNames/file.path

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Expanded TREATMENT_CODES with VariableDetails.xlsx SCT codes**
- **Found during:** Task 1 (cross-referencing Treatment sheet per plan instruction)
- **Issue:** VariableDetails.xlsx Treatment sheet contained SCT codes not in existing TREATMENT_CODES: 3 HCPCS codes (S2140/S2142/S2150), ~32 additional ICD-10-PCS codes (open approach, allogeneic related/unrelated, embryonic, new-tech Omidubicel), and 16 CAR T-cell codes (DRG 018)
- **Fix:** Added sct_hcpcs list, expanded sct_icd10pcs with all xlsx codes while retaining existing Phase 9 codes, added cart_icd10pcs_prefixes for CAR T-cell coverage
- **Files modified:** R/00_config.R
- **Committed in:** a0929bf (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 2 - missing critical treatment codes from xlsx source)
**Impact on plan:** Required by plan instruction to cross-reference Treatment sheet and add missing codes. No scope creep.

## Issues Encountered

- Surveillance Strategy sheet row for MUGA contained a duplicate ICD-10-PCS code "C21G1ZZ" (appeared twice) - deduplicated to unique values in SURVEILLANCE_CODES
- Treatment sheet only contained SCT and CAR T-cell codes (rows 2-60 active data, 61-123 empty); chemo and radiation treatment codes are in a separate Word document referenced in row 62 ("TreatmentVariables_2024.07.17"). Existing TREATMENT_CODES chemo/radiation entries were not modified as no new codes were provided in the xlsx.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All 4 config code lists in 00_config.R ready for use by 13_surveillance.R and 14_survivorship_encounters.R
- LAB_RESULT_CM and PROVIDER will load as NULL if CSV files are absent (graceful skip per existing load_pcornet_table behavior)
- PROVIDER_SPECIALTY_PRIM diagnostic logging will validate actual NUCC codes in data vs PROVIDER_SPECIALTIES list on first run
- LAB_LOINC null rate logging will reveal whether CPT fallback (LAB_PX column) will be needed

---
*Phase: 10-incorporate-variabledetails-xlsx-surveillance-strategy-and-treatment-variable-documentation-docx-variables-into-pipeline-then-regenerate-treatment-variable-documentation-docx*
*Completed: 2026-03-31*
