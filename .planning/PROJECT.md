# PCORnet Payer Variable Investigation (R Pipeline)

## What This Is

A standalone R-based exploration pipeline that loads raw PCORnet CDM CSV files for a Hodgkin Lymphoma cohort (OneFlorida+), builds a filtered cohort using human-readable named predicates, extracts treatment episodes with encounter-level cancer linkage and regimen identification, and produces payer-stratified analyses. Runs on RStudio on HiPerGator (production) and locally on Windows (testing with synthetic fixtures).

## Core Value

A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## Requirements

### Validated

- [x] Load PCORnet CDM CSV tables from HiPerGator with correct data types — v1.0 Phase 1
- [x] Multi-format date parsing for PCORnet data — v1.0 Phase 1
- [x] Attrition logging infrastructure — v1.0 Phase 1
- [x] Harmonize payer variables into 9 categories matching Python pipeline — v1.0 Phase 2
- [x] Dual-eligible detection (Medicare+Medicaid) — v1.0 Phase 2
- [x] ICD code normalization and HL diagnosis matching (149 codes) — v1.0 Phase 2
- [x] Named predicate cohort filter chain (has_*, with_*, exclude_*) — v1.0 Phase 3
- [x] Automatic attrition logging at every filter step — v1.0 Phase 3
- [x] HL_SOURCE tracking (DIAGNOSIS, TR, Both) with Neither exclusion — v1.0 Phase 6
- [x] Treatment-anchored payer mode (+/-30 day window) — v1.0 Phase 8
- [x] Expanded treatment detection (7 source types) — v1.0 Phase 9
- [x] Surveillance modality + survivorship encounter detection — v1.0 Phase 10
- [x] Auto-generated variable documentation (.md + .docx) — v1.0 Phase 10
- [x] PPTX presentation with glossary, footnotes, encounter analysis — v1.0 Phases 11-12
- [x] RDS caching with FORCE_RELOAD and time-savings logging — v1.1 Phase 15
- [x] Cohort + output snapshots as .rds files — v1.1 Phase 16
- [x] 1900 sentinel date filtering + stacked histograms — v1.1 Phase 17
- [x] DuckDB ingest with atomic write and round-trip verification — v1.3 Phase 29
- [x] Backend abstraction layer (get_pcornet_table dispatcher) — v1.3 Phase 30
- [x] Cohort pipeline DuckDB migration with parity testing — v1.3 Phase 31
- [x] Diagnostic scripts DuckDB migration + speedup report — v1.3 Phase 32
- [x] AV+TH multi-source overlap detection (R/33) — v1.4 Phase 33
- [x] AV+TH overlap classification (Identical/Partial/Distinct, R/34) — v1.4 Phase 33
- [x] Payer code frequency analysis with xlsx cross-reference (R/35) — v1.5 Phase 34
- [x] Tiered same-day payer resolution with Amy Crisp hierarchy (R/36) — v1.5 Phase 35
- [x] AMC 8-category centralized payer mapping in R/00_config.R — v1.5 Phase 36
- [x] 8-tier resolution hierarchy with distinct Other govt tier — v1.5 Phase 37
- [x] Encounter-level cancer category linkage replacing patient-level join — v1.8 Phase 61
- [x] HL flag on encounter, not patient — v1.8 Phase 61
- [x] Drop ICD diagnosis codes from SCT detection — v1.8 Phase 60
- [x] First-line therapy regimen labeling (ABVD, BV+AVD, Nivo+AVD) for adults 21+ — v1.8 Phase 61/62
- [x] Death date analysis table — v1.8 Phase 62
- [x] New Gantt output files preserving existing versions — v1.8 Phase 63
- [x] Renumber all R scripts sequentially in logical execution order — v2.0 Phase 66
- [x] Update all cross-references (source() calls, comments, docs) to match new numbering — v2.0 Phase 66
- [x] Add section header comments and key-logic comments to every script — v2.0 Phase 69
- [x] Create full reference manual for the pipeline — v2.0 Phase 74
- [x] Auto-format all R scripts with styler tidyverse style — v2.0 Phase 70
- [x] Configure lintr with project .lintr file and fix violations — v2.0 Phases 70-71
- [x] Add input validation (checkmate assert_file_exists) before each script — v2.0 Phase 72
- [x] Add defensive checks (type/structure, row-count assertions) — v2.0 Phase 72
- [x] Create smoke test script to verify pipeline integrity — v2.0 Phases 66-74
- [x] Consolidate duplicated lookup tables to R/00_config.R — v2.0 Phase 73
- [x] Extract repeated code patterns into shared utility functions — v2.0 Phase 73
- [x] Fix cancer_summary_table_pre_post to require 7-day gap for ALL cancer categories — v2.1 Phase 77
- [x] Break out NLPHL (C81.0 / 201.4x) from Hodgkin Lymphoma as distinct cancer category — v2.1 Phase 75/77
- [x] Drop all treatment data sourced from tumor registry — v2.1 Phase 76
- [x] Include cause of death in outputs — v2.1 Phase 75/78
- [x] Cancer_category and triggering code description per episode — v2.1 Phase 78
- [x] Environment auto-detection (local Windows vs HiPerGator Linux) — v2.2 Phase 83
- [x] Hand-crafted test fixtures (20 patients, 11 edge cases, 15 CDM tables) — v2.2 Phase 84
- [x] DuckDB integration validation and end-to-end local test runner — v2.2 Phase 85
- [x] All new/modified scripts follow v2.0 quality standards — v2.2 Phase 86
- [x] Unified ICD-9/ICD-10 cancer code handling via shared utils_cancer.R — v2.2 Phase 87
- [x] Instance-level drug grouping tables with human-readable names (R/57) — v2.2 Phase 88
- [x] Episode vs encounter grain labeling for drug grouping outputs — v2.2 Phase 89
- [x] SCT code 0362 investigation (overlap rate with standard SCT codes) — v2.1 Phase 79
- [x] Replaced-by code verification (pairwise + chain analysis) — v2.1 Phase 79
- [x] Drug grouping summary tables (sub-category + encounter treatment) — v2.1 Phases 79/81/82

