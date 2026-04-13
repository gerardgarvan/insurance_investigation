---
phase: 21-generalize-phase-19-to-all-sources
verified: 2026-04-13T19:30:00Z
status: human_needed
score: 7/7 must-haves verified
human_verification:
  - test: "Run script on HiPerGator and verify console output shows all 5 sites"
    expected: "Console shows AMS, UMI, FLM, VRT, UFH with patient counts, encounter counts, and missingness rates"
    why_human: "Script must execute with real data on HiPerGator to verify runtime behavior and actual cross-site data production"
  - test: "Verify 6 CSV files are created in output/tables/"
    expected: "All 6 CSV files exist: all_source_payer_raw_value_distribution.csv, all_source_payer_missingness_by_year.csv, all_source_payer_missingness_by_enc_type.csv, all_source_payer_missingness_year_x_enc_type.csv, all_source_payer_raw_vs_harmonized.csv, all_source_cross_site_summary.csv"
    why_human: "CSV file creation requires script execution with real PCORnet data"
  - test: "Verify cross-site summary has correct structure"
    expected: "all_source_cross_site_summary.csv has one row per site (AMS, UMI, FLM, VRT, UFH) plus one ALL aggregate row, with columns n_patients, n_encounters, n_primary_missing, pct_primary_missing, n_secondary_missing, pct_secondary_missing, n_both_missing, pct_both_missing"
    why_human: "Requires inspection of actual CSV file structure and data after script execution"
  - test: "Verify UFH rates match Phase 19 findings"
    expected: "UFH row in cross-site summary shows missingness rates consistent with Phase 19's UFH-specific investigation"
    why_human: "Requires cross-referencing with Phase 19 output for consistency validation"
---

# Phase 21: Generalize Phase 19 to All Sources Verification Report

**Phase Goal:** Extend Phase 19's UFH-specific payer missingness investigation to all 5 partner sites (AMS, UMI, FLM, VRT, UFH) using group_by(SOURCE) instead of site-specific filtering, producing combined CSVs with cross-site comparison for head-to-head payer data completeness assessment

**Verified:** 2026-04-13T19:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth   | Status     | Evidence       |
| --- | ------- | ---------- | -------------- |
| 1   | User can see payer missingness rates for each partner site (AMS, UMI, FLM, VRT, UFH) in a single CSV with SOURCE column | ✓ VERIFIED | R/20_all_source_missingness.R Section 3 produces all_source_payer_raw_value_distribution.csv with SOURCE grouping (lines 140-172) |
| 2   | User can see temporal missingness by year grouped by SOURCE | ✓ VERIFIED | Section 4 produces all_source_payer_missingness_by_year.csv with group_by(SOURCE, admit_year) (lines 211-225) |
| 3   | User can see encounter-type missingness grouped by SOURCE | ✓ VERIFIED | Section 5 produces all_source_payer_missingness_by_enc_type.csv with group_by(SOURCE, ENC_TYPE_LABEL) (lines 248-262) |
| 4   | User can see year x encounter type crosstab grouped by SOURCE | ✓ VERIFIED | Section 6 produces all_source_payer_missingness_year_x_enc_type.csv with group_by(SOURCE, admit_year, ENC_TYPE_LABEL) (lines 285-295) |
| 5   | User can see raw vs harmonized comparison grouped by SOURCE | ✓ VERIFIED | Section 7 produces all_source_payer_raw_vs_harmonized.csv with per-SOURCE and per-SOURCE-per-year comparisons (lines 336-369) |
| 6   | User can see cross-site summary CSV with one row per site for head-to-head comparison | ✓ VERIFIED | Section 8 produces all_source_cross_site_summary.csv with one row per SOURCE + ALL aggregate row (lines 386-418) |
| 7   | User can review per-site missingness rates in console output on HiPerGator | ✓ VERIFIED | Section 9 provides comprehensive console summary with per-site breakdowns (lines 438-504) |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact | Expected    | Status | Details |
| -------- | ----------- | ------ | ------- |
| `R/20_all_source_missingness.R` | Multi-site payer missingness diagnostic script (min 350 lines) | ✓ VERIFIED | Exists, 504 lines, complete implementation with 9 sections |
| `output/tables/all_source_payer_raw_value_distribution.csv` | Raw value distribution by SOURCE | ⚠️ NEEDS EXECUTION | File will be created when script runs; write_csv call verified at line 172 |
| `output/tables/all_source_payer_missingness_by_year.csv` | Year-level missingness by SOURCE | ⚠️ NEEDS EXECUTION | File will be created when script runs; write_csv call verified at line 225 |
| `output/tables/all_source_payer_missingness_by_enc_type.csv` | Encounter-type missingness by SOURCE | ⚠️ NEEDS EXECUTION | File will be created when script runs; write_csv call verified at line 262 |
| `output/tables/all_source_payer_missingness_year_x_enc_type.csv` | Year x encounter type crosstab by SOURCE | ⚠️ NEEDS EXECUTION | File will be created when script runs; write_csv call verified at line 295 |
| `output/tables/all_source_payer_raw_vs_harmonized.csv` | Raw vs harmonized comparison by SOURCE | ⚠️ NEEDS EXECUTION | File will be created when script runs; write_csv call verified at line 369 |
| `output/tables/all_source_cross_site_summary.csv` | Cross-site summary with one row per site | ⚠️ NEEDS EXECUTION | File will be created when script runs; write_csv call verified at line 418 |

