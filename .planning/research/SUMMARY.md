# Project Research Summary

**Project:** v2.1 Clinical Data Refinements & NLPHL Breakout
**Domain:** PCORnet cancer registry cohort analysis — clinical data refinements
**Researched:** 2026-06-02
**Confidence:** HIGH

## Executive Summary

The v2.1 milestone adds 8 clinical data refinement features to the mature v2.0 PCORnet R pipeline without requiring any new package dependencies. Research confirms that the existing validated stack (tidyverse, openxlsx2, lubridate, stringr, DuckDB backend) is sufficient for all features. The most significant finding is that **zero new technologies are needed** — all capabilities map to existing validated patterns from the 74-phase v1.0-v2.0 baseline.

The recommended approach follows a 3-wave implementation: (1) configuration extensions for NLPHL breakout and cause of death categories, (2) core modifications to cancer summary logic, treatment sources, and episode classification, and (3) additive investigations and new table generation. This sequence minimizes integration risk by establishing foundational changes before building dependent features. The architecture provides well-defined integration points (R/00_config.R for classifications, R/26-29 for treatment episodes, R/49 for cancer summary, R/28 for episode-level cancer linkage), making modifications isolated and testable.

The key risks center on data classification correctness rather than technical integration: NLPHL breakout must use mutually exclusive logic to avoid double-counting patients in both NLPHL and classical HL categories; tumor registry removal requires pre-implementation coverage analysis to quantify impact; and 7-day gap extension must be applied with output versioning to maintain comparability with baseline. These are data quality and validation challenges, not stack or architecture limitations. With proper validation infrastructure (smoke tests, baseline comparisons, domain expert review), all risks are mitigatable using existing project patterns.

## Key Findings

### Recommended Stack

**NO NEW PACKAGES REQUIRED.** All v2.1 features use the existing validated stack from v2.0. The research thoroughly evaluated specialized packages (icd, readxl, narcan, icdpicr, comorbidity packages) and found them unnecessary or unsuitable.

**Core technologies:**
- **stringr + dplyr (tidyverse)**: ICD code pattern matching for NLPHL breakout (C81.0x / 201.4x simple prefix matching, no complex hierarchy traversal needed)
- **lubridate (tidyverse)**: 7-day gap calculation for cancer diagnosis temporal separation (extending existing validated logic from R/43)
- **openxlsx2 (v1.27)**: Reading xlsx templates AND writing formatted output tables (replaces need for separate readxl package, follows DRY consolidation from v2.0)
- **Base R + checkmate**: Code verification logic, input validation, data quality assertions
- **DuckDB backend (Phases 29-32)**: Table access via get_pcornet_table() for cause of death integration

**Key decision:** The icd package (ARCHIVED on CRAN since 2020-10-06) was evaluated for NLPHL classification but rejected because NLPHL codes are already in R/00_config.R (lines 173-174, 225-226) and simple string pattern matching is sufficient. This avoids adding unmaintained dependencies for functionality already achievable with validated tools.

**Integration risk:** ZERO — No new dependencies, no version updates needed, no compatibility concerns. All 8 features use patterns validated across 69 numbered scripts in v1.0-v2.0.

### Expected Features

**Must have (table stakes):**
- **Temporal separation for ALL cancer categories (7-day gap)** — SEER and IARC standards require clear temporal thresholds; currently only applied to HL, must extend to all categories to reach total population = 6,347
- **NLPHL separate classification** — C81.0 is biologically and clinically distinct from other Hodgkin Lymphomas with different treatment and better prognosis (5-year survival >90% vs 85-90%)
- **Treatment source validation (drop tumor registry)** — Tumor registry treatment data has known reliability issues (8-32% capture) vs EHR sources (95-100% accuracy); critical for research validity
- **Cause of death in outputs** — NAACCR standard field, vital for survival analysis and competing risks models; table stakes for cancer registries
- **Per-episode cancer categorization** — Treatment episodes must be linked to specific cancer diagnoses to avoid conflating unrelated treatments; already implemented at encounter level in Phase 61, extension to include triggering code descriptions is incremental

