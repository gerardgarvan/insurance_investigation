# Architecture Research: R Analysis Pipeline Reorganization

**Domain:** PCORnet clinical cohort analysis pipeline (R)
**Researched:** 2026-06-01
**Confidence:** HIGH

## Executive Summary

This architecture research defines the reorganization strategy for ~80 R analysis scripts in a PCORnet CDM cohort analysis pipeline. The existing codebase has evolved organically across 63 phases, resulting in:

- **Numbering gaps** (missing 30-32, 37, 57)
- **Sub-lettered scripts** (22a/b, 43a/b, etc.) mixing production and test code
- **Scattered logical groupings** (treatment scripts at 38-44 AND 60-62)
- **Mixed utilities** (7 utils_*.R files in main R/ directory)
- **Unnumbered ad-hoc scripts** (6 diagnostic/exploratory files)

**Recommended reorganization:**
- **Decade-based numbering:** 00-09 foundation, 10-19 cohort, 20-39 treatment, 40-59 cancer, 60-69 payer/QA, 70-79 outputs, 80-89 tests, 90-99 ad-hoc
- **Separate utils/ folder:** Move 7 utility modules out of main directory
- **Archive/ folder:** Deprecated scripts preserved for reference
- **Sequential migration:** 9 phases with smoke tests after each decade

**Integration points:** 95+ source() calls, 25+ RDS artifacts, 50+ output files. RDS and output files use semantic naming (no changes required). Only source() paths and inline comments need updates.

---

## Current State Analysis

### Inventory

**Total scripts:** 81 R files
- **Numbered scripts (00-99):** 63 files
  - Sequential (01-29): 29 files (gaps at 30-32, 37)
  - Scattered (33-63): 30 files
  - Special: 00_config.R, 99_claude_diagnostics.R
- **Unnumbered utility scripts:** 7 files (`utils_*.R`)
- **Unnumbered ad-hoc scripts:** 6 files
- **Runner scripts:** 1 file (`run_phase12_outputs.R`)

### Numbering Problems

| Problem | Examples | Impact |
|---------|----------|--------|
| Missing sequence numbers | No 30-32, 37, 57 | ~15 gaps, unclear ordering |
| Duplicate prefixes | Two scripts start with 55_ | Name collision |
| Sub-lettered scripts | 22a/b, 43a/b, 44a/b, 45a/b, 46a/b, 48a/b | 12 files, confuses hierarchy |
| Unnumbered ad-hoc | `date_range_check.R`, `sct_code_inventory.R` | 6 files, unclear if production |
| Test scripts in main sequence | 43b, 44b | 2 files, mixed with production code |

### Cross-Reference Patterns

**Foundation chain:**
```
00_config.R (auto-sources 7 utils)
  ├── 01_load_pcornet.R (28 scripts reference)
  ├── 02_harmonize_payer.R (8 scripts reference)
  └── 03_cohort_predicates.R (2 scripts reference)
      └── 04_build_cohort.R (7 scripts reference)
          ├── Inline: 10_treatment_payer.R
          ├── Inline: 13_surveillance.R
          └── Inline: 14_survivorship_encounters.R
```

**Integration point categories:**
1. **source() calls:** 95+ explicit source statements
2. **RDS artifacts:** 25+ .rds files with semantic names (hl_cohort.rds, treatment_episodes.rds)
3. **Output filenames:** ~50 CSV/XLSX/PNG with semantic names (gantt_episodes.csv)
4. **Inline comments:** "Phase NN" references in docstrings

---

## Recommended Project Structure

### Decade-Based Numbering Scheme

```
R/
├── 00-09: Foundation (config, data loading)
├── 10-19: Cohort Building (predicates, attrition)
├── 20-39: Treatment Analysis (episodes, regimens) — 20 slots for expansion
├── 40-59: Cancer Diagnosis Analysis (sites, summaries) — 20 slots
├── 60-69: Payer & Data Quality (resolution, validation)
├── 70-79: Visualization & Reports (tables, figures, PPTX)
├── 80-89: Testing & Diagnostics (parity, benchmarks)
├── 90-99: Ad-Hoc & Deprecated (exploratory, one-offs)
├── utils/ (NEW folder) — 7 utility modules
└── archive/ (NEW folder) — 6 deprecated scripts
```