### Active

(None — all requirements validated through v2.2)

### Out of Scope

- Statistical modeling / regression — exploration only
- Payer x treatment initiation timing analysis — v2
- Payer x diagnosis timing analysis — v2
- RMarkdown / Shiny rendering — v1 produces raw R scripts and PNG figures
- Replicating Python pipeline's data cleaning — R pipeline applies its own filter chain
- Publication-ready figure formatting — exploratory quality is sufficient
- PREFIX_MAP centralization to R/00_config.R — moved to Active for v2.0 (DRY-01)
- Stanford V / BEACOPP regimen identification — only 3 regimens (ABVD, BV+AVD, Nivo+AVD) cover ~95% of adult first-line
- Pediatric protocols (age <21) — adult protocols only for v1.x
- Multi-line therapy sequencing — requires episode boundary formalization first

## Current State

**Shipped:** v2.2 (2026-06-05)

**Pipeline status:** 89 phases completed across 13 milestones (v1.0-v2.2). 98 R scripts total (77 numbered in decade-based organization + 10 utils + 8 archived + 3 test scripts). DuckDB backend with dual-environment support (HiPerGator production + Windows local testing). Treatment episodes with encounter-level cancer linkage, first-line regimen identification, unified ICD-9/ICD-10 cancer code handling, instance-level drug grouping tables with descriptive names, episode/encounter grain-labeled outputs, and comprehensive smoke test with 33 validation sections.

## Previous Milestones

### v2.2 Local Testing Infrastructure & Clinical Refinements (Shipped 2026-06-05)

**Goal:** Add environment auto-detection and local test fixtures, unify ICD-9/ICD-10 cancer code handling, create instance-level drug grouping tables, and label output grain.

**Shipped:**
- Environment auto-detection: IS_LOCAL flag via Sys.info() with R_TESTING_ENV env var override, conditional paths for data/cache/DuckDB (Phase 83)
- Test fixtures: FIXTURE_DESIGN.md mapping 20 patients to 11 clinical edge cases, 15 PCORnet CDM fixture CSVs (Phase 84)
- DuckDB integration validation and end-to-end test runner (tests/run_local_test.R) (Phase 85)
- Quality standards validation and milestone documentation (Phase 86)
- Unified ICD-9/ICD-10 cancer code handling via shared utils_cancer.R with is_cancer_code() and 4-tier classify_codes() cascade (Phase 87)
- Instance-level drug grouping tables (R/57) with human-readable sub-category and cancer site names (Phase 88)
- Episode vs encounter grain labeling: self-documenting filenames, grain-prefixed sheet names, backward-compatible old filenames (Phase 89)

### v2.1 Clinical Data Refinements & NLPHL Breakout (Shipped 2026-06-03)

**Goal:** Refine cancer summary tables, break out NLPHL as a distinct category, remove tumor registry treatment data, and add cause of death and per-episode cancer categorization to outputs.

