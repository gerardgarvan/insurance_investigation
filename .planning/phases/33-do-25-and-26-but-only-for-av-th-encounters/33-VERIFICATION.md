---
phase: 33-do-25-and-26-but-only-for-av-th-encounters
verified: 2026-04-24T14:15:00Z
status: human_needed
score: 10/10 must-haves verified (scripts complete, awaiting HiPerGator execution)
re_verification: false
human_verification:
  - test: "Run R/33_multi_source_overlap_av_th.R on HiPerGator"
    expected: "4 CSV files created in output/tables/ with _av_th suffix: multi_source_same_date_detail_av_th.csv, multi_source_same_week_detail_av_th.csv, multi_source_combo_frequencies_av_th.csv, multi_source_per_source_summary_av_th.csv"
    why_human: "Script execution requires HiPerGator environment with actual PCORnet data; cannot run locally"
  - test: "Run R/34_overlap_classification_av_th.R on HiPerGator after R/33"
    expected: "4 CSV files created in output/tables/ with _av_th suffix: classified_same_date_detail_av_th.csv, classified_same_week_detail_av_th.csv, per_site_overlap_profile_av_th.csv, overlap_source_payer_completeness_av_th.csv"
    why_human: "Script execution requires HiPerGator environment; depends on R/33 outputs"
  - test: "Verify console output shows ENC_TYPE distribution with per-site AV/TH counts"
    expected: "Console output includes 'ENC_TYPE distribution after AV+TH filter' section with per-SOURCE breakdown and WARNING messages for sites with zero AV or TH encounters"
    why_human: "Console output verification requires actual script execution"
  - test: "Verify classification output shows Identical/Partial/Distinct recommendations"
    expected: "Console output includes per-source-combo recommendations (e.g., 'Safe to deduplicate' or 'Retain all')"
    why_human: "Classification logic verification requires actual data"
  - test: "Confirm baseline outputs preserved"
    expected: "R/22_multi_source_overlap_detection.R and R/23_overlap_classification.R remain unchanged; baseline CSV files without _av_th suffix are not overwritten"
    why_human: "Visual inspection of output directory after script execution"
---

# Phase 33: AV+TH Multi-Source Overlap Detection & Classification Verification Report

**Phase Goal:** User can run the Phase 25 (multi-source overlap detection) and Phase 26 (overlap classification and recommendations) analyses restricted to Ambulatory Visit (AV) and Telehealth (TH) encounter types only, producing separate CSV outputs with _av_th suffix for focused outpatient/non-institutional analysis

**Verified:** 2026-04-24T14:15:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth | Status | Evidence |
|-----|-------|--------|----------|
| 1   | User can see same-date multi-source encounter groups restricted to AV+TH encounter types only | ✓ VERIFIED | R/33_multi_source_overlap_av_th.R line 85: `filter(ENC_TYPE %in% c("AV", "TH"))` applied before overlap detection; writes multi_source_same_date_detail_av_th.csv (line 467) |
| 2   | User can see same-week near-duplicate pairs restricted to AV+TH encounter types only | ✓ VERIFIED | Same filter applies to all downstream logic; writes multi_source_same_week_detail_av_th.csv (line 473) |
| 3   | User can see per-source counts and source combination frequencies for AV+TH encounters | ✓ VERIFIED | R/33 computes per_source_same_date (lines 301-311), per_source_same_week (lines 375-385), combo frequencies (lines 324-340, 400-415); writes combo_frequencies_av_th.csv and per_source_summary_av_th.csv |
| 4   | User can see ENC_TYPE distribution after filtering logged to console with per-site AV/TH counts | ✓ VERIFIED | R/33 lines 88-123: ENC_TYPE distribution computed and logged per SOURCE with WARNING messages for sites with zero AV or TH |
| 5   | Phase 25 baseline CSVs are not overwritten (outputs use _av_th suffix) | ✓ VERIFIED | R/22 unchanged (0 _av_th references); R/33 writes all 4 CSVs with _av_th suffix (lines 467, 473, 479, 504) |
| 6   | User can see field-by-field match/mismatch flags for each same-date AV+TH multi-source group | ✓ VERIFIED | R/34_overlap_classification_av_th.R lines 210-280: field_match() applied to 5 fields (ENC_TYPE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, PROVIDERID, DISCHARGE_DATE) for same-date pairs |
| 7   | User can see each AV+TH multi-source group classified as Identical, Partial, or Distinct | ✓ VERIFIED | R/34 lines 290-305: classification logic with thresholds (5/5 = Identical, 3-4/5 = Partial, 0-2/5 = Distinct); same logic for same-week (lines 370-385) |
| 8   | User can see per-source-combo overlap profiles for AV+TH encounters | ✓ VERIFIED | R/34 lines 425-465: sd_site_profile and sw_site_profile compute pct_identical/pct_partial/pct_distinct per source_combo; writes per_site_overlap_profile_av_th.csv (line 587) |
| 9   | User can see per-site actionable recommendations for AV+TH encounter deduplication | ✓ VERIFIED | R/34 lines 470-508: recommendations generated based on pct_identical thresholds with preferred source from payer completeness; logged in console summary (lines 635-641) |
| 10  | User can see a console summary with AV+TH classification breakdown and key findings | ✓ VERIFIED | R/34 lines 601-653: comprehensive console summary with same-date/same-week classification counts, per-combo breakdown, recommendations, and file list |

