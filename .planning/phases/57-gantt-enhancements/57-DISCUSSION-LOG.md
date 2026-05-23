# Phase 57: Gantt Enhancements - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-22
**Phase:** 57-gantt-enhancements
**Areas discussed:** Cancer category linkage, Multi-cancer handling, Death date sourcing, Death row structure

---

## Cancer Category Linkage

| Option | Description | Selected |
|--------|-------------|----------|
| Patient-level from cancer_summary.csv | Load cancer_summary.csv (already has patient ID + cancer_category per code). Group by patient to get all cancer categories. Avoids re-querying DuckDB. Fast and consistent with Phase 55 output. | ✓ |
| Fresh DIAGNOSIS query with PREFIX_MAP | Query DIAGNOSIS table via DuckDB, apply PREFIX_MAP classification. Independent of R/55 output but duplicates work. Allows applying additional filters. | |
| From confirmed_hl_cohort.rds only | Only label episodes as 'Hodgkin Lymphoma' for confirmed HL patients. Simpler but doesn't fulfill GANTT-01 fully. | |

**User's choice:** Patient-level from cancer_summary.csv (Recommended)
**Notes:** Avoids DuckDB re-query, consistent with Phase 55's refined output (D-codes already removed).

---

## Multi-cancer Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Comma-separated list | cancer_category = "Hodgkin Lymphoma,Breast" — lists all categories for the patient. Matches triggering_codes pattern. | ✓ |
| Primary + has_multiple flag | cancer_category = most common category, plus separate has_multiple_cancers boolean. Loses secondary cancer types. | |
| One row per cancer category | Duplicate each episode row per cancer category. Inflates row count, changes data shape significantly. | |

**User's choice:** Comma-separated list (Recommended)
**Notes:** Consistent with triggering_codes pattern already in Gantt data.

---

## Death Date Sourcing

| Option | Description | Selected |
|--------|-------------|----------|
| Extend DEMOGRAPHIC load spec | Add DEATH_DATE to DEMOGRAPHIC_SPEC in R/01_load_pcornet.R. | |
| Read DEATH_DATE directly from CSV | Bypass DuckDB, read DEMOGRAPHIC CSV directly. | |
| Separate DEATH table if available | Check for standalone DEATH table in data directory. | |

**User's choice:** Free-text response — DEATH_Mailhot_V1.csv exists as a separate table with columns: ID, DEATH_DATE, DEATH_DATE_IMPUTE, DEATH_SOURCE, DEATH_MATCH_CONFIDENCE, SOURCE. Full pipeline integration chosen (config + load spec + DuckDB ingest).

**Follow-up question:** How should the DEATH table be integrated?

| Option | Description | Selected |
|--------|-------------|----------|
| Full pipeline integration | Add DEATH to PCORNET_TABLES, define DEATH_SPEC in R/01, re-ingest into DuckDB, query via get_pcornet_table("DEATH"). | ✓ |
| Direct CSV read in R/57 only | Read DEATH_Mailhot_V1.csv directly with vroom. Quick but breaks DuckDB-first pattern. | |

**User's choice:** Full pipeline integration (Recommended)
**Notes:** Consistent with all other 14 tables in the pipeline. Reusable for future scripts.

---

## Death Row Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Single point row | treatment_type = "Death", episode_start = episode_stop = death_date, episode_length_days = 0, episode_number = 1. Same row in both CSVs. | ✓ |
| Endpoint-only in episodes table | Death rows only in gantt_episodes.csv, not in gantt_detail.csv. | |
| Separate death_date column | Add death_date column to every existing row instead of pseudo-treatment rows. | |

**User's choice:** Single point row (Recommended)
**Notes:** Treated as a point event on timeline. Appears in both gantt_episodes.csv and gantt_detail.csv.

---

## Claude's Discretion

- Column ordering for new columns (cancer_category, is_hodgkin)
- Cancer category list sorting order (alphabetical vs frequency)
- Script numbering for Phase 57
- Whether Death pseudo-treatment rows get the patient's cancer_category or empty
- DuckDB re-ingest handling (instructions vs automated)

## Deferred Ideas

None — discussion stayed within phase scope
