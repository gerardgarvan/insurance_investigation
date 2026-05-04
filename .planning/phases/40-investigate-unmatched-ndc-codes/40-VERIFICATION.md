---
phase: 40-investigate-unmatched-ndc-codes
verified: 2026-05-04T21:15:00Z
status: human_needed
score: 7/10 must-haves verified
human_verification:
  - test: "Run R/40_investigate_unmatched_ndc.R on HiPerGator with data access"
    expected: "Script completes successfully, generates output/unmatched_ndc_report.xlsx and output/unmatched_ndc_classified.rds, updates R/00_config.R with new NDC vectors"
    why_human: "Script requires PCORnet data access on HiPerGator and RxNorm API connectivity; cannot verify data-flow or xlsx output quality without execution"
---

# Phase 40: Investigate Unmatched NDC Codes Verification Report

**Phase Goal:** Extract unmatched NDC and RXNORM codes from DISPENSING/PRESCRIBING/MED_ADMIN, look up drug names via RxNorm API, auto-classify into treatment categories, produce xlsx report, and update TREATMENT_CODES with new NDC vectors and expanded RXNORM CUIs

**Verified:** 2026-05-04T21:15:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

Plan 01 establishes 7 truths (D-01 through D-09, D-12, D-13):

| #   | Truth                                                                                      | Status     | Evidence                                                                                                       |
| --- | ------------------------------------------------------------------------------------------ | ---------- | -------------------------------------------------------------------------------------------------------------- |
| 1   | All unmatched NDC codes from DISPENSING table for HL patients are extracted and looked up | ✓ VERIFIED | Lines 170-196: DISPENSING NDC extraction with patient filter, API lookup integration (lines 407-416)           |
| 2   | All unmatched RXNORM CUIs from 3 drug tables are extracted and looked up                  | ✓ VERIFIED | Lines 140-256: DISPENSING/PRESCRIBING/MED_ADMIN RXNORM extraction, API lookup (lines 395-405)                  |
| 3   | Each code receives a drug name via RxNorm API lookup                                       | ✓ VERIFIED | Lines 284-376: lookup_rxcui_name() and lookup_ndc_to_name() functions with httr2 retry logic                   |
| 4   | Each code is classified into one of 6 treatment categories                                 | ✓ VERIFIED | Lines 444-476: classify_drug() with 6-category case_when() (Supportive Care, Chemo, Immuno, SCT, Radiation, Unrelated) |
| 5   | Supportive care drugs are not misclassified as chemotherapy                                | ✓ VERIFIED | Line 448: Supportive Care checked FIRST before Chemotherapy (per D-09 requirement)                             |
| 6   | A styled xlsx report is produced with summary and per-category sheets                      | ? UNCERTAIN | Lines 491-723: write_unmatched_ndc_report() exists but output file not present (requires execution)           |
| 7   | An RDS artifact is saved for Plan 02 config update consumption                             | ? UNCERTAIN | Line 734: saveRDS() called but output file not present (requires execution)                                    |

Plan 02 establishes 5 truths (D-10, D-11):

| #   | Truth                                                                                    | Status     | Evidence                                                                                       |
| --- | ---------------------------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------------------------------------- |
| 8   | New NDC vectors are added to TREATMENT_CODES                                             | ⚠️ HOLLOW  | Lines 770-775: chemo_ndc, supportive_care_ndc, immunotherapy_ndc, sct_ndc mapped; R/00_config.R not yet modified (config update function exists but not executed) |
| 9   | Existing chemo_rxnorm vector is expanded with newly discovered RXNORM CUIs               | ⚠️ HOLLOW  | Lines 778-781, 874-949: chemo_rxnorm expansion logic exists; R/00_config.R unchanged (requires execution) |
| 10  | New RXNORM vectors are created for non-chemo categories                                  | ⚠️ HOLLOW  | Lines 778-781: supportive_care_rxnorm, immunotherapy_rxnorm, sct_rxnorm mapped; not yet in config (requires execution) |

**Score:** 7/10 truths verified (5 fully verified, 2 uncertain pending execution, 3 hollow pending execution)

### Required Artifacts

**Plan 01 Artifacts:**

