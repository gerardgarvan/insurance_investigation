# R Script Index

Quick-reference map of all R scripts in this directory, grouped by functional area.
**Sources** column shows which scripts are loaded via `source()` at runtime.

---

## Core Pipeline (00-04)

Foundation scripts that load data, harmonize payer categories, define cohort predicates, and build the HL cohort.

| Script | Purpose | Sources |
|--------|---------|---------|
| 00_config.R | Project-wide configuration: data paths, ICD code lists, payer mapping rules, treatment codes, analysis parameters. Auto-sources all R/utils/*.R utility modules via list.files(). | (auto-sources all 8 R/utils/ modules) |
| 01_load_pcornet.R | Load 13 PCORnet CDM CSV tables with explicit column types into a named list (`pcornet$ENROLLMENT`, etc.) | 00_config |
| 02_harmonize_payer.R | AMC 8-category payer mapping from raw PAYER_TYPE codes. Produces patient-level payer summary. | 01_load_pcornet |
| 03_duckdb_ingest.R | Ingest 13 PCORnet tables from RDS cache into DuckDB with atomic write (renumbered from 25 in Phase 65) | 00_config, utils/utils_duckdb |
| 03_cohort_predicates.R | Named filter predicates (`has_*`, `with_*`, `exclude_*`) for HL cohort building. Also defines treatment flag functions. | (loaded via 00_config dependency chain) |
| 04_build_cohort.R | Compose predicates into sequential filter chain, add treatment flags, calculate ages, assemble final HL cohort. | 02_harmonize_payer, 03_cohort_predicates, 10_treatment_payer, 13_surveillance, 14_survivorship_encounters |

## Visualization (05-06)

| Script | Purpose | Sources |
|--------|---------|---------|
| 05_visualize_waterfall.R | Attrition waterfall chart showing cohort reduction through filter steps (VIZ-01) | 04_build_cohort |
| 06_visualize_sankey.R | Payer-stratified Sankey/alluvial diagram: Payer Category to Treatment Type (VIZ-02) | 04_build_cohort |

## Diagnostics & Data Quality (07-09)

| Script | Purpose | Sources |
|--------|---------|---------|
| 07_diagnostics.R | Reusable data quality diagnostic tool: date parsing audit, column detection, missing values, HL identification, payer mapping audit | 01_load_pcornet |
| 08_data_quality_summary.R | Data quality resolution tracker: before/after counts for each issue type | 01_load_pcornet |
| 09_dx_gap_analysis.R | Diagnosis gap analysis for excluded "Neither" patients (no HL evidence) | 01_load_pcornet |

## Treatment & Encounter Analysis (10-16)

| Script | Purpose | Sources |
|--------|---------|---------|
| 10_treatment_payer.R | Treatment-anchored payer mode within +/-30 day window around first treatment date | (sourced by 04_build_cohort) |
| 11_generate_pptx.R | Generate insurance tables PowerPoint (15-slide deck matching Python pipeline output) | utils_pptx, 16_encounter_analysis |
| 12_no_treatment_medicaid.R | Profile patients with Medicaid + no treatment evidence | (depends on 04_build_cohort environment) |
| 13_surveillance.R | Surveillance modality detection: 9 procedure-based + 10 lab-based post-diagnosis events | (sourced by 04_build_cohort) |
| 14_survivorship_encounters.R | 4-level survivorship encounter classification (non-acute, cancer-related, cancer provider, survivorship provider) | (sourced by 04_build_cohort) |
| 15_generate_documentation.R | Auto-generate variable documentation (.md + .docx) from config code lists | 00_config |
| 16_encounter_analysis.R | Encounter analysis by payer, DX year, age group (histograms and summary tables) | 04_build_cohort |

## Value & Missingness Audits (17-21)

| Script | Purpose | Sources |
|--------|---------|---------|
| 17_value_audit.R | Comprehensive value audit: every distinct value for every column in every PCORnet table | 01_load_pcornet |
| 18_uf_insurance_missingness.R | UFH-specific payer data missingness diagnostic by year, encounter type | 02_harmonize_payer |
| 19_flm_duplicate_dates.R | FLM duplicate date investigation: same-date duplicate encounters, payer completeness | 00_config |
| 20_all_source_missingness.R | All-source payer missingness: extends Phase 19 UFH analysis to all 5 partner sites | 02_harmonize_payer |
| 21_all_site_duplicate_dates.R | All-site duplicate date investigation: extends Phase 20 FLM analysis to all sites | 00_config |

## Multi-Source Overlap Detection (22-24)

| Script | Purpose | Sources |
|--------|---------|---------|
| 22a_multi_source_overlap_detection.R | Detect same-date and same-week encounter pairs from different ENCOUNTER.SOURCE values (all encounter types) | 00_config |
| 22b_generate_phase19_20_pptx.R | Standalone PowerPoint deck for Phases 19 (UF missingness) and 20 (FLM duplicates) | utils_pptx |
| 23_overlap_classification.R | Classify multi-source encounter groups as Identical/Partial/Distinct with per-site recommendations | 00_config |
| 24_per_patient_source_detection.R | Per-patient source detection by date: which SOURCE values present on each patient-date | 00_config |

## DuckDB Backend Testing (26-29)

| Script | Purpose | Sources |
|--------|---------|---------|
| 26_smoke_test_backends.R | Backend parity smoke test: run 6 predicates on RDS vs DuckDB with 100-patient sample | 00_config, 01_load_pcornet, 02_harmonize_payer, 03_cohort_predicates |
| 27_parity_test_cohort.R | Full cohort build parity verification: RDS vs DuckDB using waldo::compare() | 00_config, 01_load_pcornet, 04_build_cohort |
| 28_benchmark_cohort.R | RDS vs DuckDB cohort build benchmark: 3 runs per backend, median comparison | 00_config, 01_load_pcornet |
| 29_generate_speedup_report.R | Generate DuckDB vs RDS speedup report from benchmark CSV | 00_config |

## AV+TH Overlap & Payer Frequency (33-36)

| Script | Purpose | Sources |
|--------|---------|---------|
| 33_multi_source_overlap_av_th.R | Multi-source overlap detection for AV+TH encounters only | 00_config |
| 34_overlap_classification_av_th.R | Overlap classification and recommendations for AV+TH encounters | 00_config |
| 35_payer_code_frequency_av_th.R | Payer code frequency summary (AV+TH only) cross-referenced against PayerVariable.xlsx | 00_config |
| 36_tiered_same_day_payer.R | Tiered same-day payer categorization with AMC 8-category hierarchy (all + AV+TH scopes) | 00_config |

## Treatment Inventory & Code Investigation (38-42)

| Script | Purpose | Sources |
|--------|---------|---------|
| 38_treatment_inventory.R | Treatment inventory by source table: code frequencies across 7 PCORnet tables for 4 treatment types | 00_config, 01_load_pcornet |
| 39_investigate_unmatched.R | Investigate unmatched CPT/HCPCS codes via NLM HCPCS API, auto-classify, produce xlsx report | 00_config, 01_load_pcornet |
| 40_investigate_unmatched_ndc.R | Investigate unmatched NDC/RXNORM drug codes via RxNorm API, auto-classify | 00_config, 01_load_pcornet |
| 41_combine_reports.R | Merge Phase 39 (CPT/HCPCS) and Phase 40 (NDC/RXNORM) unmatched code reports into consolidated xlsx | 00_config |
| 42_treatment_codes_resolved.R | Create per-treatment-type resolved xlsx files (Radiation, SCT, Immunotherapy, Supportive Care) | 00_config |

## Treatment Duration & Episodes (43-44)

| Script | Purpose | Sources |
|--------|---------|---------|
| 43a_treatment_durations.R | Extract treatment dates from 7 PCORnet tables, calculate per-patient duration metrics (span, date count, episodes) | 00_config, 01_load_pcornet |
| 43b_test_durations.R | Verification script: clinical plausibility checks, structural validation, anomaly detection for treatment_durations.rds | 00_config |
| 44a_treatment_episodes.R | Per-episode start/stop dates with episode length, historical date flagging, triggering codes | 00_config, 01_load_pcornet, 43a_treatment_durations |
| 44b_test_episodes.R | Verification script: structural, data quality, historical flag, clinical plausibility checks for treatment_episodes.rds | 00_config |

## Payer Tiering (45-46)

| Script | Purpose | Sources |
|--------|---------|---------|
| 45a_tiered_encounter_level.R | Assign AMC 8-category payer tiers to every individual encounter (no same-day collapsing) | 00_config |
| 45b_radiation_cpt_audit.R | Audit full CPT 70010-79999 radiology range to justify pipeline's narrow radiation code set | 00_config, 01_load_pcornet |
| 46a_tiered_date_level.R | Expand treatment episodes to daily rows and assign payer tier per patient+date with 3-tier fill cascade | 00_config |
| 46b_treatment_cross_reference.R | Two-way gap report comparing reference document code lists against live TREATMENT_CODES config | 00_config, 01_load_pcornet |

## Cancer Site & Code Analysis (47-48)

| Script | Purpose | Sources |
|--------|---------|---------|
| 47_cancer_site_frequency.R | Classify every cancer code in the data using ICD-10 prefix rules; patient/record counts per category | 00_config, 01_load_pcornet |
| 48a_extract_all_codes.R | Extract all unique ICD-10 diagnosis and ICD-O-3 topography codes from data with counts | 00_config, 01_load_pcornet |
| 48b_build_code_descriptions.R | Build static named character vector mapping treatment codes to human-readable descriptions from 4 sources | 00_config |

## Gantt Chart & Cancer Confirmation (49-54)

| Script | Purpose | Sources |
|--------|---------|---------|
| 49_gantt_data_export.R | Combine treatment episode and detail RDS artifacts into two CSV files for Gantt chart visualization | 00_config |
| 50_cancer_site_confirmation.R | Confirm cancer site codes by requiring 2+ distinct diagnosis dates per code per patient | 00_config, 01_load_pcornet |
| 51_cancer_site_confirmation_7day.R | Confirm cancer site codes requiring diagnosis dates at least 7 calendar days apart | 00_config, 01_load_pcornet |
| 52_all_codes_resolved.R | Regenerate all_codes_resolved.xlsx with current TREATMENT_CODES, patient counts, and multi-source descriptions | 00_config |
| 53_cancer_summary.R | Cancer summary dataset: patient-code level with date-based confirmation metrics | 00_config, 01_load_pcornet |
| 54_cancer_summary_table.R | Cancer summary table: category-level and code-level aggregation with styled xlsx output | 00_config, 01_load_pcornet |

## Diagnostics (99)

| Script | Purpose | Sources |
|--------|---------|---------|
| 99_claude_diagnostics.R | Generate comprehensive data profile text file for Claude (row counts, column types, cardinality, payer distribution) | 00_config, 01_load_pcornet |

---

## Utility Libraries

Sourced by 00_config.R (auto-loaded via list.files() from R/utils/ subfolder). These define reusable functions, not standalone analyses.

| Script | Purpose | Auto-sourced by |
|--------|---------|-----------------|
| utils/utils_attrition.R | Attrition logging for cohort construction (init_attrition_log, log_attrition) | 00_config |
| utils/utils_dates.R | Multi-format date parsing for PCORnet CDM data (parse_pcornet_date) | 00_config |
| utils/utils_duckdb.R | DuckDB utility functions: get_pcornet_table(), connection management, materialization | 00_config |
| utils/utils_icd.R | ICD code normalization and HL diagnosis matching (normalize_icd, is_hl_diagnosis) | 00_config |
| utils/utils_payer.R | Shared payer classification and comparison helpers (is_missing_payer, etc.) | 00_config |
| utils/utils_pptx.R | PowerPoint styling and slide generation helpers (UF brand colors, table styling) | 11_generate_pptx, 22b_generate_phase19_20_pptx |
| utils/utils_snapshot.R | Snapshot helper for consistent RDS output creation (save_output_data) | 00_config |
| utils/utils_treatment.R | Shared treatment analysis helpers (safe_table, get_hl_patient_ids, empty_result) | 00_config |

---

## Reorganization & Smoke Tests (65+)

| Script | Purpose | Sources |
|--------|---------|---------|
| 65_smoke_test_foundation.R | Validates Phase 65 foundation reorganization (utils subfolder, script renumbering, source references) | 00_config |

---

## Ad-hoc / One-off Scripts

Standalone diagnostic or helper scripts, not part of the numbered pipeline sequence.

| Script | Purpose | Sources |
|--------|---------|---------|
| check_deleted_proton_code.R | Check for deleted proton CPT code 77521 in PROCEDURES table | 00_config, 01_load_pcornet |
| date_range_check.R | Quick diagnostic for earliest DIAGNOSIS and latest TUMOR_REGISTRY dates | 00_config |
| payer_frequency_from_resolved.R | Payer frequency table from 36_tiered_same_day_payer.R resolved detail CSV | (reads CSV directly) |
| run_phase12_outputs.R | HiPerGator execution helper: generate all Phase 12 outputs (4 PNGs + PPTX) | (orchestration script) |
| sct_code_inventory.R | SCT evidence: all codes from every PCORnet source table per patient per date | 00_config, 01_load_pcornet |
| tiered_payer_summary.R | Tiered payer summary styled xlsx from 36_tiered_same_day_payer.R CSV outputs | 00_config |

---

## Script Count

- **Numbered pipeline scripts:** 59 (00-54, 65, 99; includes a/b suffixed scripts)
- **Utility libraries:** 8 (in R/utils/ subfolder)
- **Ad-hoc scripts:** 6
- **Total:** 73

## Key Dependency Chains

```
00_config -> utils/*.R (auto-sourced via list.files(): 8 modules)
01_load_pcornet -> 00_config
02_harmonize_payer -> 01_load_pcornet
03_duckdb_ingest -> 00_config, utils/utils_duckdb (renumbered from 25 in Phase 65)
03_cohort_predicates -> (via 00_config)
04_build_cohort -> 02_harmonize_payer, 03_cohort_predicates, 10_treatment_payer, 13_surveillance, 14_survivorship_encounters
05_visualize_waterfall -> 04_build_cohort
06_visualize_sankey -> 04_build_cohort
43a_treatment_durations -> 00_config, 01_load_pcornet
44a_treatment_episodes -> 00_config, 01_load_pcornet, 43a_treatment_durations
```
