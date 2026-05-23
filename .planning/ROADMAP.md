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
- **v1.7 Cancer Summary Refinement & Gantt Enhancements** — Phases 55-57 (active)

## v1.7 Phases

- [x] **Phase 55: Cancer Summary Refinement Foundation** — Remove benign D-codes, confirm HL cohort with 2+ codes 7 days apart, compute first HL diagnosis date (completed 2026-05-22)
- [x] **Phase 56: Temporal Filtering** — Produce post-HL cancer summary variants filtered to cancers occurring after first HL diagnosis (completed 2026-05-23)
- [ ] **Phase 57: Gantt Enhancements** — Add cancer category labels, is_hodgkin binary flag, and death dates to Gantt chart data

## Remaining Phases (Unassigned)

- [x] **Phase 38: Chemo Treatment Inventory by Source Table** — List all chemo treatments and categorize by PCORnet table (procedures, dispensing, prescribing, etc.) (completed 2026-05-05)
  - **Goal:** Aggregate inventory of all treatment codes (chemo, radiation, SCT, immunotherapy) across 7 PCORnet tables with styled xlsx output
  - **Plans:** 1 plan
  - Plans:
    - [x] 38-01-PLAN.md — Data extraction, aggregation, unknown code detection, styled xlsx output
- [x] **Phase 39: Investigate Unmatched Codes** — Investigate CPT/HCPCS codes in HL patient data not in curated TREATMENT_CODES lists (completed 2026-05-04)
  - **Goal:** Widen heuristic detection ranges, auto-classify unmatched codes via NLM API lookup and keyword heuristics, produce xlsx report, and update TREATMENT_CODES with confirmed treatment codes
  - **Depends on:** Phase 38
  - **Plans:** 2 plans
  - Plans:
    - [x] 39-01-PLAN.md — Investigation script: extraction, NLM API lookup, classification, xlsx report
    - [x] 39-02-PLAN.md — Config updates: TREATMENT_CODES expansion and widened heuristic ranges
- [x] **Phase 40: Investigate Unmatched NDC Codes** — Investigate NDC codes and RXNORM CUIs in HL patient drug data not in curated TREATMENT_CODES lists (completed 2026-05-05)
  - **Goal:** Extract unmatched NDC and RXNORM codes from DISPENSING/PRESCRIBING/MED_ADMIN, look up drug names via RxNorm API, auto-classify into treatment categories, produce xlsx report, and update TREATMENT_CODES with new NDC vectors and expanded RXNORM CUIs
  - **Depends on:** Phase 39
  - **Plans:** 2 plans
  - Plans:
    - [x] 40-01-PLAN.md — Investigation script: drug code extraction, RxNorm API lookup, classification, xlsx report + RDS artifact
    - [x] 40-02-PLAN.md — Config update: new NDC vectors and expanded RXNORM CUIs in TREATMENT_CODES
- [x] **Phase 41: Combine NDC and HCPCS Reports** — Combine Phase 39 (HCPCS/CPT) and Phase 40 (NDC/RXNORM) unmatched code investigation reports into a single consolidated xlsx report (completed 2026-05-05)
  - **Goal:** Merge the two separate investigation xlsx reports into one unified report with consistent formatting, combined summary statistics, and cross-code-type views
  - **Depends on:** Phase 39, Phase 40
  - **Plans:** 1 plan
  - Plans:
    - [x] 41-01-PLAN.md — Load RDS artifacts, harmonize schemas, produce combined styled xlsx report
- [x] **Phase 42: Treatment Codes Resolved XLSX (All Types)** — Create resolved xlsx reports for other treatment types (radiation, SCT, immunotherapy) from combined_unmatched_report.xlsx, and verify chemotherapy_codes_resolved.xlsx accuracy (completed 2026-05-05)
  - **Goal:** Extend the chemotherapy_codes_resolved.xlsx pattern to all treatment categories, producing per-type resolved xlsx files, and audit chemotherapy_codes_resolved.xlsx for correctness
  - **Depends on:** Phase 41
  - **Plans:** 1 plan
  - Plans:
    - [x] 42-01-PLAN.md — Per-type resolved xlsx generation (radiation, SCT, immunotherapy, supportive care) + chemotherapy verification
- [x] **Phase 43: Establish Treatment Lengths for SCT, Chemo, and Radiation** — Determine treatment duration windows for stem cell transplant, chemotherapy, and radiation therapy from PCORnet data (completed 2026-05-05)
  - **Goal:** Establish treatment length estimates for SCT, chemo, radiation, and immunotherapy using procedure/dispensing/prescribing timestamps with 90-day episode gap detection
  - **Depends on:** Phase 42
  - **Plans:** 1 plan
  - Plans:
    - [x] 43-01-PLAN.md — Multi-source date extraction, duration/episode computation, styled xlsx + boxplot PNG + RDS output
