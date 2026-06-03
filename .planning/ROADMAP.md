# Roadmap: PCORnet Payer Variable Investigation (R Pipeline)

**Project:** PCORnet CDM Payer Analysis Pipeline (R)
**Created:** 2026-03-24

## Milestones

- **v1.0 MVP** — Phases 1-14 (shipped 2026-04-01)
- **v1.1 RDS Cache & Viz Polish** — Phases 15-17 (shipped 2026-04-03)
- **v1.2 Multi-Source Overlap** — Phases 18-23, 25 (shipped 2026-04-21; Phases 24/26/27/28 dropped)
- **v1.3 DuckDB Backend Migration** — Phases 29-32 (shipped 2026-04-23)
- **v1.4 AV+TH Subset Analysis** — Phase 33 (shipped 2026-04-27) — [archive](milestones/v1.4-ROADMAP.md)
- **v1.5 Payer Analysis Expansion** — Phases 34-37 (shipped 2026-05-01) — [archive](milestones/v1.5-ROADMAP.md)
- **v1.6 Treatment Code Validation & Cancer Site Analysis** — Phases 45-54 (shipped 2026-05-22) — [archive](milestones/v1.6-ROADMAP.md)
- **v1.7 Cancer Summary Refinement & Gantt Enhancements** — Phases 55-59 (shipped 2026-05-28) — [archive](milestones/v1.7-ROADMAP.md)
- **v1.8 Episode-Level Cancer Linkage & First-Line Therapy Identification** — Phases 60-63 (shipped 2026-06-01) — [archive](milestones/v1.8-ROADMAP.md)
- **v2.0 Codebase Cleanup & Documentation** — Phases 65-74 (shipped 2026-06-02) — [archive](milestones/v2.0-ROADMAP.md)
- **v2.1 Clinical Data Refinements & NLPHL Breakout** — Phases 75-80 (active) — see below

## Remaining Phases (Unassigned)

- [x] **Phase 38: Chemo Treatment Inventory by Source Table** (completed 2026-05-05)
- [x] **Phase 39: Investigate Unmatched Codes** (completed 2026-05-04)
- [x] **Phase 40: Investigate Unmatched NDC Codes** (completed 2026-05-05)
- [x] **Phase 41: Combine NDC and HCPCS Reports** (completed 2026-05-05)
- [x] **Phase 42: Treatment Codes Resolved XLSX (All Types)** (completed 2026-05-05)
- [x] **Phase 43: Establish Treatment Lengths for SCT, Chemo, and Radiation** (completed 2026-05-05)
- [x] **Phase 44: Treatment Episode Start/Stop Dates** (completed 2026-05-11)
- [x] **Phase 45: Tiered Encounter-Level Payer Assignment** (completed 2026-05-12)
- [x] **Phase 46: Tiered Date-Level Payer Assignment** (completed 2026-05-12)

## Progress

| Phase | Milestone | Status | Completed |
|-------|-----------|--------|-----------|
| 1-14 | v1.0 | Complete | 2026-04-01 |
| 15-17 | v1.1 | Complete | 2026-04-03 |
| 18-23, 25 | v1.2 | Complete | 2026-04-21 |
| 24, 26-28 | v1.2 (deferred) | Dropped | 2026-05-05 |
| 29-32 | v1.3 | Complete | 2026-04-23 |
| 33 | v1.4 | Complete | 2026-04-24 |
| 34-37 | v1.5 | Complete | 2026-05-01 |
| 38-44 | Unassigned | Complete | 2026-05-12 |
| 45-54 | v1.6 | Complete | 2026-05-22 |
| 55-59 | v1.7 | Complete | 2026-05-28 |
| 60-63 | v1.8 | Complete | 2026-06-01 |
| 64 | v1.8 | Complete | 2026-06-01 |
| 65-74 | v2.0 | Complete | 2026-06-02 |

## v2.1 Clinical Data Refinements & NLPHL Breakout (Active Milestone)

**Milestone Goal:** Refine cancer summary tables, break out NLPHL as a distinct category, investigate SCT code 0362, remove tumor registry treatment data, verify replaced-by codes, create new tables, and add cause of death and per-episode cancer categorization to outputs — maintaining v2.0 code quality standards throughout.

