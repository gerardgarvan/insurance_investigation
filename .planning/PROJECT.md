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
- [x] Broadened drug grouping output with cancer_linked flag and dual-output (all encounters + linked-only) — v3.1 Phase 101
- [x] SCT code 0362 investigation (overlap rate with standard SCT codes) — v2.1 Phase 79
- [x] Replaced-by code verification (pairwise + chain analysis) — v2.1 Phase 79
- [x] Drug grouping summary tables (sub-category + encounter treatment) — v2.1 Phases 79/81/82
- [x] Remove 5 false-positive SCT codes from treatment detection — v2.3 Phase 90
- [x] F/S/E/N treatment line labels per code in Gantt output — v2.3 Phase 91
- [x] Medication names (human-readable) in Gantt output — v2.3 Phase 91
- [x] Code Type column (RXNORM, CPT/HCPCS, ICD-10-CM) in Gantt output — v2.3 Phase 91
- [x] Source Table column (PRESCRIBING, PROCEDURES, DIAGNOSIS) in Gantt output — v2.3 Phase 91
- [x] SCT conditioning / immunotherapy cross-use flags in Gantt output — v2.3 Phase 91
- [x] Flag questionable immunotherapy codes (vitamin combos, CAR-T classification) — v2.3 Phase 93
- [x] Proton Therapy as distinct treatment category from Radiation (4 CPT codes split) — v2.3 Phase 94
- [x] data.table infrastructure with conversion helpers and 6 keyed lookup tables — v3.0 Phase 95
- [x] classify_payer_tier_dt() data.table variant with output parity — v3.0 Phase 96
- [x] R/60 same-day payer resolution migrated to data.table — v3.0 Phase 97
- [x] R/28 episode classification lookups replaced with keyed joins — v3.0 Phase 98
- [x] Gantt v1/v2 consolidation with dynamic schema verification — v3.0 Phase 99

### Active

#### v3.2 Meeting Gap Resolution Report

- [x] Radiation before HL diagnosis investigation — flag/quantify treatments occurring before first HL dx date — v3.2 Phase 104
- [x] HL+NHL code overlap validation report — focused analysis of ~4,000/8,000 dual-code patients — v3.2 Phase 105
- [x] "Ethna" immunotherapy code investigation — verify/correct classification — v3.2 Phase 105
- [x] Organ transplant code verification — cross-check line 11 inclusion — v3.2 Phase 105
- [x] SCT codes above line 22 verification — validate patient data and appropriateness — v3.2 Phase 105
- [x] Secondary malignancy table — 7-day gap criterion, population-based columns — v3.2 Phase 104
- [x] TABLE 1: Encounter ID → all cancer diagnosis codes (Tableau-ready) — v3.2 Phase 106
- [x] TABLE 2: Chemo drugs by class/category + cancer codes (Tableau-ready) — v3.2 Phase 106
- [ ] RMarkdown gap resolution report compiling all investigation findings
- [ ] Update meeting notes to mark resolved gaps and remove stale items

#### v3.0 Remaining

- [ ] Smoke test R/88 passes with all existing sections after v3.0 optimization (VALID-01)

### Out of Scope

- Statistical modeling / regression — exploration only
- Payer x treatment initiation timing analysis — v2
- Payer x diagnosis timing analysis — v2
- Replicating Python pipeline's data cleaning — R pipeline applies its own filter chain
- Publication-ready figure formatting — exploratory quality is sufficient
- PREFIX_MAP centralization to R/00_config.R — moved to Active for v2.0 (DRY-01)
- Stanford V / BEACOPP regimen identification — only 3 regimens (ABVD, BV+AVD, Nivo+AVD) cover ~95% of adult first-line
- Pediatric protocols (age <21) — adult protocols only for v1.x
- Multi-line therapy sequencing — requires episode boundary formalization first
- Insurance category consolidation (self-pay+uninsured, other govt+other merge) — superseded by AMC 8-category framework

## Current Milestone: v3.2 Meeting Gap Resolution Report

**Goal:** Create investigation scripts for all remaining meeting note gaps (G4, G5, G8, G10, G11, secondary malignancy, TABLE 1/2) and compile findings into an RMarkdown report for team presentation.

**Target features:**
- Radiation before HL diagnosis — flag and quantify treatments occurring before first HL dx date
- HL+NHL overlap validation — focused report on ~4,000/8,000 dual-code patient concern
- "Ethna" immunotherapy — verify/correct in code mappings
- Organ transplant code (line 11) — cross-check inclusion appropriateness
- SCT codes above line 22 — verify patient data
- Secondary malignancy table — 7-day gap criterion, population-based columns
- TABLE 1: Encounter ID → all cancer diagnosis codes (Tableau-ready)
- TABLE 2: Chemo drugs by class/category + associated cancer codes (Tableau-ready)
- RMarkdown report compiling all investigation findings with tables and summaries

## Current State

**Shipped:** v3.1 (2026-06-12). 106 phases completed across 16 milestones (v1.0-v3.2). Phase 106 complete — Tableau-ready xlsx tables (TABLE-1 encounter cancer codes, TABLE-2 chemo drugs by class). Phase 105 — code classification verification (Ethna/etanercept, organ transplant 0362, SCT diagnosis codes) and HL+NHL dual-code overlap validation. Phase 104 — pre-diagnosis treatment flagging and secondary malignancy table.

