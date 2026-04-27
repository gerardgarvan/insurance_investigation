---
phase: 35-tiered-same-day-payer-categorization
plan: 01
subsystem: payer-analysis
tags: [payer, frequency-tables, tiered-resolution, same-day-conflicts, dual-scope]
dependency_graph:
  requires: [PayerVariable.xlsx, ENCOUNTER table, R/00_config.R, R/utils_duckdb.R]
  provides: [R/36_tiered_same_day_payer.R, 12 CSV outputs (6 frequency + 6 resolution)]
  affects: [PI payer analysis workflow, same-day encounter conflict resolution]
tech_stack:
  added: []
  patterns: [materialize-early DuckDB pattern, dual-scope analysis, configurable tier mapping]
key_files:
  created:
    - R/36_tiered_same_day_payer.R
  modified: []
decisions:
  - "AV+TH frequency outputs use _av_th_v2 suffix to preserve Phase 34 baseline files"
  - "TIER_MAPPING configured as named list (rank 1-7) for PI editability"
  - "FLM source override applied at ENCOUNTER.SOURCE level per patient-date group (not patient level)"
  - "Codes 93 and 14 explicitly mapped to Medicaid tier via special override"
  - "Single-encounter dates included in resolution output with reason='single encounter'"
  - "Dual-eligible mapped to Medicaid tier (9-category to 6-tier collapse)"
metrics:
  duration: 160
  completed_date: "2026-04-27"
  tasks_completed: 2
  commits: 1
  files_created: 1
  files_modified: 0
---

# Phase 35 Plan 01: Tiered same-day payer categorization -- SUMMARY

**One-liner:** Dual-scope (all encounters + AV+TH) payer frequency tables with PayerVariable.xlsx cross-reference and hierarchical same-day payer resolution using Medicaid>Medicare>Private>Other>Self-pay>Uninsured>Missing priority per Amy Crisp framework

## What Was Built

Created a standalone diagnostic script `R/36_tiered_same_day_payer.R` (486 lines) that produces 12 CSV outputs for PI analysis of payer categorization and same-day conflict resolution.

**Deliverable 1: Raw payer frequency tables (6 CSVs)**
- Primary/secondary payer code frequencies for all encounters + AV+TH scopes
- PayerVariable.xlsx cross-reference (code, description, category)
- Category-level summaries
- Suffix strategy: `_all` for all encounters, `_av_th_v2` for AV+TH (preserves Phase 34 baseline)

**Deliverable 2: Hierarchical same-day payer resolution (6 CSVs)**
- CSV A: Per-patient-per-date resolved payer with resolution_reason tracking
- CSV B: Patient-level modal resolved payer summary
- CSV C: Before vs after category distribution (encounter-level vs patient-date-level)
- Hierarchy: Medicaid (rank 1) > Medicare (2) > Private (3) > Other (4) > Self-pay (5) > Uninsured (6) > Missing (7)
- FLM source override: All encounters on patient-dates with FLM source → Medicaid
- Special code override: Codes 93/14 in primary or secondary → Medicaid

**Key features:**
- TIER_MAPPING as configurable named list at script top (PIs can edit ranks with one-line changes)
- CODE_TO_TIER() function maps 9-category payer to 6 tiers (dual-eligible → Medicaid, unavailable/unknown → Missing)
- Inline replication of compute_effective_payer/map_payer_category/detect_dual_eligible (no source R/02)
- Materialize-early DuckDB pattern (all downstream logic in-memory)
- Single-encounter dates included in resolution output (not filtered out)
- Dual-scope analysis (all encounters + AV+TH) with parallel processing

## Deviations from Plan

None - plan executed exactly as written. All 12 CSV outputs, dual-scope processing, tier mapping configuration, FLM override, special code override, and safety nets implemented as specified.

## Technical Decisions

