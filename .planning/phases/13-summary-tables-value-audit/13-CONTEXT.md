# Phase 13: Summary Tables Value Audit

## Phase Goal

Create comprehensive summary/frequency tables for every categorical variable across all loaded PCORnet CDM tables. The purpose is to enumerate every distinct value that appears in the data so the user can feed these tables to Claude and identify any coding inconsistencies, unexpected values, or mapping errors.

## User Intent

> "Make summary tables that give every possible value to ensure everything is coded correctly. The plan is create summary tables, feed them to you, and see if anything is inconsistent."

This is a **data quality / validation** phase. The output is CSV summary tables (one per CDM table) showing value counts for every categorical column, which will be reviewed interactively for inconsistencies.

## Decisions

- D-01: **Scope** — All 13 loaded PCORnet CDM tables (ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC, TUMOR_REGISTRY1/2/3, DISPENSING, MED_ADMIN, LAB_RESULT_CM, PROVIDER)
- D-02: **What to tabulate** — Every character/categorical column gets a frequency table (value + count + percentage). Numeric columns get summary stats (min, max, mean, median, n_missing, n_distinct).
- D-03: **Output format** — CSV files in `output/tables/value_audit/` directory, one file per table (e.g., `DEMOGRAPHIC_values.csv`, `ENCOUNTER_values.csv`)
- D-04: **HIPAA compliance** — Counts 1-10 must be suppressed (replaced with "<11") per project constraint
- D-05: **Date columns** — Show min date, max date, n_missing, n_valid (not full value enumeration since dates are continuous)
- D-06: **Script location** — New script `R/17_value_audit.R` that sources `R/01_load_pcornet.R` and produces all summary tables
- D-07: **Derived/computed variables** — Also summarize key derived variables from the pipeline: payer_category (from 02_harmonize_payer.R), HL_SOURCE (from cohort building), treatment flags (HAD_CHEMO, HAD_RADIATION, HAD_SCT)

## Key Variables to Audit

### High-priority (directly used in analysis logic):
- ENCOUNTER: PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, ENC_TYPE, DRG, DRG_TYPE, FACILITY_TYPE
- DIAGNOSIS: DX, DX_TYPE, DX_SOURCE, DX_ORIGIN, PDX, ENC_TYPE
- PROCEDURES: PX, PX_TYPE, PX_SOURCE, ENC_TYPE
- DEMOGRAPHIC: SEX, RACE, HISPANIC, GENDER_IDENTITY, SEXUAL_ORIENTATION
- ENROLLMENT: CHART, ENR_BASIS
- All tables: SOURCE (partner provenance)

### Medium-priority (used in some analyses):
- PRESCRIBING: RXNORM_CUI, RX_ROUTE, RX_BASIS, RX_FREQUENCY
- DISPENSING: RXNORM_CUI, DISPENSE_ROUTE
- MED_ADMIN: MEDADMIN_TYPE, MEDADMIN_ROUTE, RXNORM_CUI
- LAB_RESULT_CM: LAB_LOINC, LAB_PX_TYPE, RESULT_QUAL, RESULT_MODIFIER, ABN_IND
- PROVIDER: PROVIDER_SPECIALTY_PRIMARY, PROVIDER_SEX

### Lower-priority (wide tables, many coded fields):
- TUMOR_REGISTRY1: 314 columns — focus on HISTOLOGICAL_TYPE, GRADE, SITE_CODE, LATERALITY, BEHAVIOR_CODE, STAGE columns
- TUMOR_REGISTRY2/3: 140 columns — focus on MORPH, SITE, GRADE, staging columns

## Upstream Dependencies

- R/00_config.R (configuration, code lists)
- R/01_load_pcornet.R (data loading)
- R/02_harmonize_payer.R (payer_summary with derived payer categories)
- R/04_build_cohort.R (cohort with HL_SOURCE, treatment flags)

## Success Criteria

1. One CSV per table showing all distinct values for each categorical column
2. Counts and percentages for each value
3. HIPAA-compliant (small cells suppressed)
4. Output directory: `output/tables/value_audit/`
5. Runs end-to-end from `source("R/17_value_audit.R")`
