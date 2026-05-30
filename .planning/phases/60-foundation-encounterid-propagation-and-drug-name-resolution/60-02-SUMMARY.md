---
phase: 60-foundation-encounterid-propagation-and-drug-name-resolution
plan: 02
subsystem: treatment-analysis
tags: [drug-resolution, rxnorm-api, cache-optimization]
dependency_graph:
  requires: [R/00_config.R, R/utils_duckdb.R, R/40_investigate_unmatched_ndc.R]
  provides: [drug_name_lookup.rds, drug_name_lookup.csv, lookup_rxcui_name, lookup_ndc_to_name, lookup_drug_codes_batch]
  affects: []
tech_stack:
  added: [httr2]
  patterns: [api-retry-logic, cache-aware-queries, standalone-script]
key_files:
  created:
    - path: R/60_drug_name_resolution.R
      purpose: Standalone drug name resolution script
      lines: 355
  modified: []
decisions:
  - id: D-06
    summary: Drug name resolution covers chemotherapy only
    rationale: Phase 61 regimen identification needs ABVD component drugs; non-chemo drugs out of scope
  - id: D-07
    summary: Both RXNORM_CUI and NDC codes resolved via R/40 functions
    rationale: PRESCRIBING uses RXNORM_CUI, DISPENSING may have NDC codes; both needed for coverage
  - id: D-08
    summary: Only codes from patient data (not all config codes) are resolved
    rationale: Reduces API calls; config has 200+ codes but patient data likely has subset
  - id: D-09
    summary: Results cached in drug_name_lookup.rds; re-runs only query new codes
    rationale: RxNorm API rate limits; cache avoids redundant lookups
  - id: D-10
    summary: Standalone script separate from episode extraction
    rationale: One-time resolution task; R/44a will load cached RDS file
metrics:
  duration_seconds: 112
  duration_readable: "2 minutes"
  tasks_completed: 1
  tasks_total: 1
  files_created: 1
  files_modified: 0
  commits: 1
  completed_date: "2026-05-30"
---

# Phase 60 Plan 02: Drug Name Resolution via RxNorm API Summary

**One-liner:** Standalone script that extracts unique RXNORM_CUI and NDC codes from chemotherapy patient data (PRESCRIBING/DISPENSING/MED_ADMIN) and resolves them to generic drug names via NLM RxNorm API with caching and retry logic.

## What Was Built

Created `R/60_drug_name_resolution.R`, a standalone script that:

1. **Extracts unique drug codes** from patient data tables (PRESCRIBING, DISPENSING, MED_ADMIN)
   - Filters to chemotherapy codes only (`TREATMENT_CODES$chemo_rxnorm` per D-06)
   - Extracts both RXNORM_CUI and NDC codes (per D-07)
   - Only queries codes that appear in actual patient data, not all config codes (per D-08)

2. **Resolves codes to drug names** via NLM RxNorm REST API
   - Copied three lookup functions from R/40_investigate_unmatched_ndc.R for script independence:
     - `lookup_rxcui_name(rxcui)`: Direct RxCUI -> drug name
     - `lookup_ndc_to_name(ndc)`: 2-step NDC -> RxCUI -> drug name
     - `lookup_drug_codes_batch(codes_df)`: Batch processing with progress logging
   - Uses httr2 with retry logic for transient failures (429, 503, 504)
   - 0.1s sleep between requests for rate limiting

3. **Caches results** for re-run efficiency (per D-09)
   - Loads existing `drug_name_lookup.rds` if present
   - Only queries codes not in cache (cache-aware API calls)
   - Saves updated cache after new lookups

4. **Produces two outputs**
   - `cache/outputs/drug_name_lookup.rds`: RDS cache for downstream scripts (TREAT-02)
   - `output/drug_name_lookup.csv`: Human-readable reference table (TREAT-03)

5. **Console logging**
   - Unique code counts by type (RXNORM, NDC)
   - API lookup progress (every 10 codes)
   - Summary statistics (success/not_found/error counts)
   - List of unique drug names resolved