- [x] **Phase 44: Treatment Episode Start/Stop Dates** — Produce per-patient per-episode start and stop dates for each 90-day treatment period with episode length; single-date episodes for historical treatments outside the 2012-2025 data window (completed 2026-05-11)
  - **Goal:** Expand treatment duration output to include per-episode start/stop dates and episode length, with special handling for isolated historical treatment dates (e.g., tumor registry dates from 1970s-2000s)
  - **Depends on:** Phase 43
  - **Plans:** 1 plan
  - Plans:
    - [x] 44-01-PLAN.md — Per-episode date extraction, historical flagging, styled xlsx + per-type CSVs + RDS output
- [x] **Phase 45: Tiered Encounter-Level Payer Assignment** — Assign AMC 8-category payer tiers to every individual encounter without same-day collapsing (completed 2026-05-12)
  - **Goal:** Per-encounter payer tier assignment with dual-scope (all encounters + AV+TH) detail and summary CSV output
  - **Depends on:** Phase 37
  - **Plans:** 1 plan
  - Plans:
    - [x] 45-01-PLAN.md — Encounter-level tier assignment, dual-scope CSV output (executed outside GSD workflow)
- [x] **Phase 46: Tiered Date-Level Payer Assignment** — Expand treatment episodes to per-calendar-date rows and assign payer tiers with forward/backward fill and enrollment fallback (completed 2026-05-12)
  - **Goal:** Per-calendar-date payer tier assignment within treatment episodes using encounter tiers, forward/backward fill, and FLM enrollment fallback
  - **Depends on:** Phase 44, Phase 45
  - **Plans:** 1 plan
  - Plans:
    - [x] 46-01-PLAN.md — Episode-to-daily expansion, tier cascade (encounter > fill > enrollment), summary CSVs (executed outside GSD workflow)

## v1.6 Phases

- [x] **Phase 45: Radiation CPT Audit** — Classify CPT 70010-79999 sub-ranges with citations, identify which codes appear in HL patient data, and add proton therapy codes to config (completed 2026-05-15)
  - **Goal:** The radiation CPT range 70010-79999 is documented, every code in HL patient data is classified as imaging or treatment, and proton therapy codes are captured in config
  - **Depends on:** Phase 44
  - **Requirements:** RADCPT-01, RADCPT-02, RADCPT-03
  - **Plans:** 2 plans
  - Plans:
    - [x] 45-01-PLAN.md — Config update (proton codes, fixed descriptions, comment block) + audit script (classification table, PROCEDURES query, styled xlsx)
    - [x] 45-02-PLAN.md — Gap closure: execute audit script on HiPerGator to generate xlsx output
- [x] **Phase 46: Treatment Code Cross-Reference & Triggering Codes** — Two-way gap report comparing TreatmentVariables docx against config, plus triggering_codes column in episode CSV output (completed 2026-05-15)
  - **Goal:** Users can see which codes are in the reference doc but not in config (and vice versa), and each episode row shows which code(s) triggered it
  - **Depends on:** Phase 45
  - **Requirements:** TXREF-01, TXREF-02
  - **Plans:** 2 plans
  - Plans:
    - [x] 46-01-PLAN.md — Gap report: hardcoded reference data from docx/xlsx files, two-way comparison, DuckDB counts, styled 5-sheet xlsx
    - [x] 46-02-PLAN.md — Triggering codes: extract_dates_with_codes() function, triggering_codes column in episode CSV and xlsx
- [x] **Phase 47: Cancer Site Frequency** — Frequency table of all 42 cancer site categories from CancerSiteCategories.xlsx with styled xlsx output ready to email (completed 2026-05-19)
  - **Goal:** Users can see patient counts and encounter counts per cancer site category across the full PCORnet extract
  - **Depends on:** Nothing (independent)
  - **Requirements:** CSITE-01, CSITE-02
  - **Plans:** 1 plan
  - Plans:
    - [x] 47-01-PLAN.md — Cancer site frequency script: range expansion, DIAGNOSIS + TUMOR_REGISTRY queries, styled xlsx output
