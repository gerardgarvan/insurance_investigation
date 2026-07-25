---
phase: 10-incorporate-variabledetails-xlsx-surveillance-strategy-and-treatment-variable-documentation-docx-variables-into-pipeline-then-regenerate-treatment-variable-documentation-docx
verified: 2026-03-31T00:00:00Z
status: gaps_found
score: 10/13 must-haves verified
gaps:
  - truth: "Both .md (source of truth) and .docx (sharing copy) are produced per D-15"
    status: failed
    reason: "output/docs/ directory does not exist; 15_generate_documentation.R must be RUN to produce the files. The script is correctly written to create them, but neither Treatment_Variable_Documentation.md nor Treatment_Variable_Documentation.docx exists in the repository at this time."
    artifacts:
      - path: "output/docs/Treatment_Variable_Documentation.md"
        issue: "File does not exist -- not yet generated"
      - path: "output/docs/Treatment_Variable_Documentation.docx"
        issue: "File does not exist -- not yet generated"
    missing:
      - "Run R/15_generate_documentation.R to produce both output files"
  - truth: "Pipeline runs end-to-end with new columns appearing in cohort summary"
    status: partial
    reason: "Section 8 (console summary) in 04_build_cohort.R references HAD_ENC_NONACUTE (line 378) but the actual column name produced by 14_survivorship_encounters.R is HAD_ENC_NONACUTE_CARE (with _CARE suffix). The CSV output is unaffected because Section 7 uses starts_with('HAD_ENC_') which captures the correct column. However, the console summary will silently report 0 for Level 1 non-acute care count on every run."
    artifacts:
      - path: "R/04_build_cohort.R"
        issue: "Line 378: hl_cohort$HAD_ENC_NONACUTE should be hl_cohort$HAD_ENC_NONACUTE_CARE"
    missing:
      - "Fix line 378 in R/04_build_cohort.R: change HAD_ENC_NONACUTE to HAD_ENC_NONACUTE_CARE"
  - truth: "13_surveillance.R connects to 00_config.R via source() for SURVEILLANCE_CODES and LAB_CODES"
    status: partial
    reason: "R/13_surveillance.R does not directly source('R/00_config.R'). It relies on SURVEILLANCE_CODES and LAB_CODES already loaded in the global environment by the caller (04_build_cohort.R sources 00_config.R first). The wiring works at runtime but 13_surveillance.R cannot be sourced standalone without 00_config.R already loaded. Similarly 14_survivorship_encounters.R does not source 00_config.R. The plan key_links pattern 'source.*00_config' is not satisfied in these files."
    artifacts:
      - path: "R/13_surveillance.R"
        issue: "No source('R/00_config.R') -- relies on caller to have loaded config globals"
      - path: "R/14_survivorship_encounters.R"
        issue: "No source('R/00_config.R') -- relies on caller to have loaded config globals"
    missing:
      - "Either add source('R/00_config.R') guard at top of 13_surveillance.R and 14_survivorship_encounters.R, OR document in headers that these scripts must be called from 04_build_cohort.R context"
human_verification:
  - test: "Run R/15_generate_documentation.R in RStudio and inspect output/docs/Treatment_Variable_Documentation.md"
    expected: "11-section markdown document covering all pipeline variables with code counts from config lists, no patient counts"
    why_human: "File does not exist yet; pandoc availability for .docx render depends on machine configuration"
  - test: "Run R/04_build_cohort.R end-to-end and check console output for survivorship Level 1 count"
    expected: "Non-acute care (L1) should report a non-zero patient count (not 0 due to column name mismatch)"
    why_human: "Requires actual PCORnet CSV data to execute"
---

# Phase 10: Surveillance, Survivorship, and Documentation Verification Report

