# Phase 113: Investigate Encounters After Death Date - Research

**Researched:** 2026-06-24
**Domain:** Post-death clinical activity data quality investigation for PCORnet CDM
**Confidence:** HIGH

## Summary

Phase 113 is a data quality drill-down investigation analyzing ~200 patients flagged with post-death clinical activity (encounters, diagnoses, or treatments occurring after recorded death dates). The core deliverable is quantifying temporal gaps in days between death dates and subsequent clinical events, formatted as a meeting-ready two-sheet xlsx with distribution bucketing and per-event detail.

This follows the established investigation script pattern (standalone, reads existing artifacts, produces styled xlsx, no upstream modification) consistent with R/59 (death date cross-tab summary) and R/30 (CONDITION linkage investigation). The technical domain centers on lubridate date arithmetic for gap calculations, openxlsx2 for meeting-presentable styling, and DuckDB queries for raw clinical event data.

**Primary recommendation:** Build R/60 as standalone investigation script reading validated_death_dates.rds, querying DuckDB ENCOUNTER/DIAGNOSIS tables and treatment_episodes.rds, computing days_after_death gaps using lubridate date subtraction, bucketing into clinically meaningful ranges (0-30, 31-90, 91-365, >1 year), and producing two-sheet xlsx (Sheet 1: per-patient summary with bucket counts/stats; Sheet 2: per-encounter detail with raw days and source table labels).

## User Constraints (from CONTEXT.md)

<user_constraints>

### Locked Decisions

**Output Structure:**
- **D-01:** Two-sheet xlsx output. Sheet 1: per-patient summary (one row per patient with count of post-death events, min/max/median gap in days, bucket assignment). Sheet 2: per-encounter detail (every individual post-death event with exact date and gap from death date in raw days).
- **D-02:** Investigation script pattern (standalone, reads existing artifacts, no upstream modification) -- consistent with R/59, R/58, R/30.

**Time Bucketing:**
- **D-03:** Gap distribution presented using clinically meaningful bucketed ranges: 0-30 days, 31-90 days, 91-365 days, >1 year. Summary sheet shows patient count per bucket.
- **D-04:** Detail sheet includes raw days_after_death column (exact days) alongside the bucket label so users can re-bucket in Excel if needed.

**Clinical Scope:**
- **D-05:** All three clinical activity types included: ENCOUNTER admits, DIAGNOSIS records, and treatment episodes. Mirrors the scope R/53 already checks.
- **D-06:** Each post-death event row should identify its source table (ENCOUNTER, DIAGNOSIS, TREATMENT) so the user can filter by activity type.

### Claude's Discretion

- Styled xlsx headers following existing meeting-presentable pattern (dark gray FF374151, white bold text, freeze panes)
- Whether to add a third summary sheet with bucket distribution cross-tabbed by activity type
- R/88 smoke test section additions

</user_constraints>

## Canonical References

### Death Date Infrastructure (PRIMARY DATA SOURCES)

**R/53_death_date_validation.R:**
- Produces `validated_death_dates.rds` with post_death_activity boolean flag, post_death_encounters/diagnoses/treatments counts, and latest_post_death_encounter dates
- Section 5 (lines 198-249) already computes post-death clinical activity across all three sources (ENCOUNTER, DIAGNOSIS, treatment_episodes)
- Logic reusable: inner_join with valid_deaths, filter for dates > DEATH_DATE, group_by patient, summarise counts and max dates
- Population: ~200 patients with post_death_activity == TRUE

**R/59_death_date_summary.R:**
- Phase 103 investigation script pattern reference
- Standalone investigation (reads validated_death_dates.rds, no upstream modification)
- Meeting-presentable xlsx styling: dark gray headers FF374151, white bold text, freeze panes, Calibri font
- Single-sheet summary with Metric/Count/Pct columns, title row, subtitle with generation date