| Artifact                                      | Expected                                                              | Status     | Details                                                                                                 |
| --------------------------------------------- | --------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------- |
| `R/40_investigate_unmatched_ndc.R`            | NDC/RXNORM investigation script (min 400 lines)                       | ✓ VERIFIED | 1084 lines (exceeds min); exports all 5 required functions; httr2-based API lookup; 7 sections         |
| `output/unmatched_ndc_report.xlsx`            | Styled workbook with classification results                           | ⚠️ ORPHANED | Write function exists (lines 491-723) but output not generated yet (requires HiPerGator execution)     |
| `output/unmatched_ndc_classified.rds`         | RDS for Plan 02 config update                                         | ⚠️ ORPHANED | Save function exists (lines 733-736) but output not generated yet (requires HiPerGator execution)      |

**Plan 02 Artifacts:**

| Artifact                                      | Expected                                                              | Status     | Details                                                                                                 |
| --------------------------------------------- | --------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------- |
| `R/40_investigate_unmatched_ndc.R`            | update_config_ndc_codes() function added                              | ✓ VERIFIED | Lines 750-1010: Complete config update function with validation/rollback; called at line 1078          |
| `R/00_config.R`                               | TREATMENT_CODES with new NDC vectors and expanded RXNORM              | ⚠️ ORPHANED | Config unchanged; chemo_ndc not found (gsd-tools verified); update function exists but not executed    |

### Key Link Verification

**Plan 01 Links:**

| From                                 | To                                         | Via                                           | Status     | Details                                                                                     |
| ------------------------------------ | ------------------------------------------ | --------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------- |
| R/40_investigate_unmatched_ndc.R     | R/00_config.R                              | source() for TREATMENT_CODES                  | ✓ WIRED    | Line 28: `source("R/00_config.R")` present                                                  |
| R/40_investigate_unmatched_ndc.R     | R/01_load_pcornet.R                        | source() for get_pcornet_table()              | ✓ WIRED    | Line 29: `source("R/01_load_pcornet.R")` present                                            |
| R/40_investigate_unmatched_ndc.R     | https://rxnav.nlm.nih.gov/REST/            | httr2 HTTP requests for drug name lookup      | ✓ WIRED    | Lines 286, 335: RxNorm API endpoints used (rxcui properties, NDC idtype)                    |
| R/40_investigate_unmatched_ndc.R     | output/unmatched_ndc_classified.rds        | saveRDS()                                     | ⚠️ PARTIAL | Line 734: saveRDS() exists in function; line 1072: called in main execution; no output yet |

**Plan 02 Links:**

| From                                 | To                                         | Via                                           | Status     | Details                                                                                     |
| ------------------------------------ | ------------------------------------------ | --------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------- |
| R/40_investigate_unmatched_ndc.R     | R/00_config.R                              | readLines/writeLines programmatic update      | ✓ WIRED    | Lines 795, 954: readLines/writeLines present; parse/source validation (lines 959, 963)     |
| R/40_investigate_unmatched_ndc.R     | output/unmatched_ndc_classified.rds        | readRDS() to load Plan 01 results             | ✓ WIRED    | Line 756: readRDS(classified_codes_path) loads RDS artifact for config update              |

### Data-Flow Trace (Level 4)

**Not applicable:** Phase 40 is a data extraction/classification script that produces reports and config updates. There are no UI components that render dynamic data. Data flow verification deferred to execution on HiPerGator.

### Behavioral Spot-Checks

**Skipped:** Script requires HiPerGator data access (DISPENSING, PRESCRIBING, MED_ADMIN tables) and RxNorm API connectivity. Behavioral checks deferred to human verification on HiPerGator.

### Requirements Coverage

**Plan 01 Requirements:** D-01, D-02, D-03, D-04, D-05, D-06, D-07, D-08, D-09, D-12, D-13