**Phase Goal:** Incorporate VariableDetails.xlsx surveillance strategy and Treatment_Variable_Documentation.docx variables into pipeline, then regenerate Treatment_Variable_Documentation.docx
**Verified:** 2026-03-31
**Status:** gaps_found
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | 00_config.R contains SURVEILLANCE_CODES with CPT/HCPCS/ICD-10-PCS codes for all 9 surveillance modalities transcribed from VariableDetails.xlsx | VERIFIED | `SURVEILLANCE_CODES <- list(` at line 570; all 9 modalities (mammogram, breast_mri, echo, stress_test, ecg, muga, pft, tsh, cbc) confirmed with real code values |
| 2  | 00_config.R contains LAB_CODES with LOINC codes for all 10 lab types | VERIFIED | `LAB_CODES <- list(` at line 723; all 10 types (crp, alt, ast, alp, ggt, bilirubin, platelets, fobt, tsh, cbc) with LOINC codes confirmed |
| 3  | 00_config.R contains SURVIVORSHIP_CODES with personal history ICD-9 and ICD-10 codes | VERIFIED | `SURVIVORSHIP_CODES <- list(` at line 790; V87.41/V87.42/V87.43/V87.46/V15.3 ICD-9 and Z92.21/Z92.22/Z92.23/Z92.25/Z92.3 ICD-10 confirmed |
| 4  | 00_config.R contains PROVIDER_SPECIALTIES with NUCC taxonomy codes | VERIFIED | `PROVIDER_SPECIALTIES <- list(` at line 816; 6 NUCC codes (207RH0000X through 2080P0207X) confirmed |
| 5  | 01_load_pcornet.R loads LAB_RESULT_CM and PROVIDER tables with proper col_types | VERIFIED | LAB_RESULT_CM_SPEC (line 281, 23 columns), PROVIDER_SPEC (line 314, 7 columns), both in TABLE_SPECS (lines 340-341); diagnostic logging at lines 518-535 |
| 6  | 13_surveillance.R produces HAD/FIRST/N columns for 9 surveillance modalities | VERIFIED | All 9 detect_*() wrappers confirmed; detect_tsh() and detect_cbc() are combined procedure+lab functions; assemble_surveillance_flags() joins all 17 sub-results into wide tibble (51 columns) |
| 7  | Each lab type produces HAD/FIRST/N columns via LOINC matching | VERIFIED | 8 lab-only detect_*() wrappers (crp, alt, ast, alp, ggt, bilirubin, platelets, fobt) at lines 369-410; all called from assemble_surveillance_flags() |
| 8  | All surveillance/lab detection is restricted to post-diagnosis events (D-03) | VERIFIED | `filter(!is.na(PX_DATE), PX_DATE > first_hl_dx_date)` at line 102; `filter(!is.na(lab_date), lab_date > first_hl_dx_date)` at line 167 |
| 9  | Missing tables handled gracefully with 0-valued flags | VERIFIED | `if (is.null(pcornet$PROCEDURES))` at line 74 and `if (is.null(pcornet$LAB_RESULT_CM))` at line 152; 14_survivorship_encounters.R has `if (is.null(pcornet$PROVIDER))` at line 150 |
| 10 | 4-level survivorship encounter classification produces correct hierarchy | VERIFIED | Level 1 (ENC_NONACUTE_CARE), Level 2 (ENC_CANCER_RELATED), Level 3 (ENC_CANCER_PROVIDER), Level 4 (ENC_SURVIVORSHIP) all implemented with correct nested subsetting |
| 11 | hl_cohort.csv contains timing columns (DAYS_DX_TO_*) and new surveillance/survivorship columns | VERIFIED | Section 6.6 computes 3 timing columns (line 236-238); Section 6.7/6.8 join surveillance and survivorship flags; Section 7 select() includes DAYS_DX_TO_* explicitly (lines 305-307) and surveillance/survivorship via matches()/starts_with() (lines 309-313) |
| 12 | Documentation .md and .docx files produced by 15_generate_documentation.R | FAILED | R/15_generate_documentation.R exists (674 lines) and is correctly written, but output/docs/ does not exist -- the script has not been run. Neither output file exists. |
| 13 | Pipeline console summary accurately reports survivorship encounter counts | PARTIAL | Section 8 line 378 uses `hl_cohort$HAD_ENC_NONACUTE` but the actual column is `HAD_ENC_NONACUTE_CARE`. The CSV output is correct (starts_with captures it), but the console summary will always show 0 for Level 1 non-acute care count. |