**R/29_first_line_and_death_analysis.R:**
- Original death date analysis with DEATH-01/02/03 metrics
- Contains age_at_treatment calculation using difftime: `as.numeric(difftime(episode_start, BIRTH_DATE, units = "days")) / 365.25`

### Data Sources

**cache/outputs/validated_death_dates.rds** (R/53 output):
- Columns: ID, DEATH_DATE, DEATH_SOURCE, death_valid, validation_reason, post_death_activity (boolean), post_death_encounters (count), post_death_diagnoses (count), post_death_treatments (count), latest_post_death_encounter (date), latest_post_death_diagnosis (date), latest_post_death_treatment (date)
- Population: patients with death_valid == TRUE
- Subset: ~200 patients with post_death_activity == TRUE (exact count from R/59 output)

**DuckDB ENCOUNTER table:**
- Columns needed: ID, ADMIT_DATE, ENCOUNTERID (for detail sheet event identification)
- Access via: `get_pcornet_table("ENCOUNTER")`, parse_pcornet_date(ADMIT_DATE)

**DuckDB DIAGNOSIS table:**
- Columns needed: ID, DX_DATE, DIAGNOSISID (for detail sheet event identification)
- Access via: `get_pcornet_table("DIAGNOSIS")`, parse_pcornet_date(DX_DATE)

**cache/outputs/treatment_episodes.rds** (R/26 output):
- Columns needed: patient_id, episode_start, episode_number, treatment_type (for detail sheet event identification)

## Standard Stack

### Core Libraries
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| lubridate | 1.9.3+ | Date arithmetic and gap calculations | Tidyverse standard for date differences; `as.numeric(date1 - date2)` returns days automatically |
| dplyr | 1.2.0+ | Data manipulation and aggregation | Established pipeline standard; case_when() for bucket assignment |
| openxlsx2 | 1.4.3+ (May 2026) | Styled xlsx output | Current production xlsx library; wb_workbook() pipe-friendly API, wb_color() for hex colors |
| glue | 1.8.0 | String formatting for logging | Consistent logging pattern across investigation scripts |

### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| stringr | 1.5.1+ | String operations (minimal use) | Only if event ID formatting needed |
| tibble | 3.2.1+ | Data frame construction | summary_table construction following R/59 pattern |

### Utility Functions (Project-Specific)
| Utility | Source File | Purpose |
|---------|-------------|---------|
| get_pcornet_table() | R/utils/utils_duckdb.R | Query DuckDB tables |
| open_pcornet_con() | R/utils/utils_duckdb.R | Open DuckDB connection |
| close_pcornet_con() | R/utils/utils_duckdb.R | Close DuckDB connection |
| parse_pcornet_date() | R/utils/utils_dates.R | Parse PCORnet date strings to R Date objects |
| assert_rds_exists() | R/utils/utils_assertions.R | Validate input RDS files exist |
| assert_df_valid() | R/utils/utils_assertions.R | Validate data frame structure |

### Installation

All packages already installed in project renv (verified from R/59, R/53 imports). No new package installation required.

## Architecture Patterns

### Investigation Script Pattern (from R/59, R/30)