**Should have (competitive):**
- **SCT code 0362 investigation** — Data quality audit feature distinguishing true transplants from coding errors; adds research credibility
- **Drug grouping tables from resolved codes** — Enables regimen-agnostic treatment pattern analysis beyond pre-specified regimens (ABVD, BV+AVD, Nivo+AVD)
- **Per-episode triggering code descriptions** — Human-readable treatment rationale (e.g., "Doxorubicin 50mg IV" vs "J9000") improves clinical interpretability and stakeholder review

**Defer (v2.2+):**
- **Waterfall chart visualization (VIZ-01)** — Attrition logging infrastructure exists; visualization is separate effort
- **Payer-stratified Sankey (VIZ-02)** — Requires ggalluvial integration; separate visualization milestone
- **HIPAA suppression (VIZ-03)** — Apply when outputs move from exploratory to publication phase

### Architecture Approach

v2.1 integrates cleanly into the mature v2.0 architecture (69 numbered scripts, DuckDB backend, encounter-level cancer linkage, first-line regimen detection) through well-defined extension points. Most features are additive (new columns, new outputs) with one isolated breaking change (tumor registry removal affects 7 scripts via source filtering).

**Major components modified:**
1. **Configuration Layer (R/00_config.R)** — Extend CANCER_SITE_MAP to separate NLPHL (C81.0) from classical HL (C81.1-C81.9); add DEATH_CAUSE_MAP for ICD-10 cause of death categorization; add ICD9_NLPHL_CODES (201.4x series)
2. **Cancer Classification (R/utils/utils_cancer.R)** — Modify classify_codes() to support 4-char prefix matching (C810 for NLPHL) before 3-char fallback (C81 for HL), enabling mutually exclusive categorization
3. **Cancer Summary Logic (R/49_cancer_summary_pre_post.R)** — Generalize 7-day gap requirement from HL-only to all cancer categories; verify total population = 6,347; add per-category breakdown
4. **Treatment Episode Pipeline (R/26-R/29)** — Remove tumor registry as treatment source (7 sources → 6 sources); affects extract_chemo_dates_with_codes(), extract_radiation_dates_with_codes(), extract_sct_dates_with_codes()
5. **Episode Classification (R/28_episode_classification.R)** — Join drug groupings from all_codes_resolved_next_tables.xlsx to add triggering_code_description column; builds on existing encounter-level cancer linkage from Phase 61
6. **Gantt Outputs (R/52_gantt_v2_export.R)** — Join DEATH table to add cause_of_death column (14 → 15 columns); map DEATH_CAUSE via DEATH_CAUSE_MAP from config

**Build order rationale:** Configuration extensions establish NLPHL/cause mappings before core modifications use them. Core modifications to cancer summary, treatment sources, and episode classification must complete before investigations and new tables that depend on refined data. Wave 3 features are fully additive and can run in parallel.

### Critical Pitfalls

1. **NLPHL Breakout Double-Counting or Loss** — Breaking out NLPHL from parent Hodgkin Lymphoma creates counting errors if classification logic is additive (patients in both categories) rather than mutually exclusive. Create NLPHL category FIRST, then define HL as "C81.* EXCLUDING C81.0". Add validation: `nrow(nlphl) + nrow(hl_excluding_nlphl) == nrow(original_hl_cohort)`. Warning signs: HL cohort size changes unexpectedly, total cancer counts don't match sum of subcategories. Address in Phase 1 with unit tests.

2. **Tumor Registry Removal Silently Drops Treatment Episodes** — Dropping tumor registry treatment data causes massive undercounting without visible error. Tumor registry may be ONLY source for certain treatments (external facilities, bundled procedures). BEFORE dropping: quantify overlap via source_coverage_analysis showing episode counts by source combinations (TR-only, claims-only, both). Add assertion: if treatment episode count drops >20%, halt with explicit warning. Alternative: flag TR-sourced episodes as "lower_confidence" rather than dropping entirely. Address in Phase 2 (coverage analysis) before Phase 3 (conditional removal).

3. **7-Day Gap Applied Retrospectively Breaks Pre/Post Counts** — Extending 7-day gap to all cancers retrospectively invalidates existing baselines. Gap requirements improve specificity but decrease sensitivity, creating fundamentally different populations. Version output files (cancer_summary_table_pre_post_v1.rds vs. v2_7day.rds), create before/after comparison table, add pipeline metadata documenting which validation rules were applied, regenerate ENTIRE pipeline from cohort selection (not just cancer summary scripts). Address in Phase 4 with output versioning.