## Task Completion

| Task | Name                                      | Status    | Commit  | Files Created                  |
| ---- | ----------------------------------------- | --------- | ------- | ------------------------------ |
| 1    | Create R/60_drug_name_resolution.R        | Complete  | 1ad7593 | R/60_drug_name_resolution.R    |

All tasks completed successfully. No checkpoints hit.

## Deviations from Plan

None. Plan executed exactly as written.

## Outputs

### Artifacts Created

1. **R/60_drug_name_resolution.R** (355 lines)
   - Standalone script (does not source R/40 to avoid side effects)
   - Sources only R/00_config.R and R/utils_duckdb.R
   - Contains complete API lookup logic copied from R/40

2. **Cached lookup table** (not created yet — requires first run on HiPerGator)
   - Path: `cache/outputs/drug_name_lookup.rds`
   - Schema: `code`, `code_type`, `drug_name`, `lookup_status`, `source_tables`

3. **CSV reference** (not created yet — requires first run on HiPerGator)
   - Path: `output/drug_name_lookup.csv`
   - Same schema as RDS cache

### Verification Results

All automated verification checks passed:

- ✓ `lookup_rxcui_name` function exists (3 occurrences: definition + 2 calls)
- ✓ `lookup_ndc_to_name` function exists (2 occurrences: definition + call)
- ✓ `lookup_drug_codes_batch` function exists (2 occurrences: definition + call)
- ✓ `TREATMENT_CODES$chemo_rxnorm` filter present (4 occurrences in PRESCRIBING/DISPENSING/MED_ADMIN queries)
- ✓ `drug_name_lookup` references present (5 occurrences in cache/output paths)
- ✓ RxNorm API endpoint `rxnav.nlm.nih.gov` present (2 URLs)
- ✓ `anti_join(cached_lookups)` cache-aware logic present
- ✓ `library(httr2)` API request library loaded
- ✓ Script does NOT source R/40 (no `source.*40` matches)
- ✓ Script sources R/00_config.R
- ✓ Script sources R/utils_duckdb.R

## Known Stubs

None. This script has no UI or data visualization components. It produces complete RDS and CSV artifacts after API queries.

## Next Steps

1. **Run on HiPerGator** to generate initial drug name lookup tables
   - Expected API call count: ~20-50 unique codes (subset of 200+ config codes)
   - Estimated runtime: 2-5 minutes for initial run (with 0.1s sleep per API call)
   - Re-runs will be instant (cache hit)

2. **Phase 60 Plan 03** will integrate this lookup table into R/43a or R/44a for episode-level drug name labeling

3. **Phase 61** will use drug names to identify first-line regimens (ABVD, BV+AVD, Nivo+AVD)

## Technical Notes

### Why Copy Functions from R/40?

R/40_investigate_unmatched_ndc.R is an analysis script with side effects (it runs analysis on load). Sourcing it directly would trigger unwanted behavior. Copying the three lookup functions ensures R/60 is truly standalone.

### Cache Strategy

The cache-aware approach reduces API calls dramatically on re-runs:
- First run: queries all codes in patient data (~20-50 codes)
- Subsequent runs: only queries new codes (e.g., if new patient data added)
- Cache file is portable (can be shared across environments)

### API Rate Limiting

RxNorm API has no documented rate limit, but the 0.1s sleep (10 req/sec) is conservative to avoid transient 429 errors. If API becomes unresponsive, httr2 retry logic handles 429/503/504 automatically (max 3 tries).

## Self-Check

**Files Created:**
- ✓ R/60_drug_name_resolution.R exists (verified via test -f)

**Commits:**
- ✓ Commit 1ad7593 exists (verified via git log)

**Result:** PASSED

All claimed artifacts exist and are committed to the repository.

---

**Summary:** R/60_drug_name_resolution.R successfully created as a standalone, cache-aware drug name resolution script. Ready for first run on HiPerGator to generate drug_name_lookup.rds and drug_name_lookup.csv artifacts for Phase 61 regimen identification.
