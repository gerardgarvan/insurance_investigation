# Roadmap: PCORnet Payer Variable Investigation (R Pipeline)

**Project:** PCORnet CDM Payer Analysis Pipeline (R)
**Created:** 2026-03-24
**Granularity:** Coarse (4 phases)
**Coverage:** 21/21 v1 requirements mapped

## Phases

- [x] **Phase 1: Foundation & Data Loading** - Configure paths, load 22 PCORnet CSV tables with correct data types, build utilities
- [x] **Phase 2: Payer Harmonization** - Implement 9-category payer mapping with encounter-level dual-eligible detection
- [x] **Phase 3: Cohort Building** - Build HL cohort using named filter predicates with attrition logging
- [x] **Phase 4: Visualization** - Produce attrition waterfall and payer-stratified Sankey diagrams with HIPAA suppression (completed 2026-03-25)
- [x] **Phase 11: PPTX Clarity & Missing Data Consolidation** - Eliminate ambiguous labels, collapse Unknown/Other/Unavailable into "Missing", add encounter analysis slides (completed 2026-03-31)
- [x] **Phase 12: More PPTX Polishing** - Add glossary slide, per-slide footnotes, fix graph issues, add summary stats slide (completed 2026-04-01)
- [x] **Phase 13: Summary Tables Value Audit** - Comprehensive frequency/summary tables for every column across all 13 PCORnet CDM tables (completed 2026-04-01)
- [x] **Phase 14: CSV Values Data Audit & Code Optimization** - Review value_audit CSVs for coding inconsistencies, optimize R pipeline code (completed 2026-04-01)
- [x] **Phase 15: RDS Caching Infrastructure** - Add persistent RDS cache for all PCORnet tables with cache-check logic and time-savings logging (completed 2026-04-03)
- [x] **Phase 16: Dataset Snapshots** - Save cohort snapshots, final outputs, and figure/table backing data as RDS files (completed 2026-04-03)
- [x] **Phase 17: Visualization Polish** - Filter 1900 sentinel dates, add post-treatment encounter analysis, stacked histograms (completed 2026-04-03)
- [x] **Phase 18: One Enrolled Person Does Not Have an HL Diagnosis Caught** - Investigate and fix single patient classified as "Neither" despite having lymphoma codes (completed 2026-04-07)
- [x] **Phase 19: Investigate Insurance Missingness Source UF Specifically** - Standalone diagnostic script profiling UFH payer data missingness by year, encounter type, and raw vs harmonized comparison (completed 2026-04-09)
- [x] **Phase 20: Check Duplicate Dates of FLM Subjects** - Standalone diagnostic script investigating FLM encounter date duplication across data sources with payer completeness comparison (completed 2026-04-09)
- [x] **Phase 21: Generalize Phase 19 to All Sources** - Standalone diagnostic script profiling payer data missingness across all 5 partner sites with cross-site comparison (completed 2026-04-13)
- [x] **Phase 22: Generalize Phase 20 to All Sites** - Standalone diagnostic script extending FLM duplicate date investigation to all 5 partner sites with cross-site comparison and per-site source recommendations (completed 2026-04-14)
- [x] **Phase 23: Make Visual Presentation of Tables from Last 2 Pages** - Convert Phase 21/22 CSV outputs into PPTX slides with formatted tables and bar chart visualizations (completed 2026-04-14)
- [ ] **Phase 24: Make Presentation of Just Phases 19 and 20** - Build a focused PPTX containing only UF missingness (Phase 19) and FLM duplicate-date (Phase 20) outputs
- [x] **Phase 25: Multi-Source Overlap Detection** - Detect same-date and same-week multi-source encounter pairs across all 5 sites, with per-site counts and source combination frequencies (completed 2026-04-21)
- [ ] **Phase 26: Overlap Classification and Recommendations** - Classify multi-source encounter groups as Identical/Partial/Distinct via field comparison and produce CSV outputs, console summary, and per-site actionable recommendations
- [x] **Phase 29: DuckDB Ingest Infrastructure** - Ingest 13 PCORnet tables from RDS cache into indexed DuckDB file with atomic write and round-trip verification (completed 2026-04-23)
- [ ] **Phase 30: Query Backend Abstraction Layer** - Create dual-backend dispatcher with USE_DUCKDB flag and smoke test predicates on both backends
- [ ] **Phase 31: Cohort Pipeline DuckDB Migration** - Migrate cohort build to DuckDB with full parity testing and benchmark comparison
- [ ] **Phase 32: Diagnostic Scripts DuckDB Migration & Benchmarks** - Migrate 5 diagnostic scripts, generate speedup report and migration guide, flip default to DuckDB

## Phase Details

### Phase 1: Foundation & Data Loading
**Goal**: User can load raw PCORnet CDM data with correct data types and configure analysis parameters

**Depends on**: Nothing (first phase)

**Requirements**: LOAD-01, LOAD-02, LOAD-03

**Success Criteria** (what must be TRUE):
1. User can load 22 PCORnet CSV tables (ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC + 16 others) into R with explicit column type specifications
2. User can parse dates in mixed SAS formats (DATE9, DATETIME, YYYYMMDD, Excel serial) with < 5% NA rate
3. User can configure file paths, ICD code lists (149 HL codes: 77 ICD-10 C81.xx + 72 ICD-9 201.xx), and payer mapping rules via `00_config.R`
4. User can access utility functions for attrition logging (`init_attrition_log()`, `log_attrition()`) and HIPAA suppression (primary + secondary suppression)

**Plans:** 2 plans

Plans:
- [x] 01-01-PLAN.md -- Config, scaffolding, date parser, attrition logger (LOAD-02, LOAD-03)
- [x] 01-02-PLAN.md -- PCORnet CSV loader with explicit col_types for 9 tables (LOAD-01)

---

### Phase 2: Payer Harmonization
**Goal**: User can harmonize payer data into 9 standard categories with encounter-level dual-eligible detection

**Depends on**: Phase 1 (requires loaded ENROLLMENT table and payer mapping config)

**Requirements**: PAYR-01, PAYR-02, PAYR-03

