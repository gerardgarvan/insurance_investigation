---
phase: 117-make-a-lifespan-gannt-that-collapses-across-all-time-but-still-keeps-treatment-type-etc-sepearate
plan: "01"
subsystem: gantt-export
tags: [gantt, lifespan, collapse, treatment-episodes, tableau, csv-export]
dependency_graph:
  requires:
    - output/gantt_episodes.csv (produced by R/52_gantt_v2_export.R)
  provides:
    - output/gantt_lifespan.csv (one row per patient_id x treatment_type)
    - R/101_gantt_lifespan_collapse.R (standalone collapse script)
  affects:
    - R/39_run_all_investigations.R (investigation_scripts vector)
    - R/88_smoke_test_comprehensive.R (Section 15n structural checks)
    - R/SCRIPT_INDEX.md (Post-Renumber Investigations table)
tech_stack:
  added: []
  patterns:
    - group_by/summarise collapse with union_field() helper for semicolon-already-separated multi-value fields
    - clean_multi_value() verbatim copy from R/52 (R/52 does not export it)
    - LIFESPAN_SCHEMA dynamic verification (mirrors R/52 EPISODES_SCHEMA pattern)
    - read.csv(colClasses="character") + explicit ymd() parse to avoid coercion surprises
key_files:
  created:
    - R/101_gantt_lifespan_collapse.R
    - .planning/phases/117-make-a-lifespan-gannt-that-collapses-across-all-time-but-still-keeps-treatment-type-etc-sepearate/117-01-SUMMARY.md
  modified:
    - R/39_run_all_investigations.R
    - R/88_smoke_test_comprehensive.R
    - R/SCRIPT_INDEX.md
decisions:
  - "episode_length_days computed as span in days (max_stop - min_start), not total active days -- matches lifespan semantics"
  - "distinct_dates_in_episode is SUM of per-episode counts across merged episodes, not re-distinct from raw data"
  - "age_at_episode is the patient's age at the EARLIEST episode_start (which.min row within group)"
  - "is_hodgkin re-derived from unioned cancer_category string (consistent with R/52 line 857 pattern)"
  - "clean_multi_value() copied verbatim from R/52 (standalone copy acceptable; R/52 does not export it)"
  - "union_field() helper pastes group values with ';' then calls clean_multi_value(sep_in=';') to handle already-semicolon-separated input"
metrics:
  duration: "~3 minutes"
  completed: "2026-07-09"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 3
---

# Phase 117 Plan 01: Lifespan Gantt Collapse Summary

**One-liner:** Standalone R/101 script collapses gantt_episodes.csv into one row per patient_id x treatment_type, spanning min(episode_start) to max(episode_stop), unioning multi-value fields via clean_multi_value() verbatim from R/52.

## What Was Built

A new standalone script `R/101_gantt_lifespan_collapse.R` (314 lines) that:

1. Reads `output/gantt_episodes.csv` (the 20-column Gantt export produced by R/52)
2. Excludes Death and HL Diagnosis pseudo-rows (D-08)
3. Groups by `patient_id` x `treatment_type` and collapses to one row per group
4. Spans each bar from `min(episode_start)` to `max(episode_stop)` (D-05)
5. Sums `distinct_dates_in_episode` and counts `episode_count` (replaces `episode_number`)
6. Unions all multi-value fields via `union_field()` -> `clean_multi_value()` (D-07)
7. Re-derives `is_hodgkin` from the unioned `cancer_category` string
8. Verifies a 20-column `LIFESPAN_SCHEMA` before writing
9. Writes `output/gantt_lifespan.csv` with `row.names=FALSE, na=""` (D-02)

Output enables a Tableau Gantt chart showing one bar per treatment type per patient from that patient's first to last treatment date -- reducing per-episode clutter to a single lifespan bar per treatment.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Create R/101_gantt_lifespan_collapse.R | 086debe | R/101_gantt_lifespan_collapse.R (created, 314 lines) |
| 2 | Register R/101 in R/39, R/88 Section 15n, SCRIPT_INDEX.md | 5300d2c | R/39, R/88, R/SCRIPT_INDEX.md |

## Verification

### Structural (local, all PASS)

- R/101 exists, 314 lines (>= 150 required)
- `group_by(patient_id, treatment_type)` present (D-04/D-06 collapse grain)
- `filter(!treatment_type %in% c("Death", "HL Diagnosis"))` present (D-08)
- `min(episode_start` and `max(episode_stop` present (D-05 span)
- `episode_count` present (replaces episode_number)
- `clean_multi_value` present (D-07 union behavior)
- `str_detect(cancer_category, "Hodgkin") & !str_detect(cancer_category, "Non-Hodgkin")` present
- `LIFESPAN_SCHEMA` + `identical(colnames(` both present (D-13 schema check)
- `gantt_episodes.csv` and `gantt_lifespan.csv` both via `file.path(CONFIG$output_dir, ...)`
- `write.csv(` ... `row.names = FALSE, na = ""` present (D-02)
- `source("R/00_config.R")` present
- 8 SECTION markers present (>= 7 required)
- No `ggplot` / `ggsave` / `geom_` references (D-01: data export only)
- No `open_pcornet_con` / `get_pcornet_table` (no DuckDB connection)
- R/39 investigation_scripts vector contains R/101 (R/100 has trailing comma -- valid R syntax)
- R/88 Section 15n present with 14 checks and r101_exists if/else guard
- R/88 checks cover LIFESPAN-01, LIFESPAN-02, LIFESPAN-03, LIFESPAN-04
- R/88 summary block has LIFESPAN-01 through SMOKE-117-01 message lines
- SCRIPT_INDEX.md has R/101 row under Post-Renumber Investigations (100+)

### Runtime (HiPerGator only -- requires real PCORnet data)

The following validations require running on HiPerGator after a full R/39/R/52 run:
- `output/gantt_lifespan.csv` produced with fewer rows than `gantt_episodes.csv`
- Zero output rows with `treatment_type` in `c("Death", "HL Diagnosis")`
- Spot-checked patient x treatment_type: `episode_start` == min and `episode_stop` == max of underlying episodes; `episode_count` == number of merged episodes
- Full R/88 Section 15n passes (may stop earlier at classify_codes production gate, per Phase 116 precedent)

This follows the Phase 116 precedent: structural checks pass locally on Windows; full data validation is HiPerGator-only.

## Deviations from Plan

None -- plan executed exactly as written.

The R/88 check #13 (no ggplot) required removing a comment mentioning "ggplot" in a negative context from R/101 (the comment read "no ggplot/rendered chart"). The comment was reworded to "no in-R chart rendering" to prevent the `grepl("ggplot|ggsave|geom_", r101_lines)` check from false-positiving. This is a minor documentation refinement, not a plan deviation.

## Known Stubs

None. R/101 is a complete standalone collapse script that reads a real input file and writes a real output file. No hardcoded empty values, placeholder text, or unconnected data sources.

## Self-Check: PASSED

- `R/101_gantt_lifespan_collapse.R` exists: CONFIRMED
- Commit 086debe exists: CONFIRMED
- Commit 5300d2c exists: CONFIRMED
- R/39 contains `101_gantt_lifespan_collapse`: CONFIRMED
- R/88 contains `SECTION 15n`: CONFIRMED
- R/SCRIPT_INDEX.md contains `R/101_gantt_lifespan_collapse.R`: CONFIRMED
