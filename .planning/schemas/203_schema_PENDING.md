# Phase 203 Schema Probe — PENDING HiPerGator run

This file documents every input Phase 203 will probe on HiPerGator before any
join or characterization code uses a column name.  The probe must run against
real data there; the local parse machine must not open data/RDS files.

Phase 203 join/characterization code must use only column names confirmed in
203_schema_<date>.md once this probe runs.

## Inputs to probe

- **confirmed_hl_cohort.rds** — env `R203_COHORT_RDS`, default
  `/blue/erin.mobley-hl.bcu/insurance_investigation/output/internal/confirmed_hl_cohort.rds`.
  Columns needed: ID, first_hl_dx_date, treatment-episode count column (name TBD
  by probe — candidate `n_treatment_episodes`), enrollment/first-encounter date
  column, NLPHL vs cHL indicator, age-at-dx, payer category, far_from_care_100mi.

- **gantt_episodes_180.csv** — env `R203_GANTT180_CSV`, default
  `output/gantt_episodes_180.csv`. Columns: ID, treatment_type, tr_hl_dx,
  tr_nhl_dx, ever_abvd, abvd_class, immune_flag, ever_brentuximab.

- **single_source_care RDS (R/169)** — env `R203_R169_RDS`, default
  `/blue/erin.mobley-hl.bcu/insurance_investigation/output/internal/single_source_care_20261013.rds`.
  Columns: ID, single_source_care, single_source_care_post, primary_source.

- **tr_lymphoma_flags_all_patients_<DATED>.rds (R/193)** — env `R203_TRFLAGS_RDS`,
  default
  `/blue/erin.mobley-hl.bcu/insurance_investigation/output/internal/tr_lymphoma_flags_all_patients_20261113.rds`.
  Columns TBD by probe: TR treatment summary / first-course treatment flags.

## Probe call (paste in HiPerGator interactive session)

```r
source("R/00_config.R")
source("R/utils/utils_schema_probe.R")
probe_inputs("203", files = c(Sys.getenv("R203_COHORT_RDS"), Sys.getenv("R203_GANTT180_CSV"), Sys.getenv("R203_R169_RDS"), Sys.getenv("R203_TRFLAGS_RDS")))
```

Paste the resulting `.planning/schemas/203_schema_<date>.md` back before
writing any Phase 203 join code (Plan 203-02).