**Success Criteria** (what must be TRUE):
1. User can map raw PAYER_TYPE codes to 9 standard categories (Medicare, Medicaid, Dual eligible, Private, Other government, No payment/Self-pay, Other, Unavailable, Unknown) matching Python pipeline reference
2. User can identify dual-eligible patients via encounter-level detection (patients with Medicare+Medicaid cross-payer encounters or dual codes 14/141/142)
3. User can generate per-partner enrollment completeness report showing percentage of patients with enrollment records, mean enrollment duration, and gap patterns for each site (AMS, UMI, FLM, VRT)
4. User can validate payer harmonization output against Python pipeline counts (dual-eligible rate within 10-20% of Medicare + Medicaid combined)

**Plans:** 1 plan

Plans:
- [x] 02-01-PLAN.md -- ICD utility, 9-category payer mapping, dual-eligible detection, patient summary, enrollment completeness report (PAYR-01, PAYR-02, PAYR-03)

---

### Phase 3: Cohort Building
**Goal**: User can build HL cohort using named filter predicates with automatic attrition logging

**Depends on**: Phase 2 (requires harmonized payer categories and enrollment data)

**Requirements**: CHRT-01, CHRT-02, CHRT-03

**Success Criteria** (what must be TRUE):
1. User can apply named filter predicates (`has_hodgkin_diagnosis()`, `with_enrollment_period()`, `exclude_missing_payer()`) that read like clinical protocol steps
2. User can see N patients before and after every filter step via automatic attrition logging (accumulated into data frame with columns: step_name, n_before, n_after, n_excluded)
3. User can match HL diagnosis codes across both dotted (C81.10, 201.90) and undotted (C8110, 20190) ICD formats via normalization
4. User can generate final cohort dataset with all 149 HL codes identified, payer categories assigned, and enrollment periods validated

**Plans:** 2 plans

Plans:
- [x] 03-01-PLAN.md -- Treatment code config + named filter predicates and treatment flag functions (CHRT-01, CHRT-03)
- [x] 03-02-PLAN.md -- Cohort build pipeline with filter chain, attrition logging, and CSV output (CHRT-01, CHRT-02, CHRT-03)

---

### Phase 4: Visualization
**Goal**: User can visualize cohort attrition and payer-stratified patient flow

**Depends on**: Phase 3 (requires final cohort and attrition log)

**Requirements**: VIZ-01, VIZ-02, VIZ-03

**Success Criteria** (what must be TRUE):
1. User can produce attrition waterfall chart showing progressive cohort reduction through filter steps (vertical bars with N excluded at each step)
2. User can produce payer-stratified Sankey/alluvial diagram showing patient flow from payer category to treatment type, with flow thickness proportional to N patients and colored by payer category
3. User can verify HIPAA small-cell suppression is deferred to v2 per D-11 (exploratory outputs on HiPerGator)
4. User can save visualizations as PNG files (`output/figures/waterfall_attrition.png`, `output/figures/sankey_patient_flow.png`)

**Plans:** 1 plan

Plans:
- [x] 04-01-PLAN.md -- Waterfall attrition chart + payer-stratified Sankey diagram with colorblind-safe palette (VIZ-01, VIZ-02, VIZ-03)

---

### Phase 5: Fix parsing of dates and other possible parsing errors and investigate why not everyone has an HL diagnosis

**Goal:** Fix date parsing and column detection issues across the pipeline, expand HL identification to include TUMOR_REGISTRY histology codes (ICD-O-3 9650-9667), and produce a reusable diagnostic script auditing data quality across all loaded tables
**Requirements**: FIX-01, FIX-02, FIX-03, FIX-04
**Depends on:** Phase 4 (builds on completed pipeline)
**Plans:** 3/3 plans complete

Plans:
- [x] 05-01-PLAN.md -- Config + utility fixes: ICD-O-3 histology codes, is_hl_histology(), expanded has_hodgkin_diagnosis(), date regex update (FIX-01, FIX-02, FIX-03)
- [x] 05-02-PLAN.md -- Reusable diagnostic script 07_diagnostics.R with 6 audit sections (FIX-01, FIX-02, FIX-03, FIX-04)
- [x] 05-03-PLAN.md -- Cohort rebuild with expanded HL identification + human verification checkpoint (FIX-01, FIX-02) -- superseded by Phase 6

---

### Phase 6: Use debug output to rectify issues

**Goal:** Take the diagnostic output from 07_diagnostics.R and use those findings to fix data quality issues across the pipeline: HL_SOURCE tracking, date parser expansion, col_types corrections, numeric validation, payer documentation, and full pipeline rebuild with data quality summary
**Requirements**: RECT-01, RECT-02, RECT-03, RECT-04, RECT-05
**Depends on:** Phase 5
**Plans:** 3/3 plans executed

Plans:
- [x] 06-01-PLAN.md -- HL_SOURCE tracking in cohort predicates + Neither exclusion with audit CSV (RECT-01, RECT-02)
- [x] 06-02-PLAN.md -- Data-driven fixes: date parser, regex, col_types, validation columns, payer docs (RECT-03, RECT-04)
- [x] 06-03-PLAN.md -- Diagnostics update, data quality summary script, full pipeline rebuild + verification (RECT-05)

---

### Phase 7: Dx gap analysis for excluded Neither patients

**Goal:** Investigate the 19 patients excluded as "Neither" (no HL evidence) to characterize the data gap by diagnosis history, enrollment, and tumor registry cross-reference, and determine whether the gap is closable or a data quality limitation
**Requirements**: GAP-01, GAP-02, GAP-03
**Depends on:** Phase 6
**Plans:** 1/1 plans complete

Plans:
- [x] 07-01-PLAN.md -- Gap analysis script with diagnosis exploration, enrollment/TR cross-reference, gap classification, and pipeline decision checkpoint (GAP-01, GAP-02, GAP-03)

---

### Phase 8: Add insurance mode around three treatment types (chemo, radiation, stem cell) from procedures tables with plus/minus 30 days window

**Goal:** For each of three treatment types (chemotherapy, radiation, stem cell transplant), compute the patient's insurance payer mode within a +-30 day window around the first treatment procedure date, adding PAYER_AT_CHEMO, PAYER_AT_RADIATION, PAYER_AT_SCT columns (plus first treatment dates) to the existing hl_cohort output
**Requirements**: TPAY-01, TPAY-02, TPAY-03
**Depends on:** Phase 7
**Plans:** 1 plan

