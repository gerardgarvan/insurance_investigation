# PCORnet Payer Variable Investigation (R Pipeline)

## What This Is

A standalone R-based exploration pipeline that loads raw PCORnet CDM CSV files for a Hodgkin Lymphoma cohort (OneFlorida+), builds a filtered cohort using human-readable named predicates, and produces attrition waterfall and Sankey/alluvial visualizations stratified by payer type. Runs on RStudio on HiPerGator.

## Core Value

A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## Requirements

### Validated

- [x] Load PCORnet CDM CSV tables from HiPerGator with correct data types — Validated in Phase 1: Foundation Data Loading (9 primary tables with explicit col_types)
- [x] Multi-format date parsing for PCORnet data — Validated in Phase 1: 4-format fallback chain (ISO, Excel serial, SAS DATE9, compact)
- [x] Attrition logging infrastructure — Validated in Phase 1: init_attrition_log() + log_attrition() for patient-level counts
- [x] Harmonize payer variables into 9 categories matching the Python pipeline — Validated in Phase 2: Payer Harmonization (map_payer_category with prefix-based case_when)
- [x] Implement dual-eligible detection (Medicare+Medicaid combinations) — Validated in Phase 2: encounter-level cross-payer detection + codes {14, 141, 142}
- [x] ICD code normalization and HL diagnosis matching — Validated in Phase 2: utils_icd.R with 149 codes (77 ICD-10 + 72 ICD-9)
- [x] Build cohort filter chain using named predicates (has_*, with_*, exclude_*) — Validated in Phase 3: Cohort Building (has_hodgkin_diagnosis, with_enrollment_period, exclude_missing_payer)
- [x] Log N patients before and after every filter step automatically — Validated in Phase 3: attrition_log data frame with step_name, n_before, n_after, n_excluded
- [x] Identify HL patients using 149 ICD codes (77 ICD-10 C81.xx, 72 ICD-9 201.xx) — Validated in Phase 3: has_hodgkin_diagnosis() via is_hl_diagnosis() with dotted/undotted normalization
- [x] Handle multi-site data (OneFlorida+ partner institutions: AMS, UMI, FLM, VRT) — Validated in Phase 3: primary site strategy via inner_join on SOURCE

- [x] Track HL identification source (DIAGNOSIS, TR, Both) per patient — Validated in Phase 6: HL_SOURCE column in has_hodgkin_diagnosis() with Neither exclusion
- [x] Add numeric range validation for age, tumor size, and date fields — Validated in Phase 6: _VALID suffix columns in load_pcornet_table()
- [x] Document R vs Python payer mapping comparison — Validated in Phase 6: comparison table in 00_config.R
- [x] Full pipeline end-to-end verification with data quality summary — Validated in Phase 6: 08_data_quality_summary.R with 13-category resolution tracker

### Active (carried from v1.0)

- [ ] Produce attrition waterfall chart from filter log
- [ ] Produce Sankey/alluvial showing enrollment → diagnosis date → treatment type, stratified by payer
- [ ] Apply HIPAA small-cell suppression (counts 1-10) in outputs

## Current Milestone: v1.1 RDS Cache & Visualization Polish

**Goal:** Eliminate redundant CSV parsing with persistent RDS caching, fix remaining 1900 sentinel date display issues, and add post-treatment encounter analysis with stacked histograms.

**Target features:**
- RDS caching for all PCORnet tables with cache-check, FORCE_RELOAD flag, and time-savings logging
- ~~Cohort snapshot `.rds` files at each filter step and final cohort~~ — Validated in Phase 16
- ~~Output-backing datasets: every figure/table gets its source data frame saved as `.rds`~~ — Validated in Phase 16
- ~~Shared `save_output_data()` helper utility~~ — Validated in Phase 16
- 1900 sentinel date filtering across all PPTX content
- Post-treatment summary table (unique encounter dates per person by payer, after last treatment)
- Stacked encounter histograms with post-treatment shading (post-treatment on bottom)

### Validated (Phase 8)

- [x] Treatment-anchored payer mode (PAYER_AT_CHEMO, PAYER_AT_RADIATION, PAYER_AT_SCT) computed within +/-30 day window of first treatment date — Validated in Phase 8

### Validated (Phase 9)