### Complete Reorganization Mapping

**00-09: Foundation**
- 00_config.R (unchanged)
- 01_data_ingest_duckdb.R ← 25_duckdb_ingest.R
- 02_data_load_pcornet.R ← 01_load_pcornet.R
- 03_data_harmonize_payer.R ← 02_harmonize_payer.R

**10-19: Cohort Building**
- 10_cohort_predicates.R ← 03_cohort_predicates.R
- 11_cohort_assemble.R ← 04_build_cohort.R
- 12_treatment_payer_window.R ← 10_treatment_payer.R
- 13_surveillance_detection.R ← 13_surveillance.R
- 14_survivorship_encounters.R ← 14_survivorship_encounters.R

**20-39: Treatment Analysis**
- 20_treatment_code_inventory.R ← 38_treatment_inventory.R
- 21_treatment_code_resolution.R ← 39-42 merged
- 22_treatment_durations.R ← 43a_treatment_durations.R
- 23_treatment_episodes.R ← 44a_treatment_episodes.R
- 24_drug_name_resolution.R ← 60_drug_name_resolution.R
- 25_episode_cancer_linkage.R ← 61_episode_classification.R
- 26_first_line_therapy.R ← 62_first_line_and_death_analysis.R
- 27_treatment_cross_reference.R ← 46b_treatment_cross_reference.R

**40-59: Cancer Diagnosis Analysis**
- 40_cancer_site_frequency.R ← 47_cancer_site_frequency.R
- 41_cancer_site_confirmation.R ← 50+51 merged
- 42_cancer_summary_refined.R ← 55_cancer_summary_refined.R
- 43_cancer_summary_temporal.R ← 56+58 merged
- 44_all_codes_catalog.R ← 48a+48b+52 combined

**60-69: Payer & Data Quality**
- 60_payer_code_frequency.R ← 35_payer_code_frequency_av_th.R
- 61_payer_tiered_resolution.R ← 36_tiered_same_day_payer.R
- 62_encounter_overlap_detection.R ← 22a+33 merged
- 63_encounter_overlap_classification.R ← 23+34 merged
- 64_death_date_validation.R ← 59_death_date_validation.R
- 65_data_quality_summary.R ← 08_data_quality_summary.R
- 66_dx_gap_analysis.R ← 09_dx_gap_analysis.R
- 67_encounter_missingness.R ← 18+20 merged

**70-79: Visualization & Reports**
- 70_encounter_analysis.R ← 16_encounter_analysis.R
- 71_attrition_waterfall.R ← 05_visualize_waterfall.R
- 72_payer_sankey.R ← 06_visualize_sankey.R
- 73_pptx_main_report.R ← 11_generate_pptx.R
- 74_pptx_overlap_report.R ← 22b_generate_phase19_20_pptx.R
- 75_documentation_export.R ← 15_generate_documentation.R
- 76_gantt_v1_export.R ← 49_gantt_data_export.R
- 77_gantt_v2_export.R ← 63_gantt_v2_export.R

**80-89: Testing & Diagnostics**
- 80_backend_smoke_test.R ← 26_smoke_test_backends.R
- 81_cohort_parity_test.R ← 27_parity_test_cohort.R
- 82_benchmark_cohort.R ← 28_benchmark_cohort.R
- 83_speedup_report.R ← 29_generate_speedup_report.R
- 84_test_durations.R ← 43b_test_durations.R
- 85_test_episodes.R ← 44b_test_episodes.R