Plans:
- [x] 08-01-PLAN.md -- ICD procedure code config + treatment-anchored payer mode script + cohort integration (TPAY-01, TPAY-02, TPAY-03)

---

### Phase 9: Expand treatment detection using docx-specified tables and researched codes

**Goal:** Expand treatment detection for the existing 3 treatment types (chemotherapy, radiation, SCT) to cover all data sources specified in TreatmentVariables_2024.07.17.docx, adding DISPENSING, MED_ADMIN, DIAGNOSIS Z/V codes, ENCOUNTER DRG codes, and PROCEDURES revenue codes to both HAD_* flags and treatment-anchored payer computation
**Requirements**: TXEXP-01, TXEXP-02, TXEXP-03, TXEXP-04, TXEXP-05, TXEXP-06
**Depends on:** Phase 8
**Plans:** 3 plans

Plans:
- [x] 09-01-PLAN.md -- Expanded treatment code lists in config + DISPENSING/MED_ADMIN table loading (TXEXP-01, TXEXP-02, TXEXP-03, TXEXP-04)
- [x] 09-02-PLAN.md -- Expand has_chemo/radiation/sct() with DIAGNOSIS, DRG, DISPENSING, MED_ADMIN, revenue sources (TXEXP-01, TXEXP-02, TXEXP-03, TXEXP-04, TXEXP-05)
- [x] 09-03-PLAN.md -- Expand compute_payer_at_chemo/radiation/sct() date extraction with new sources (TXEXP-06)

---

### Phase 10: Incorporate VariableDetails.xlsx surveillance strategy and Treatment_Variable_Documentation.docx variables into pipeline, then regenerate Treatment_Variable_Documentation.docx

**Goal:** Add post-diagnosis surveillance modality detection (9 modalities + labs), survivorship encounter classification (4 levels), timing derivation variables (DAYS_DX_TO_*), and auto-generated comprehensive variable documentation covering the full pipeline output
**Requirements**: SURV-01, SURV-02, SURV-03, SURV-04, SVENC-01, SVENC-02, SVENC-03, SVENC-04, TDOC-01, TDOC-02, TDOC-03
**Depends on:** Phase 9
**Plans:** 5/5 plans complete

Plans:
- [x] 10-01-PLAN.md -- Config code lists from VariableDetails.xlsx + LAB_RESULT_CM/PROVIDER table loading (SURV-01, SVENC-01)
- [x] 10-02-PLAN.md -- Surveillance detection script 13_surveillance.R with 9 modalities + labs (SURV-02, SURV-03)
- [x] 10-03-PLAN.md -- Survivorship encounter classification 14_survivorship_encounters.R with 4 levels (SVENC-02, SVENC-03)
- [x] 10-04-PLAN.md -- Cohort integration: timing derivation + surveillance/survivorship joins in 04_build_cohort.R (SURV-04, SVENC-04, TDOC-01)
- [x] 10-05-PLAN.md -- Auto-documentation generation 15_generate_documentation.R with .md and .docx output (TDOC-02, TDOC-03)

---

### Phase 11: PPTX Clarity & Missing Data Consolidation

**Goal:** Make every PPTX slide unambiguous by collapsing Unknown, Unavailable, Other, and No Information payer categories into a single "Missing" label; add encounter analysis visualizations (histograms by payor, encounters by DX year, age group breakdowns); incorporate column totals, age groups (0-17/18-39/40-64/65+), DX year, and post-treatment encounter Yes/No flag
**Requirements**: PPTX-01, PPTX-02, PPTX-03, PPTX-04, PPTX-05
**Depends on:** Phase 10
**Plans:** 2/2 plans complete

Plans:
- [x] 11-01-PLAN.md -- Consolidate 9 payer categories to 6+Missing, fix all labels for clarity (PPTX-01, PPTX-02, PPTX-05)
- [x] 11-02-PLAN.md -- Add 4 encounter analysis slides embedding PNG figures (PPTX-03, PPTX-04)

---

### Phase 12: More PPTX Polishing

**Goal:** Add glossary/definitions slide replacing title slide, per-slide footnotes with term definitions, fix encounter analysis graphs (payer consolidation, overflow bin, masked date filtering, label clipping), remove "No Treatment Recorded" row, and add summary statistics slide
**Requirements**: PPTX2-01, PPTX2-02, PPTX2-03, PPTX2-04, PPTX2-05, PPTX2-06, PPTX2-07
**Depends on:** Phase 11
**Plans:** 4/4 plans complete

Plans:
- [x] 12-01-PLAN.md -- Fix encounter analysis graphs: payer consolidation, overflow bin, DX_YEAR filter, label clipping (PPTX2-04, PPTX2-06, PPTX2-07)
- [x] 12-02-PLAN.md -- Replace title slide with glossary, remove NTR row, add summary stats slide (PPTX2-01, PPTX2-03, PPTX2-05)
- [x] 12-03-PLAN.md -- Add per-slide footnotes with term definitions and DX_YEAR exclusion note (PPTX2-02, PPTX2-06)
- [x] 12-04-PLAN.md -- Gap closure: HiPerGator execution helper + visual verification of generated PNGs (PPTX2-04, PPTX2-07)

---

### Phase 13: Summary Tables Value Audit

**Goal:** Create comprehensive frequency/summary tables for every categorical variable across all 13 loaded PCORnet CDM tables, enumerating every distinct value so the user can review for coding inconsistencies
**Requirements**: AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04
**Depends on:** Phase 1 (only needs loaded PCORnet tables; optionally uses Phase 2/3 derived variables)
**Plans:** 1/1 plans complete

Plans:
- [x] 13-01-PLAN.md -- Value audit script R/17_value_audit.R with per-table CSV output and HIPAA suppression (AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04)

---

### Phase 14: CSV Values Data Audit & Code Optimization

**Goal:** Review value_audit CSVs for coding inconsistencies (same concept coded differently across tables/columns) via conversational analysis with Claude, then apply style-preserving code optimizations across all R scripts (00-17) to eliminate redundant operations, dead code, and unnecessary data copies while preserving named predicate patterns and dplyr chains
**Requirements**: CSVAUDIT-01, CSVAUDIT-02, OPTIM-01, OPTIM-02
**Depends on:** Phase 13
**Plans:** 3/3 plans complete