**Pipeline status:** 103 phases completed across 16 milestones (v1.0-v3.1). 99+ R scripts total (77 numbered in decade-based organization + 11 utils + 8 archived + validation/test scripts). DuckDB backend with dual-environment support (HiPerGator production + Windows local testing). data.table infrastructure with 6 keyed lookup tables, classify_payer_tier_dt() for hot-path payer classification. Treatment episodes with encounter-level cancer linkage, first-line regimen identification, unified ICD-9/ICD-10 cancer code handling, instance-level drug grouping tables, SCT conditioning temporal context flags, 5 treatment categories, consolidated Gantt export with dynamic schema verification, and comprehensive smoke test with 35+ validation sections.

## Previous Milestones

### v3.1 Meeting Gap Closure — Clinical Data Coverage (Shipped 2026-06-12)

**Goal:** Close analytical gaps identified in team meetings by quantifying unlinked treatments, analyzing single-agent co-administration patterns, producing death date cross-tabs, and improving cancer linkage rates via the CONDITION table.

**Shipped:**
- CONDITION table cancer linkage investigation as 3rd-tier supplement to DIAGNOSIS-based linkage (Phase 100)
- Broadened drug grouping output with cancer_linked flag and dual-output (all encounters + linked-only) (Phase 101)
- Single-agent co-administration analysis with +/-30 day temporal window and pattern summary (Phase 102)
- Death date cross-tab summary with cascading 4-row metrics and styled xlsx (Phase 103)

### v2.3 Gantt Data Enrichment (Shipped 2026-06-08)

**Goal:** Enrich Gantt export data with per-code treatment line labels, medication names, code metadata, and cross-use flags from all_codes_resolved2.xlsx, while fixing false-positive SCT codes.

**Shipped:**
- False-positive SCT code removal: 5 status/complication codes removed from DRUG_GROUPINGS, smoke test Section 15c validates absence (Phase 90)
- Reference data loader: R/utils/utils_xlsx_lookups.R parses all_codes_resolved2.xlsx, enriches R/28 with 5 metadata columns (medication_name, code_type, source_table, treatment_line, sct_cross_use_flag) (Phase 91)
- Gantt v2 schema extension: Episodes 16→22 columns, detail 14→20 columns with defensive fallbacks, backward-compatible v1 exports (Phase 92)
- Cross-use flag implementation: SCT conditioning temporal context (30-day window), immunotherapy confidence column for 11 questionable codes (8 vitamin, 3 CAR-T), smoke test Section 15f with 16 checks (Phase 93)

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

- **Current state**: 99 phases completed across 15 milestones (v1.0-v3.0), 99+ R scripts total, DuckDB backend with dual-environment support, data.table infrastructure (6 keyed lookup tables, classify_payer_tier_dt, R/60 and R/28 migrated), AMC 8-category payer system, unified ICD-9/ICD-10 cancer code handling via shared utils_cancer.R, instance-level drug grouping tables, episode/encounter grain-labeled xlsx outputs, xlsx metadata enrichment (5 columns from all_codes_resolved2.xlsx), SCT conditioning temporal context and immunotherapy confidence flags, consolidated Gantt export with dynamic schema verification (Phase 99), 20-patient test fixture suite with 11 clinical edge cases, end-to-end local test runner, comprehensive smoke test (R/88) with 35+ validation sections
- **Existing Python pipeline** at `C:\cygwin64\home\Owner\Data loading and cleaing\` — parallel exploration tool, not a replacement
- **Data source**: OneFlorida+ PCORnet CDM extract (Mailhot HL cohort, extracted 2025-09-15), 22 CSV tables on HiPerGator
- **Study**: UFPTI 2405-HLX17A — investigating insurance disparities in Hodgkin Lymphoma treatment
- **PCORnet CDM tables in scope**: 13 tables loaded via DuckDB (ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC, DISPENSING, MED_ADMIN, LAB_RESULT_CM, PROVIDER, TUMOR_REGISTRY1/2/3)
- **Partner sites**: AMS, UMI, FLM (claims-only), VRT (death-only), UFH
- **Payer analysis**: AMC 8-category payer mapping centralized in R/00_config.R, 8-tier hierarchical same-day resolution, dual-scope (all encounters + AV+TH) output

## Constraints

- **Runtime environment**: RStudio on UF HiPerGator (production) and local Windows (testing via IS_LOCAL flag)
- **R packages**: tidyverse ecosystem (dplyr, ggplot2, stringr, lubridate), data.table for performance-critical joins and aggregations, ggalluvial for Sankey, scales, janitor, glue
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
| Broadened output as primary, linked-only as _linked_only suffix | Broadened (all encounters) is the default; linked-only preserved for backward compatibility | ✓ Phase 101 |
| cancer_linked derived from encounter-level DX presence | !is.na(cancer_codes) at encounter level — self-contained within R/57, no R/28 dependency | ✓ Phase 101 |
| Adopt data.table for performance | Named vector lookups and dplyr group_by are bottlenecks at scale on ENCOUNTER table (millions of rows); data.table keyed joins are 10-50x faster | -- v3.0 |

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
*Last updated: 2026-06-15 — Phase 106 complete (Tableau-ready data tables for encounter cancer codes + chemo drugs by class)*