**Score:** 10/10 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| R/33_multi_source_overlap_av_th.R | Multi-source overlap detection for AV+TH encounters, 500+ lines | ✓ VERIFIED | Exists, 591 lines, contains ENC_TYPE filter, get_pcornet_table("ENCOUNTER"), materialize(), 4 write_csv calls with _av_th suffix |
| R/34_overlap_classification_av_th.R | Overlap classification for AV+TH encounters, 550+ lines | ✓ VERIFIED | Exists, 653 lines, reads Plan 01 CSVs with _av_th suffix, filters ENCOUNTER to AV+TH, field comparison logic, 4 write_csv calls with _av_th suffix |
| output/tables/multi_source_same_date_detail_av_th.csv | Same-date detail for AV+TH | ⚠️ NOT_YET_CREATED | Script exists and writes this file (line 467 of R/33), but file not present (awaiting HiPerGator execution) |
| output/tables/multi_source_same_week_detail_av_th.csv | Same-week detail for AV+TH | ⚠️ NOT_YET_CREATED | Script exists and writes this file (line 473 of R/33), but file not present (awaiting HiPerGator execution) |
| output/tables/multi_source_combo_frequencies_av_th.csv | Source combo frequencies for AV+TH | ⚠️ NOT_YET_CREATED | Script exists and writes this file (line 479 of R/33), but file not present (awaiting HiPerGator execution) |
| output/tables/multi_source_per_source_summary_av_th.csv | Per-source summary for AV+TH | ⚠️ NOT_YET_CREATED | Script exists and writes this file (line 504 of R/33), but file not present (awaiting HiPerGator execution) |
| output/tables/classified_same_date_detail_av_th.csv | Classified same-date detail for AV+TH | ⚠️ NOT_YET_CREATED | Script exists and writes this file (line 530 of R/34), but file not present (awaiting HiPerGator execution) |
| output/tables/classified_same_week_detail_av_th.csv | Classified same-week detail for AV+TH | ⚠️ NOT_YET_CREATED | Script exists and writes this file (line 544 of R/34), but file not present (awaiting HiPerGator execution) |
| output/tables/per_site_overlap_profile_av_th.csv | Per-source-combo overlap profile for AV+TH | ⚠️ NOT_YET_CREATED | Script exists and writes this file (line 587 of R/34), but file not present (awaiting HiPerGator execution) |
| output/tables/overlap_source_payer_completeness_av_th.csv | Source payer completeness for AV+TH | ⚠️ NOT_YET_CREATED | Script exists and writes this file (line 594 of R/34), but file not present (awaiting HiPerGator execution) |