Plans:
- [x] 14-01-PLAN.md -- Conversational CSV value audit review: user provides HiPerGator output, Claude identifies coding inconsistencies (CSVAUDIT-01, CSVAUDIT-02)
- [x] 14-02-PLAN.md -- Optimize foundation scripts: consolidate TUMOR_REGISTRY bind_rows in 01_load_pcornet.R, simplify TR queries in 03_cohort_predicates.R (OPTIM-01, OPTIM-02)
- [x] 14-03-PLAN.md -- Optimize analysis scripts: consolidate PROCEDURES queries in 10_treatment_payer.R, extract HIPAA helper in 17_value_audit.R, dead code scan across 02-16 (OPTIM-01, OPTIM-02)

---

### Phase 15: RDS Caching Infrastructure

**Goal:** User can load PCORnet tables from persistent RDS cache instead of re-parsing CSVs on every run, with cache-check logic, force-reload override, and time-savings logging

**Depends on:** Phase 1 (extends `load_pcornet_table()` function)

**Requirements**: CACHE-01, CACHE-02, CACHE-03, CACHE-04, GIT-01, GIT-02

**Success Criteria** (what must be TRUE):
1. User can see cached RDS files for all 22 PCORnet tables written to `/blue/erin.mobley-hl.bcu/clean/rds/raw/` after first CSV load
2. User can see `[CACHE HIT]` or `[CSV PARSE]` logged to console for each table during pipeline startup
3. User can set `FORCE_RELOAD <- TRUE` in `00_config.R` to bypass cache and re-parse all CSVs
4. User can see wall-clock time saved per table logged when loading from cache (e.g., "ENROLLMENT: 2.3s (cache) vs 18.7s (CSV) — saved 16.4s")
5. User can verify cache directory is gitignored and documented in config

**Plans:** 2/2 plans complete

Plans:
- [x] 15-01-PLAN.md -- Config cache settings in 00_config.R + .gitignore for blue storage (CACHE-03, GIT-01, GIT-02)
- [x] 15-02-PLAN.md -- Cache-check/write logic in load_pcornet_table() + TUMOR_REGISTRY_ALL caching + diagnostic skip on cache hits (CACHE-01, CACHE-02, CACHE-04)

---

### Phase 16: Dataset Snapshots

**Goal:** User can save cohort snapshots at every filter step, final outputs, and figure/table backing datasets as RDS files for reproducibility and debugging

**Depends on:** Phase 15 (uses cache directory structure), Phase 3 (needs cohort chain)

**Requirements**: SNAP-01, SNAP-02, SNAP-03, SNAP-04, SNAP-05

**Success Criteria** (what must be TRUE):
1. User can see RDS snapshot after each named filter step saved to `/blue/erin.mobley-hl.bcu/clean/rds/cohort/cohort_<step_name>.rds`
2. User can see final cohort and attrition log saved as `cohort_final.rds` and `attrition_log.rds`
3. User can see figure-backing data frames (e.g., `encounter_histogram_data.rds`) saved to `/blue/erin.mobley-hl.bcu/clean/rds/outputs/` before plot rendering
4. User can see table-backing data frames (e.g., `payer_summary_table_data.rds`) saved before PPTX table creation
5. User can call `save_output_data(df, "name")` helper from any script for consistent snapshot creation with automatic path construction and logging

**Plans:** 2/2 plans complete

Plans:
- [x] 16-01-PLAN.md -- Config cache extension + utils_snapshot.R helper + cohort filter step snapshots (SNAP-01, SNAP-02, SNAP-05)
- [x] 16-02-PLAN.md -- Visualization backing data snapshots in waterfall, sankey, encounter analysis, and PPTX scripts (SNAP-03, SNAP-04)

---

### Phase 17: Visualization Polish

**Goal:** User can see 1900 sentinel dates filtered from all PPTX content, post-treatment encounter summary table, and stacked encounter histograms showing pre/post-treatment breakdown by payer

**Depends on:** Phase 16 (needs snapshot infrastructure for reproducibility), Phase 12 (builds on existing PPTX generation)

**Requirements**: VIZP-01, VIZP-02, VIZP-03, PPTX2-04, PPTX2-07

**Success Criteria** (what must be TRUE):
1. User can verify no 1900 dates appear in any PPTX table or graph (filtered at data preparation stage, not display suppression)
2. User can see new PPTX slide with summary table showing unique encounter dates per person by payer category, counted only after last treatment date (max of LAST_CHEMO_DATE, LAST_RADIATION_DATE, LAST_SCT_DATE)
3. User can see stacked encounter histogram faceted by payer with post-treatment encounters on bottom (colored distinctly) and pre-treatment on top
4. User can see encounter histogram with 6+Missing payer categories and >500 overflow bin with per-facet count annotation (completing PPTX2-04)
5. User can see age group bar chart with labels not clipped at plot top (completing PPTX2-07)

**Plans:** 2/2 plans complete

Plans:
- [x] 17-01-PLAN.md -- Filter 1900 sentinel dates from PPTX display layer + stacked pre/post histogram in encounter analysis (VIZP-01, VIZP-03, PPTX2-04, PPTX2-07)
- [x] 17-02-PLAN.md -- New PPTX slides: post-treatment encounter summary table + stacked histogram embedding + summary stats (VIZP-02, VIZP-03)

---

### Phase 18: One Enrolled Person Does Not Have an HL Diagnosis Caught

**Goal:** Investigate and resolve why one enrolled patient is classified as "Neither" (no HL evidence) despite having lymphoma/cancer codes, by diagnosing the root cause and applying a targeted fix or documenting correct exclusion

**Depends on:** Phase 17

**Requirements**: INV-01, INV-02, INV-03

**Success Criteria** (what must be TRUE):
1. User can see the exact ICD codes for the "Neither" patient via gap analysis CSV output
2. Root cause is diagnosed as one of 5 possibilities: missing code, DX_TYPE mismatch, normalization bug, histology outside range, or correctly excluded non-HL lymphoma
3. If fix applied: patient appears in cohort with corrected HL_SOURCE after pipeline rerun
4. If correctly excluded: exclusion documented with specific codes and rationale