**Shipped:**
- NLPHL breakout as distinct cancer category with 4-char prefix matching (Phase 75)
- Tumor registry treatment data removal with coverage analysis (Phase 76)
- 7-day gap filter for all cancer categories, drug groupings centralization (Phase 77)
- Episode enrichment with code descriptions + drug groups, cause of death integration (Phase 78)
- SCT 0362 investigation, replaced-by code verification, drug grouping summary tables (Phase 79)
- Comprehensive smoke test updates for all v2.1 changes (Phase 80)
- CODE_SUBCATEGORY_MAP, category column, NA filtering in drug grouping tables (Phase 81)
- Encounter-level dx code deduplication with orphan preservation (Phase 82)

### v2.0 Codebase Cleanup & Documentation (Shipped 2026-06-02)

**Goal:** Reorganize, harden, and document the entire R pipeline for maintainability and onboarding.

**Shipped:**
- Full renumbering of 69 scripts into decade-based scheme (Phases 65-68)
- Script documentation: headers, section headers, inline WHY comments (Phase 69)
- styler formatting + lintr configuration and cleanup (Phases 70-71)
- Checkmate assertions and input validation across all scripts (Phase 72)
- DRY consolidation: CANCER_SITE_MAP, TIER_MAPPING centralized, utility functions extracted (Phase 73)
- Comprehensive smoke test (R/88) and reference manual generator (R/89) (Phase 74)

### v1.8 Episode-Level Cancer Linkage & First-Line Therapy Identification (Shipped 2026-06-01)

**Goal:** Link cancer diagnoses to specific treatment episodes via encounter IDs, identify first-line HL therapy regimens, tighten treatment source validation, and produce death date analysis.

**Shipped:**
- ENCOUNTERID propagation through treatment episodes + drug name resolution via RxNorm API (Phase 60)
- Encounter-level cancer linkage replacing patient-level joins (Phase 61)
- First-line HL regimen detection (ABVD, BV+AVD, Nivo+AVD) with dropped-agent tolerance (Phase 61)
- First-line therapy flagging for adults 21+ + death date analysis tables (Phase 62)
- Gantt v2 CSV export with encounter-level cancer, regimen labels, first-line flags (Phase 63)

### v1.7 Cancer Summary Refinement & Gantt Enhancements (Shipped 2026-05-28)

**Goal:** Refine cancer summary table by removing benign D-codes and enforcing HL cohort confirmation, add temporal filtering relative to HL diagnosis, and enhance Gantt chart data with cancer category labels, HL flags, and death dates.

**Shipped:**
- Refined cancer summary with D-code removal and HL cohort confirmation (Phase 55)
- Temporal filtering relative to HL diagnosis date (Phase 56)
- Gantt chart enhancements: cancer categories, HL flags, death dates (Phase 57)
- Cancer summary table with pre/post HL counts (Phase 58)
- Death date validation with impossible death exclusion, HL Diagnosis pseudo-treatment rows (Phase 59)

### v1.6 Treatment Code Validation & Cancer Site Analysis (Shipped 2026-05-22)

**Goal:** Validate treatment code coverage, audit radiation CPT codes, add triggering codes to treatment episodes, and produce cancer site frequency and summary tables.

**Shipped:**
- Radiation CPT audit with imaging vs treatment classification (Phase 45)
- Treatment code cross-reference + triggering codes in episode output (Phase 46)
- Cancer site frequency table from CancerSiteCategories.xlsx (Phase 47)
- Gantt chart CSV export with human-readable code descriptions (Phases 48-49)
- Cancer site confirmation with 2-date and 7-day separation (Phases 50-51)
- All codes resolved xlsx regeneration (Phase 52)
- Cancer summary dataset and summary table (Phases 53-54)

### v1.5 Payer Analysis Expansion (Shipped 2026-05-01)

**Goal:** Payer code frequency analysis, hierarchical same-day payer resolution, AMC 8-category mapping, and 8-tier resolution hierarchy.

**Shipped:**
- R/35_payer_code_frequency_av_th.R — payer code frequency with xlsx cross-reference (Phase 34)
- R/36_tiered_same_day_payer.R — dual-scope frequency + hierarchical same-day payer resolution (Phase 35)
- AMC_PAYER_LOOKUP centralized in R/00_config.R, eliminating xlsx runtime dependency (Phase 36)
- 8-tier hierarchy with distinct "Other govt" tier (Phase 37)

### v1.4 AV+TH Subset Analysis (Shipped 2026-04-27)

**Goal:** AV+TH-restricted multi-source overlap detection and classification with preserved baseline outputs.