4. **External Classification File (XLSX) Creates Runtime Dependencies** — Reading all_codes_resolved_next_tables.xlsx at runtime creates fragile pipeline with hidden dependencies. If xlsx moves or updates, pipeline fails or produces non-reproducible results. Follow AMC_PAYER_LOOKUP pattern from Phase 36: centralize mappings in R/00_config.R as named lists. Create conversion script: read xlsx → generate R code → commit R code. Snapshot xlsx in version control with date stamp. Add checkmate assertions verifying expected columns/types. Address in Phase 7 with dependency management strategy.

5. **Cause of Death Integration Without Data Quality Validation** — Adding cause of death without validating data quality creates misleading mortality analyses. Cause of death may be missing (>40%), miscoded, inconsistent across sources, or temporally misaligned. Profile data quality FIRST: what % of deaths have cause coded? Cross-reference against existing death date validation from Phase 59 (1,295 validated deaths). Create missingness analysis stratified by payer. Document limitations in outputs. Consider external linkage (NDI, state vital statistics) or predictive models (literature shows 86% accuracy). Address in Phase 8 with data quality profiling.

## Implications for Roadmap

Based on research, suggested phase structure follows 3-wave implementation to minimize integration risk:

### Wave 1: Configuration & Utilities (Foundation)

#### Phase v2.1-01: NLPHL Configuration Extension
**Rationale:** NLPHL breakout requires mutually exclusive classification logic established BEFORE any data processing. Modifying R/00_config.R and R/utils/utils_cancer.R creates foundation for all downstream cancer category changes.
**Delivers:** CANCER_SITE_MAP with C810 = "NLPHL" and C81 = "Hodgkin Lymphoma (non-NLPHL)"; ICD9_NLPHL_CODES (201.4x series); classify_codes() supporting 4-char prefix matching
**Addresses:** NLPHL separate classification (table stakes feature); creates distinct category for biologically different subtype
**Avoids:** Double-counting pitfall by implementing 4-char match (C810) before 3-char fallback (C81), ensuring mutual exclusivity
**Research flag:** Standard pattern (no deeper research needed) — ICD code mapping well-documented, config extension follows existing CANCER_SITE_MAP pattern

#### Phase v2.1-02: Cause of Death Configuration
**Rationale:** DEATH_CAUSE_MAP in R/00_config.R enables downstream Gantt integration without adding runtime xlsx dependencies
**Delivers:** DEATH_CAUSE_MAP with ICD-10 cause categories (50+ entries covering major categories)
**Addresses:** Cause of death integration (table stakes for cancer registries)
**Avoids:** Runtime xlsx dependency pitfall by centralizing in config following AMC_PAYER_LOOKUP pattern from Phase 36
**Research flag:** Standard pattern — ICD-10 chapter structure well-documented, config centralization validated in Phase 36

### Wave 2: Core Modifications (Data Processing)

#### Phase v2.1-03: Treatment Source Coverage Analysis
**Rationale:** BEFORE removing tumor registry, quantify impact to avoid silent episode loss. Coverage analysis creates evidence base for informed decision.
**Delivers:** source_coverage_analysis.R showing episode counts by source combinations (TR-only, claims-only, both); overlap percentages; expected count reduction
**Addresses:** Treatment source validation (table stakes); prepares for tumor registry removal
**Avoids:** Silent treatment episode loss pitfall by quantifying TR-only episodes and establishing expected count reduction
**Research flag:** Needs light research — No standard pattern for coverage analysis in existing codebase, but straightforward dplyr group_by logic

#### Phase v2.1-04: Drop Tumor Registry Treatment Data (Conditional)
**Rationale:** Remove tumor registry sources from R/26 treatment episode pipeline ONLY IF coverage analysis shows <5% unique TR episodes, otherwise implement confidence flagging
**Delivers:** Treatment episodes from 6 sources (PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, ENCOUNTER DRG, DIAGNOSIS); validation report showing episode count delta
**Addresses:** Treatment source validation (critical for research validity per literature: TR captures 8-32% vs EHR 95-100%)
**Avoids:** Silent episode loss by implementing assertion: if count drops >20%, halt with explicit warning
**Dependencies:** Requires Phase v2.1-03 coverage analysis completion
**Research flag:** Standard pattern — Source filtering follows existing Phase 9 pattern, well-isolated change