**Plans:** 1/1 plans complete

Plans:
- [x] 18-01-PLAN.md -- HiPerGator gap analysis, root cause diagnosis, targeted fix or documentation (INV-01, INV-02, INV-03)

---

### Phase 19: Investigate Insurance Missingness Source UF Specifically

**Goal:** Characterize why insurance/payer data is missing for UFH (University of Florida) patients by profiling raw ENCOUNTER PAYER_TYPE fields and derived harmonized categories, with breakdowns by year, encounter type, and their combination

**Depends on:** Phase 18

**Requirements**: UFMISS-01, UFMISS-02, UFMISS-03, UFMISS-04

**Success Criteria** (what must be TRUE):
1. User can see overall payer missingness rate for UFH encounters on both PRIMARY and SECONDARY fields
2. User can see missingness broken down by admission year to identify temporal submission gaps
3. User can see missingness broken down by encounter type to identify systematic data gaps
4. User can see year x encounter type crosstab revealing concentrated missingness patterns
5. User can see raw vs harmonized missingness comparison to determine if gap is in data submission or harmonization logic
6. User can see 5 CSV files in output/tables/ with all UFH missingness breakdowns

**Plans:** 1/1 plans complete

Plans:
- [x] 19-01-PLAN.md -- Standalone diagnostic script R/18_uf_insurance_missingness.R with raw field profiling, temporal/encounter-type breakdowns, raw vs harmonized comparison, and CSV outputs (UFMISS-01, UFMISS-02, UFMISS-03, UFMISS-04)

---

### Phase 20: Check Duplicate Dates of FLM Subjects

**Goal:** Investigate whether FLM-sourced patients have duplicate ENCOUNTER rows on the same date from multiple data sources, quantify duplication rates (same-date collisions and exact row duplicates), compare payer data completeness across sources for duplicate encounters, and recommend which source to prefer

**Depends on:** Phase 19

**Requirements**: FLMDUP-01, FLMDUP-02, FLMDUP-03, FLMDUP-04

**Success Criteria** (what must be TRUE):
1. User can see same-date duplicate encounter counts and rates for all FLM patients
2. User can see exact row duplicates detected separately from same-date collisions
3. User can see which SOURCE values contribute to duplicate-date encounters (multi-source dates)
4. User can compare payer data completeness across sources for multi-source duplicate encounters
5. User can see source-preference recommendation based on payer completeness rates
6. User can see 3 CSV files in output/tables/ with patient-level, date-level, and aggregate summaries

**Plans:** 1/1 plans complete

Plans:
- [x] 20-01-PLAN.md -- Standalone diagnostic script R/19_flm_duplicate_dates.R with same-date and exact duplicate detection, multi-source identification, payer completeness comparison, source recommendation, and 3 CSV outputs (FLMDUP-01, FLMDUP-02, FLMDUP-03, FLMDUP-04)

---

### Phase 21: Generalize Phase 19 to All Sources

**Goal:** Extend Phase 19's UFH-specific payer missingness investigation to all 5 partner sites (AMS, UMI, FLM, VRT, UFH) using group_by(SOURCE) instead of site-specific filtering, producing combined CSVs with cross-site comparison for head-to-head payer data completeness assessment

**Depends on:** Phase 20

**Requirements**: ALLMISS-01, ALLMISS-02, ALLMISS-03, ALLMISS-04, ALLMISS-05

**Success Criteria** (what must be TRUE):
1. User can see raw payer value distributions for all 5 sites in a single CSV with SOURCE column
2. User can see temporal, encounter-type, and year x type missingness breakdowns grouped by SOURCE
3. User can see raw vs harmonized comparison grouped by SOURCE identifying per-site submission vs harmonization gaps
4. User can see cross-site summary CSV with one row per site for head-to-head missingness comparison
5. User can review per-site missingness rates in console output on HiPerGator
6. User can see 6 CSV files in output/tables/ with all_source_ prefix

**Plans:** 1/1 plans complete

Plans:
- [x] 21-01-PLAN.md -- Standalone diagnostic script R/20_all_source_missingness.R with grouped missingness breakdowns, cross-site summary CSV, and console output (ALLMISS-01, ALLMISS-02, ALLMISS-03, ALLMISS-04, ALLMISS-05)

---

### Phase 22: Generalize Phase 20 to All Sites

**Goal:** Extend Phase 20's FLM-specific duplicate date investigation to ALL 5 partner sites (AMS, UMI, FLM, VRT, UFH) using DEMOGRAPHIC.SOURCE as site assignment, producing combined CSVs with per-site duplicate detection, multi-source identification, payer completeness comparison, per-site source-preference recommendations, and a cross-site summary for head-to-head duplication rate comparison

**Depends on:** Phase 21

**Requirements**: ALLDUP-01, ALLDUP-02, ALLDUP-03, ALLDUP-04, ALLDUP-05

**Success Criteria** (what must be TRUE):
1. User can see same-date duplicate encounter counts and rates for ALL patients at each of the 5 partner sites
2. User can see exact row duplicates detected separately from same-date collisions per site
3. User can see which ENCOUNTER.SOURCE values contribute to multi-source duplicate dates per DEMOGRAPHIC.SOURCE site
4. User can compare payer data completeness across ENCOUNTER.SOURCE values for multi-source duplicates at each site
5. User can see per-site source-preference recommendations based on payer completeness rates
6. User can see a cross-site summary CSV with one row per site for head-to-head comparison of duplication rates
7. User can see 5 CSV files in output/tables/ with all_site_ prefix

**Plans:** 1/1 plans complete

Plans:
- [x] 22-01-PLAN.md -- Standalone diagnostic script R/21_all_site_duplicate_dates.R with per-site duplicate detection, multi-source identification, payer completeness comparison, source recommendations, cross-site summary, and 5 CSV outputs (ALLDUP-01, ALLDUP-02, ALLDUP-03, ALLDUP-04, ALLDUP-05)

---

### Phase 23: Make Visual Presentation of Tables from Last 2 Pages