**Note:** CSV artifacts are marked NOT_YET_CREATED because this is a code-generation phase. The scripts are complete and ready to run on HiPerGator. CSV creation requires actual execution with PCORnet data.

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| R/33_multi_source_overlap_av_th.R | R/utils_duckdb.R | get_pcornet_table('ENCOUNTER') %>% materialize() | ✓ WIRED | Line 83: `enc <- get_pcornet_table("ENCOUNTER") %>% materialize() %>% filter(...)` |
| R/33_multi_source_overlap_av_th.R | output/tables/ | write_csv with _av_th suffix | ✓ WIRED | 4 write_csv calls found: lines 467, 473, 479, 504; all use _av_th suffix |
| R/34_overlap_classification_av_th.R | output/tables/multi_source_same_date_detail_av_th.csv | read_csv of Plan 01 output | ✓ WIRED | Line 100: `read_csv(file.path(output_dir, "multi_source_same_date_detail_av_th.csv"), ...)` |
| R/34_overlap_classification_av_th.R | output/tables/multi_source_same_week_detail_av_th.csv | read_csv of Plan 01 output | ✓ WIRED | Line 115: `read_csv(file.path(output_dir, "multi_source_same_week_detail_av_th.csv"), ...)` |
| R/34_overlap_classification_av_th.R | R/utils_duckdb.R | get_pcornet_table for ENCOUNTER and DEMOGRAPHIC | ✓ WIRED | Lines 134, 163: `get_pcornet_table("ENCOUNTER")`, `get_pcornet_table("DEMOGRAPHIC")` |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|-------------------|--------|
| R/33_multi_source_overlap_av_th.R | enc | get_pcornet_table("ENCOUNTER") via DuckDB | Yes - loads from DuckDB database | ✓ FLOWING |
| R/33_multi_source_overlap_av_th.R | same_date_detail | Self-join on enc where n_distinct(SOURCE) > 1 per (ID, ADMIT_DATE) | Yes - derived from real enc data | ✓ FLOWING |
| R/33_multi_source_overlap_av_th.R | same_week_detail | Self-join on enc with 7-day window | Yes - derived from real enc data | ✓ FLOWING |
| R/34_overlap_classification_av_th.R | same_date_detail | read_csv from Plan 01 output | Depends on R/33 execution | ⚠️ AWAITING_INPUT |
| R/34_overlap_classification_av_th.R | enc_prepared | get_pcornet_table("ENCOUNTER") filtered to AV+TH | Yes - loads from DuckDB database | ✓ FLOWING |
| R/34_overlap_classification_av_th.R | sd_pairs | Pairwise field comparison via self-join | Yes - derived from real enc_prepared data | ✓ FLOWING |

**Note:** R/34 data flow depends on R/33 output CSVs, which will be created on HiPerGator execution.

### Behavioral Spot-Checks

Phase 33 produces R scripts that require HiPerGator execution with PCORnet data. Local spot-checks are not feasible.