- [x] **Phase 48: Combine Treatment Episode and Detail for Gantt Chart** — Export existing treatment episode and episode detail RDS artifacts as two universal CSV files (gantt_episodes.csv and gantt_detail.csv) for third-party Gantt chart visualization (completed 2026-05-19)
  - **Goal:** Export existing treatment episode and episode detail RDS artifacts as two universal CSV files (gantt_episodes.csv and gantt_detail.csv) for third-party Gantt chart visualization
  - **Requirements**: GANTT-01, GANTT-02
  - **Depends on:** Phase 44
  - **Plans:** 1 plan
  - Plans:
    - [x] 48-01-PLAN.md — Create R/49_gantt_data_export.R: load RDS artifacts, validate columns, write gantt_episodes.csv (bars) and gantt_detail.csv (ticks)
- [x] **Phase 49: Add descriptions of codes to the Gantt CSVs** — Enrich gantt_episodes.csv and gantt_detail.csv with human-readable code descriptions (completed 2026-05-22)
  - **Goal:** Enrich gantt_episodes.csv and gantt_detail.csv with human-readable code descriptions by building a static code-to-description lookup from Phase 39-41 RDS artifacts, R/45 hardcoded descriptions, and R/00_config.R inline comments
  - **Requirements**: GDESC-01, GDESC-02, GDESC-03
  - **Depends on:** Phase 48
  - **Plans:** 1 plan
  - Plans:
    - [x] 49-01-PLAN.md — Build code_descriptions.rds lookup (R/48) + add description columns to both Gantt CSVs (R/49)
- [x] **Phase 50: Confirm cancer site codes by distinct date count** — Validate cancer site diagnosis codes by requiring 2+ distinct dates per code per patient (completed 2026-05-20)
  - **Goal:** Validate cancer site diagnosis codes from the DIAGNOSIS table by requiring 2+ distinct dates per code per patient before counting as "confirmed," producing a styled two-sheet xlsx comparing total vs confirmed counts at exact-code and 3-character prefix levels
  - **Requirements**: CCONF-01, CCONF-02, CCONF-03, CCONF-04
  - **Depends on:** Phase 49
  - **Plans:** 1 plan
  - Plans:
    - [x] 50-01-PLAN.md — Create R/50_cancer_site_confirmation.R: DIAGNOSIS query with DX_DATE, 2-date confirmation at exact-code and prefix levels, styled two-sheet xlsx output
- [x] **Phase 51: Confirm cancer site codes with 7-day separation** — Validate cancer site diagnosis codes using a 7-day temporal separation requirement (completed 2026-05-20)
  - **Goal:** Validate cancer site diagnosis codes using a 7-day temporal separation requirement (max date - min date >= 7 days per code per patient), producing a standalone styled xlsx with exact-code and prefix-level confirmation sheets for side-by-side comparison with Phase 50 output
  - **Requirements**: C7DAY-01, C7DAY-02, C7DAY-03, C7DAY-04
  - **Depends on:** Phase 50
  - **Plans:** 1 plan
  - Plans:
    - [x] 51-01-PLAN.md — Clone R/50 to R/51_cancer_site_confirmation_7day.R with 7-day gap filter replacing 2-date count filter, styled two-sheet xlsx output
- [x] **Phase 52: all_codes_resolved.xlsx update** — Regenerate all_codes_resolved.xlsx from current config with DuckDB counts (completed 2026-05-20)
  - **Goal:** Regenerate all_codes_resolved.xlsx and 5 per-type resolved xlsx files from current R/00_config.R TREATMENT_CODES with DuckDB patient/record counts, multi-source description cascade, and config comment curation
  - **Requirements**: RESOLVE-01, RESOLVE-02, RESOLVE-03, RESOLVE-04, RESOLVE-05, RESOLVE-06
  - **Depends on:** Phase 51
  - **Plans:** 1 plan
  - Plans:
    - [x] 52-01-PLAN.md — Create R/52_all_codes_resolved.R: config-driven code extraction, DuckDB count queries, description cascade, config comment curation, all_codes_resolved.xlsx (6 sheets) + 5 per-type xlsx files
- [x] **Phase 53: Make dataset that produces cancer_summary_template.xlsx** — Create patient-code level cancer summary dataset (completed 2026-05-20)
  - **Goal:** Create R/53_cancer_summary.R that produces a patient-code level dataset from the DIAGNOSIS table with date-based confirmation metrics (2+ distinct dates, 7-day gap), outputting cancer_summary.xlsx and cancer_summary.csv to output/tables/
  - **Requirements**: CSUM-01, CSUM-02, CSUM-03, CSUM-04
  - **Depends on:** Phase 52
  - **Plans:** 1 plan
  - Plans:
    - [x] 53-01-PLAN.md — Create R/53_cancer_summary.R: DIAGNOSIS query, PREFIX_MAP classification, patient-code aggregation with date metrics, description cascade, minimal xlsx + CSV output