- [x] Expanded treatment detection to DISPENSING/MED_ADMIN (RXNORM_CUI), DIAGNOSIS (Z/V codes), ENCOUNTER (DRG), PROCEDURES (revenue codes) — Validated in Phase 9
- [x] Multi-source treatment date extraction for payer anchoring (7 sources chemo, 4 radiation/SCT) — Validated in Phase 9
- [x] Aggregate per-source treatment contribution logging — Validated in Phase 9

### Out of Scope

- Statistical modeling / regression — exploration only for v1
- Payer × treatment initiation timing analysis — v2
- Payer × diagnosis timing analysis — v2
- Missing data audit by site and year — v2
- RMarkdown / Shiny rendering — v1 produces raw R scripts and PNG figures
- Replicating the Python pipeline's data cleaning (deduplication, consistency flags) — R pipeline loads raw CSVs and applies its own filter chain
- Publication-ready figure formatting — exploratory quality is fine

## Context

- **Existing Python pipeline** at `C:\cygwin64\home\Owner\Data loading and cleaing\` handles production-grade data loading, cleaning, and payer analysis using Python/Polars. This R project is a parallel exploration tool, not a replacement.
- **Data source**: OneFlorida+ PCORnet CDM extract (Mailhot HL cohort, extracted 2025-09-15), 22 CSV tables on HiPerGator
- **Study**: UFPTI 2405-HLX17A — investigating insurance disparities in Hodgkin Lymphoma treatment
- **PCORnet CDM tables in scope**: ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC, DISPENSING, MED_ADMIN (primary — 11 tables), plus TUMOR_REGISTRY1/2/3 and reference to DEATH, HARVEST for metadata
- **Payer logic reference**: `docs/PAYER_VARIABLES_AND_CATEGORIES.md` in the Python pipeline defines the exact 9-category mapping and dual-eligible rules to replicate
- **ICD codes**: 149 HL diagnosis codes — ICD-10 C81.00–C81.9A (77 codes) and ICD-9 201.00–201.98 (72 codes), format-adaptive (dotted and undotted)
- **Partner provenance**: Some partners are claims-only (FLM), some have mapped ICD codes (AMS, UMI), one is death-only (VRT)

## Constraints

- **Runtime environment**: RStudio on UF HiPerGator — scripts must work in that environment
- **R packages**: tidyverse ecosystem (dplyr, ggplot2, stringr, lubridate), ggalluvial for Sankey, scales, janitor, glue
- **Data access**: Raw CSVs on HiPerGator filesystem — paths configured in `R/00_config.R`
- **HIPAA compliance**: All patient counts 1-10 must be suppressed in any output
- **Code style**: Filtering logic uses named predicate functions (`has_*`, `with_*`, `exclude_*`) — no opaque one-liners
- **Payer fidelity**: Must match the Python pipeline's 9-category payer mapping exactly, including dual-eligible detection

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Standalone R (not consuming Python output) | Enables independent exploration without Python pipeline dependency | — Pending |
| Replicate exact payer logic from Python pipeline | Ensures results are comparable across both pipelines | ✓ Phase 2 |
| Cohort + viz only for v1 | Focus on getting the filter chain and visualizations working before adding analysis tables | — Pending |
| Named predicate functions for filtering | Readability — code should read like a clinical protocol | ✓ Phase 3 |
| Treatment flag detection from multiple sources | TUMOR_REGISTRY dates (primary) + PROCEDURES/PRESCRIBING codes (supplemental) for maximum coverage | ✓ Phase 3 |
| Primary site strategy for multi-site patients | Inner join on SOURCE to keep enrollment from patient's primary site | ✓ Phase 3 |
| Treatment-anchored payer mode via +/-30 day window | Reuses Section 4c mode pattern from payer harmonization, anchors on PX_DATE per treatment type | ✓ Phase 8 |
| Expanded treatment detection across all docx-specified sources | Maximizes sensitivity by querying DISPENSING, MED_ADMIN, DIAGNOSIS, ENCOUNTER DRG, and PROCEDURES revenue codes | ✓ Phase 9 |
| `.rds` over `.RData` for caching | `readRDS()` returns a single named object directly into an assignment — no namespace side-effects | ✓ Phase 15/16 |
| Cache at `/blue/erin.mobley-hl.bcu/clean/rds/` | Keeps large binary files on blue storage, outside repo root, gitignored | ✓ Phase 15/16 |
| Cohort + output snapshots via `save_output_data()` helper | Consistent path construction, logging, and RDS serialization for all 21 snapshot files | ✓ Phase 16 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-03 after Phase 16 (Dataset Snapshots) completion*