**Goal:** Convert Phase 21 (all-source payer missingness, 6 CSVs) and Phase 22 (all-site duplicate dates, 5 CSVs) diagnostic outputs into formatted PPTX slides with both data tables and bar chart visualizations, appended to the existing 38-slide insurance_tables presentation

**Depends on:** Phase 22

**Requirements**: PPTX3-01, PPTX3-02, PPTX3-03, PPTX3-04, PPTX3-05, PPTX3-06, PPTX3-07

**Success Criteria** (what must be TRUE):
1. User can see all 11 CSV outputs from Phase 21 and Phase 22 as formatted PPTX slides
2. User can see 3 bar chart visualizations: missingness by site, duplication by site, missingness by encounter type
3. User can see wide/tall tables split across multiple slides for readability
4. User can see detail-level CSVs (9332 rows, 262K rows) summarized into presentation-friendly aggregates
5. User can see consistent styling (UF blue headers, alternating rows, footnotes) matching existing Slides 1-38
6. User can see dynamic slide count in console output reflecting all new slides

**Plans:** 2/2 plans complete

Plans:
- [x] 23-01-PLAN.md -- Generate 3 bar chart PNGs and add Phase 21 missingness slides to PPTX (PPTX3-01, PPTX3-02, PPTX3-03, PPTX3-04)
- [x] 23-02-PLAN.md -- Add Phase 22 duplication slides, update SAVE section, HiPerGator verification (PPTX3-05, PPTX3-06, PPTX3-07)

---

### Phase 24: Make Presentation of Just Phases 19 and 20

**Goal:** Create a focused presentation that includes only the Phase 19 (UF insurance missingness) and Phase 20 (FLM duplicate dates) analyses, without the generalized all-site/all-source content from Phases 21/22

**Depends on:** Phase 23

**Requirements**: PPTX4-01, PPTX4-02, PPTX4-03, PPTX4-04

**Success Criteria** (what must be TRUE):
1. User can generate a PPTX containing Phase 19 outputs (UF missingness tables/charts) and Phase 20 outputs (FLM duplicate-date tables/charts) only
2. User can confirm no Phase 21/22 all-site/all-source slides appear in the focused deck
3. User can see consistent visual styling with existing presentation conventions (titles, footnotes, table formatting)
4. User can save the focused deck with a clear filename distinguishing it from the full multi-phase presentation

**Plans:** 0/1 plans complete

Plans:
- [ ] 24-01-PLAN.md -- Add focused Phase 19/20 PPTX generation path with UF + FLM-only slide set and output naming (PPTX4-01, PPTX4-02, PPTX4-03, PPTX4-04)

### Phase 25: Close gaps between existing code and OneFLQuestions.docx and QuantAnalysisMtgNotes_ZoomAI.docx, lowest hanging fruit first

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 24
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 25 to break down)

---

### Phase 25: Multi-Source Overlap Detection

**Goal:** User can identify all patient-date and patient-week groups where encounters originate from more than one distinct ENCOUNTER.SOURCE value, across all 5 partner sites, with per-site counts and source combination frequencies

**Depends on:** Phase 24 (builds on Phase 22 detection patterns in R/21_all_site_duplicate_dates.R)

**Requirements**: SAMEDT-01, SAMEDT-02, SAMEDT-03, SAMEWK-01, SAMEWK-02, SAMEWK-03

**Success Criteria** (what must be TRUE):
1. User can see all patient-date pairs where encounters come from more than one distinct ENCOUNTER.SOURCE on the same ADMIT_DATE, across all 5 sites (AMS, UMI, FLM, VRT, UFH)
2. User can see per-site counts of patients affected and total same-date multi-source encounter pairs, separated from same-week-only near-duplicates
3. User can see which SOURCE combinations appear together on the same date (e.g., UFH+FLM, AMS+UMI) with frequency counts per site
4. User can see same-week near-duplicates (encounters from different sources within a 7-day window but not on the same date) identified and categorized separately
5. User can see per-site counts and rates for same-week near-duplicates alongside same-date exact counts for direct comparison

**Plans:** 1/1 plans complete

Plans:
- [x] 25-01-PLAN.md -- Standalone R script R/22_multi_source_overlap_detection.R: same-date grouping, 7-day window near-duplicate detection, per-site counts, source combination frequencies (SAMEDT-01, SAMEDT-02, SAMEDT-03, SAMEWK-01, SAMEWK-02, SAMEWK-03)

---

### Phase 26: Overlap Classification and Recommendations

**Goal:** User can see each multi-source encounter group (same-date and same-week) classified as Identical, Partial, or Distinct based on field-by-field comparison, with CSV outputs, a console summary, and per-site actionable recommendations on whether to deduplicate or retain encounters

**Depends on:** Phase 25 (consumes detection output from R/22_multi_source_overlap_detection.R)

**Requirements**: OVRLP-01, OVRLP-02, OVRLP-03, OVRLP-04, OUTPT-01, OUTPT-02, OUTPT-03

**Success Criteria** (what must be TRUE):
1. User can see field-by-field match/mismatch flags for ENC_TYPE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, PROVIDERID, and DISCHARGE_DATE for each same-date multi-source group
2. User can see each multi-source group labeled Identical (all compared fields match), Partial (some fields match), or Distinct (most fields differ), for both same-date and same-week groups
3. User can see per-site overlap profiles showing the percentage breakdown of Identical vs Partial vs Distinct for same-date and same-week encounter groups
4. User can see CSV files in output/tables/ with patient-level same-date detail, same-week detail, and per-site aggregate summaries including overlap classification counts
5. User can see a console summary on HiPerGator with per-site multi-source rates, Identical/Partial/Distinct breakdown, and key findings
6. User can read per-site actionable recommendations derived from overlap patterns (e.g., "Site X: 85% Identical — safe to deduplicate by keeping preferred source; Site Y: 60% Distinct — encounters are genuinely different, retain all")

**Plans:** 1 plan

Plans:
- [ ] 26-01-PLAN.md -- Standalone R script R/23_overlap_classification.R: field comparison flags, Identical/Partial/Distinct labeling for same-date and same-week groups, CSV outputs, console summary, per-site recommendations (OVRLP-01, OVRLP-02, OVRLP-03, OVRLP-04, OUTPT-01, OUTPT-02, OUTPT-03)