#### Phase v2.1-05: Extend 7-Day Gap to All Cancer Categories
**Rationale:** Generalize existing validated HL 7-day logic (R/43) to all categories to reach total population = 6,347
**Delivers:** cancer_summary_table_pre_post_v2_7day.rds with per-category 7-day confirmation; validation confirming total = 6,347; comparison table showing v1 vs v2 deltas
**Addresses:** Temporal separation for all cancer categories (table stakes per SEER/IARC standards)
**Avoids:** Retrospective baseline breakage by versioning outputs (v1 vs v2_7day) and regenerating full pipeline from cohort selection
**Research flag:** Standard pattern — Extending existing R/43 logic, lubridate date arithmetic validated throughout pipeline

#### Phase v2.1-06: Load Drug Groupings from XLSX
**Rationale:** Centralize drug groupings in R/00_config.R following AMC_PAYER_LOOKUP pattern to avoid runtime dependencies
**Delivers:** Conversion script reading all_codes_resolved_next_tables.xlsx → generating DRUG_GROUPINGS named list in R/00_config.R; snapshot versioned xlsx in git with date stamp
**Addresses:** Prerequisite for per-episode triggering code descriptions and drug grouping tables
**Avoids:** Runtime xlsx dependency pitfall by generating R code from xlsx template, centralizing in config
**Research flag:** Standard pattern — Follows Phase 36 AMC_PAYER_LOOKUP centralization pattern, openxlsx2 reading validated in 11 scripts

#### Phase v2.1-07: Enhance Episode Classification with Triggering Code Descriptions
**Rationale:** Builds on existing Phase 61 encounter-level cancer linkage by adding human-readable drug descriptions from DRUG_GROUPINGS
**Delivers:** R/28 episode classification with triggering_code_description column (14 → 15 columns); validation confirming descriptions populated for common codes
**Addresses:** Per-episode cancer categorization with human-readable treatment rationale (competitive feature for stakeholder review)
**Avoids:** No major pitfall (additive change), but validates against drug grouping contradicting cancer categories
**Dependencies:** Requires Phase v2.1-06 drug groupings
**Research flag:** Standard pattern — Extends existing Phase 61/Phase 46 infrastructure, straightforward lookup join

#### Phase v2.1-08: Cause of Death Data Quality Profiling
**Rationale:** Profile cause of death completeness and quality BEFORE integration to detect missingness and source bias
**Delivers:** Cause of death quality report: % deaths with cause coded by payer/site; ICD-10 code distribution; temporal alignment validation
**Addresses:** Prerequisite for cause of death integration; guards against misleading mortality analyses
**Avoids:** Data quality pitfall by profiling missingness (literature suggests >40% is common), documenting limitations, deciding whether to proceed or defer pending external linkage
**Research flag:** Needs light research — Data profiling pattern exists (Phase 59 death dates), but cause-specific validation is new

#### Phase v2.1-09: Integrate Cause of Death in Gantt Outputs (Conditional)
**Rationale:** Add cause of death to R/52 Gantt v2 IF profiling shows <40% missingness, otherwise document deferral
**Delivers:** Gantt v2 with cause_of_death column (14 → 15 columns); DEATH_CAUSE mapped via DEATH_CAUSE_MAP; missingness documented in output footnotes
**Addresses:** Cause of death in outputs (NAACCR standard field, table stakes for survival analysis)
**Avoids:** Misleading analysis by documenting limitations and suppressing if missingness too high
**Dependencies:** Requires Phase v2.1-02 (DEATH_CAUSE_MAP) and Phase v2.1-08 (quality profiling)
**Research flag:** Standard pattern — DEATH table join follows existing death date integration from Phase 62

### Wave 3: Investigations & New Tables (Additive)

#### Phase v2.1-10: SCT Code 0362 Investigation
**Rationale:** Audit data quality by investigating whether 90 patients with code 0362 have other SCT codes during same encounters; non-blocking, additive feature
**Delivers:** R/92_investigate_sct_0362.R producing encounter-level summary CSV; findings report distinguishing true transplants from coding errors
**Addresses:** SCT code validation investigation (competitive feature for data quality credibility)
**Avoids:** Wrong granularity pitfall by defining scope explicitly (same ENCOUNTERID) and validating with manual chart review of 10 patients
**Research flag:** Needs light research — Encounter-level grouping pattern exists (Phase 61), but code 0362 is non-standard (not in CPT databases), requires internal documentation review