**Canonical structure:**
```r
# ==============================================================================
# 60_post_death_encounter_investigation.R
# ==============================================================================
#
# Purpose:
#   Drill-down investigation of ~200 patients with post-death clinical activity.
#   Quantify temporal gaps (days after death) for each encounter/diagnosis/treatment.
#
# Inputs:
#   - cache/outputs/validated_death_dates.rds (R/53 output)
#   - DuckDB ENCOUNTER table
#   - DuckDB DIAGNOSIS table
#   - cache/outputs/treatment_episodes.rds (R/26 output)
#
# Outputs:
#   - output/post_death_encounter_investigation.xlsx
#
# Decision traceability:
#   D-01: Two-sheet xlsx (per-patient summary + per-encounter detail)
#   D-02: Standalone investigation script (no upstream modification)
#   D-03: Time buckets: 0-30, 31-90, 91-365, >1 year days
#   D-04: Raw days_after_death column included for re-bucketing
#   D-05: All three activity types (ENCOUNTER, DIAGNOSIS, TREATMENT)
#   D-06: source_table column identifies event origin
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(lubridate)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")
source("R/utils/utils_assertions.R")

# Define paths
DEATH_RDS <- file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")
EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "post_death_encounter_investigation.xlsx")

# Input validation
assert_rds_exists(DEATH_RDS, script_name = "R/60")
assert_rds_exists(EPISODES_RDS, script_name = "R/60")

# Section 1: Load validated death dates
# Section 2: Query post-death encounters from DuckDB
# Section 3: Query post-death diagnoses from DuckDB
# Section 4: Query post-death treatments from RDS
# Section 5: Combine and compute gaps
# Section 6: Build per-patient summary
# Section 7: Create styled xlsx
```

### Date Gap Calculation Pattern

**Standard approach (from existing scripts):**
```r
# From R/02_harmonize_payer.R line 316
mutate(days_from_dx = as.numeric(ADMIT_DATE - first_hl_dx_date))

# From R/28_episode_classification.R line 226
mutate(days_before = as.numeric(episode_start - DX_DATE))

# From R/31_pre_diagnosis_treatments.R line 123
mutate(days_before_dx = as.numeric(first_hl_dx_date - episode_start))

# For post-death gaps (date2 - date1 where date2 > date1):
mutate(days_after_death = as.numeric(event_date - DEATH_DATE))
```

**Bucketing pattern:**
```r
mutate(
  gap_bucket = case_when(
    days_after_death <= 30 ~ "0-30 days",
    days_after_death <= 90 ~ "31-90 days",
    days_after_death <= 365 ~ "91-365 days",
    days_after_death > 365 ~ ">1 year",
    TRUE ~ NA_character_
  )
)
```

### Per-Patient Summary Pattern

**Aggregation structure (Sheet 1):**
```r
patient_summary <- post_death_events %>%
  group_by(ID, DEATH_DATE) %>%
  summarise(
    event_count = n(),
    min_gap_days = min(days_after_death),
    max_gap_days = max(days_after_death),
    median_gap_days = median(days_after_death),
    gap_bucket = case_when(
      max_gap_days <= 30 ~ "0-30 days",
      max_gap_days <= 90 ~ "31-90 days",
      max_gap_days <= 365 ~ "91-365 days",
      max_gap_days > 365 ~ ">1 year"
    ),
    .groups = "drop"
  )
```

### Styled XLSX Pattern (from R/59)

