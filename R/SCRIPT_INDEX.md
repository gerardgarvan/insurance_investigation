# R Script Index

> **Documentation Status (Phase 69):** All 87 scripts (69 numbered + 10 utils + 8 archived) have standardized
> 5-field headers (Purpose, Inputs, Outputs, Dependencies, Requirements) per DOC-01. All 69
> numbered scripts have RStudio-compatible section headers (DOC-02). WHY comments added for
> clinical and business logic (DOC-03). Completed 2026-06-01.

Quick-reference map of all R scripts in this directory, grouped by functional area.
**Sources** column shows which scripts are loaded via `source()` at runtime.

---

## Foundation (00-03)

Foundation scripts that load data, harmonize payer categories, and provide DuckDB ingest.

| Script | Purpose | Sources |
|--------|---------|---------|
| 00_config.R | Project-wide configuration: data paths, ICD code lists, payer mapping rules, treatment codes, analysis parameters. Auto-sources all R/utils/*.R utility modules via list.files(). | (auto-sources all 10 R/utils/ modules) |
| 01_load_pcornet.R | Load 13 PCORnet CDM CSV tables with explicit column types into a named list (`pcornet$ENROLLMENT`, etc.) | 00_config |
| 02_harmonize_payer.R | AMC 8-category payer mapping from raw PAYER_TYPE codes. Produces patient-level payer summary. | 01_load_pcornet |
| 03_duckdb_ingest.R | Ingest 13 PCORnet tables from RDS cache into DuckDB with atomic write (renumbered from 25 in Phase 65) | 00_config, utils/utils_duckdb |

## Cohort Building (10-14)

Named filter predicates and cohort assembly pipeline.

| Script | Purpose | Sources |
|--------|---------|---------|
| 10_cohort_predicates.R | Named filter predicates (`has_*`, `with_*`, `exclude_*`) for HL cohort building. Also defines treatment flag functions. | (loaded via 00_config dependency chain) |
| 11_treatment_payer.R | Treatment-anchored payer mode within +/-30 day window around first treatment date | (sourced by 14_build_cohort) |
| 12_surveillance.R | Surveillance modality detection: 9 procedure-based + 10 lab-based post-diagnosis events | (sourced by 14_build_cohort) |
| 13_survivorship_encounters.R | 4-level survivorship encounter classification (non-acute, cancer-related, cancer provider, survivorship provider) | (sourced by 14_build_cohort) |
| 14_build_cohort.R | Compose predicates into sequential filter chain, add treatment flags, calculate ages, assemble final HL cohort. | 02_harmonize_payer, 10_cohort_predicates, 11_treatment_payer, 12_surveillance, 13_survivorship_encounters |

## Treatment Analysis (20-29)

Treatment inventory, duration, episodes, drug resolution, and first-line therapy identification.

| Script | Purpose | Sources |
|--------|---------|---------|
| 20_treatment_inventory.R | Treatment inventory by source table: code frequencies across 7 PCORnet tables for 4 treatment types | 00_config, 01_load_pcornet |
| 21_investigate_unmatched.R | Investigate unmatched CPT/HCPCS codes via NLM HCPCS API, auto-classify, produce xlsx report | 00_config, 01_load_pcornet |
| 22_investigate_unmatched_ndc.R | Investigate unmatched NDC/RXNORM drug codes via RxNorm API, auto-classify | 00_config, 01_load_pcornet |
| 23_combine_reports.R | Merge Phase 39 (CPT/HCPCS) and Phase 40 (NDC/RXNORM) unmatched code reports into consolidated xlsx | 00_config |
| 24_treatment_codes_resolved.R | Create per-treatment-type resolved xlsx files (Radiation, SCT, Immunotherapy, Supportive Care) | 00_config |
| 25_treatment_durations.R | Extract treatment dates from 7 PCORnet tables, calculate per-patient duration metrics (span, date count, episodes) | 00_config, 01_load_pcornet |
| 26_treatment_episodes.R | Per-episode start/stop dates with episode length, historical date flagging, triggering codes | 00_config, 01_load_pcornet, 25_treatment_durations |
| 27_drug_name_resolution.R | Drug name resolution for chemotherapy via RxNorm API (chemotherapy only) | 00_config, utils/utils_duckdb |
| 28_episode_classification.R | Episode-level cancer linkage (ENCOUNTERID + 30-day temporal fallback) with regimen detection (ABVD/BV+AVD/Nivo+AVD) | 00_config, utils/utils_duckdb, utils/utils_dates |
| 29_first_line_and_death_analysis.R | First-line therapy flagging (60-day clean period) and death date validation | 00_config, utils/utils_duckdb, utils/utils_dates |

## Cancer Site Analysis (40-53)

Cancer code classification, site confirmation, Gantt export, and death date validation.

| Script | Purpose | Sources |
|--------|---------|---------|
| 40_cancer_site_frequency.R | Classify every cancer code in the data using ICD-10 prefix rules; patient/record counts per category | 00_config, 01_load_pcornet |
| 41_extract_all_codes.R | Extract all unique ICD-10 diagnosis and ICD-O-3 topography codes from data with counts | 00_config, 01_load_pcornet |
| 42_build_code_descriptions.R | Build static named character vector mapping treatment codes to human-readable descriptions from 4 sources | 00_config |
| 43_cancer_site_confirmation.R | Confirm cancer site codes by requiring 2+ distinct diagnosis dates per code per patient | 00_config, 01_load_pcornet |
| 44_cancer_site_confirmation_7day.R | Confirm cancer site codes requiring diagnosis dates at least 7 calendar days apart | 00_config, 01_load_pcornet |
| 45_cancer_summary.R | Cancer summary dataset: patient-code level with date-based confirmation metrics | 00_config, 01_load_pcornet |
| 46_cancer_summary_table.R | Cancer summary table: category-level and code-level aggregation with styled xlsx output | 00_config, 01_load_pcornet |
| 47_cancer_summary_refined.R | Refined cancer summary: remove D-codes, enforce HL cohort confirmation, compute first HL diagnosis date | 00_config, 01_load_pcornet |
| 48_cancer_summary_post_hl.R | Cancer summary filtered to diagnoses after first HL diagnosis (exploratory temporal analysis) | 00_config, 01_load_pcornet |
| 49_cancer_summary_pre_post.R | Cancer summary with pre/post HL diagnosis counts per code (temporal partition analysis) | 00_config, 01_load_pcornet |
| 50_all_codes_resolved.R | Regenerate all_codes_resolved.xlsx with current TREATMENT_CODES, patient counts, and multi-source descriptions | 00_config |
| 51_gantt_data_export.R | Gantt chart CSV export with human-readable code descriptions (v1 schema) | 00_config, utils/utils_duckdb, utils/utils_dates |
| 52_gantt_v2_export.R | Gantt v2 CSV export with encounter-level cancer categories, regimen labels, first-line flags | 00_config, utils/utils_duckdb, utils/utils_dates |
| 53_death_date_validation.R | Death date validation with impossible death exclusion and HL Diagnosis pseudo-treatment rows | 00_config, utils/utils_duckdb, utils/utils_dates |

## Payer & QA (60-69)

Payer tiering, missingness analysis, multi-source overlap detection, and value audit.

| Script | Purpose | Sources |
|--------|---------|---------|
| 60_tiered_same_day_payer.R | Tiered same-day payer categorization with AMC 8-category hierarchy (all + AV+TH scopes) | 00_config |
| 61_tiered_encounter_level.R | Assign AMC 8-category payer tiers to every individual encounter (no same-day collapsing) | 00_config |
| 62_tiered_date_level.R | Expand treatment episodes to daily rows and assign payer tier per patient+date with 3-tier fill cascade | 00_config |
| 63_value_audit.R | Comprehensive value audit: every distinct value for every column in every PCORnet table | 01_load_pcornet |
| 64_all_source_missingness.R | All-source payer missingness: extends Phase 19 UFH analysis to all 5 partner sites | 02_harmonize_payer |
| 65_uf_insurance_missingness.R | UFH-specific payer data missingness diagnostic by year, encounter type | 02_harmonize_payer |
| 66_all_site_duplicate_dates.R | All-site duplicate date investigation: extends Phase 20 FLM analysis to all sites | 00_config |
| 67_multi_source_overlap_detection.R | Detect same-date and same-week encounter pairs from different ENCOUNTER.SOURCE values (all encounter types) | 00_config |
| 68_overlap_classification.R | Classify multi-source encounter groups (same-date/same-week) as Identical, Partial, or Distinct with per-site recommendations | 00_config |
| 69_per_patient_source_detection.R | Per-patient source detection by date: which SOURCE values present on each patient-date | 00_config |

## Output & Visualization (70-75)

Visualizations, PowerPoint presentations, and documentation generation.

| Script | Purpose | Sources |
|--------|---------|---------|
| 70_visualize_waterfall.R | Attrition waterfall chart showing cohort reduction through filter steps (VIZ-01) | 14_build_cohort |
| 71_visualize_sankey.R | Payer-stratified Sankey/alluvial diagram: Payer Category to Treatment Type (VIZ-02) | 14_build_cohort |
| 72_generate_pptx.R | Generate insurance tables PowerPoint (52-slide deck with encounter analysis, payer missingness, duplicates) | utils_pptx, 75_encounter_analysis |
| 73_generate_phase19_20_pptx.R | Standalone PowerPoint deck for Phases 19 (UF missingness) and 20 (FLM duplicates) | utils_pptx, 94_flm_duplicate_dates |
| 74_generate_documentation.R | Auto-generate variable documentation (.md + .docx) from config code lists | 00_config |
| 75_encounter_analysis.R | Encounter analysis by payer, DX year, age group (histograms and summary tables) | 14_build_cohort |

## Testing (80-89)

Backend parity tests, cohort benchmarks, treatment verification, and smoke tests.

| Script | Purpose | Sources |
|--------|---------|---------|
| 80_smoke_test_backends.R | Backend parity smoke test: run 6 predicates on RDS vs DuckDB with 100-patient sample | 00_config, 01_load_pcornet, 02_harmonize_payer, 10_cohort_predicates |
| 81_parity_test_cohort.R | Full cohort build parity verification: RDS vs DuckDB using waldo::compare() | 00_config, 01_load_pcornet, 14_build_cohort |
| 82_benchmark_cohort.R | RDS vs DuckDB cohort build benchmark: 3 runs per backend, median comparison | 00_config, 01_load_pcornet |
| 83_generate_speedup_report.R | Generate DuckDB vs RDS speedup report from benchmark CSV | 00_config |
| 84_test_durations.R | Verification script: clinical plausibility checks, structural validation, anomaly detection for treatment_durations.rds | 00_config, 25_treatment_durations |
| 85_test_episodes.R | Verification script: structural, data quality, historical flag, clinical plausibility checks for treatment_episodes.rds | 00_config, 26_treatment_episodes |
| 86_smoke_test_foundation.R | Validates Phase 65 foundation reorganization (utils subfolder, script renumbering, source references) | 00_config |
| 87_smoke_test_full_pipeline.R | Validates Phase 66 complete reorganization (outputs, tests, ad-hoc decades) and Phase 67 cleanup (87 in test decade, 10 payer scripts, archive created) | (standalone) |
| 88_smoke_test_comprehensive.R | Comprehensive structural smoke test: consolidates R/86+R/87 checks plus DRY validation, config constants, defensive coding infrastructure, cross-platform data gating | 00_config |
| 89_generate_reference_manual.R | Auto-generate docs/REFERENCE_MANUAL.md by parsing script headers into dependency matrix | (standalone) |

## Ad-hoc & Diagnostics (90-99)

Standalone diagnostic and analysis scripts, not part of the numbered pipeline sequence.

| Script | Purpose | Sources |
|--------|---------|---------|
| 90_diagnostics.R | Reusable data quality diagnostic tool: date parsing audit, column detection, missing values, HL identification, payer mapping audit | 01_load_pcornet |
| 91_data_quality_summary.R | Data quality resolution tracker: before/after counts for each issue type | 01_load_pcornet |
| 92_dx_gap_analysis.R | Diagnosis gap analysis for excluded "Neither" patients (no HL evidence) | 01_load_pcornet |
| 93_no_treatment_medicaid.R | Profile patients with Medicaid + no treatment evidence | (depends on 14_build_cohort environment) |
| 94_flm_duplicate_dates.R | FLM duplicate date investigation: same-date duplicate encounters, payer completeness | 00_config, 01_load_pcornet |
| 95_multi_source_overlap_av_th.R | Multi-source overlap detection for AV+TH encounters only | 00_config |
| 96_overlap_classification_av_th.R | Overlap classification and recommendations for AV+TH encounters | 00_config, 95_multi_source_overlap_av_th |
| 97_payer_code_frequency_av_th.R | Payer code frequency summary (AV+TH only) cross-referenced against PayerVariable.xlsx | 00_config |
| 98_radiation_cpt_audit.R | Audit full CPT 70010-79999 radiology range to justify pipeline's narrow radiation code set | 00_config, 01_load_pcornet |
| 99_claude_diagnostics.R | Generate comprehensive data profile text file for Claude (row counts, column types, cardinality, payer distribution) | 00_config, 01_load_pcornet, 14_build_cohort |

---

## Post-Renumber Investigations (100+)

Standalone investigation scripts added after the 00-99 decade-based renumbering (Phase 66). These sit outside the decade scheme intentionally.

| Script | Purpose | Phase |
|--------|---------|-------|
| `R/100_ruca_rurality_summary.R` | USDA 2020 ZIP RUCA rurality classification of the HL cohort. Produces a 4-sheet styled xlsx: (1) patient-level rurality frequency, (2) rurality x AMC 8-category payer (encounter-level), (3) rurality x treatment type (encounter-level), (4) rurality x cancer category (episode-level). Bundles the USDA reference xlsx in `data/reference/RUCA-codes-2020-zipcode.xlsx`. | 116 |
| `R/101_gantt_lifespan_collapse.R` | Collapses the per-episode Gantt export (`output/gantt_episodes.csv`) into a "lifespan" CSV: one row per patient x treatment type spanning that patient's earliest episode_start to latest episode_stop (calendar dates preserved, not normalized). Multi-value metadata is unioned/deduped/sorted (reuses R/52 `clean_multi_value`). Death and HL Diagnosis pseudo-rows excluded. Output: `output/gantt_lifespan.csv` for Tableau. | 117 |
| `R/102_death_cause_nhl_flag.R` | Writes output/death_cause_nhl_flag.csv: one row per deceased patient (valid DEATH_DATE) with PATID and a three-state cause_of_death_is_nhl flag (TRUE = NHL cause of death, FALSE = other coded cause, blank = uncoded). NHL determined via classify_codes() == "Non-Hodgkin Lymphoma". (Phase 119: source corrected to read the separate DEATH_CAUSE table instead of the empty DEATH.DEATH_CAUSE column) | 118, 119 |
| `R/103_death_cause_diagnostic.R` | Read-only Phase 119 diagnostic: inventories every candidate cause-of-death source (DEATH_CAUSE table, TUMOR_REGISTRY1.CAUSE_OF_DEATH, TR2/TR3.DCAUSE) restricted to the deceased patient set — reports non-null counts, deceased-set coverage, sample values, and classify_codes() NHL matches, plus a recommendation. Writes output/diagnostics/death_cause_source_inventory.csv. | 119 |
| `R/104_gantt_entire_history.R` | Projects output/gantt_lifespan.csv into gantt_entire_history.csv (repo root) with 6 columns: patient_id, treatment_type, treatment_start (renamed from episode_start), treatment_stop (renamed from episode_stop), drug_names, and cancer_7day_confirmed. The 7-day cancer column is RE-DERIVED as the union directly from output/gantt_episodes.csv (grouped by patient_id x treatment_type after excluding Death + HL Diagnosis) and asserted (non-fatally) against lifespan's own column. Reuses R/101 clean_multi_value/union_field; blank-safe read/write (na=""). | quick-260710-i1e |
| `R/105_normalize_supportive_care_meaning.R` | Resolves each Supportive Care RXNORM code to its RxNorm IN generic ingredient via RxNav (`related.json?tty=IN`, historystatus fallback for retired codes, rule-based canonicalize_drug_name fallback for misses), caches to `data/reference/rxnorm_ingredient_cache.csv`, and appends a `Normalized Meaning` column (col G) to the Supportive Care tab of `all_codes_resolved_next_tables_v2.1.xlsx` in place (combos kept as sorted "/"-joined labels). | 120 |
| `R/106_zip_change_frequency.R` | Read-only Phase 121 investigation: probes for LDS_ADDRESS_HISTORY (the only CDM table with a time-varying 9-digit ZIP), and if present quantifies per-patient ZIP change frequency at BOTH ZIP9 and ZIP5 granularity — distinct-ZIP distribution, % ever-changed (incl. ZIP9-change-only), time-between-changes (from ADDRESS_PERIOD_START), and most-recent-vs-modal tie-break disagreement rate. Produces a 5-sheet styled xlsx (`output/zip_change_frequency.xlsx`) + console summary to inform the downstream SES-index (ADI/SVI) ZIP-handling decision. Reads the CSV directly by path (not in PCORNET_TABLES); exits gracefully if absent. | 121 |

---

## Utility Libraries

Sourced by 00_config.R (auto-loaded via list.files() from R/utils/ subfolder). These define reusable functions, not standalone analyses.

| Script | Purpose | Auto-sourced by |
|--------|---------|-----------------|
| utils/utils_assertions.R | Checkmate-based defensive coding helpers (assert_rds_exists, assert_df_valid, assert_col_types, warn_date_range, warn_row_count) | 00_config |
| utils/utils_attrition.R | Attrition logging for cohort construction (init_attrition_log, log_attrition) | 00_config |
| utils/utils_cancer.R | Cancer site classification using CANCER_SITE_MAP (classify_codes) | 00_config |
| utils/utils_dates.R | Multi-format date parsing for PCORnet CDM data (parse_pcornet_date) | 00_config |
| utils/utils_duckdb.R | DuckDB utility functions: get_pcornet_table(), connection management, materialization | 00_config |
| utils/utils_icd.R | ICD code normalization and HL diagnosis matching (normalize_icd, is_hl_diagnosis) | 00_config |
| utils/utils_payer.R | Shared payer classification and comparison helpers (is_missing_payer, classify_payer_tier) | 00_config |
| utils/utils_pptx.R | PowerPoint styling and slide generation helpers (UF brand colors, table styling) | 72_generate_pptx, 73_generate_phase19_20_pptx |
| utils/utils_snapshot.R | Snapshot helper for consistent RDS output creation (save_output_data, build_output_path) | 00_config |
| utils/utils_treatment.R | Shared treatment analysis helpers (safe_table, get_hl_patient_ids, empty_result) | 00_config |

---

## Archived Scripts

**All unnumbered scripts archived to R/archive/ (Phase 67).**

See `R/archive/README.md` for details on 8 archived scripts:
- check_deleted_proton_code.R
- date_range_check.R
- payer_frequency_from_resolved.R
- run_phase12_outputs.R
- sct_code_inventory.R
- search_C8190.R
- tiered_payer_summary.R
- treatment_cross_reference.R

These scripts represent one-off investigations, superseded implementations, or environment-specific orchestration helpers. They are preserved for reference but are no longer part of the active pipeline.

---

## Script Count

- **Numbered pipeline scripts:**
  - Foundation (00-03): 4
  - Cohort (10-14): 5
  - Treatment (20-29): 10
  - Cancer (40-53): 14
  - Payer/QA (60-69): 10
  - Outputs (70-75): 6
  - Tests (80-89): 10
  - Ad-hoc (90-99): 10
  - **Total numbered:** 69
- **Post-renumber investigations (100+):** 7 (R/100 RUCA, R/101 Gantt lifespan, R/102 death-cause NHL flag, R/103 death-cause diagnostic, R/104 Gantt entire-history, R/105 Supportive Care Normalized Meaning, R/106 ZIP change frequency)
- **Utility libraries:** 10 (in R/utils/ subfolder)
- **Archived scripts:** 8 (in R/archive/ directory)
- **Total:** 93

## Key Dependency Chains

```
00_config -> utils/*.R (auto-sourced via list.files(): 10 modules)
01_load_pcornet -> 00_config
02_harmonize_payer -> 01_load_pcornet
03_duckdb_ingest -> 00_config, utils/utils_duckdb
10_cohort_predicates -> (via 00_config)
14_build_cohort -> 02_harmonize_payer, 10_cohort_predicates, 11_treatment_payer, 12_surveillance, 13_survivorship_encounters
70_visualize_waterfall -> 14_build_cohort
71_visualize_sankey -> 14_build_cohort
25_treatment_durations -> 00_config, 01_load_pcornet
26_treatment_episodes -> 00_config, 01_load_pcornet, 25_treatment_durations
72_generate_pptx -> utils/utils_pptx, 75_encounter_analysis
75_encounter_analysis -> 14_build_cohort
73_generate_phase19_20_pptx -> utils/utils_pptx, 94_flm_duplicate_dates
```