---

### Phase 27: Cross-Table Data Quality Assessment

**Goal:** Run a comprehensive QA pass across all 13 loaded PCORnet CDM tables applying 6 QA dimensions (field completeness, value validity against CDM v7.0 value sets, exact/semantic row duplicates, multi-source overlap, temporal consistency, and referential integrity), producing per-table CSV reports and a full console scorecard identifying data that is not analytically useful

**Depends on:** Phase 26

**Requirements**: D-01, D-02, D-03, D-04, D-05, D-06, D-07, D-08, D-09, D-10, D-11, D-12

**Success Criteria** (what must be TRUE):
1. User can see per-column completeness percentages and sentinel counts for every column in all 13 tables
2. User can see invalid values flagged against PCORnet CDM v7.0 value sets for coded columns
3. User can see exact and semantic row duplicate counts per table
4. User can see multi-source overlap detection for tables with date fields (skipping DEMOGRAPHIC, PROVIDER)
5. User can see temporal consistency violations (start > end, future dates, sentinel dates)
6. User can see referential integrity gaps (orphaned IDs not in DEMOGRAPHIC)
7. User can see per-table CSV reports in output/tables/ with qa_ prefix and HIPAA-suppressed counts
8. User can see a console scorecard with per-table findings across all 6 dimensions

**Plans:** 2 plans

Plans:
- [ ] 27-01-PLAN.md -- Create R/24_cross_table_qa.R with QA framework, PCORnet CDM v7.0 value sets, and four mandatory dimensions (completeness, validity, duplicates, overlap) (D-01, D-02, D-03, D-04, D-05, D-06, D-07, D-08, D-09, D-10, D-11, D-12)
- [ ] 27-02-PLAN.md -- Add temporal consistency and referential integrity dimensions, expand console scorecard, HiPerGator verification (D-03, D-04, D-07, D-10, D-11)

---

### Phase 28: Per-Patient Source Detection by Date

**Goal:** For each patient on each date, detect which ENCOUNTER.SOURCE values are present and how many encounters each source contributes, replacing the Phase 25-26 pairwise overlap approach with a simpler per-date source enumeration strategy using data.table for speed

**Depends on:** Phase 27

**Requirements**: PDSRC-01, PDSRC-02, PDSRC-03, PDSRC-04, PDSRC-05

**Success Criteria** (what must be TRUE):
1. User can see one row per (patient, date) with n_sources, source_combo, n_encounters for ALL dates (including single-source)
2. User can see source combination frequency summary showing how often each combo (e.g., "UFH", "FLM+UFH") appears across patient-dates
3. User can see per-source aggregate counts (total encounters, patient-dates, patients)
4. User can see HIPAA-suppressed counts (1-10 replaced with "<11") in all 3 CSV outputs
5. User can see console summary with total encounters, parse rate, single vs multi-source breakdown, per-source counts, top 10 combos

**Plans:** 1 plan

Plans:
- [ ] 28-01-PLAN.md -- Standalone R script R/24_per_patient_source_detection.R: data.table per-date source enumeration, 3 CSV outputs, HIPAA suppression, console summary (PDSRC-01, PDSRC-02, PDSRC-03, PDSRC-04, PDSRC-05)

---

### Phase 29: DuckDB Ingest Infrastructure

**Goal:** User can ingest all 13 PCORnet tables from RDS cache into a single indexed DuckDB file with atomic write and round-trip verification

**Depends on:** Phase 15 (requires RDS cache infrastructure)

**Requirements**: DBING-01, DBING-02, DBING-03

**Success Criteria** (what must be TRUE):
1. User can see all 13 PCORnet tables (ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC, DISPENSING, MED_ADMIN, LAB_RESULT_CM, PROVIDER, TUMOR_REGISTRY1/2/3) ingested into a single DuckDB file at configured path
2. User can verify atomic write via `.tmp` file swap — interrupted runs leave the canonical DuckDB file untouched
3. User can see per-table ingest log CSV showing row counts and durations for all 13 tables
4. User can see PATID indexes on all 13 tables and ENCOUNTERID indexes on 8 tables that have it
5. User can verify round-trip dimension and column verification passes for all tables (no schema drift)

**Plans:** 2/2 plans complete

Plans:
- [x] 29-01-PLAN.md -- DuckDB ingest script with atomic write, per-table logging, and sequential table ingestion from RDS cache (DBING-01, DBING-02)
- [x] 29-02-PLAN.md -- Index creation after ingest and round-trip verification helper (DBING-03)

---

### Phase 30: Query Backend Abstraction Layer

**Goal:** User can transparently query PCORnet tables from either RDS or DuckDB backend via a single dispatcher function with USE_DUCKDB flag control

**Depends on:** Phase 29 (requires DuckDB file with indexed tables)

**Requirements**: DBAPI-01, DBAPI-02, DBAPI-03, DBAPI-04

**Success Criteria** (what must be TRUE):
1. User can call `get_pcornet_table(name, con)` to get a pipeable dplyr-compatible object from either backend
2. User can toggle `USE_DUCKDB` flag in `00_config.R` to switch all scripts between RDS and DuckDB without changing downstream code
3. User can open/close DuckDB connections via `open_pcornet_con()` / `close_pcornet_con()` with read-only enforcement
4. User can convert lazy DuckDB queries to tibbles via `materialize()` helper
5. User can see all existing named predicates passing smoke test on 100-patient sample under both backends with PATID set equality
6. User can review `docs/DUCKDB_TRANSLATION_NOTES.md` documenting any dbplyr translation gaps found and workarounds applied

**Plans:** 2 plans

Plans:
- [ ] 30-01-PLAN.md -- Backend abstraction helpers in utils_duckdb.R with get_pcornet_table dispatcher and connection management (DBAPI-01, DBAPI-02, DBAPI-03)
- [ ] 30-02-PLAN.md -- Smoke test all predicates on both backends with 100-patient sample and document translation gaps (DBAPI-04)

---

### Phase 31: Cohort Pipeline DuckDB Migration

**Goal:** User can run the full cohort build pipeline under DuckDB backend with verified parity against Phase 16 RDS snapshots and benchmark comparison