**Meeting-presentable formatting:**
```r
# Source: R/59_death_date_summary.R lines 187-248
wb <- wb_workbook()
wb$add_worksheet("Patient Summary")
wb$add_worksheet("Event Detail")

# Sheet 1: Patient Summary
# Title row
wb$add_data(sheet = "Patient Summary", x = "Post-Death Encounter Investigation",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "Patient Summary", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))

# Subtitle row
subtitle <- glue("Generated: {Sys.Date()} | Population: ~200 patients with post-death activity")
wb$add_data(sheet = "Patient Summary", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(sheet = "Patient Summary", dims = "A2",
            name = "Calibri", size = 10, color = wb_color("FF6B7280"))

# Data table starting at row 4
wb$add_data(sheet = "Patient Summary", x = patient_summary, start_row = 4, start_col = 1)

# Header styling (dark gray background FF374151, white bold text)
wb$add_fill(sheet = "Patient Summary", dims = "A4:G4", color = wb_color("FF374151"))
wb$add_font(sheet = "Patient Summary", dims = "A4:G4",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Number formatting for integer columns
wb$add_numfmt(sheet = "Patient Summary", dims = "C5:F200", numfmt = "#,##0")

# Freeze panes below header
wb$freeze_pane(sheet = "Patient Summary", firstActiveRow = 5)

# Column widths
wb$set_col_widths(sheet = "Patient Summary", cols = 1:7,
                  widths = c(15, 15, 12, 12, 12, 12, 15))
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Date gap calculation | Custom day-counting logic with loops | lubridate `as.numeric(date2 - date1)` | Built-in R Date subtraction returns difftime in days; as.numeric() extracts integer days automatically |
| Bucket assignment | Nested if-else chains | dplyr `case_when()` | Readable, maintainable; established project pattern from R/28, R/31, R/59 |
| Multi-sheet xlsx styling | Base R write.csv() loops | openxlsx2 wb_workbook() API | Already in production; pipe-friendly; meeting-presentable styling; established pattern from R/59, R/30, R/35 |
| Post-death event detection | Re-implement R/53 logic | Read validated_death_dates.rds flags | R/53 Section 5 already computes this; validated artifact exists; investigation scripts read artifacts, don't recompute |

**Key insight:** R/53 already solved post-death detection and counting. This phase drills into the HOW FAR (temporal gap quantification), not the WHETHER (boolean flag). Don't re-detect; read flags, query raw events, compute gaps.

## Common Pitfalls

### Pitfall 1: Date Subtraction Direction Error
**What goes wrong:** Computing death_date - event_date instead of event_date - death_date produces negative gaps
**Why it happens:** Post-death events occur AFTER death, so event_date > death_date. Subtraction order matters.
**How to avoid:** Always subtract earlier date from later date: `as.numeric(later_date - earlier_date)`. For post-death: `as.numeric(ADMIT_DATE - DEATH_DATE)` (event date first)
**Warning signs:** Negative days_after_death values in output; median_gap_days showing negative numbers

### Pitfall 2: Including Invalid Deaths
**What goes wrong:** Using all rows from validated_death_dates.rds without filtering death_valid == TRUE
**Why it happens:** R/53 marks some death dates as invalid (death_valid == FALSE, validation_reason = "Death date before treatment"). These must be excluded.
**How to avoid:** Filter deaths early: `valid_deaths <- readRDS(DEATH_RDS) %>% filter(death_valid == TRUE)`
**Warning signs:** Patient counts don't match R/59 DEATH-01 metric; impossible death dates in output

### Pitfall 3: Missing DuckDB Connection Cleanup
**What goes wrong:** Leaving DuckDB connections open causes "database locked" errors in subsequent scripts
**Why it happens:** R/53 pattern opens connection once, queries multiple tables, closes at end. Forgetting close_pcornet_con() leaks connection.
**How to avoid:** Always pair open_pcornet_con() with close_pcornet_con() in same section; consider on.exit(close_pcornet_con()) for error safety
**Warning signs:** R/39 pipeline runner fails on next script with "database is locked"

### Pitfall 4: Incorrect Bucket Boundaries
**What goes wrong:** Off-by-one errors in bucket boundaries (e.g., using `< 30` instead of `<= 30`, causing day 30 to fall into wrong bucket)
**Why it happens:** Misunderstanding inclusive vs exclusive boundaries in case_when() conditions
**How to avoid:** Use consistent `<=` boundaries: `<= 30`, `<= 90`, `<= 365`, `> 365`. Day 30 is "within 30 days", so inclusive boundary correct.
**Warning signs:** Manual spot-check shows days_after_death = 30 assigned to "31-90 days" bucket

### Pitfall 5: Per-Event Detail Explosion
**What goes wrong:** Millions of rows in Sheet 2 if ALL post-death events included (not just those from flagged patients)
**Why it happens:** Querying DuckDB ENCOUNTER/DIAGNOSIS tables without joining to validated_death_dates subset first
**How to avoid:** Start with `valid_deaths %>% filter(post_death_activity == TRUE)` (~200 patients), then inner_join with event queries. This limits population to flagged patients only.
**Warning signs:** Sheet 2 has >10,000 rows (implausible for ~200 patients); xlsx file size >10MB

## Code Examples

Verified patterns from canonical references:

### Date Gap Calculation (R/53 Section 5 pattern)
```r
# Source: R/53_death_date_validation.R lines 205-213 (ENCOUNTER post-death)
encounter_post_death <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ADMIT_DATE, ENCOUNTERID) %>%
  collect() %>%
  mutate(ADMIT_DATE = parse_pcornet_date(ADMIT_DATE)) %>%
  filter(!is.na(ADMIT_DATE)) %>%
  inner_join(valid_deaths %>% select(ID, DEATH_DATE), by = "ID") %>%
  filter(ADMIT_DATE > DEATH_DATE) %>%
  mutate(
    days_after_death = as.numeric(ADMIT_DATE - DEATH_DATE),
    event_date = ADMIT_DATE,
    event_id = ENCOUNTERID,
    source_table = "ENCOUNTER"
  ) %>%
  select(ID, DEATH_DATE, event_date, event_id, source_table, days_after_death)