- [x] **Phase 54: Summary table of cancer_summary data** — Aggregate patient-code level data into category-level and code-level summaries (completed 2026-05-22)
  - **Goal:** Create R/54_cancer_summary_table.R that aggregates the Phase 53 patient-code level cancer_summary dataset into category-level and code-level summaries with patient counts, confirmation rates, date distribution stats, and DuckDB record counts, outputting a styled two-sheet cancer_summary_table.xlsx
  - **Requirements**: D-01, D-02, D-03, D-04, D-05, D-06, D-07, D-08, D-09, D-10, D-11, D-12, D-13, D-14, D-15
  - **Depends on:** Phase 53
  - **Plans:** 1 plan
  - Plans:
    - [x] 54-01-PLAN.md — Create R/54_cancer_summary_table.R: load cancer_summary.csv, DuckDB record count query, category + code aggregation, styled two-sheet xlsx output

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
| 55-57 | v1.7 | Not started | -- |

## Phase Details

### Phase 55: Cancer Summary Refinement Foundation

**Goal:** Cancer summary table excludes benign D-codes and is regenerated for a validated HL cohort confirmed by 2+ diagnosis codes at least 7 days apart, with first HL diagnosis date computed from both DIAGNOSIS and TUMOR_REGISTRY sources

**Depends on:** Phase 54

**Requirements:** CREF-01, CREF-02, CREF-03

**Success Criteria** (what must be TRUE):
1. Cancer summary table contains only malignant C-codes (benign D10-D48 codes excluded from all outputs)
2. Cohort is filtered to patients with at least 2 HL diagnosis codes separated by 7+ days
3. Each confirmed HL patient has a first_hl_dx_date computed as the minimum date across both DIAGNOSIS and TUMOR_REGISTRY tables
4. Cancer summary table Column F (Hodgkin Lymphoma %) reaches 100% after cohort confirmation
5. First HL diagnosis source is logged (DIAGNOSIS only, TR only, or Both) for traceability

**Plans:** 1/1 plans complete

Plans:
- [x] 55-01-PLAN.md -- Create R/55_cancer_summary_refined.R: D-code removal, C81 cohort confirmation, first_hl_dx_date computation, styled xlsx regeneration, confirmed_hl_cohort.rds artifact

### Phase 56: Temporal Filtering

**Goal:** Cancer summary table is produced in two versions (all cancers and post-HL cancers) to enable comparison of cancer burden before and after first HL diagnosis

**Depends on:** Phase 55

**Requirements:** CREF-04

**Success Criteria** (what must be TRUE):
1. Baseline cancer summary outputs (cancer_summary.csv and cancer_summary_table.xlsx) remain unchanged for reproducibility
2. New post-HL variant outputs (cancer_summary_post_hl.csv and cancer_summary_table_post_hl.xlsx) are produced with DX_DATE > first_hl_dx_date filter applied
3. Post-HL variant is clearly labeled as EXPLORATORY to indicate potential immortal time bias
4. Side-by-side comparison shows denominator differences (how many patients/cancers excluded by temporal filter)

**Plans:** 1/1 plans complete

Plans:
- [x] 56-01-PLAN.md -- Create R/56_cancer_summary_post_hl.R: DuckDB DIAGNOSIS query, temporal filter (DX_DATE > first_hl_dx_date), re-aggregation, EXPLORATORY-labeled xlsx outputs, Comparison sheet

### Phase 57: Gantt Enhancements

**Goal:** Gantt chart data includes cancer category labels and is_hodgkin flags for each treatment episode, plus death dates as a clinical endpoint for timeline visualization

**Depends on:** Phase 55

**Requirements:** GANTT-01, GANTT-02, GANTT-03

**Success Criteria** (what must be TRUE):
1. Each treatment episode row in gantt_episodes.csv and gantt_detail.csv has a cancer_category column derived from the CancerSiteCategories mapping (D-codes excluded)
2. Each episode row has an is_hodgkin binary column (TRUE when cancer_category equals "Hodgkin Lymphoma")
3. Death dates from DEATH table are added to Gantt CSVs as pseudo-treatment rows (treatment_type = "Death")
4. Death dates undergo the same 1900 sentinel date nullification as diagnosis dates
5. Multi-cancer episodes show all applicable cancer categories (comma-separated or primary category with flag for multiple)

**Plans:** 1 plan

Plans:
- [ ] 57-01-PLAN.md -- Modify R/00_config.R + R/01_load_pcornet.R (DEATH table infrastructure) + R/49_gantt_data_export.R (cancer categories, is_hodgkin, death pseudo-treatment rows)

---
*Last updated: 2026-05-23 -- v1.7 Phase 57 planned*