#### Phase v2.1-11: Verify Replaced-By Codes
**Rationale:** Validate "replaced by" mappings from all_codes_resolved_next_tables.xlsx to guard against circular references and mapping errors
**Delivers:** R/93_verify_replaced_by_codes.R producing verification CSV; graph cycle detection report; cross-reference against SEER ICD-9 to ICD-10 conversion tables
**Addresses:** ICD code replacement/deprecation tracking (table stakes data quality check)
**Avoids:** Circular mapping pitfall by using igraph::is_dag() to detect cycles and flagging replacement chains >3 steps
**Research flag:** Needs light research — Graph cycle detection requires igraph package (not currently in stack, but lightweight addition), pattern is new to codebase

#### Phase v2.1-12: Generate New Tables from Drug Groupings
**Rationale:** Create 2 new summary tables using drug groupings and template structure from all_codes_resolved_next_tables.xlsx; enables regimen-agnostic treatment pattern analysis
**Delivers:** R/76_new_tables_from_groupings.R producing multi-sheet xlsx with drug group frequency by payer and by cancer category
**Addresses:** Drug grouping tables (competitive feature for treatment pattern discovery)
**Avoids:** Runtime xlsx dependency by using DRUG_GROUPINGS from R/00_config.R (loaded in Phase v2.1-06)
**Dependencies:** Requires Phase v2.1-06 (drug groupings) and Phase v2.1-07 (episode classification)
**Research flag:** Standard pattern — Table generation follows existing R/29 styled xlsx output pattern, openxlsx2 formatting validated in Phase 62

### Wave 4: Quality Assurance

#### Phase v2.1-13: Update Smoke Tests
**Rationale:** Validate all new/modified scripts and update baseline expectations for breaking changes (7-day gap, NLPHL breakout, Gantt schema)
**Delivers:** R/88_smoke_test_comprehensive.R with tests for R/76, R/92, R/93; NLPHL category validation; Gantt v2 15-column schema validation
**Addresses:** v2.0 quality standards enforcement (competitive differentiator for maintainability)
**Avoids:** Stale baseline expectations by updating smoke test expectations with each breaking change and documenting expected deltas
**Research flag:** Standard pattern — Smoke test infrastructure exists (Phase 74), extension follows established pattern

#### Phase v2.1-14: Documentation and Reference Manual Updates
**Rationale:** Document all v2.1 changes in SCRIPT_INDEX.md, PROJECT.md, and R/89 reference manual
**Delivers:** Updated documentation reflecting NLPHL breakout, 7-day gap extension, tumor registry removal, new scripts
**Addresses:** Onboarding ease and long-term maintainability
**Avoids:** Undocumented breaking changes by explicitly noting v1 vs v2 differences
**Research flag:** Standard pattern — Documentation follows existing Phase 74 reference manual pattern

### Phase Ordering Rationale

- **Configuration first (Phases 01-02):** NLPHL and cause of death mappings must exist before data processing references them
- **Coverage analysis before removal (Phases 03-04):** Quantify tumor registry impact before dropping to avoid silent episode loss
- **7-day gap with versioning (Phase 05):** Extends existing logic but requires output versioning to maintain baseline comparability
- **Drug groupings centralized (Phase 06):** Avoids runtime xlsx dependencies for all downstream features (Phases 07, 12)
- **Episode enhancement builds on linkage (Phase 07):** Depends on Phase 61 encounter-level cancer linkage infrastructure and Phase 06 drug groupings
- **Cause of death profiled before integration (Phases 08-09):** Data quality check prevents integration of incomplete data
- **Investigations in parallel (Phases 10-12):** Non-blocking additive features can run concurrently after core modifications complete
- **Quality assurance last (Phases 13-14):** Validates entire wave of changes with updated expectations

### Research Flags