**Artifact Status:** 1/7 artifacts exist and verified substantive; 6/7 require script execution to produce outputs

### Key Link Verification

| From | To  | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| R/20_all_source_missingness.R | R/02_harmonize_payer.R | source() at script top | ✓ WIRED | Line 35: `source("R/02_harmonize_payer.R")` |
| R/20_all_source_missingness.R | pcornet$ENCOUNTER + pcornet$DEMOGRAPHIC | inner_join + left_join for HL patients with SOURCE | ✓ WIRED | Lines 93-95: select(-SOURCE) from ENCOUNTER, inner_join hl_patients, left_join DEMOGRAPHIC for SOURCE; also lines 320-322 for harmonized comparison |
| R/20_all_source_missingness.R | PAYER_MAPPING config | missing_indicators from sentinel_values + unavailable_codes | ✓ WIRED | Line 85: `missing_indicators <- c(PAYER_MAPPING$sentinel_values, PAYER_MAPPING$unavailable_codes)` |
| R/20_all_source_missingness.R | R/04_build_cohort.R | Conditional source() for HL cohort | ✓ WIRED | Line 56: `if (!exists("hl_cohort")) source("R/04_build_cohort.R")` |

**Key Links:** 4/4 verified as WIRED

### Data-Flow Trace (Level 4)

Data-flow verification deferred to human testing. The script processes real PCORnet data that only exists on HiPerGator. The following data flows are structurally correct based on code inspection:

1. **HL cohort identification** (Section 1): hl_patients extracted from hl_cohort, joined to DEMOGRAPHIC for SOURCE
2. **Encounter dataset** (Section 2): pcornet$ENCOUNTER joined to hl_patients (inner) and DEMOGRAPHIC (left) for SOURCE, with missingness flags computed from PAYER_TYPE fields
3. **All breakdown sections** (3-6): Group by SOURCE with real aggregations (n(), sum(), percentages)
4. **Raw vs harmonized** (Section 7): encounters tibble from 02_harmonize_payer.R provides payer_category for comparison
5. **Cross-site summary** (Section 8): Aggregates all_encounters by SOURCE with bind_rows for ALL row