```

### Bucket Assignment with case_when()
```r
# Standard pattern from R/28, R/31 (adapted for phase requirements)
post_death_events <- bind_rows(
  encounter_post_death,
  diagnosis_post_death,
  treatment_post_death
) %>%
  mutate(
    gap_bucket = case_when(
      days_after_death <= 30 ~ "0-30 days",
      days_after_death <= 90 ~ "31-90 days",
      days_after_death <= 365 ~ "91-365 days",
      days_after_death > 365 ~ ">1 year",
      TRUE ~ NA_character_
    )
  )
```

### Per-Patient Summary Aggregation
```r
patient_summary <- post_death_events %>%
  group_by(ID, DEATH_DATE) %>%
  summarise(
    total_events = n(),
    encounter_events = sum(source_table == "ENCOUNTER"),
    diagnosis_events = sum(source_table == "DIAGNOSIS"),
    treatment_events = sum(source_table == "TREATMENT"),
    min_gap_days = min(days_after_death),
    max_gap_days = max(days_after_death),
    median_gap_days = median(days_after_death),
    earliest_post_death_event = min(event_date),
    latest_post_death_event = max(event_date),
    # Assign patient to bucket based on maximum gap
    gap_bucket = case_when(
      max_gap_days <= 30 ~ "0-30 days",
      max_gap_days <= 90 ~ "31-90 days",
      max_gap_days <= 365 ~ "91-365 days",
      max_gap_days > 365 ~ ">1 year"
    ),
    .groups = "drop"
  ) %>%
  arrange(desc(max_gap_days))  # Order by longest gap first
```

### Two-Sheet XLSX with Styled Headers
```r
# Source: R/59_death_date_summary.R pattern (lines 187-250)
wb <- wb_workbook()

