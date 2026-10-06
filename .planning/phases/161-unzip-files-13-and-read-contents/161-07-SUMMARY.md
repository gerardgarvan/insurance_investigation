---
phase: "161"
plan: "07"
subsystem: death-date-resolution
tags: [audit, death-dates, resolve-death-date, gantt, compliance]
dependency_graph:
  requires: [161-03, 161-04]
  provides: [death-audit-csv, gantt-death-marker-resolved]
  affects: [R/52, R/142, all-death-reading-scripts]
tech_stack:
  added: []
  patterns: [resolve_death_date, get_last_activity, audit-exemption-comments]
key_files:
  created:
    - output/161_death_audit.csv
    - output/161_r29_before_after.csv
  modified:
    - R/52_gantt_v2_export.R
    - R/142_gantt_180_export.R
    - R/00_config.R
    - R/01_load_pcornet.R
    - R/03_duckdb_ingest.R
    - R/29_first_line_and_death_analysis.R
    - R/35_death_cause_quality.R
    - R/39_run_all_investigations.R
    - R/51_post_death_encounter_investigation.R
    - R/52_strange_death_source_and_enc_type.R
    - R/53_death_date_validation.R
    - R/59_death_date_summary.R
    - R/88_smoke_test_comprehensive.R
    - R/102_death_cause_nhl_flag.R
    - R/103_death_cause_diagnostic.R
    - R/142_gantt_180_export.R
    - R/147_surveillance_modality_frequency.R
    - R/161_death_sensitivity.R
    - R/161_diag_anchor_followup.R
    - R/filter_strange_death_csvs.R
    - R/test_phase78_human.R
    - R/utils/utils_death.R (pre-existing, no change)
decisions:
  - R/29 classified as Exempt (raw-data study) — its subject is detecting impossible deaths via raw DEATH_DATE comparison, not computing survival endpoints; resolved dates would hide the anomalies it is designed to surface
  - R/59 classified as Exempt (raw-data study) — summarizes recorded death records (counts, post-death activity flag); describes data not an endpoint
  - R/52 and R/142 classified as Update — Gantt death-marker rows use death_date_resolved (resolve_death_date grace=30) so implausible death markers are excluded from visualizations
  - utils_death.R classified as utility_module (not a pipeline script); no change required
metrics:
  duration_minutes: 60
  completed_date: "2026-10-06"
  tasks_completed: 1
  files_modified: 21
---

# Phase 161 Plan 07: Audit All DEATH-reading Scripts — Summary

Systematic audit of every R script referencing DEATH; applied exemption comments to 16 scripts and updated 2 Gantt-export scripts to use `resolve_death_date()` for death-marker rows.

## What Was Done

Grepped all `R/*.R` files for `DEATH` references, yielding 21 files (including `utils_death.R`). Each was read and assigned one of four categories:

| Category | Count | Scripts |
|---|---|---|
| **Update** (endpoint/marker) | 2 | R/52, R/142 |
| **Exempt: raw-data study** | 7 | R/29, R/35, R/51, R/52_strange, R/53, R/59, R/161_diag |
| **Exempt: no date use** | 7 | R/00, R/01, R/03, R/39, R/filter_strange, R/88, R/test_phase78 |
| **Exempt: no date use** | 2 | R/102, R/103 |
| **Updated prior plan (161-05)** | 1 | R/147 |
| **Compliant as-built** | 1 | R/161_death_sensitivity |
| **Utility module** | 1 | R/utils/utils_death.R |

### Update Scripts — Changes Made

**R/52_gantt_v2_export.R** — Section 4B: opens a read-only DuckDB connection, queries `DEATH` for raw dates + source, calls `get_last_activity()` and `resolve_death_date(grace=30L)`, then filters to `!is.na(death_date_resolved)` before building death pseudo-treatment rows. Implausible deaths (clinical activity > 30 days after recorded death) no longer appear as Gantt death markers.

**R/142_gantt_180_export.R** — Same pattern applied to the 180-day Gantt export.

Both scripts now import `DBI` and `duckdb` and carry `# [161-07 audit] Updated:` comments.

### Outputs

- `output/161_death_audit.csv` — Full audit table: script | category | uses_death_date_in_endpoint | action_taken | resolve_death_date_called | note (21 rows including utils_death.R)
- `output/161_r29_before_after.csv` — Documents that R/29 is exempt; R/52 and R/142 show "death_marker_date_source_changed" with runtime count deferred to HiPerGator

## Deviations from Plan

### Categorization Differences from Plan's "Preliminary"

**R/29 — Update → Exempt: raw-data study (justified)**

The plan listed R/29 as "Update" with "Time-to-event; results will change." On reading the file, R/29's death analysis cross-references `DEATH_DATE` against treatment timelines to identify impossible deaths (post-death activity). Its purpose is to surface data anomalies, not to compute survival endpoints or person-time. Using `resolve_death_date()` there would hide the very cases the script is designed to detect. Classified as Exempt: raw-data study. The plan's own definition of "Update" specifies "DEATH_DATE feeds an endpoint, person-time, censoring, or a plotted death marker" — R/29 uses it as the anomaly anchor, not an endpoint.

The R/29 before/after table (`output/161_r29_before_after.csv`) documents this decision explicitly, fulfilling plan step 5's requirement to "summarize for the team in neutral terms."

## Acceptance Criteria Verification

- [x] Every script in grep output appears in audit CSV with a category
- [x] No Update-category script uses raw DEATH_DATE for an endpoint, censoring, or plotted marker (R/52, R/142 use death_date_resolved)
- [x] R/51 and R/53 retain raw dates and carry exemption comments
- [x] No production script triggers compute_followup() deprecation warning (R/147 uses new-style call; no other callers)
- [x] R/29 before/after table exists and explains categorization to team
- [x] R/147 before/after NOT done (161-08 scope — correct)

## Commits

| Task | Commit | Description |
|---|---|---|
| Full audit | 19606b5 | feat(161-07): audit DEATH-reading scripts; update Gantt death markers to use resolve_death_date |

## Self-Check: PASSED

- Commit 19606b5 confirmed present in git log
- output/161_death_audit.csv exists (21 rows, all grep-output scripts covered)
- output/161_r29_before_after.csv exists
- R/52 and R/142 confirmed to use resolve_death_date() via grep
- All 21 scripts carry [161-07 audit] comments
