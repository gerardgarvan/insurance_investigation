---
phase: 10-incorporate-variabledetails-xlsx-surveillance-strategy-and-treatment-variable-documentation-docx-variables-into-pipeline-then-regenerate-treatment-variable-documentation-docx
plan: "02"
subsystem: pipeline
tags: [r, dplyr, pcornet, surveillance, loinc, cpt, hcpcs, icd10pcs]

requires:
  - phase: 10-01
    provides: SURVEILLANCE_CODES and LAB_CODES lists in 00_config.R; LAB_RESULT_CM and PROVIDER table specs in 01_load_pcornet.R

provides:
  - detect_procedure_modality() generic helper for CPT/HCPCS/ICD-10-PCS procedure matching
  - detect_lab_modality() generic helper for LOINC matching against LAB_RESULT_CM
  - detect_mammogram/breast_mri/echo/stress_test/ecg/muga/pft wrapper functions (7 procedure-only)
  - detect_tsh() and detect_cbc() combined (procedure + lab) functions
  - detect_crp/alt/ast/alp/ggt/bilirubin/platelets/fobt wrapper functions (8 lab-only)
  - assemble_surveillance_flags() returning single wide tibble (51 columns + ID)
  - R/13_surveillance.R (468 lines)

affects:
  - 04_build_cohort.R (will call assemble_surveillance_flags to add columns to final cohort)
  - 10-03 (survivorship encounters plan)
  - 10-04 (documentation regeneration plan)

tech-stack:
  added: []
  patterns:
    - "detect_procedure_modality(post_dx_date_map, name, code_vectors): generic procedure detection with PX_TYPE dispatch"
    - "detect_lab_modality(post_dx_date_map, name, loinc_codes): generic lab detection via LAB_LOINC matching"
    - "Combined modality pattern (TSH/CBC): merge procedure and lab sub-functions, pmin dates, sum counts"
    - "Null-safe table access: if (is.null(pcornet$TABLE)) return default-zero result"
    - "Post-diagnosis restriction: filter(event_date > first_hl_dx_date) via inner_join to post_dx_date_map"

key-files:
  created:
    - R/13_surveillance.R
  modified: []

key-decisions:
  - "ICD-10-CM screening Z codes (echo_icd10_dx, ecg_icd10_dx, pft_icd10_dx) omitted from procedure detection -- these are diagnosis codes not procedure codes and cannot match via PROCEDURES PX_TYPE"
  - "mammogram_cpt G0279 treated as CPT entry in SURVEILLANCE_CODES (config decision from Plan 01) -- matched via PX_TYPE CH"
  - "TSH/CBC use pmin(px_date, lab_date) for FIRST_*_DATE and sum(N_*_PX, N_*_LAB) for count -- patient counted once if either source fires"

patterns-established:
  - "detect_procedure_modality: all 9 procedure modalities use the same generic helper with code_vectors dispatch"
  - "detect_lab_modality: all 10 lab types use the same generic helper with LOINC vector"
  - "assemble_surveillance_flags: canonical assembly function returns wide tibble for left_join to cohort"

requirements-completed: [SURV-02, SURV-03]

duration: 15min
completed: 2026-03-31
---

# Phase 10 Plan 02: Surveillance Detection Summary

**Post-diagnosis surveillance detection for 9 modalities + 10 lab types via CPT/HCPCS/ICD-10-PCS and LOINC matching, producing HAD/DATE/COUNT triplets per patient via detect_procedure_modality() and detect_lab_modality() generics with null-safe fallback**

## Performance

- **Duration:** 15 min
- **Started:** 2026-03-31T00:00:00Z
- **Completed:** 2026-03-31T00:15:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Created R/13_surveillance.R (468 lines) with two generic detection helpers and 17 modality-specific wrapper functions
- All detection restricted to post-diagnosis events via inner_join with post_dx_date_map and filter(event_date > first_hl_dx_date) per D-03
- TSH and CBC merge procedure-based (CPT/HCPCS) and LOINC-based sources so patients with either form of evidence are captured
- assemble_surveillance_flags() produces a 51-column wide tibble (HAD/DATE/N for each of 17 modalities) safe to left_join onto hl_cohort

## Task Commits

1. **Task 1: Create 13_surveillance.R** - `0998783` (feat)

**Plan metadata:** (pending final docs commit)

## Files Created/Modified

- `R/13_surveillance.R` - All surveillance detection functions and assemble_surveillance_flags() entry point

## Decisions Made

- ICD-10-CM screening Z codes (Z13.6, Z13.83) stored in SURVEILLANCE_CODES but omitted from procedure detection -- they are diagnosis codes, not procedure codes, and PCORnet PROCEDURES table uses PX_TYPE not DX codes; these would need to be matched via DIAGNOSIS table in a separate step if ever needed
- mammogram G0279 is HCPCS but stored under mammogram_cpt in config (Plan 01 decision) -- the detect_mammogram wrapper passes it via codes$cpt which maps to PX_TYPE="CH", which is correct for both CPT and HCPCS codes per PCORnet CDM spec
- Combined TSH/CBC design: sub-functions (detect_tsh_procedure, detect_tsh_lab, detect_cbc_procedure, detect_cbc_lab) exposed as callable helpers for debugging; the top-level detect_tsh() and detect_cbc() are the canonical combined versions called by assemble_surveillance_flags()

## Deviations from Plan

None -- plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- R/13_surveillance.R is complete and ready for use
- 04_build_cohort.R needs a call to `assemble_surveillance_flags(post_dx_date_map)` and left_join to add the 51 surveillance columns to the final cohort (expected in a later plan or as part of plan 05)
- 10-03 can proceed to implement 14_survivorship_encounters.R using the same generic patterns established here

---
*Phase: 10-incorporate-variabledetails-xlsx-surveillance-strategy-and-treatment-variable-documentation-docx-variables-into-pipeline-then-regenerate-treatment-variable-documentation-docx*
*Completed: 2026-03-31*