**Shipped:**
- R/33_multi_source_overlap_av_th.R — same-date and same-week detection for AV+TH encounters
- R/34_overlap_classification_av_th.R — Identical/Partial/Distinct classification with per-site recommendations
- ENC_TYPE subset analysis pattern (clone-and-filter with _av_th suffix)

### v1.3 DuckDB Backend Migration (Shipped 2026-04-23)

**Goal:** Migrate data access layer from RDS/CSV to DuckDB with dual-backend abstraction.

**Shipped:**
- Atomic DuckDB ingest (13 tables, PATID + ENCOUNTERID indexes) — Phase 29
- Backend abstraction layer (get_pcornet_table dispatcher with USE_DUCKDB flag) — Phase 30
- Cohort pipeline migration with full parity testing — Phase 31
- 5 diagnostic scripts migrated with speedup report and migration guide — Phase 32

### v1.2 Multi-Source Overlap Investigation (On Hold)

**Goal:** Determine whether multi-source same-date encounters represent duplicates or genuine encounters.

**Shipped:** Same-date/same-week detection (Phase 25), all-source missingness and all-site duplicate profiling (Phases 19-23).
**Deferred:** Phase 24, 26, 27, 28.

### v1.1 RDS Cache & Visualization Polish (Shipped 2026-04-03)

**Goal:** RDS caching, 1900 sentinel date filtering, post-treatment encounter analysis.

**Shipped:** RDS cache infrastructure, cohort snapshots, output-backing datasets, stacked histograms.

### v1.0 MVP (Shipped 2026-04-01)

**Goal:** Working cohort filter chain with payer-stratified visualizations.

**Shipped:** Foundation (Phases 1-4), data quality fixes (Phases 5-7), treatment-anchored payer (Phase 8), expanded treatment detection (Phase 9), surveillance/survivorship (Phase 10), PPTX presentations (Phases 11-14).

## Context