**Depends on:** Phase 30 (requires abstraction layer and smoke-tested predicates)

**Requirements**: DBCOH-01, DBCOH-02, DBCOH-03

**Success Criteria** (what must be TRUE):
1. User can run cohort build end-to-end under `USE_DUCKDB = TRUE` with lazy evaluation up to final materialize call
2. User can verify full parity between RDS and DuckDB outputs via `waldo::compare()` — row count equality, PATID set equality, and full structural equality on final cohort and attrition log
3. User can see RDS vs DuckDB benchmark timings in `output/logs/duckdb_benchmark.csv` from 3 runs per backend with median comparison
4. User can confirm `USE_DUCKDB = FALSE` still reproduces Phase 16 RDS snapshot behavior (no regression)

**Plans:** 2 plans

Plans:
- [ ] 31-01-PLAN.md -- Migrate cohort build script to get_pcornet_table calls with late materialize and full parity testing (DBCOH-01, DBCOH-02)
- [ ] 31-02-PLAN.md -- Benchmark wrapper helper and cohort build timing comparison (DBCOH-03)

---

### Phase 32: Diagnostic Scripts DuckDB Migration & Benchmarks

**Goal:** User can run all 5 diagnostic scripts under DuckDB backend with parity-verified outputs, speedup report, migration guide, and DuckDB as the new default

**Depends on:** Phase 31 (requires cohort migration pattern and benchmark infrastructure)

**Requirements**: DBDIAG-01, DBDIAG-02, DBDIAG-03, DBDIAG-04

**Success Criteria** (what must be TRUE):
1. User can run 5 diagnostic scripts (R/20-24: all-source missingness, all-site duplicates, multi-source overlap, overlap classification, per-patient source detection) under `USE_DUCKDB = TRUE` without error
2. User can verify CSV output parity for all 5 scripts via md5sum comparison or documented tolerance for HIPAA boundary diffs only
3. User can read generated speedup report (`output/reports/duckdb_speedup_report.md`) showing per-script RDS vs DuckDB median timing and speedup ratio
4. User can read migration guide (`docs/DUCKDB_MIGRATION_GUIDE.md`) with connection pattern, template script, translation gap reference, and parity test methodology
5. User can verify `USE_DUCKDB` defaults to `TRUE` in `00_config.R` with deprecation comment and RDS fallback documented
6. User can run full pipeline end-to-end on HiPerGator with new default and verify all outputs match expected shapes

**Plans:** 2 plans

Plans:
- [ ] 32-01-PLAN.md -- Migrate 5 diagnostic scripts with parity testing and benchmark all vs RDS baseline (DBDIAG-01, DBDIAG-02)
- [ ] 32-02-PLAN.md -- Generate speedup report, write migration guide, flip USE_DUCKDB default to TRUE, full pipeline verification (DBDIAG-03, DBDIAG-04)

---

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation & Data Loading | 2/2 | Complete | 2026-03-24 |
| 2. Payer Harmonization | 1/1 | Complete | 2026-03-24 |
| 3. Cohort Building | 2/2 | Complete | 2026-03-25 |
| 4. Visualization | 1/1 | Complete | 2026-03-25 |
| 5. Fix Parsing & HL Diagnosis Gaps | 3/3 | Complete | 2026-03-25 |
| 6. Use Debug Output to Rectify Issues | 3/3 | Complete | 2026-03-25 |
| 7. Dx Gap Analysis for Neither Patients | 1/1 | Complete | 2026-03-25 |
| 8. Treatment-Anchored Payer Mode | 1/1 | Complete | 2026-03-26 |
| 9. Expand Treatment Detection | 3/3 | Complete | 2026-03-31 |
| 10. Surveillance, Survivorship & Documentation | 5/5 | Complete | 2026-03-31 |
| 11. PPTX Clarity & Missing Data | 2/2 | Complete | 2026-03-31 |
| 12. More PPTX Polishing | 4/4 | Complete | 2026-04-01 |
| 13. Summary Tables Value Audit | 1/1 | Complete | 2026-04-01 |
| 14. CSV Values Data Audit & Code Optimization | 3/3 | Complete | 2026-04-01 |
| 15. RDS Caching Infrastructure | 2/2 | Complete | 2026-04-03 |
| 16. Dataset Snapshots | 2/2 | Complete | 2026-04-03 |
| 17. Visualization Polish | 2/2 | Complete | 2026-04-03 |
| 18. One Enrolled Person Without HL Diagnosis | 1/1 | Complete | 2026-04-07 |
| 19. Investigate Insurance Missingness (UF) | 1/1 | Complete | 2026-04-09 |
| 20. Check Duplicate Dates of FLM Subjects | 1/1 | Complete | 2026-04-09 |
| 21. Generalize Phase 19 to All Sources | 1/1 | Complete | 2026-04-13 |
| 22. Generalize Phase 20 to All Sites | 1/1 | Complete | 2026-04-14 |
| 23. Visual Presentation of Phase 21/22 Tables | 2/2 | Complete | 2026-04-14 |
| 24. Focused Presentation of Phases 19/20 | 0/1 | Planned | - |
| 25. Multi-Source Overlap Detection | 1/1 | Complete | 2026-04-21 |
| 26. Overlap Classification and Recommendations | 0/1 | Not started | - |
| 27. Cross-Table Data Quality Assessment | 0/2 | Planned | - |
| 28. Per-Patient Source Detection by Date | 0/1 | Planned | - |
| 29. DuckDB Ingest Infrastructure | 2/2 | Complete    | 2026-04-23 |
| 30. Query Backend Abstraction Layer | 0/2 | Not started | - |
| 31. Cohort Pipeline DuckDB Migration | 0/2 | Not started | - |
| 32. Diagnostic Scripts DuckDB Migration & Benchmarks | 0/2 | Not started | - |

## Next Actions

Milestone v1.3 (DuckDB Backend Migration) roadmap created. Phases 29-32 added with 8 plans total. All 14 v1.3 requirements mapped.

Execute Phase 29 with `/gsd:execute-phase 29`.

*Last updated: 2026-04-23 (Phases 29-32 added for milestone v1.3 DuckDB Backend Migration)*