# Sheet 1: Patient Summary
wb$add_worksheet("Patient Summary")
wb$add_data(sheet = "Patient Summary", x = "Post-Death Clinical Activity Investigation",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "Patient Summary", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Patient Summary", dims = "A1:J1")

subtitle <- glue("Generated: {Sys.Date()} | Population: {nrow(patient_summary)} patients with post-death activity")
wb$add_data(sheet = "Patient Summary", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(sheet = "Patient Summary", dims = "A2",
            name = "Calibri", size = 10, color = wb_color("FF6B7280"))
wb$merge_cells(sheet = "Patient Summary", dims = "A2:J2")

# Data starting row 4
wb$add_data(sheet = "Patient Summary", x = patient_summary, start_row = 4, start_col = 1)

# Header styling (dark gray FF374151, white bold)
header_cols <- ncol(patient_summary)
wb$add_fill(sheet = "Patient Summary", dims = glue("A4:{LETTERS[header_cols]}4"),
            color = wb_color("FF374151"))
wb$add_font(sheet = "Patient Summary", dims = glue("A4:{LETTERS[header_cols]}4"),
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Freeze panes
wb$freeze_pane(sheet = "Patient Summary", firstActiveRow = 5)

# Sheet 2: Event Detail
wb$add_worksheet("Event Detail")
# [Repeat header pattern for Sheet 2]
wb$add_data(sheet = "Event Detail", x = post_death_events, start_row = 4, start_col = 1)

wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| openxlsx (v4.x) | openxlsx2 (v1.x) | 2023 rewrite | Pipe-friendly API, better performance, wb_color() replaces createStyle(); project already migrated |
| Base R difftime() verbose | lubridate date subtraction | Ongoing | `as.numeric(date2 - date1)` cleaner than `as.numeric(difftime(date2, date1, units = "days"))` |
| Manual bucket assignment with ifelse() | dplyr case_when() | dplyr 0.7+ (2017) | Readable, maintainable; established project pattern |

**Deprecated/outdated:**
- openxlsx v4.x createStyle() API: Replaced by openxlsx2 wb_add_fill(), wb_add_font() in project (R/59 canonical)
- Base R for() loops for multi-table queries: DuckDB + dplyr collect() pattern standard (R/53 pattern)

## Open Questions

None identified. All technical patterns verified from canonical references (R/53, R/59). Data sources exist. Investigation scope defined by user decisions.

## Environment Availability

> Phase has external dependencies (DuckDB, RDS artifacts) - audit required.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| DuckDB connection | ENCOUNTER/DIAGNOSIS queries | ✓ | Verified via R/53 | — |
| validated_death_dates.rds | Death date population | ✓ | R/53 output exists | — |
| treatment_episodes.rds | Treatment post-death events | ✓ | R/26 output exists | — |
| R/utils/ utility functions | DuckDB access, date parsing | ✓ | Project utilities | — |
| openxlsx2 package | Styled xlsx output | ✓ | 1.4.3 in renv | — |
| lubridate package | Date arithmetic | ✓ | 1.9.3 in renv | — |

**Missing dependencies with no fallback:**
None — all dependencies verified available

**Missing dependencies with fallback:**
None — investigation script has no fallback scenario

## Sources

### Primary (HIGH confidence)
- R/53_death_date_validation.R (canonical reference for post-death detection logic, Section 5 lines 198-249)
- R/59_death_date_summary.R (canonical reference for investigation script pattern and xlsx styling)
- R/30_condition_linkage_investigation.R (canonical reference for standalone investigation pattern)
- 113-CONTEXT.md (user decisions D-01 through D-06)
- Existing codebase date gap patterns (R/02 line 316, R/28 line 226, R/31 line 123, R/29 line 129)

### Secondary (MEDIUM confidence)
- [CRAN openxlsx2 package](https://cran.r-project.org/package=openxlsx2) - Version 1.4.3 published May 25, 2026
- [openxlsx2 documentation](https://janmarvin.github.io/openxlsx2/) - wb_workbook() API reference
- [lubridate date differences](https://lubridate.tidyverse.org/reference/lubridate-package.html) - Date subtraction returns difftime in days
- [R date difference tutorial](https://www.statology.org/lubridate-difference-between-two-dates/) - as.numeric() extraction pattern

### Tertiary (LOW confidence)
None used — all findings verified from project codebase or official CRAN documentation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All packages verified in project renv, canonical scripts use these libraries
- Architecture: HIGH - Direct replication of R/59 investigation pattern with R/53 data source patterns
- Pitfalls: HIGH - All pitfalls derived from code review of R/53, R/59; date subtraction direction from mathematical logic
- Environment: HIGH - All dependencies verified available from existing artifacts and renv

**Research date:** 2026-06-24
**Valid until:** 30 days (stable investigation pattern, no fast-moving dependencies)

**Phase requirement coverage:**
- Phase has no formal requirement IDs in REQUIREMENTS.md (not yet mapped)
- Investigation addresses data quality question: "how far after death do the ~200 patients' encounters occur?"
- Deliverable: Two-sheet xlsx with temporal gap quantification