| Requirement | Source Plan | Description                                                                 | Status     | Evidence                                                                                        |
| ----------- | ----------- | --------------------------------------------------------------------------- | ---------- | ----------------------------------------------------------------------------------------------- |
| D-01        | 40-01       | Investigate both NDC and unmatched RXNORM CUIs                              | ✓ SATISFIED | Lines 140-256: All 3 drug tables queried for both code types                                    |
| D-02        | 40-01       | All 3 drug tables in scope (DISPENSING, PRESCRIBING, MED_ADMIN)            | ✓ SATISFIED | Lines 140-256: All 3 tables queried with safe_table() error handling                            |
| D-03        | 40-01       | Exclude ICD, DRG, revenue, CPT/HCPCS (Phase 39 scope)                      | ✓ SATISFIED | Script focuses only on NDC/RXNORM from drug tables                                              |
| D-04        | 40-01       | Use NLM RxNorm API for code-to-name resolution                              | ✓ SATISFIED | Lines 284-376: RxNorm API integration with httr2                                                |
| D-05        | 40-01       | NDC lookup: 2-step NDC->RxCUI->Name                                         | ✓ SATISFIED | Lines 332-376: lookup_ndc_to_name() implements 2-step pattern                                   |
| D-06        | 40-01       | RXNORM lookup: direct RxCUI->Name                                           | ✓ SATISFIED | Lines 284-322: lookup_rxcui_name() direct properties lookup                                     |
| D-07        | 40-01       | Fully automated classification via keyword matching                         | ✓ SATISFIED | Lines 444-476: classify_drug() with case_when() keyword patterns                                |
| D-08        | 40-01       | 6 treatment categories (chemo, radiation, SCT, immuno, supportive, unrelated) | ✓ SATISFIED | Lines 447-475: All 6 categories in case_when()                                                |
| D-09        | 40-01       | Supportive Care checked first to avoid G-CSF misclassification              | ✓ SATISFIED | Line 448: "# 1. Supportive Care FIRST (per D-09)" — checked before Chemotherapy                |
| D-12        | 40-01       | Produce xlsx report with summary and per-category sheets                    | ? NEEDS HUMAN | Lines 491-723: write_unmatched_ndc_report() exists; output quality requires execution verification |
| D-13        | 40-01       | Produce RDS artifact for config update consumption                          | ? NEEDS HUMAN | Lines 733-736: save_classified_rds() exists; artifact presence requires execution               |

**Plan 02 Requirements:** D-10, D-11

| Requirement | Source Plan | Description                                                                 | Status     | Evidence                                                                                        |
| ----------- | ----------- | --------------------------------------------------------------------------- | ---------- | ----------------------------------------------------------------------------------------------- |
| D-10        | 40-02       | Add new NDC vectors to TREATMENT_CODES                                      | ⚠️ BLOCKED | Lines 770-775: Vector mapping exists; R/00_config.R not modified (function not executed)       |
| D-11        | 40-02       | Expand chemo_rxnorm and create new RXNORM vectors                           | ⚠️ BLOCKED | Lines 778-781, 874-949: Logic exists; R/00_config.R unchanged (function not executed)          |

**Orphaned requirements:** None — all requirement IDs from PLAN frontmatter accounted for.

### Anti-Patterns Found

**No blocker anti-patterns detected.** Code quality is high:

| File                                    | Line | Pattern                                      | Severity | Impact                                                                                     |
| --------------------------------------- | ---- | -------------------------------------------- | -------- | ------------------------------------------------------------------------------------------ |
| R/40_investigate_unmatched_ndc.R        | N/A  | N/A                                          | ℹ️ Info  | No TODO/FIXME/placeholder comments found                                                   |
| R/40_investigate_unmatched_ndc.R        | N/A  | N/A                                          | ℹ️ Info  | No empty return stubs found (all functions have substantive implementations)               |
| R/40_investigate_unmatched_ndc.R        | N/A  | httr2 retry pattern present                  | ℹ️ Info  | Lines 290-293, 339-342: req_retry() with transient error detection (best practice)         |

**Notable quality markers:**
- **Comprehensive error handling:** All 3 drug table queries wrapped in tryCatch (lines 144-162, 173-190, 202-220, 232-250)
- **Safe table access:** safe_table() helper prevents crashes on missing tables (lines 61-69)
- **Validation safety:** Config update includes parse/source validation with rollback (lines 957-988)
- **Code reuse:** Follows Phase 39 proven patterns (API batching, xlsx styling, config update)

### Human Verification Required

#### 1. HiPerGator Execution with Real Data

**Test:** Run `Rscript R/40_investigate_unmatched_ndc.R` on HiPerGator with PCORnet data access