**Phases needing deeper research during planning:**
- **Phase v2.1-10 (SCT code investigation):** Code 0362 not in standard CPT databases; requires internal documentation or data dictionary review to understand provenance
- **Phase v2.1-11 (Replaced-by verification):** Graph cycle detection may require igraph package addition (lightweight but new dependency); validation pattern is new to codebase

**Phases with standard patterns (skip research-phase):**
- **Phase v2.1-01 (NLPHL config):** ICD code mapping follows existing CANCER_SITE_MAP pattern
- **Phase v2.1-02 (Cause of death config):** Centralization follows AMC_PAYER_LOOKUP pattern from Phase 36
- **Phase v2.1-04 (Drop tumor registry):** Source filtering follows Phase 9 pattern
- **Phase v2.1-05 (7-day gap):** Extends existing R/43 logic
- **Phase v2.1-06 (Drug groupings):** openxlsx2 reading validated in 11 scripts
- **Phase v2.1-07 (Episode enhancement):** Extends Phase 61/46 infrastructure
- **Phase v2.1-09 (Cause of death Gantt):** DEATH table join follows Phase 62 pattern
- **Phase v2.1-12 (New tables):** Styled xlsx output validated in Phase 62 (R/29)
- **Phase v2.1-13 (Smoke tests):** Extension of Phase 74 infrastructure
- **Phase v2.1-14 (Documentation):** Follows Phase 74 reference manual pattern

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| **Stack** | HIGH | All 8 features map to existing validated packages; no new dependencies needed. NLPHL codes already in R/00_config.R (lines 173-174, 225-226). icd package (ARCHIVED) evaluated and rejected. openxlsx2 read/write capabilities validated in 11 scripts. |
| **Features** | HIGH | Table stakes vs competitive features clearly distinguished based on SEER/IARC/NAACCR standards and tumor registry literature. 7-day gap, NLPHL breakout, cause of death, treatment source validation all have strong clinical justification. SCT investigation and drug groupings are value-add audits. |
| **Architecture** | HIGH | Integration points well-defined from existing codebase review. Configuration layer (R/00_config.R), classification utilities (R/utils/utils_cancer.R), treatment pipeline (R/26-29), cancer summary (R/49), episode classification (R/28), Gantt outputs (R/52) all identified with specific modification requirements. Wave structure minimizes risk. |
| **Pitfalls** | MEDIUM-HIGH | Top 5 critical pitfalls identified from literature (tumor registry reliability 8-32%, cause of death missingness >40%, ICD-9 to ICD-10 mapping complexity) and existing pipeline patterns (encounter-level linkage from Phase 61, DRY consolidation from Phase 73). Mitigation strategies specific and actionable. Some project-specific risks (0362 code provenance, xlsx schema) require validation during execution. |

**Overall confidence:** HIGH

### Gaps to Address

- **SCT code 0362 provenance:** Code "0362" not found in standard CPT databases (38204-38241 are standard SCT codes). Likely internal/proprietary code or data entry artifact. Requires project-specific code documentation or data dictionary review during Phase v2.1-10. If documentation unavailable, manual chart review of sample patients will resolve.

- **all_codes_resolved_next_tables.xlsx schema:** Drug grouping tables and template structure referenced but not verified. Will need to read xlsx during Phase v2.1-06 to confirm: (a) sheet names (Drug Groupings, Replaced By, Template), (b) column structure (code, code_type, drug_group, description), (c) template formatting requirements for 2 new tables. If schema differs from assumptions, adjust conversion logic accordingly.

- **Cause of death field name/format:** Vital status linkage provides death dates (Phase 59/62 validation: 1,295 deaths), but cause-of-death field name and coding system not verified. PCORnet CDM DEATH table may use DEATH_CAUSE (ICD-10), CAUSE_OF_DEATH (text), or external linkage required. Phase v2.1-08 profiling will identify available fields; if unavailable, document deferral pending external linkage (NDI, state vital statistics).

- **Drug grouping table purpose:** "2 new tables" referenced but specific research questions not documented. Likely drug group frequency by payer (addresses payer analysis objective) and drug group by cancer category (addresses treatment pattern objective), but confirm with domain expert during Phase v2.1-12 planning to ensure correct structure.

- **Total population = 6,347 validation:** Current cohort size referenced as validation target for 7-day gap extension (Phase v2.1-05). Confirm this is correct baseline by checking existing cancer_summary_table_pre_post.rds row count before implementing changes.