**Granularity:** Coarse
**Requirements Coverage:** 11/11 mapped (100%)

### Phases

- [x] **Phase 75: Configuration Extensions (NLPHL & Death Cause)** - Extend R/00_config.R with NLPHL classification and death cause mapping (completed 2026-06-02)
- [x] **Phase 76: Treatment Source Analysis & Removal** - Analyze tumor registry coverage and remove TR from treatment pipeline (completed 2026-06-03)
- [ ] **Phase 77: Cancer Classification Refinements** - Extend 7-day gap to all categories, implement NLPHL breakout, load drug groupings
- [ ] **Phase 78: Episode Enhancement & Death Integration** - Add triggering code descriptions, profile and integrate cause of death
- [ ] **Phase 79: Code Investigations & New Tables** - SCT 0362 investigation, replaced-by verification, generate new drug grouping tables
- [ ] **Phase 80: Smoke Test Updates** - Update comprehensive smoke test for all v2.1 changes

### Phase Details

#### Phase 75: Configuration Extensions (NLPHL & Death Cause)
**Goal**: Extend configuration layer with NLPHL classification logic and death cause mapping to support all downstream cancer and mortality features
**Depends on**: Phase 74
**Requirements**: CANCER-01, DEATH-01, DEATH-02, QUAL-01
**Success Criteria** (what must be TRUE):
  1. CANCER_SITE_MAP in R/00_config.R contains C810 = "NLPHL" and C81 = "Hodgkin Lymphoma (non-NLPHL)" with mutually exclusive logic
  2. ICD9_NLPHL_CODES list in R/00_config.R contains 201.4x series codes
  3. classify_codes() in R/utils/utils_cancer.R supports 4-char prefix matching (C810) before 3-char fallback (C81)
  4. DEATH_CAUSE_MAP in R/00_config.R contains ICD-10 cause categories (50+ entries covering major categories)
  5. Unit tests validate NLPHL mutual exclusivity: no patient classified as both NLPHL and classical HL
**Plans:** 2/2 plans complete
Plans:
- [x] 75-01-PLAN.md — Config constants (ICD9_NLPHL_CODES, CANCER_SITE_MAP NLPHL entries, DEATH_CAUSE_MAP) and classify_codes() update
- [x] 75-02-PLAN.md — Smoke test NLPHL mutual exclusivity and DEATH_CAUSE_MAP validation

#### Phase 76: Treatment Source Analysis & Removal
**Goal**: Analyze tumor registry coverage then remove TR treatment data from treatment episode pipeline to improve data source reliability
**Depends on**: Phase 75
**Requirements**: TREAT-01, QUAL-01
**Success Criteria** (what must be TRUE):
  1. Coverage analysis script produces source_coverage_analysis.csv showing episode counts by source combinations (TR-only, claims-only, both)
  2. Treatment episode pipeline (R/26-29) removes tumor registry as source, reducing from 7 to 6 sources
  3. Validation report documents episode count delta and confirms count reduction matches coverage analysis prediction
  4. Assertion added: if treatment episode count drops >20%, pipeline halts with explicit warning
  5. All modified scripts follow v2.0 standards (styler, lintr, checkmate, headers)
**Plans:** 2/2 plans complete
Plans:
- [x] 76-01-PLAN.md — Coverage analysis script (R/76_treatment_source_coverage.R) producing source_coverage_analysis.csv/xlsx
- [x] 76-02-PLAN.md — Remove TR source blocks from R/26 extraction functions, add episode count assertion, update smoke test

#### Phase 77: Cancer Classification Refinements
**Goal**: Extend 7-day gap requirement to all cancer categories, implement NLPHL breakout in classification logic, and centralize drug groupings
**Depends on**: Phase 76
**Requirements**: CANCER-01, CANCER-02, TREAT-02, QUAL-01
**Success Criteria** (what must be TRUE):
  1. Cancer summary table (R/49) applies 7-day unique day gap to ALL cancer categories, reaching total population = 6,347
  2. Output versioned as cancer_summary_table_pre_post_v2_7day.rds with comparison table showing v1 vs v2 deltas
  3. classify_codes() correctly routes C81.0 / 201.4x codes to NLPHL category, all other C81.x to classical HL
  4. DRUG_GROUPINGS in R/00_config.R contains mappings from all_codes_resolved_next_tables.xlsx with versioned xlsx snapshot in git
  5. Validation confirms no patient double-counted in NLPHL and classical HL categories