**Step 7b: DEFERRED** — Scripts are runnable only on HiPerGator with access to DuckDB PCORnet database and RDS cache. No local entry points available. Human verification required after HiPerGator execution.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| AVTH-DET-01 | 33-01 | User can see same-date multi-source encounter groups restricted to AV+TH | ✓ SATISFIED | R/33 line 85: `filter(ENC_TYPE %in% c("AV", "TH"))` before detection; writes multi_source_same_date_detail_av_th.csv |
| AVTH-DET-02 | 33-01 | User can see same-week near-duplicate pairs restricted to AV+TH | ✓ SATISFIED | R/33 applies AV+TH filter to all logic; writes multi_source_same_week_detail_av_th.csv |
| AVTH-DET-03 | 33-01 | User can see per-source counts and source combination frequencies for AV+TH | ✓ SATISFIED | R/33 computes per_source_same_date/same_week and combo frequencies; writes 2 CSVs |
| AVTH-DET-04 | 33-01 | User can see ENC_TYPE distribution after filtering with per-site AV/TH counts | ✓ SATISFIED | R/33 lines 88-123: ENC_TYPE distribution logged per SOURCE with WARNING for zero counts |
| AVTH-DET-05 | 33-01 | User can see 4 CSV output files with _av_th suffix | ✓ SATISFIED | R/33 writes 4 CSVs: multi_source_same_date_detail_av_th.csv, multi_source_same_week_detail_av_th.csv, multi_source_combo_frequencies_av_th.csv, multi_source_per_source_summary_av_th.csv |
| AVTH-DET-06 | 33-01 | Phase 25 baseline CSV outputs preserved unchanged | ✓ SATISFIED | R/22 unchanged (0 _av_th references); baseline CSVs not overwritten |
| AVTH-CLS-01 | 33-02 | User can see field-by-field match/mismatch flags for AV+TH same-date groups | ✓ SATISFIED | R/34 lines 210-280: field_match() on 5 fields (ENC_TYPE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, PROVIDERID, DISCHARGE_DATE) |
| AVTH-CLS-02 | 33-02 | User can see AV+TH groups classified as Identical/Partial/Distinct | ✓ SATISFIED | R/34 lines 290-305 (same-date), 370-385 (same-week): classification logic with thresholds |
| AVTH-CLS-03 | 33-02 | User can see per-source-combo overlap profiles for AV+TH | ✓ SATISFIED | R/34 lines 425-465: sd_site_profile and sw_site_profile with pct_identical/partial/distinct; writes per_site_overlap_profile_av_th.csv |
| AVTH-CLS-04 | 33-02 | User can see per-site actionable recommendations for AV+TH deduplication | ✓ SATISFIED | R/34 lines 470-508: recommendations based on pct_identical with preferred source; console output lines 635-641 |
| AVTH-CLS-05 | 33-02 | User can see console summary with AV+TH classification breakdown | ✓ SATISFIED | R/34 lines 601-653: comprehensive summary with classification counts, per-combo breakdown, recommendations |
| AVTH-CLS-06 | 33-02 | User can see 4 CSV output files with _av_th suffix | ✓ SATISFIED | R/34 writes 4 CSVs: classified_same_date_detail_av_th.csv, classified_same_week_detail_av_th.csv, per_site_overlap_profile_av_th.csv, overlap_source_payer_completeness_av_th.csv |
| AVTH-CLS-07 | 33-02 | Phase 26 baseline CSV outputs preserved; ENCOUNTER filtered to AV+TH | ✓ SATISFIED | R/23 unchanged (0 _av_th references); R/34 line 136: `filter(ENC_TYPE %in% c("AV", "TH"))` on ENCOUNTER before field comparison |

**Orphaned requirements:** None — all 13 requirements (AVTH-DET-01 through AVTH-DET-06, AVTH-CLS-01 through AVTH-CLS-07) mapped to Phase 33 in REQUIREMENTS.md are claimed by Plans 01 and 02.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| _(none)_ | — | — | — | No anti-patterns detected |

**Anti-pattern scan results:**
- **TODO/FIXME/PLACEHOLDER comments:** 0 found in R/33, 0 found in R/34
- **Empty implementations (return null/{}/_):** 0 found
- **Hardcoded empty data (= [] / = {}):** None that are stubs (some empty initializations before loops are valid)
- **Console.log only implementations:** Not applicable (R code uses message() for logging, which is intentional)

Both scripts are production-ready clones of Phase 25/26 baseline scripts with targeted modifications. No stub patterns detected.

### Human Verification Required

#### 1. HiPerGator Execution - R/33 Multi-Source Overlap Detection (AV+TH)

**Test:** Run `source("R/33_multi_source_overlap_av_th.R")` on HiPerGator in RStudio session after loading DuckDB backend

**Expected:**
- Console output shows "ENC_TYPE distribution after AV+TH filter" section with per-SOURCE AV and TH encounter counts
- WARNING messages appear for any sites with zero AV or zero TH encounters
- Console summary shows total encounters, parse rate, same-date and same-week counts
- 4 CSV files created in `output/tables/`:
  - multi_source_same_date_detail_av_th.csv
  - multi_source_same_week_detail_av_th.csv
  - multi_source_combo_frequencies_av_th.csv
  - multi_source_per_source_summary_av_th.csv
- Script completes without errors

**Why human:** Script execution requires HiPerGator environment with PCORnet DuckDB database and RDS cache; cannot verify programmatically without actual data

#### 2. HiPerGator Execution - R/34 Overlap Classification (AV+TH)