- **Current state**: 89 phases completed across 13 milestones (v1.0-v2.2), 98 R scripts total, DuckDB backend with dual-environment support, AMC 8-category payer system, unified ICD-9/ICD-10 cancer code handling via shared utils_cancer.R, instance-level drug grouping tables with descriptive names, episode/encounter grain-labeled xlsx outputs, 20-patient test fixture suite with 11 clinical edge cases, end-to-end local test runner, comprehensive smoke test (R/88) with 33 validation sections
- **Existing Python pipeline** at `C:\cygwin64\home\Owner\Data loading and cleaing\` — parallel exploration tool, not a replacement
- **Data source**: OneFlorida+ PCORnet CDM extract (Mailhot HL cohort, extracted 2025-09-15), 22 CSV tables on HiPerGator
- **Study**: UFPTI 2405-HLX17A — investigating insurance disparities in Hodgkin Lymphoma treatment
- **PCORnet CDM tables in scope**: 13 tables loaded via DuckDB (ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC, DISPENSING, MED_ADMIN, LAB_RESULT_CM, PROVIDER, TUMOR_REGISTRY1/2/3)
- **Partner sites**: AMS, UMI, FLM (claims-only), VRT (death-only), UFH
- **Payer analysis**: AMC 8-category payer mapping centralized in R/00_config.R, 8-tier hierarchical same-day resolution, dual-scope (all encounters + AV+TH) output

## Constraints

- **Runtime environment**: RStudio on UF HiPerGator (production) and local Windows (testing via IS_LOCAL flag)
- **R packages**: tidyverse ecosystem (dplyr, ggplot2, stringr, lubridate), ggalluvial for Sankey, scales, janitor, glue
- **Data access**: Raw CSVs on HiPerGator filesystem — paths configured in `R/00_config.R`
- **HIPAA compliance**: All patient counts 1-10 must be suppressed in any output
- **Code style**: Filtering logic uses named predicate functions (`has_*`, `with_*`, `exclude_*`) — no opaque one-liners
- **Payer fidelity**: AMC 8-category payer mapping (centralized in R/00_config.R), with dual-eligible detection and hierarchical same-day resolution

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Standalone R (not consuming Python output) | Enables independent exploration without Python pipeline dependency | ✓ Good |
| Replicate exact payer logic from Python pipeline | Ensures results are comparable across both pipelines | ✓ Phase 2 |
| Named predicate functions for filtering | Readability — code should read like a clinical protocol | ✓ Phase 3 |
| Treatment flag detection from multiple sources | TUMOR_REGISTRY dates (primary) + PROCEDURES/PRESCRIBING codes (supplemental) for maximum coverage | ✓ Phase 3 |
| Primary site strategy for multi-site patients | Inner join on SOURCE to keep enrollment from patient's primary site | ✓ Phase 3 |
| Treatment-anchored payer mode via +/-30 day window | Reuses Section 4c mode pattern from payer harmonization, anchors on PX_DATE per treatment type | ✓ Phase 8 |
| Expanded treatment detection across all docx-specified sources | Maximizes sensitivity by querying DISPENSING, MED_ADMIN, DIAGNOSIS, ENCOUNTER DRG, and PROCEDURES revenue codes | ✓ Phase 9 |
| `.rds` over `.RData` for caching | `readRDS()` returns a single named object directly into an assignment — no namespace side-effects | ✓ Phase 15/16 |
| Cache at `/blue/erin.mobley-hl.bcu/clean/rds/` | Keeps large binary files on blue storage, outside repo root, gitignored | ✓ Phase 15/16 |
| Cohort + output snapshots via `save_output_data()` helper | Consistent path construction, logging, and RDS serialization for all 21 snapshot files | ✓ Phase 16 |
| DuckDB as default backend with RDS fallback | DuckDB provides faster queries; USE_DUCKDB flag enables transparent switching | ✓ Phase 32 |
| Clone-and-filter for encounter type subsetting | Clone baseline script with ENC_TYPE filter + _suffix outputs preserves baseline while enabling focused analysis | ✓ Phase 33 |
| PayerVariable.xlsx for independent cross-reference | Provides independent view of raw code mapping separate from R pipeline's PAYER_MAPPING | ✓ Phase 34 |
| Amy Crisp hierarchical same-day payer resolution | Medicaid > Medicare > Private priority resolves same-day multi-payer encounters deterministically | ✓ Phase 35 |
| AMC 8-category centralized mapping in R/00_config.R | Single source of truth for payer categories, eliminates runtime xlsx dependency | ✓ Phase 36 |
| Other govt as distinct tier (rank 4) | Government programs (VA, TRICARE) distinguished from generic "Other" for payer analysis | ✓ Phase 37 |
| Encounter-level cancer linkage replaces patient-level | Episode-specific cancer categories are clinically meaningful; patient-level conflates unrelated diagnoses | ✓ Phase 61 |
| Drop ICD DX codes from SCT detection | Diagnosis codes indicate history/status, not procedure occurrence — PROCEDURES/PRESCRIBING/DISPENSING are authoritative | ✓ Phase 60 |
| New Gantt files instead of overwriting | Preserves existing v1.7 output for comparison | ✓ Phase 63 |
| Drug name resolution for chemotherapy only | Other treatment types identified adequately by code; chemotherapy requires specific drug names for regimen matching | ✓ Phase 60 |
| Regimen detection via 28-day cycle composition | ABVD/BV+AVD/Nivo+AVD have distinct drug fingerprints; dropped-agent tolerance handles real-world practice variation | ✓ Phase 61 |
| First-line therapy: 60-day clean period | Standard oncology definition; no prior chemotherapy in 60 days before regimen start | ✓ Phase 62 |
| Gantt v2 as superset of v1 schema | All 14 v1 columns preserved plus 3 new columns; downstream tools can consume either version | ✓ Phase 63 |
| ICD-9 + ICD-10 unified cancer code detection | Map-based is_cancer_code() from shared utility ensures gap-free coverage; classify_codes() 4-tier cascade (ICD-10 4/3-char → ICD-9 4/3-char) | ✓ Phase 87 |
| ICD-9 201.x in HL cohort confirmation | Cross-system category-level confirmation allowed (1x 201.x + 1x C81 with 7-day gap); code-level summaries keep systems separate | ✓ Phase 87 |
| IS_LOCAL via OS detection with env var override | Windows-only local dev in project; env var enables Linux VM testing without OS misdetection | ✓ Phase 83 |
| tempdir() for all local cache paths | Avoids gitignore conflicts, R session cleanup automatically removes cache | ✓ Phase 83 |
| Hand-crafted 20-patient fixtures over synthetic generator | Targeted edge case coverage (11 cases) beats statistical realism for logic testing | ✓ Phase 84 |
| Fully-qualified DBI::/dplyr:: calls in R/88 Sections 32-33 | Avoids namespace pollution; smoke test only loads glue at top | ✓ Phase 85 |
| Instance-level tables with descriptive names (R/57) | Patient-traceable rows with human-readable names enable clinical review | ✓ Phase 88 |
| Dual wb$save() for backward compatibility | Old filenames preserved alongside new grain-labeled filenames | ✓ Phase 89 |

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
*Last updated: 2026-06-07 after stale Active items cleanup*