- **igraph package for graph cycle detection:** Phase v2.1-11 replaced-by code verification may require igraph package (not currently in renv.lock) for is_dag() function. igraph is lightweight CRAN package (1.6.0, stable) but represents new dependency. Alternative: implement custom cycle detection with base R (more complex). Decide during phase planning whether graph analysis justifies adding igraph.

## Sources

### Primary (HIGH confidence)

**Stack research:**
- CRAN official package pages: tidyverse 2.0.0, dplyr 1.2.0, stringr 1.5.1, lubridate 1.9.3, openxlsx2 1.27, checkmate 2.3.4 — all versions verified as current (published within 1-12 months of 2026-06-02)
- CRAN icd package status (https://cran.r-project.org/package=icd) — ARCHIVED 2020-10-06, not recommended for new dependencies
- openxlsx2 documentation (https://janmarvin.github.io/openxlsx2/) — read/write xlsx with formatting, validated in 11 existing scripts
- Project codebase: R/00_config.R (ICD_CODES with NLPHL codes lines 173-174, 225-226), R/26-29 treatment episode pipeline, R/43 7-day gap logic

**Features research:**
- PMC3651576: Tumor registry treatment capture 12-32% radiation, 8-29% chemo vs EHR 95-100% accuracy
- PMC11178108: EHR linkage adds only 5% surgery, 1% radiation, 7% chemo updates (registry incompleteness)
- PMC12303076: Real-time EHR extraction achieves 100% diagnosis accuracy, 95%+ treatment accuracy
- ICD-10-CM 2026 official codes: C81.0 = Nodular lymphocyte predominant Hodgkin lymphoma (NLPHL)
- ICD-9-CM: 201.4x = Lymphocytic-histiocytic predominance (NLPHL historical code)
- PMC4005906: Multiple primary cancer definitions (SEER 2-month, Warren/Gates 6-month, 60-day exclusion)
- PMC12798275: NAACCR standards for death reporting (cause of death table stakes)

**Architecture research:**
- Project internal documentation: R/00_config.R (CANCER_SITE_MAP 324 prefixes → 15 categories), R/utils/utils_cancer.R (classify_codes implementation), R/26_treatment_episodes.R (7 sources), R/28_episode_classification.R (Phase 61 encounter-level cancer linkage), R/49_cancer_summary_pre_post.R (7-day logic), R/52_gantt_v2_export.R (14-column schema)
- WHO ICD-O-3: Histology 9659 = Nodular lymphocyte predominant Hodgkin lymphoma (clinical validation)

**Pitfalls research:**
- PMC7512330: ICD code mapping validation (86% accuracy, 57% increased uncertainty Shannon entropy analysis)
- Academic JAMIA: Cause of death ML models 86% accuracy with multimodal data
- Wiley Health Services Research: EHR + external mortality database integration best practices
- SEER ICD-9 to ICD-10 conversion tables: Official 201.4 → {C81.0, C81.4} mapping (disambiguation required)
- LinkedIn data pipeline framework: Schema evolution and backward compatibility versioning strategies
- Project Phase 36: AMC_PAYER_LOOKUP centralization pattern for xlsx → R config conversion

### Secondary (MEDIUM confidence)

- PMC5519797: Multiple primary tumors temporal thresholds (2-month SEER, 6-month Warren/Gates documented but less authoritative than SEER official)
- PMC3879655: Cause of death accuracy validation in cancer registries (older study, 2013, but methodology relevant)
- PMC5898735: Treatment episode definition (≥45-day gap) documented but for cost analysis context, not clinical
- AAPC CPT codes: 38240, 38241, 38204-38208, 38230 standard SCT codes (community resource, not official AMA)
- ArXiv 2308.04478: Multi-sheet XLSX handling in R (technical resource for openxlsx2 patterns)

### Tertiary (LOW confidence, needs validation)

- libmaneducation.com: SCT code classification (educational resource, not authoritative coding reference)
- LinkedIn Blackcoffer: Centralized analytics platform lookup table management (general best practice, not domain-specific)
- thelinuxcode.com: dplyr 2026 common mistakes (community blog, practical tips but not research-backed)

---
*Research completed: 2026-06-02*
*Ready for roadmap: yes*
