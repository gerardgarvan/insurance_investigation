# Roadmap: PCORnet Payer Variable Investigation (R Pipeline)

**Project:** PCORnet CDM Payer Analysis Pipeline (R)
**Created:** 2026-03-24
**Granularity:** Coarse (4 phases)
**Coverage:** 21/21 v1 requirements mapped

## Phases

- [x] **Phase 1: Foundation & Data Loading** - Configure paths, load 22 PCORnet CSV tables with correct data types, build utilities
- [x] **Phase 2: Payer Harmonization** - Implement 9-category payer mapping with encounter-level dual-eligible detection
- [x] **Phase 3: Cohort Building** - Build HL cohort using named filter predicates with attrition logging
- [ ] **Phase 4: Visualization** - Produce attrition waterfall and payer-stratified Sankey diagrams with HIPAA suppression
- [x] **Phase 11: PPTX Clarity & Missing Data Consolidation** - Eliminate ambiguous labels, collapse Unknown/Other/Unavailable into "Missing", add encounter analysis slides (completed 2026-03-31)
- [ ] **Phase 12: More PPTX Polishing** - Add glossary slide, per-slide footnotes, fix graph issues, add summary stats slide (gap closure pending)
- [ ] **Phase 13: Summary Tables Value Audit** - Comprehensive frequency/summary tables for every column across all 13 PCORnet CDM tables
- [x] **Phase 14: CSV Values Data Audit & Code Optimization** - Review value_audit CSVs for coding inconsistencies, optimize R pipeline code (completed 2026-04-01)
- [x] **Phase 15: RDS Caching Infrastructure** - Add persistent RDS cache for all PCORnet tables with cache-check logic and time-savings logging (completed 2026-04-03)
- [x] **Phase 16: Dataset Snapshots** - Save cohort snapshots, final outputs, and figure/table backing data as RDS files (completed 2026-04-03)
- [x] **Phase 17: Visualization Polish** - Filter 1900 sentinel dates, add post-treatment encounter analysis, stacked histograms (completed 2026-04-03)
- [x] **Phase 18: One Enrolled Person Does Not Have an HL Diagnosis Caught** - Investigate and fix single patient classified as "Neither" despite having lymphoma codes (completed 2026-04-07)

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
**Plans:** 2/3 plans executed

Plans:
- [x] 05-01-PLAN.md -- Config + utility fixes: ICD-O-3 histology codes, is_hl_histology(), expanded has_hodgkin_diagnosis(), date regex update (FIX-01, FIX-02, FIX-03)
- [x] 05-02-PLAN.md -- Reusable diagnostic script 07_diagnostics.R with 6 audit sections (FIX-01, FIX-02, FIX-03, FIX-04)
- [ ] 05-03-PLAN.md -- Cohort rebuild with expanded HL identification + human verification checkpoint (FIX-01, FIX-02)

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
**Plans:** 1 plan

Plans:
- [ ] 07-01-PLAN.md -- Gap analysis script with diagnosis exploration, enrollment/TR cross-reference, gap classification, and pipeline decision checkpoint (GAP-01, GAP-02, GAP-03)

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
**Plans:** 4 plans (3 complete, 1 gap closure)

Plans:
- [x] 12-01-PLAN.md -- Fix encounter analysis graphs: payer consolidation, overflow bin, DX_YEAR filter, label clipping (PPTX2-04, PPTX2-06, PPTX2-07)
- [x] 12-02-PLAN.md -- Replace title slide with glossary, remove NTR row, add summary stats slide (PPTX2-01, PPTX2-03, PPTX2-05)
- [x] 12-03-PLAN.md -- Add per-slide footnotes with term definitions and DX_YEAR exclusion note (PPTX2-02, PPTX2-06)
- [ ] 12-04-PLAN.md -- Gap closure: HiPerGator execution helper + visual verification of generated PNGs (PPTX2-04, PPTX2-07)

---

### Phase 13: Summary Tables Value Audit

**Goal:** Create comprehensive frequency/summary tables for every categorical variable across all 13 loaded PCORnet CDM tables, enumerating every distinct value so the user can review for coding inconsistencies
**Requirements**: AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04
**Depends on:** Phase 1 (only needs loaded PCORnet tables; optionally uses Phase 2/3 derived variables)
**Plans:** 1 plan

Plans:
- [ ] 13-01-PLAN.md -- Value audit script R/17_value_audit.R with per-table CSV output and HIPAA suppression (AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04)

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

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation & Data Loading | 2/2 | Complete | 2026-03-24 |
| 2. Payer Harmonization | 1/1 | Complete | 2026-03-24 |
| 3. Cohort Building | 2/2 | Complete | 2026-03-25 |
| 4. Visualization | 1/1 | Complete | 2026-03-25 |
| 5. Fix Parsing & HL Diagnosis Gaps | 2/3 | In Progress |  |
| 6. Use Debug Output to Rectify Issues | 3/3 | Complete | 2026-03-25 |
| 7. Dx Gap Analysis for Neither Patients | 0/1 | Planned |  |
| 8. Treatment-Anchored Payer Mode | 1/1 | Complete | 2026-03-26 |
| 9. Expand Treatment Detection | 3/3 | Complete | 2026-03-31 |
| 10. Surveillance, Survivorship & Documentation | 5/5 | Complete   | 2026-03-31 |
| 11. PPTX Clarity & Missing Data | 2/2 | Complete    | 2026-03-31 |
| 12. More PPTX Polishing | 3/4 | Gap Closure   | |
| 13. Summary Tables Value Audit | 0/1 | Planned | |
| 14. CSV Values Data Audit & Code Optimization | 3/3 | Complete    | 2026-04-01 |
| 15. RDS Caching Infrastructure | 2/2 | Complete    | 2026-04-03 |
| 16. Dataset Snapshots | 2/2 | Complete    | 2026-04-03 |
| 17. Visualization Polish | 2/2 | Complete    | 2026-04-03 |
| 18. One Enrolled Person Without HL Diagnosis | 1/1 | Complete    | 2026-04-07 |

## Next Actions

1. Execute `/gsd:execute-phase 18` to investigate the single Neither patient

*Last updated: 2026-04-07 (Phase 18 plan created)*