**90-99: Ad-Hoc & Deprecated**
- 90_value_audit.R ← 17_value_audit.R
- 91_radiation_cpt_audit.R ← 45b_radiation_cpt_audit.R
- 92_no_treatment_medicaid.R ← 12_no_treatment_medicaid.R
- 93_duplicate_dates_flm.R ← 19_flm_duplicate_dates.R
- 94_duplicate_dates_all_sites.R ← 21_all_site_duplicate_dates.R
- 95_per_patient_source_detection.R ← 24_per_patient_source_detection.R
- 96_search_C8190.R ← 55_search_C8190.R
- 97_date_range_check.R ← date_range_check.R
- 98_check_deleted_proton_code.R ← check_deleted_proton_code.R
- 99_claude_diagnostics.R (unchanged)

**utils/ folder (NEW)**
- utils_attrition.R (moved from R/)
- utils_dates.R (moved from R/)
- utils_duckdb.R (moved from R/)
- utils_icd.R (moved from R/)
- utils_payer.R (moved from R/)
- utils_pptx.R (moved from R/)
- utils_snapshot.R (moved from R/)
- utils_treatment.R (moved from R/)

**archive/ folder (NEW)**
- payer_frequency_from_resolved.R (deprecated)
- tiered_payer_summary.R (deprecated)
- sct_code_inventory.R (deprecated)
- run_phase12_outputs.R (replaced)
- tiered_encounter_level.R (was 45a)
- tiered_date_level.R (was 46a)

---

## Integration Points

### 1. source() Call Updates

| Old Reference | New Reference | Affected Scripts |
|---------------|---------------|------------------|
| `source("R/01_load_pcornet.R")` | `source("R/02_data_load_pcornet.R")` | 28 scripts |
| `source("R/02_harmonize_payer.R")` | `source("R/03_data_harmonize_payer.R")` | 8 scripts |
| `source("R/03_cohort_predicates.R")` | `source("R/10_cohort_predicates.R")` | 2 scripts |
| `source("R/04_build_cohort.R")` | `source("R/11_cohort_assemble.R")` | 7 scripts |
| `source("R/43a_treatment_durations.R")` | `source("R/22_treatment_durations.R")` | 1 script |
| `source("R/utils_*.R")` | `source("R/utils/utils_*.R")` | 7 in 00_config.R |

**Verification:** Grep `source\("R/[0-9]` after each phase, confirm zero old references remain.

### 2. RDS Artifact Paths

**No changes required.** All RDS files use semantic naming:
- `hl_cohort.rds`
- `treatment_episodes.rds`
- `confirmed_hl_cohort.rds`
- `drug_name_lookup.rds`
- (No files named `04_cohort.rds` or similar)

### 3. Output Filenames

**No changes required.** All outputs use semantic naming:
- `gantt_episodes.csv`
- `encounter_summary_by_payor_age.csv`
- `encounters_per_person_by_payor.png`
- (No files named `04_output.csv` or similar)

### 4. Inline Script References

**Pattern:** Comments like `# Phase 43: Treatment Duration` → `# R/22 (treatment durations)`

**Regex search:** `Phase [0-9]{2}` and `R/[0-9]{2}[a-z]?_`

### 5. Cross-Script Function Dependencies

| Function | Defined In (OLD) | Defined In (NEW) |
|----------|------------------|------------------|
| `assign_episode_ids()` | 43a_treatment_durations.R | 22_treatment_durations.R |
| `compute_payer_at_*()` | 10_treatment_payer.R | 12_treatment_payer_window.R |
| `get_pcornet_table()` | utils_duckdb.R | utils/utils_duckdb.R |

**No functional changes** — just path updates in source() calls.

---

## Data Flow Through Reorganized Pipeline

```
00_config.R → auto-source utils/
    ↓
01_data_ingest_duckdb.R (CSV → DuckDB)
    ↓
02_data_load_pcornet.R (get_pcornet_table())
    ↓
03_data_harmonize_payer.R (8 AMC categories)
    ↓
10-14: Cohort Building → hl_cohort.rds
    ↓
20-27: Treatment Analysis → treatment_episodes.rds, regimen_labeled_episodes.rds
    ↓
40-44: Cancer Diagnosis → cancer_summary.rds, confirmed_hl_cohort.rds
    ↓
60-67: Payer & Data Quality → resolved encounters, quality metrics
    ↓
70-77: Visualization & Reports → PNG/CSV/PPTX outputs
```