All data flows from upstream sources (pcornet tables, hl_cohort, encounters) through transformations to CSV outputs. Real data flow requires HiPerGator execution.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ---------- | ----------- | ------ | -------- |
| ALLMISS-01 | 21-01-PLAN.md | User can see raw PAYER_TYPE_PRIMARY and PAYER_TYPE_SECONDARY value distributions for all HL cohort encounters grouped by SOURCE in a single combined CSV | ✓ SATISFIED | Section 3 (lines 137-187) groups by SOURCE, PAYER_TYPE_PRIMARY/SECONDARY, computes frequency/percentage, writes to all_source_payer_raw_value_distribution.csv |
| ALLMISS-02 | 21-01-PLAN.md | User can see temporal, encounter-type, and year x encounter-type missingness breakdowns grouped by SOURCE | ✓ SATISFIED | Sections 4-6 (lines 193-307) produce 3 CSV breakdowns: by year (group_by SOURCE, admit_year), by encounter type (group_by SOURCE, ENC_TYPE_LABEL), by year x type (group_by SOURCE, admit_year, ENC_TYPE_LABEL) |
| ALLMISS-03 | 21-01-PLAN.md | User can see raw vs harmonized missingness comparison grouped by SOURCE | ✓ SATISFIED | Section 7 (lines 313-377) compares primary_missing (raw) vs harmonized_missing (payer_category), grouped by SOURCE with per-year and overall rows |
| ALLMISS-04 | 21-01-PLAN.md | User can see cross-site summary CSV with one row per site plus ALL aggregate row | ✓ SATISFIED | Section 8 (lines 383-418) produces cross_site_summary by SOURCE, adds "ALL" row via bind_rows (line 404), includes n_patients, n_encounters, and all 3 missingness metrics |
| ALLMISS-05 | 21-01-PLAN.md | User can see console output on HiPerGator with per-site missingness summary, overall rates, and list of 6 CSV files | ✓ SATISFIED | Section 9 (lines 435-504) provides comprehensive console summary: per-site patient/encounter counts, overall missingness, per-site PRIMARY rates with >50% flagging, worst encounter types, CSV file list |

**Coverage:** 5/5 requirements satisfied with implementation evidence

**No orphaned requirements:** All Phase 21 requirements from REQUIREMENTS.md are claimed by this plan.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| None found | - | - | - | - |

**Scan Results:**
- No TODO/FIXME/PLACEHOLDER comments
- No empty return statements or stub implementations
- No hardcoded empty data patterns
- Correct pitfall avoidance patterns present:
  - `select(-SOURCE)` before DEMOGRAPHIC join (lines 93, 320) to avoid column collision
  - `.groups = "drop"` in all 11 summarise() calls to prevent grouped tibble warnings
  - `ENC_TYPE_LABEL = if_else(is.na(ENC_TYPE), "<NA>", ENC_TYPE)` for NA preservation (line 245)
  - `year(ADMIT_DATE) != 1900L` for sentinel date filtering (lines 205, 323)
- Script uses group_by(SOURCE) pattern 12 times as expected
- No filter(SOURCE == "UFH") — correctly uses all sites
- All 6 CSV files have all_source_ prefix
- SOURCE = "ALL" aggregate row present (line 404)

### Behavioral Spot-Checks

Behavioral spot-checks require HiPerGator execution with real PCORnet data. The following checks are deferred to human verification:

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Script loads without errors | `source("R/20_all_source_missingness.R")` | N/A | ? SKIP (needs HiPerGator) |
| Console output shows 5 sites | Check message output for AMS, UMI, FLM, VRT, UFH | N/A | ? SKIP (needs HiPerGator) |
| 6 CSV files created | `ls output/tables/all_source_*.csv | wc -l` should return 6 | N/A | ? SKIP (needs HiPerGator) |
| Cross-site summary has ALL row | `grep "^ALL," output/tables/all_source_cross_site_summary.csv` | N/A | ? SKIP (needs HiPerGator) |

### Human Verification Required

#### 1. Run Script on HiPerGator and Verify Console Output

**Test:**
1. Open RStudio on HiPerGator
2. Run: `source("R/20_all_source_missingness.R")`
3. Review console output for completeness

**Expected:**
- Console shows "ALL-SOURCE PAYER MISSINGNESS DIAGNOSTIC" banner
- Section 1 shows HL patient counts per site (AMS, UMI, FLM, VRT, UFH)
- Section 2 shows total encounters and overall missingness rates
- Section 3 shows top 3 PRIMARY values per site
- Section 4 shows year ranges and overall PRIMARY missingness per site
- Section 5 shows top 3 encounter types with highest missingness per site
- Section 6 shows top 10 SOURCE x year x type combinations
- Section 7 shows per-site raw vs harmonized delta
- Section 8 shows per-site patient/encounter counts and PRIMARY missingness
- Section 9 shows comprehensive summary with >50% flagging and worst encounter types
- Console lists all 6 CSV files written
- No error messages or warnings

