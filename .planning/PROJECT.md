# PCORnet Payer Variable Investigation (R Pipeline)

## What This Is

A standalone R-based exploration pipeline that loads raw PCORnet CDM CSV files for a Hodgkin Lymphoma cohort (OneFlorida+), builds a filtered cohort using human-readable named predicates, and produces attrition waterfall and Sankey/alluvial visualizations stratified by payer type. Runs on RStudio on HiPerGator.

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

### Active

- [ ] Produce attrition waterfall chart from filter log (VIZ-01, carried from v1.0)
- [ ] Produce Sankey/alluvial stratified by payer (VIZ-02, carried from v1.0)
- [ ] Apply HIPAA small-cell suppression in outputs (VIZ-03, carried from v1.0)
- [ ] Encounter-level cancer category linkage replacing patient-level join
- [ ] HL flag on encounter, not patient
- [x] Death date analysis table — v1.8 Phase 62
- [x] Drop ICD diagnosis codes from SCT detection — v1.8 Phase 60
- [ ] First-line therapy regimen labeling (ABVD, BV+AVD, Nivo+AVD) for adults 21+
- [ ] New Gantt output files preserving existing versions

## Current Milestone: v1.8 Episode-Level Cancer Linkage & First-Line Therapy Identification

**Goal:** Link cancer diagnoses to specific treatment episodes via encounter IDs, identify first-line HL therapy regimens (ABVD, BV+AVD, Nivo+AVD), tighten treatment source validation, and produce death date analysis.

**Target features:**
- Replace patient-level cancer category with encounter-level linkage (encounter ID match, fallback to closest diagnosis in time)
- HL flag on the encounter, not the patient
- Second cancer confirmation with 7-day-apart rule
- Death date analysis table (count with death dates, death as last encounter, encounters after death)
- Drop ICD diagnosis codes from SCT detection — PROCEDURES, PRESCRIBING, DISPENSING only
- Label treatment episodes with specific regimen names (ABVD, BV+AVD, Nivo+AVD) using granular drug names
- First-line therapy for adults 21+: 28-day cycle matching for the 3 regimen combinations
- Agents can be dropped (ABVD→AVD) and still count as first-line; nothing else added
- New Gantt output files (preserve existing versions)

### Out of Scope

- Statistical modeling / regression — exploration only
- Payer x treatment initiation timing analysis — v2
- Payer x diagnosis timing analysis — v2
- RMarkdown / Shiny rendering — v1 produces raw R scripts and PNG figures
- Replicating Python pipeline's data cleaning — R pipeline applies its own filter chain
- Publication-ready figure formatting — exploratory quality is sufficient

## Previous Milestones

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
- 8-tier hierarchy with distinct "Other govt" tier (Medicaid > Medicare > Private > Other govt > Other > Self-pay > Uninsured > Missing) (Phase 37)

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

- **Current state**: 62 phases completed across 8 milestones (v1.0-v1.8), ~62 R scripts, DuckDB as default backend, AMC 8-category payer system, per-type treatment code resolved xlsx files, refined cancer summary (D-codes removed, HL cohort confirmed), Gantt CSVs with human-readable code descriptions, validated death dates, encounter IDs, and drug names, confirmed_hl_cohort.rds artifact for temporal filtering, death date validation with impossible death exclusion and HL Diagnosis pseudo-treatment rows in Gantt output, ENCOUNTERID propagation through treatment episodes, drug name resolution via RxNorm API (drug_name_lookup.rds), SCT detection tightened to procedure/prescription sources only, first-line therapy flagging infrastructure (is_first_line column in treatment_episodes.rds), death date data quality analysis (1,295 validated deaths, 253 with post-death activity)
- **Existing Python pipeline** at `C:\cygwin64\home\Owner\Data loading and cleaing\` — parallel exploration tool, not a replacement
- **Data source**: OneFlorida+ PCORnet CDM extract (Mailhot HL cohort, extracted 2025-09-15), 22 CSV tables on HiPerGator
- **Study**: UFPTI 2405-HLX17A — investigating insurance disparities in Hodgkin Lymphoma treatment
- **PCORnet CDM tables in scope**: 13 tables loaded via DuckDB (ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC, DISPENSING, MED_ADMIN, LAB_RESULT_CM, PROVIDER, TUMOR_REGISTRY1/2/3)
- **Partner sites**: AMS, UMI, FLM (claims-only), VRT (death-only), UFH
- **Payer analysis**: AMC 8-category payer mapping centralized in R/00_config.R, 8-tier hierarchical same-day resolution, dual-scope (all encounters + AV+TH) output

## Constraints

- **Runtime environment**: RStudio on UF HiPerGator — scripts must work in that environment
- **R packages**: tidyverse ecosystem (dplyr, ggplot2, stringr, lubridate), ggalluvial for Sankey, scales, janitor, glue
- **Data access**: Raw CSVs on HiPerGator filesystem — paths configured in `R/00_config.R`
- **HIPAA compliance**: All patient counts 1-10 must be suppressed in any output
- **Code style**: Filtering logic uses named predicate functions (`has_*`, `with_*`, `exclude_*`) — no opaque one-liners
- **Payer fidelity**: AMC 8-category payer mapping (centralized in R/00_config.R), with dual-eligible detection and hierarchical same-day resolution

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
| DuckDB as default backend with RDS fallback | DuckDB provides faster queries; USE_DUCKDB flag enables transparent switching | ✓ Phase 32 |
| Clone-and-filter for encounter type subsetting | Clone baseline script with ENC_TYPE filter + _suffix outputs preserves baseline while enabling focused analysis | ✓ Phase 33 |
| PayerVariable.xlsx for independent cross-reference | Provides independent view of raw code mapping separate from R pipeline's PAYER_MAPPING | ✓ Phase 34 |
| Amy Crisp hierarchical same-day payer resolution | Medicaid > Medicare > Private priority resolves same-day multi-payer encounters deterministically | ✓ Phase 35 |
| AMC 8-category centralized mapping in R/00_config.R | Single source of truth for payer categories, eliminates runtime xlsx dependency | ✓ Phase 36 |
| Other govt as distinct tier (rank 4) | Government programs (VA, TRICARE) distinguished from generic "Other" for payer analysis | ✓ Phase 37 |
| Encounter-level cancer linkage replaces patient-level | Episode-specific cancer categories are clinically meaningful; patient-level conflates unrelated diagnoses | — Pending |
| Drop ICD DX codes from SCT detection | Diagnosis codes indicate history/status, not procedure occurrence — PROCEDURES/PRESCRIBING/DISPENSING are authoritative | ✓ Phase 60 |
| New Gantt files instead of overwriting | Preserves existing v1.7 output for comparison | — Pending |

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
*Last updated: 2026-05-30 — Phase 62 complete (first-line therapy flagging, death date data quality analysis)*