**Plans:** 2 plans
Plans:
- [ ] 77-01-PLAN.md — Centralize drug groupings from xlsx into DRUG_GROUPINGS named vector in R/00_config.R, copy versioned xlsx snapshot, add smoke test
- [ ] 77-02-PLAN.md — Extend R/49 with 7-day v2 filtered output, NLPHL diagnostic breakout, dual output strategy, population validation, smoke test

#### Phase 78: Episode Enhancement & Death Integration
**Goal**: Add triggering code descriptions to treatment episodes and integrate cause of death into outputs after quality profiling
**Depends on**: Phase 77
**Requirements**: CANCER-03, DEATH-01, DEATH-02, QUAL-01
**Success Criteria** (what must be TRUE):
  1. Cause of death quality report documents completeness (% with cause coded) stratified by payer and site
  2. Episode classification (R/28) includes triggering_code_description column using DRUG_GROUPINGS from R/00_config.R
  3. Gantt v2 output (R/52) includes cause_of_death column (14 to 15 columns) mapped via DEATH_CAUSE_MAP
  4. Missingness documented in output footnotes if cause of death >40% missing
  5. Per-episode cancer category and triggering code description populated for all episodes using drug groupings
**Plans**: TBD

#### Phase 79: Code Investigations & New Tables
**Goal**: Investigate SCT code 0362 data quality, verify replaced-by code mappings, and generate two new drug grouping summary tables
**Depends on**: Phase 78
**Requirements**: CODE-01, CODE-02, TREAT-03, QUAL-01
**Success Criteria** (what must be TRUE):
  1. R/92_investigate_sct_0362.R produces encounter-level summary distinguishing true transplants from coding errors
  2. R/93_verify_replaced_by_codes.R validates replaced-by mappings with cycle detection and flags replacement chains >3 steps
  3. R/76_new_tables_from_groupings.R generates xlsx with two tables matching all_codes_resolved_next_tables.xlsx Sheet1 templates:
     - Table 1: treatment-type-level summary (Chemo, Radiation, SCT, Immunotherapy rows) with columns: treatment type | cancer code(s) for the encounter | count of encounters
     - Table 2: drug-level summary (individual drugs/treatments per row) with columns: all drugs/treatments in an encounter | cancer code(s) for the encounter | count of encounters
  4. All new diagnostic scripts follow decade-based numbering convention and include documentation headers
  5. Verification cross-references replaced-by codes against SEER ICD-9 to ICD-10 conversion tables
**Plans**: TBD
**UI hint**: yes

#### Phase 80: Smoke Test Updates
**Goal**: Update comprehensive smoke test (R/88) to validate all v2.1 changes including NLPHL category, 7-day gap, Gantt schema, and new scripts
**Depends on**: Phase 79
**Requirements**: QUAL-01
**Success Criteria** (what must be TRUE):
  1. Smoke test (R/88) validates NLPHL category exists in CANCER_SITE_MAP and is mutually exclusive with classical HL
  2. Smoke test validates 7-day gap extension applied to all cancer categories
  3. Smoke test validates Gantt v2 15-column schema (cause_of_death added)
  4. Smoke test validates new scripts (R/76, R/92, R/93) exist with correct headers and dependencies
  5. All smoke test additions follow existing testthat patterns from Phase 74
**Plans**: TBD

### v2.1 Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 75. Configuration Extensions | 2/2 | Complete    | 2026-06-02 |
| 76. Treatment Source Analysis & Removal | 2/2 | Complete    | 2026-06-03 |
| 77. Cancer Classification Refinements | 0/2 | Planning complete | - |
| 78. Episode Enhancement & Death Integration | 0/? | Not started | - |
| 79. Code Investigations & New Tables | 0/? | Not started | - |
| 80. Visualization & Documentation | 0/? | Not started | - |

---
*Last updated: 2026-06-02 -- Phase 77 planned (2 plans, 2 waves)*