**Test:** After R/33 completes, run `source("R/34_overlap_classification_av_th.R")` on HiPerGator

**Expected:**
- Script successfully reads R/33 output CSVs (multi_source_same_date_detail_av_th.csv and multi_source_same_week_detail_av_th.csv)
- Console output shows "Filtered ENCOUNTER to AV+TH only for field comparison"
- Console summary shows classification breakdown (Identical/Partial/Distinct) for same-date and same-week
- Per-source-combo recommendations appear in console with actionable guidance (e.g., "Safe to deduplicate -- prefer UFH (85% payer completeness)")
- 4 CSV files created in `output/tables/`:
  - classified_same_date_detail_av_th.csv
  - classified_same_week_detail_av_th.csv
  - per_site_overlap_profile_av_th.csv
  - overlap_source_payer_completeness_av_th.csv
- Script completes without errors

**Why human:** Script execution requires HiPerGator environment and depends on R/33 outputs; cannot verify programmatically

#### 3. Baseline Preservation Verification

**Test:** After both scripts execute, check that baseline Phase 25/26 outputs still exist and are unchanged

**Expected:**
- Files `output/tables/multi_source_same_date_detail.csv`, `multi_source_same_week_detail.csv`, `multi_source_combo_frequencies.csv`, `multi_source_per_source_summary.csv` (Phase 25 baseline) exist and timestamps are older than new _av_th files
- Files `output/tables/classified_same_date_detail.csv`, `classified_same_week_detail.csv`, `per_site_overlap_profile.csv`, `overlap_source_payer_completeness.csv` (Phase 26 baseline) exist IF Phase 26 was previously run
- R/22_multi_source_overlap_detection.R and R/23_overlap_classification.R contain zero references to "_av_th"

**Why human:** Requires visual inspection of output directory after script execution to confirm baseline files were not overwritten

#### 4. AV+TH Data Sanity Check

**Test:** Inspect R/33 console output and CSV files for data sanity

**Expected:**
- ENC_TYPE distribution shows non-zero counts for both AV and TH at most sites
- If any site has zero AV or zero TH, WARNING message logged and flagged for investigation
- Same-date and same-week counts are plausible (lower than full-encounter baseline from Phase 25, since AV+TH is a subset)
- Source combinations are plausible (e.g., UFH+FLM, AMS+UMI, not single-source combinations)

**Why human:** Domain knowledge required to assess whether AV+TH subset produces expected data patterns

#### 5. Classification Logic Verification

**Test:** Inspect R/34 console output and per_site_overlap_profile_av_th.csv for classification results

**Expected:**
- Classification distribution shows mix of Identical, Partial, and Distinct (not 100% of one category)
- Recommendations align with classification patterns (e.g., high Identical % → "Safe to deduplicate", high Distinct % → "Retain all")
- Preferred source selection is logical (highest payer completeness per source combo)
- Comparison against Phase 26 baseline (if available) shows whether AV+TH subset has different overlap patterns than full encounter set

**Why human:** Requires domain expertise to interpret classification results and assess whether AV+TH patterns differ meaningfully from full encounter baseline

### Gaps Summary

**No blocking gaps found.**

All code artifacts (R/33, R/34) exist, are substantive (500+ lines each), correctly wired (get_pcornet_table, read_csv, write_csv), and have complete data flow from source to output. The phase goal is to provide **runnable scripts** for AV+TH subset analysis, which has been achieved.

**CSV artifacts are intentionally not created** because this is a code-generation phase. CSV creation requires execution on HiPerGator with actual PCORnet data, which is outside the scope of code development verification.

**Next steps:**
1. User executes R/33_multi_source_overlap_av_th.R on HiPerGator → creates 4 Plan 01 CSVs
2. User executes R/34_overlap_classification_av_th.R on HiPerGator → creates 4 Plan 02 CSVs
3. User compares AV+TH results against Phase 25/26 baseline to assess whether outpatient/telehealth encounters have different multi-source overlap patterns than the full encounter set

---

_Verified: 2026-04-24T14:15:00Z_
_Verifier: Claude (gsd-verifier)_