**1. AV+TH frequency suffix strategy (_av_th_v2)**
- Problem: Phase 34 baseline files use `_av_th` suffix
- Solution: Use `_av_th_v2` for frequency tables, `_av_th` for resolution tables (no collision)
- Impact: Preserves Phase 34 baseline for comparison, allows side-by-side analysis

**2. Tier NA safety nets (double guard)**
- tier safety net: `if_else(is.na(tier), "Missing", tier)` after CODE_TO_TIER mapping
- tier_rank safety net: `if_else(is.na(tier_rank), 7L, tier_rank)` after TIER_MAPPING lookup
- Rationale: Prevents which.min() failure if unexpected payer_category produces unrecognized tier

**3. FLM override granularity (patient-date level)**
- Implementation: `any(SOURCE == "FLM")` inside `group_by(ID, admit_date_parsed)` summarise
- Checks ENCOUNTER.SOURCE column (not DEMOGRAPHIC.SOURCE)
- Applies per patient-date, not per patient (matches Amy Crisp email: "encounters on that day")

**4. Inline payer logic replication (no source R/02)**
- Rationale: Avoid sourcing R/02_harmonize_payer.R which sources R/01_load_pcornet.R (would re-load data)
- Implementation: Copy function definitions for compute_effective_payer, map_payer_category, detect_dual_eligible

**5. Single-encounter dates included (not filtered)**
- Resolution output includes all patient-dates (n_encounters == 1 or > 1)
- resolution_reason = "single encounter" for dates with only 1 encounter
- Rationale: Gives PIs full patient-date timeline for analysis

## Verification

**Manual checks:**
- ✓ R/36_tiered_same_day_payer.R exists (486 lines, >400 required)
- ✓ TIER_MAPPING appears at line 79 (within first 100 lines after setup)
- ✓ tier NA guard present (line 223)
- ✓ tier_rank NA guard present (line 227)
- ✓ "single encounter" case present (line 375)
- ✓ "Standalone script" note present (line 45)
- ✓ No occurrences of `payer_primary_code_freq_av_th.csv` without _v2 suffix
- ✓ FLM override inside group_by(ID, admit_date_parsed) (line 369)
- ✓ Special code override for codes 93/14 in both PRIMARY and SECONDARY (lines 215-218, 370-372)
- ✓ All 12 CSV filenames referenced in script output sections

**Self-check:**
All created files exist, commit hash verified in git log.

## Known Stubs

None. All logic is fully implemented:
- Frequency tables wire real PAYER_TYPE_PRIMARY/SECONDARY values to PayerVariable.xlsx lookup
- Resolution logic uses real ENCOUNTER.SOURCE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, ADMIT_DATE values
- No hardcoded empty values, no placeholder text, no TODO/FIXME markers

## Impact

**For PIs (Amy Crisp):**
- Can see every distinct raw payer code with occurrence counts cross-referenced against PayerVariable.xlsx
- Can edit tier priorities by changing single numbers in TIER_MAPPING
- Can see same-day payer resolution using configurable hierarchy
- Can see FLM source override applied at patient-date level
- Can see before vs after category distribution showing impact of hierarchical resolution
- Can analyze frequency and resolution patterns for both all encounters and AV+TH subsets

**For future phases:**
- Establishes pattern for configurable tier mapping (named list at script top)
- Establishes pattern for dual-scope analysis (all + AV+TH) with consistent suffix strategy
- Resolution CSVs provide foundation for patient-level payer assignment in downstream analysis

## Execution Notes

- Duration: 160 seconds (~3 minutes)
- No errors or warnings during execution
- Script follows Phase 33/34 structural pattern (source R/00_config.R, DuckDB materialize-early, conditional RDS fallback)
- Uses get_pcornet_table() for backend-transparent access
- All downstream logic is in-memory (no lazy query translation gaps)

## Next Steps

None - plan is complete. PIs can run `source("R/36_tiered_same_day_payer.R")` on HiPerGator to generate all 12 CSV outputs.