---

## Migration Strategy: Build Order

### Phase 1: Foundation (00-09)
1. Create `R/utils/` folder
2. Move 7 `utils_*.R` → `R/utils/`
3. Update `00_config.R` lines 1501-1507: `source("R/utils/utils_*.R")`
4. Rename 25 → 01, 01 → 02, 02 → 03
5. Update source() calls (28 scripts for 01→02, 8 scripts for 02→03)
6. Run smoke test

### Phase 2: Cohort Building (10-19)
1. Rename 03 → 10, 04 → 11, 10 → 12
2. Update source() calls (7 scripts)
3. Run parity test (hl_cohort.rds row count matches)

### Phase 3: Treatment Analysis (20-39)
1. Rename 38 → 20, merge 39-42 → 21, 43a → 22, 44a → 23
2. Rename 60 → 24, 61 → 25, 62 → 26, 46b → 27
3. Update source() calls
4. Run smoke test (treatment_episodes.rds structure unchanged)

### Phase 4: Cancer Diagnosis (40-59)
1. Rename 47 → 40, merge 50+51 → 41, 55 → 42
2. Merge 56+58 → 43, merge 48a+48b+52 → 44
3. Run smoke test (cancer_summary.rds row counts match)

### Phase 5: Payer & Data Quality (60-69)
1. Rename 35 → 60, 36 → 61, merge 22a+33 → 62, merge 23+34 → 63
2. Rename 59 → 64, 08 → 65, 09 → 66, merge 18+20 → 67
3. Run smoke test

### Phase 6: Visualization & Reports (70-79)
1. Rename 16 → 70, 05 → 71, 06 → 72, 11 → 73, 22b → 74, 15 → 75, 49 → 76, 63 → 77
2. Update source() calls (73_pptx_main_report sources 70_encounter_analysis)
3. Run smoke test (output file counts match)

### Phase 7: Testing & Diagnostics (80-89)
1. Rename 26 → 80, 27 → 81, 28 → 82, 29 → 83, 43b → 84, 44b → 85
2. Run all tests in sequence

### Phase 8: Ad-Hoc & Archive (90-99)
1. Rename 17 → 90, 45b → 91, 12 → 92, 19 → 93, 21 → 94, 24 → 95, 55_search → 96
2. Rename unnumbered: date_range_check → 97, check_deleted_proton_code → 98
3. Create `R/archive/`, move 6 deprecated scripts

### Phase 9: Documentation & Verification
1. Update all "Phase NN" comments → "R/NEW_NUMBER"
2. Create `docs/PIPELINE_REFERENCE.md`
3. Run full pipeline 00 → 77
4. Final parity check (compare output/ folder before/after)

---

## Sources

- [CRAN Task View: Reproducible Research](https://cran.r-project.org/view=ReproducibleResearch)
- [Building reproducible analytical pipelines with R - targets](https://raps-with-r.dev/targets.html)
- [Reproducible Analytical Pipelines | R-bloggers](https://www.r-bloggers.com/2026/03/reproducible-analytical-pipelines/)
- [R for Data Science (2e) - Workflow: scripts](https://r4ds.hadley.nz/workflow-scripts.html)
- [Tidyverse style guide - Files](https://style.tidyverse.org/files.html)
- [Google's R Style Guide](https://web.stanford.edu/class/cs109l/unrestricted/resources/google-style.html)
- [R Packages (2e) - R code](https://r-pkgs.org/code.html)
- [renv: Introduction](https://rstudio.github.io/renv/articles/renv.html)

---
*Researched: 2026-06-01*
*Confidence: HIGH (verified against existing codebase + industry practices)*