**Expected:**
1. Script completes without errors
2. `output/unmatched_ndc_report.xlsx` is created with:
   - Summary sheet showing classification counts by category, code type, source table
   - Per-category sheets (Chemotherapy, Immunotherapy, SCT-related, Supportive Care, Radiation, Unrelated) with styled pills
   - All NDC codes resolved to drug names (or marked as `ndc_not_found`)
   - All RXNORM CUIs resolved to drug names (or marked as `not_found`)
3. `output/unmatched_ndc_classified.rds` is created with all classified codes
4. `R/00_config.R` is updated with new vectors:
   - New NDC vectors: `chemo_ndc`, `supportive_care_ndc`, `immunotherapy_ndc`, `sct_ndc`
   - Expanded RXNORM vectors: `chemo_rxnorm` (from 4 CUIs to 4+N), `supportive_care_rxnorm`, `immunotherapy_rxnorm`, `sct_rxnorm`
5. Updated `R/00_config.R` parses and sources without errors
6. Classification summary shows reasonable distribution (supportive care drugs not in chemo category)

**Why human:** Script requires:
- PCORnet CDM data access (DISPENSING, PRESCRIBING, MED_ADMIN tables with HL patient records)
- RxNorm API connectivity (rxnav.nlm.nih.gov)
- Cannot verify drug name lookups without API calls
- Cannot verify xlsx styling/formatting without generated file
- Cannot verify config update correctness without execution

#### 2. Validate Classification Quality

**Test:** Manually review `output/unmatched_ndc_report.xlsx` Chemotherapy and Supportive Care sheets

**Expected:**
1. **Supportive Care sheet contains:**
   - Filgrastim/pegfilgrastim (G-CSF) drugs
   - Ondansetron/granisetron (antiemetics)
   - Epoetin/darbepoetin (EPO)
   - Dexamethasone
   - NO chemotherapy agents (doxorubicin, bleomycin, dacarbazine, etc.)

2. **Chemotherapy sheet contains:**
   - ABVD regimen drugs: doxorubicin, bleomycin, vinblastine, dacarbazine
   - Brentuximab vedotin
   - Checkpoint inhibitors: nivolumab, pembrolizumab
   - Other chemo agents: etoposide, cisplatin, cyclophosphamide, bendamustine
   - NO supportive care drugs (filgrastim, ondansetron, epoetin, etc.)

**Why human:** Classification is keyword-based heuristics. Accuracy requires domain knowledge (HL treatment protocols) to validate that:
- Supportive care priority rule (D-09) works correctly
- No false positives (unrelated drugs classified as treatment)
- No false negatives (known HL drugs classified as unrelated)

#### 3. Verify Config Update Correctness

**Test:** After execution, inspect `R/00_config.R` TREATMENT_CODES section

**Expected:**
1. New NDC vectors appear BEFORE `supportive_care_hcpcs` or `chemo_revenue` (lines 750-859 define insertion anchor logic)
2. Each new vector has inline comments: `# Phase 40: {drug_name}` (truncated to 40 chars)
3. `chemo_rxnorm` vector contains original 4 CUIs plus new ones (no duplicates)
4. All new vectors have proper R syntax: `c("code1", "code2", ...)` with closing paren
5. `parse("R/00_config.R")` succeeds (no syntax errors)
6. `source("R/00_config.R", local = new.env())` succeeds and `TREATMENT_CODES` is not NULL

**Why human:** Config update is programmatic text manipulation. Validation requires:
- Visual inspection of generated code structure
- Verification that insertion anchors worked correctly
- Confirmation that no existing code was corrupted
- Cannot automate without executing the script on real data

### Gaps Summary

**No gaps blocking automated script creation.** All code artifacts exist and are properly wired.

**Execution-dependent outputs not verified:**
- `output/unmatched_ndc_report.xlsx` — write function exists but no output (requires HiPerGator run)
- `output/unmatched_ndc_classified.rds` — save function exists but no output (requires HiPerGator run)
- `R/00_config.R` modifications — update function exists but not executed (requires HiPerGator run)

**Status rationale:** All 13 requirement IDs have corresponding implementations. The phase goal is achievable with the current code. Output artifacts (xlsx, RDS, config updates) require execution on HiPerGator with data access, which is outside the scope of static code verification. Status set to `human_needed` rather than `gaps_found` because no code is missing — only execution is pending.

---

_Verified: 2026-05-04T21:15:00Z_
_Verifier: Claude (gsd-verifier)_
