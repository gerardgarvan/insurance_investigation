# PCORnet Payer Variable Investigation -- Pipeline Reference Manual

> **Auto-generated** by `R/89_generate_reference_manual.R` on 2026-06-02.
> To regenerate: `Rscript R/89_generate_reference_manual.R`

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Dependency Matrix](#dependency-matrix)
3. [Utils Module Reference](#utils-module-reference)
4. [Run-Order Guide](#run-order-guide)
5. [Config Constants Reference](#config-constants-reference)
6. [Onboarding Guide](#onboarding-guide)

---

## Architecture Overview

### Decade-Based Organization

The pipeline uses a decade-based numbering system for logical organization:

- **00-09 Foundation:** Configuration, data loading, payer harmonization, DuckDB ingest
- **10-19 Cohort:** Named predicates, treatment-anchored payer, cohort building
- **20-29 Treatment:** Treatment inventory, episodes, drug resolution, first-line therapy
- **40-59 Cancer:** Cancer site classification, confirmation, Gantt export, death validation
- **60-69 Payer/QA:** Payer tiering, missingness analysis, multi-source overlap, value audit
- **70-79 Outputs:** Visualizations (waterfall, Sankey), PowerPoint presentations, documentation
- **80-89 Tests:** Backend parity tests, smoke tests, verification scripts
- **90-99 Ad-hoc:** Standalone diagnostics and one-off analysis tools

### Source Chain Pattern

The pipeline follows a consistent dependency pattern:

1. **R/00_config.R** is the root configuration script
2. It auto-sources all **R/utils/*.R** modules via `list.files()`
3. Downstream scripts source `00_config.R` to inherit all utilities and constants

This creates a clean dependency tree where every script has access to:
- Configuration constants (11 objects: CONFIG, ICD_CODES, PAYER_MAPPING, etc.)
- Utility functions (8 modules: dates, attrition, DuckDB, ICD, payer, PPTX, snapshot, treatment)

### Named Predicate Pattern

Cohort building uses human-readable named predicates (`has_*`, `with_*`, `exclude_*`) rather than opaque one-liners. This makes the filter chain read like a clinical protocol:

```r
cohort <- enrollment %>%
  has_florida_enrollment() %>%
  with_hl_diagnosis() %>%
  exclude_neither_source()
```

### Defensive Coding

All production scripts (decades 00-69) use checkmate assertions via **R/utils/utils_assertions.R** helper functions:

- `assert_rds_exists()`: File existence checks
- `assert_df_valid()`: Data frame structure validation
- `assert_col_types()`: Column type validation
- `warn_date_range()`: Date range warnings
- `warn_row_count()`: Row count sanity checks

All error messages follow the `[R/XX ACTION] message` format using `glue()` for context-rich diagnostics.

---

## Dependency Matrix

### Foundation (00-09)

| Script | Purpose | source() Deps | Inputs | Outputs | Config Constants Used |
|--------|---------|---------------|--------|---------|----------------------|
| 00_config.R | Not documented | Not documented | Not documented | Not documented | None |
| 01_load_pcornet.R | Not documented | Not documented | Not documented | Not documented | CONFIG, PCORNET_PATHS |
| 02_harmonize_payer.R | Not documented | Not documented | Not documented | Not documented | CONFIG, ICD_CODES, PAYER_MAPPING, AMC_PAYER_LOOKUP |
| 03_duckdb_ingest.R | Not documented | Not documented | Not documented | Not documented | CONFIG, EXTRACT_DATE, PCORNET_TABLES |

### Cohort (10-19)

| Script | Purpose | source() Deps | Inputs | Outputs | Config Constants Used |
|--------|---------|---------------|--------|---------|----------------------|
| 10_cohort_predicates.R | Not documented | Not documented | Not documented | Not documented | CONFIG, ICD_CODES, TREATMENT_CODES |
| 11_treatment_payer.R | Not documented | Not documented | Not documented | Not documented | CONFIG, PAYER_MAPPING, TREATMENT_CODES |
| 12_surveillance.R | Not documented | Not documented | Not documented | Not documented | None |
| 13_survivorship_encounters.R | Not documented | Not documented | Not documented | Not documented | ICD_CODES |
| 14_build_cohort.R | Not documented | Not documented | Not documented | Not documented | CONFIG, ICD_CODES |

### Treatment (20-29)

| Script | Purpose | source() Deps | Inputs | Outputs | Config Constants Used |
|--------|---------|---------------|--------|---------|----------------------|
| 20_treatment_inventory.R | Not documented | Not documented | Not documented | Not documented | CONFIG, TREATMENT_CODES |
| 21_investigate_unmatched.R | Not documented | Not documented | Not documented | Not documented | CONFIG, TREATMENT_CODES |
| 22_investigate_unmatched_ndc.R | Not documented | Not documented | Not documented | Not documented | CONFIG, TREATMENT_CODES |
| 23_combine_reports.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 24_treatment_codes_resolved.R | Not documented | Not documented | Not documented | Not documented | CONFIG, TREATMENT_CODES |
| 25_treatment_durations.R | Not documented | Not documented | Not documented | Not documented | CONFIG, TREATMENT_CODES |
| 26_treatment_episodes.R | Not documented | Not documented | Not documented | Not documented | CONFIG, TREATMENT_CODES |
| 27_drug_name_resolution.R | Not documented | Not documented | Not documented | Not documented | CONFIG, TREATMENT_CODES |
| 28_episode_classification.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 29_first_line_and_death_analysis.R | Not documented | Not documented | Not documented | Not documented | CONFIG |

### Cancer (40-59)

| Script | Purpose | source() Deps | Inputs | Outputs | Config Constants Used |
|--------|---------|---------------|--------|---------|----------------------|
| 40_cancer_site_frequency.R | Not documented | Not documented | Not documented | Not documented | CANCER_SITE_MAP |
| 41_extract_all_codes.R | Not documented | Not documented | Not documented | Not documented | None |
| 42_build_code_descriptions.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 43_cancer_site_confirmation.R | Not documented | Not documented | Not documented | Not documented | CANCER_SITE_MAP |
| 44_cancer_site_confirmation_7day.R | Not documented | Not documented | Not documented | Not documented | CANCER_SITE_MAP |
| 45_cancer_summary.R | Not documented | Not documented | Not documented | Not documented | CONFIG, CANCER_SITE_MAP |
| 46_cancer_summary_table.R | Not documented | Not documented | Not documented | Not documented | CONFIG, CANCER_SITE_MAP |
| 47_cancer_summary_refined.R | Not documented | Not documented | Not documented | Not documented | CONFIG, CANCER_SITE_MAP |
| 48_cancer_summary_post_hl.R | Not documented | Not documented | Not documented | Not documented | CONFIG, CANCER_SITE_MAP |
| 49_cancer_summary_pre_post.R | Not documented | Not documented | Not documented | Not documented | CONFIG, CANCER_SITE_MAP |
| 50_all_codes_resolved.R | Not documented | Not documented | Not documented | Not documented | CONFIG, TREATMENT_CODES |
| 51_gantt_data_export.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 52_gantt_v2_export.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 53_death_date_validation.R | Not documented | Not documented | Not documented | Not documented | CONFIG |

### Payer & QA (60-69)

| Script | Purpose | source() Deps | Inputs | Outputs | Config Constants Used |
|--------|---------|---------------|--------|---------|----------------------|
| 60_tiered_same_day_payer.R | Not documented | Not documented | Not documented | Not documented | CONFIG, AMC_PAYER_LOOKUP, TIER_MAPPING |
| 61_tiered_encounter_level.R | Not documented | Not documented | Not documented | Not documented | TIER_MAPPING |
| 62_tiered_date_level.R | Not documented | Not documented | Not documented | Not documented | CONFIG, TIER_MAPPING |
| 63_value_audit.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 64_all_source_missingness.R | Not documented | Not documented | Not documented | Not documented | CONFIG, PAYER_MAPPING |
| 65_uf_insurance_missingness.R | Not documented | Not documented | Not documented | Not documented | CONFIG, PAYER_MAPPING |
| 66_all_site_duplicate_dates.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 67_multi_source_overlap_detection.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 68_overlap_classification.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 69_per_patient_source_detection.R | Not documented | Not documented | Not documented | Not documented | CONFIG |

### Outputs (70-79)

| Script | Purpose | source() Deps | Inputs | Outputs | Config Constants Used |
|--------|---------|---------------|--------|---------|----------------------|
| 70_visualize_waterfall.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 71_visualize_sankey.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 72_generate_pptx.R | Not documented | Not documented | Not documented | Not documented | CONFIG, PAYER_MAPPING, TREATMENT_CODES |
| 73_generate_phase19_20_pptx.R | Not documented | Not documented | Not documented | Not documented | None |
| 74_generate_documentation.R | Not documented | Not documented | Not documented | Not documented | CONFIG, ICD_CODES, PAYER_MAPPING, AMC_PAYER_LOOKUP, TREATMENT_CODES |
| 75_encounter_analysis.R | Not documented | Not documented | Not documented | Not documented | TREATMENT_CODES |

### Tests (80-89)

| Script | Purpose | source() Deps | Inputs | Outputs | Config Constants Used |
|--------|---------|---------------|--------|---------|----------------------|
| 80_smoke_test_backends.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 81_parity_test_cohort.R | Not documented | Not documented | Not documented | Not documented | None |
| 82_benchmark_cohort.R | Not documented | Not documented | Not documented | Not documented | None |
| 83_generate_speedup_report.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 84_test_durations.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 85_test_episodes.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 86_smoke_test_foundation.R | Not documented | Not documented | Not documented | Not documented | None |
| 87_smoke_test_full_pipeline.R | Not documented | Not documented | Not documented | Not documented | None |
| 88_smoke_test_comprehensive.R | Not documented | Not documented | Not documented | Not documented | CONFIG, EXTRACT_DATE, PCORNET_TABLES, PCORNET_PATHS, ICD_CODES, PAYER_MAPPING, AMC_PAYER_LOOKUP, TREATMENT_CODES, CANCER_SITE_MAP, TIER_MAPPING |
| 89_generate_reference_manual.R | Not documented | Not documented | Not documented | Not documented | CONFIG, EXTRACT_DATE, PCORNET_TABLES, PCORNET_PATHS, ICD_CODES, PAYER_MAPPING, AMC_PAYER_LOOKUP, TREATMENT_CODES, ANALYSIS_PARAMS, CANCER_SITE_MAP, TIER_MAPPING |

### Ad-hoc (90-99)

| Script | Purpose | source() Deps | Inputs | Outputs | Config Constants Used |
|--------|---------|---------------|--------|---------|----------------------|
| 90_diagnostics.R | Not documented | Not documented | Not documented | Not documented | CONFIG, PAYER_MAPPING, AMC_PAYER_LOOKUP |
| 91_data_quality_summary.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 92_dx_gap_analysis.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 93_no_treatment_medicaid.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 94_flm_duplicate_dates.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 95_multi_source_overlap_av_th.R | Not documented | Not documented | Not documented | Not documented | CONFIG, AMC_PAYER_LOOKUP |
| 96_overlap_classification_av_th.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 97_payer_code_frequency_av_th.R | Not documented | Not documented | Not documented | Not documented | CONFIG |
| 98_radiation_cpt_audit.R | Not documented | Not documented | Not documented | Not documented | TREATMENT_CODES |
| 99_claude_diagnostics.R | Not documented | Not documented | Not documented | Not documented | None |

---

## Utils Module Reference

Utility modules are auto-sourced by `R/00_config.R` and available to all downstream scripts.

| Module | Purpose | Key Functions | Used By |
|--------|---------|---------------|---------|
| utils_assertions.R | Not documented | assert_rds_exists, assert_df_valid, assert_col_types, warn_date_range, warn_row_count | All scripts via 00_config.R auto-sourcing |
| utils_attrition.R | Not documented | init_attrition_log, log_attrition | All scripts via 00_config.R auto-sourcing |
| utils_cancer.R | Not documented | classify_codes | All scripts via 00_config.R auto-sourcing |
| utils_dates.R | Not documented | parse_pcornet_date | All scripts via 00_config.R auto-sourcing |
| utils_duckdb.R | Not documented | verify_duckdb_roundtrip, open_pcornet_con, close_pcornet_con, get_pcornet_table, materialize | All scripts via 00_config.R auto-sourcing |
| utils_icd.R | Not documented | normalize_icd, is_hl_diagnosis, is_hl_histology | All scripts via 00_config.R auto-sourcing |
| utils_payer.R | Not documented | is_missing_payer, field_match, classify_payer_tier | All scripts via 00_config.R auto-sourcing |
| utils_pptx.R | Not documented | style_table, add_table_slide | All scripts via 00_config.R auto-sourcing |
| utils_snapshot.R | Not documented | save_output_data, build_output_path | All scripts via 00_config.R auto-sourcing |
| utils_treatment.R | Not documented | safe_table, empty_result, get_hl_patient_ids, check_file | All scripts via 00_config.R auto-sourcing |

---

## Run-Order Guide

### Recommended Run Order

#### Foundation (run once per data extract)

1. `R/00_config.R` -- Loaded automatically by all scripts
2. `R/01_load_pcornet.R` -- Load raw PCORnet tables
3. `R/02_harmonize_payer.R` -- Create payer categories
4. `R/03_duckdb_ingest.R` -- Create DuckDB backend (optional)

#### Cohort Building

5. `R/14_build_cohort.R` -- Auto-sources R/10-R/13 via source() chain

#### Treatment Analysis

6. `R/20_treatment_inventory.R` through `R/29_first_line_and_death_analysis.R` -- Run sequentially; R/26 depends on R/25

#### Cancer Site Analysis

7. `R/40_cancer_site_frequency.R` through `R/53_death_date_validation.R` -- Run sequentially

#### Payer & QA

8. `R/60_tiered_same_day_payer.R` through `R/69_per_patient_source_detection.R`

#### Outputs

9. `R/70_visualize_waterfall.R` and `R/71_visualize_sankey.R` -- Require cohort
10. `R/72_generate_pptx.R` -- Requires R/75 (auto-sources it)

**Note:** Ad-hoc scripts (90-99) are standalone and can be run independently.

---

## Config Constants Reference

All constants defined in `R/00_config.R` and available to downstream scripts:

| Constant | Type | Size | Description |
|----------|------|------|-------------|
| CONFIG | list | ~15 elements | Data paths, cache paths, DuckDB settings, performance tuning |
| EXTRACT_DATE | Date | 1 value | PCORnet data extract date (2025-09-15) |
| PCORNET_TABLES | character | 14 tables | PCORnet CDM table names to load |
| PCORNET_PATHS | named vector | 14 paths | Full CSV file paths for each table |
| ICD_CODES | list | 150 codes | HL diagnosis codes (77 ICD-10 + 73 ICD-9) |
| PAYER_MAPPING | named vector | ~50 entries | AMC 8-category payer lookup |
| AMC_PAYER_LOOKUP | data.frame | ~50 rows | Detailed payer code-to-category mapping |
| TREATMENT_CODES | list | 4 types | CPT/HCPCS/NDC codes for radiation, SCT, immunotherapy, supportive care |
| ANALYSIS_PARAMS | list | ~10 params | Thresholds for cohort filtering, HL diagnosis matching |
| CANCER_SITE_MAP | named character | 324 entries | ICD-10 prefix to cancer site category mapping |
| TIER_MAPPING | list | 8 entries | Payer tier classification rules (Medicaid > Medicare > Private) |

---

## Onboarding Guide

### HiPerGator Setup

1. SSH to HiPerGator: `ssh <gatorlink>@hpg.rc.ufl.edu`
2. Load R module: `module load R/4.4.2`
3. Navigate to project: `cd /blue/erin.mobley-hl.bcu/R`
4. Restore packages: `Rscript -e 'renv::restore()'`
5. Verify: `Rscript R/88_smoke_test_comprehensive.R`

**Data location:** `/orange/erin.mobley-hl.bcu/Mailhot_V1_20250915` (raw PCORnet CSVs)

### Local Development (Windows/RStudio)

1. Clone the repository
2. Open `insurance_investigation.Rproj` in RStudio
3. Run `renv::restore()` in R console
4. Run smoke test: `source("R/88_smoke_test_comprehensive.R")`
5. Note: Data-dependent scripts require HiPerGator data mount

### Output File Locations

| Directory | Contents |
|-----------|----------|
| output/ | Root output directory |
| output/tables/ | Excel workbooks (.xlsx) |
| output/figures/ | Visualizations (.png, .pdf) |
| output/reports/ | PowerPoint decks (.pptx) |
| output/gantt/ | Gantt chart CSV exports |
| cache/raw/ | RDS cached raw tables |
| cache/cohort/ | RDS cohort and treatment intermediates |