**Score:** 10/13 truths verified (11 VERIFIED, 1 FAILED, 1 PARTIAL)

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/00_config.R` | SURVEILLANCE_CODES, LAB_CODES, SURVIVORSHIP_CODES, PROVIDER_SPECIALTIES | VERIFIED | All 4 lists defined at lines 570, 723, 790, 816 with real code values from VariableDetails.xlsx |
| `R/01_load_pcornet.R` | LAB_RESULT_CM and PROVIDER table loading | VERIFIED | LAB_RESULT_CM_SPEC and PROVIDER_SPEC defined; both in TABLE_SPECS; diagnostic logging block present |
| `R/13_surveillance.R` | detect_{modality}() + detect_{lab}() + assemble_surveillance_flags() | VERIFIED | 468 lines (above 200 minimum); all 9 procedure modality wrappers + 8 lab wrappers + combined TSH/CBC + assembly function |
| `R/14_survivorship_encounters.R` | classify_survivorship_encounters() for 4 levels | VERIFIED | 287 lines (above 120 minimum); all 4 levels, 12-column output, NULL PROVIDER guard |
| `R/04_build_cohort.R` | Sections 6.6/6.7/6.8 + extended select() and summary | VERIFIED (with warning) | Sections 6.6/6.7/6.8 present; select() correct; Section 8 summary has column name mismatch on HAD_ENC_NONACUTE |
| `R/15_generate_documentation.R` | Auto-doc generator reading 00_config.R | VERIFIED | 674 lines (above 150 minimum); sources 00_config.R, builds 11 sections, uses writeLines + rmarkdown::render wrapped in tryCatch |
| `output/docs/Treatment_Variable_Documentation.md` | Markdown source of truth | MISSING | File does not exist; must run 15_generate_documentation.R |
| `output/docs/Treatment_Variable_Documentation.docx` | Word document sharing copy | MISSING | File does not exist; must run 15_generate_documentation.R |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `R/01_load_pcornet.R` | `R/00_config.R` | source() at top | WIRED | `source("R/00_config.R")` at line 20 of 01_load_pcornet.R |
| `R/13_surveillance.R` | `R/00_config.R` | SURVEILLANCE_CODES/LAB_CODES globals | PARTIAL | No direct source(); references SURVEILLANCE_CODES (line 195+) and LAB_CODES (line 267+) as globals provided by caller context (04_build_cohort.R). Plan pattern `source.*00_config` not satisfied in file itself. |
| `R/13_surveillance.R` | `pcornet$PROCEDURES` | filter and join | WIRED | `pcornet$PROCEDURES` at lines 74, 89 with null guard |
| `R/13_surveillance.R` | `pcornet$LAB_RESULT_CM` | filter by LAB_LOINC | WIRED | `pcornet$LAB_RESULT_CM` at lines 152, 163 with null guard |
| `R/14_survivorship_encounters.R` | `R/00_config.R` | SURVIVORSHIP_CODES/PROVIDER_SPECIALTIES globals | PARTIAL | No direct source(); uses SURVIVORSHIP_CODES (lines 214-215), PROVIDER_SPECIALTIES (line 191), ICD_CODES (lines 123-124) as globals. Plan pattern `SURVIVORSHIP_CODES|PROVIDER_SPECIALTIES` IS present in file but no source() call. |
| `R/14_survivorship_encounters.R` | `pcornet$ENCOUNTER` | filter ENC_TYPE | WIRED | `pcornet$ENCOUNTER` at line 96 |
| `R/14_survivorship_encounters.R` | `pcornet$PROVIDER` | left_join PROVIDERID | WIRED | `pcornet$PROVIDER` at line 188 with null guard at line 150 |
| `R/04_build_cohort.R` | `R/13_surveillance.R` | source() + assemble_surveillance_flags() | WIRED | `source("R/13_surveillance.R")` at line 250; `assemble_surveillance_flags(post_dx_date_map)` at line 253 |
| `R/04_build_cohort.R` | `R/14_survivorship_encounters.R` | source() + classify_survivorship_encounters() | WIRED | `source("R/14_survivorship_encounters.R")` at line 263; `classify_survivorship_encounters(post_dx_date_map)` at line 265 |
| `R/04_build_cohort.R` | `output/cohort/hl_cohort.csv` | write_csv | WIRED | `write_csv(hl_cohort, output_path)` at line 403 |
| `R/15_generate_documentation.R` | `R/00_config.R` | source() | WIRED | `source("R/00_config.R")` at line 25 |
| `R/15_generate_documentation.R` | `output/docs/Treatment_Variable_Documentation.md` | writeLines() | WIRED | `writeLines(md, md_path)` at line 646 |
| `R/15_generate_documentation.R` | `output/docs/Treatment_Variable_Documentation.docx` | rmarkdown::render() | WIRED (with tryCatch) | `rmarkdown::render(...)` at line 660 wrapped in tryCatch; .md always written, .docx conditional on pandoc |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SURV-01 | 10-01 | Surveillance modality CPT/HCPCS/LOINC code lists in 00_config.R from VariableDetails.xlsx | SATISFIED | SURVEILLANCE_CODES (9 modalities) and LAB_CODES (10 types) verified in 00_config.R with real codes |
| SURV-02 | 10-02 | Detect post-diagnosis surveillance modalities via PROCEDURES and LAB_RESULT_CM | SATISFIED | 13_surveillance.R has all 9 modality detectors + lab helpers; post-diagnosis filter confirmed |
| SURV-03 | 10-02 | Detect post-diagnosis lab results (CRP, ALT, AST, ALP, GGT, bilirubin, platelets, FOBT) via LAB_RESULT_CM LOINC | SATISFIED | 8 lab-only detect_*() wrappers verified in 13_surveillance.R; all called from assemble_surveillance_flags() |
| SURV-04 | 10-04 | HAD_/FIRST_/N_ surveillance columns in hl_cohort.csv | SATISFIED | Section 6.7 sources 13_surveillance.R and joins output; Section 7 select() uses matches() to include all surveillance columns |
| SVENC-01 | 10-01 | SURVIVORSHIP_CODES and PROVIDER_SPECIALTIES in 00_config.R; PROVIDER + LAB_RESULT_CM tables loaded | SATISFIED | Both config lists verified; both table specs in TABLE_SPECS with col_types |
| SVENC-02 | 10-03 | Classify encounters into 4 survivorship levels per VariableDetails.xlsx | SATISFIED | classify_survivorship_encounters() implements all 4 levels with correct hierarchy and HL-specific DX filter (D-07) |
| SVENC-03 | 10-03 | Per-patient survivorship encounter flags using ENCOUNTER, DIAGNOSIS, PROVIDER joins | SATISFIED | 12-column output verified; ENCOUNTER (line 96), DIAGNOSIS (lines 120-127, 211-218), PROVIDER (line 188) joins all present |
| SVENC-04 | 10-04 | Survivorship encounter columns in hl_cohort.csv | SATISFIED | Section 6.8 sources and joins survivorship flags; Section 7 select() uses starts_with("HAD_ENC_"), starts_with("N_ENC_"), starts_with("FIRST_ENC_") |
| TDOC-01 | 10-04 | DAYS_DX_TO_CHEMO, DAYS_DX_TO_RADIATION, DAYS_DX_TO_SCT in hl_cohort.csv | SATISFIED | Section 6.6 computes timing (lines 236-238); explicitly included in Section 7 select() (lines 305-307) |
| TDOC-02 | 10-05 | R script auto-generates comprehensive variable documentation | SATISFIED (conditional) | 15_generate_documentation.R exists (674 lines), reads all code lists programmatically, builds 11 sections; cannot be fully SATISFIED until the script is run and outputs verified |
| TDOC-03 | 10-05 | Documentation output as both .md and .docx | FAILED | output/docs/ does not exist; neither file has been generated yet |

**Orphaned requirements check:** All 11 Phase 10 requirements (SURV-01 through TDOC-03) are mapped in REQUIREMENTS.md traceability table as "Complete" and are accounted for across plans 10-01 through 10-05. No orphaned requirements found.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `R/04_build_cohort.R` | 378 | `hl_cohort$HAD_ENC_NONACUTE` -- wrong column name (actual: `HAD_ENC_NONACUTE_CARE`) | Warning | Console summary will always show 0 for Level 1 non-acute care count; CSV output is correct |
| `R/13_surveillance.R` | (none in file) | No source('R/00_config.R') guard -- must be called from 04_build_cohort.R context | Info | Script will fail if sourced in isolation without 00_config.R already loaded |
| `R/14_survivorship_encounters.R` | (none in file) | No source('R/00_config.R') guard -- must be called from 04_build_cohort.R context | Info | Script will fail if sourced in isolation without 00_config.R already loaded |

---

### Human Verification Required

#### 1. Generate and Inspect Documentation Output

**Test:** Run `source("R/15_generate_documentation.R")` from the project root in RStudio.
**Expected:** `output/docs/Treatment_Variable_Documentation.md` created with 11 sections; code counts dynamically read from 00_config.R. `output/docs/Treatment_Variable_Documentation.docx` created if pandoc is available.
**Why human:** Files do not yet exist; pandoc availability depends on machine configuration; documentation quality and completeness requires human review.

#### 2. Verify Level 1 Non-Acute Care Count in Pipeline Run

**Test:** Run the full pipeline (`source("R/04_build_cohort.R")`), observe console output for the survivorship summary section.
**Expected:** "Non-acute care (L1): N patients" should report a non-zero number. If it shows 0, the column name mismatch at line 378 (`HAD_ENC_NONACUTE` vs `HAD_ENC_NONACUTE_CARE`) is confirmed.
**Why human:** Requires actual PCORnet CSV data to run.

---

### Gaps Summary

Three gaps were identified:

**Gap 1 (Blocker for TDOC-03): Documentation output files not generated.**
`R/15_generate_documentation.R` is correctly written and wired (sources 00_config.R, writes markdown, renders docx), but `output/docs/` does not exist and neither output file has been produced. The script must be run at least once for the documentation deliverable to exist. This is the primary outstanding action for the phase goal of "regenerate Treatment_Variable_Documentation.docx."

**Gap 2 (Warning): Column name mismatch in 04_build_cohort.R Section 8 console summary.**
`04_build_cohort.R` line 378 references `hl_cohort$HAD_ENC_NONACUTE` but the column produced by `14_survivorship_encounters.R` is `HAD_ENC_NONACUTE_CARE`. The CSV output and all downstream analysis are unaffected (the `starts_with("HAD_ENC_")` in select() captures the correct column), but every pipeline run will silently show "0 patients" for Level 1 non-acute care in the console summary, which is misleading for diagnostic purposes.

**Gap 3 (Info): Detection scripts rely on caller for config globals.**
Neither `13_surveillance.R` nor `14_survivorship_encounters.R` sources `00_config.R` directly. This works correctly at runtime (04_build_cohort.R sources 00_config.R before sourcing either file), but the scripts cannot be run standalone without pre-loading the config. The plan key_links pattern `source.*00_config` is not satisfied within these files. This is a defensive robustness issue, not a correctness issue.

The core pipeline functionality (surveillance detection, survivorship classification, cohort integration, timing derivation) is fully implemented and wired. The primary remaining action is to run `15_generate_documentation.R` to produce the documentation deliverable that is the explicit stated goal of the phase.

---

_Verified: 2026-03-31_
_Verifier: Claude (gsd-verifier)_