**Why human:** Script requires execution with real PCORnet data on HiPerGator to verify runtime behavior, actual cross-site data processing, and console output formatting.

#### 2. Verify 6 CSV Files Are Created with Correct Structure

**Test:**
1. After running script, check output/tables/ directory
2. Verify 6 files exist with all_source_ prefix
3. Open each CSV and inspect structure

**Expected:**
- `all_source_payer_raw_value_distribution.csv`: Columns SOURCE, field, value, n, pct; rows for all SOURCE values x PAYER_TYPE fields
- `all_source_payer_missingness_by_year.csv`: Columns SOURCE, admit_year, n_encounters, n_primary_missing, n_secondary_missing, n_both_missing, pct_primary_missing, pct_secondary_missing, pct_both_missing
- `all_source_payer_missingness_by_enc_type.csv`: Columns SOURCE, ENC_TYPE_LABEL, n_encounters, n_primary_missing, n_secondary_missing, n_both_missing, pct_primary_missing, pct_secondary_missing, pct_both_missing
- `all_source_payer_missingness_year_x_enc_type.csv`: Columns SOURCE, admit_year, ENC_TYPE_LABEL, n_encounters, n_primary_missing, pct_primary_missing
- `all_source_payer_raw_vs_harmonized.csv`: Columns SOURCE, year, n_encounters, n_raw_primary_missing, pct_raw_primary, n_harmonized_missing, pct_harmonized; includes OVERALL rows
- `all_source_cross_site_summary.csv`: Columns SOURCE, n_patients, n_encounters, n_primary_missing, pct_primary_missing, n_secondary_missing, pct_secondary_missing, n_both_missing, pct_both_missing; includes ALL aggregate row

**Why human:** CSV file creation and structure validation requires script execution with real data. File existence, column names, data types, and row counts can only be verified after execution.

#### 3. Verify Cross-Site Summary Has ALL Aggregate Row

**Test:**
1. Open `all_source_cross_site_summary.csv`
2. Check for row with SOURCE = "ALL"
3. Verify counts are totals across all sites

**Expected:**
- Last row has SOURCE = "ALL"
- n_patients is total unique patients across all sites
- n_encounters is total encounters across all sites
- n_primary_missing is total across all sites
- pct_primary_missing is calculated as (total missing / total encounters) * 100
- Same for secondary and both missingness metrics

**Why human:** Aggregate row calculation correctness requires inspection of actual data values and manual verification that totals match sum of individual site rows.

#### 4. Verify UFH Rates Match Phase 19 Findings

**Test:**
1. Find UFH row in `all_source_cross_site_summary.csv`
2. Compare pct_primary_missing, pct_secondary_missing, pct_both_missing to Phase 19 output
3. Check for consistency (within 1-2 percentage points)

**Expected:**
- UFH PRIMARY missingness rate should approximately match Phase 19's finding (R/18_uf_insurance_missingness.R output)
- Minor differences acceptable due to:
  - HL cohort scoping (Phase 21 uses hl_cohort; Phase 19 may have used different patient filter)
  - Date range filtering (1900 sentinel exclusion)
- Large discrepancies (>5 percentage points) would indicate implementation error

**Why human:** Cross-phase consistency validation requires manual comparison of outputs from two different phases and domain knowledge to assess whether differences are expected or problematic.

### Gaps Summary

No gaps found in code implementation. All observable truths are verified, all artifacts are structurally correct, all key links are wired, and all requirements are satisfied with evidence.

The script is ready for execution on HiPerGator. The 6 CSV output files do not exist yet because the script has not been run with real data. This is expected — the script is a standalone diagnostic that must be executed manually.

**Status: human_needed** reflects the need for user execution on HiPerGator to:
1. Verify runtime behavior with real PCORnet data
2. Confirm 6 CSV files are created with expected structure
3. Validate cross-site data correctness
4. Cross-reference UFH rates with Phase 19 for consistency

No code changes are required. The implementation is complete and verified as structurally sound.

---

_Verified: 2026-04-13T19:30:00Z_
_Verifier: Claude (gsd-verifier)_
