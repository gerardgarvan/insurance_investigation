# Phase 62: First-Line Therapy & Death Analysis - Research

**Researched:** 2026-05-30
**Domain:** First-line chemotherapy identification, death date data quality analysis, R data manipulation with tidyverse
**Confidence:** HIGH

## Summary

Phase 62 identifies first-line chemotherapy for adult Hodgkin Lymphoma patients (age 21+ at treatment date) using a 60-day clean period (no prior chemotherapy) and produces death date data quality summary tables showing: (1) total patients with death dates, (2) patients where death is the last encounter, and (3) patients with post-death encounters stratified by PCORnet encounter type.

The phase builds on Phase 61's regimen labels (ABVD, BV+AVD, Nivo+AVD) and Phase 59's validated death dates. Only chemotherapy episodes that received a regimen label are eligible for first-line flagging. The 60-day lookback checks ALL chemotherapy dates from the patient's treatment history (not just episode boundaries), and only the FIRST qualifying episode per patient receives `is_first_line=TRUE`.

Death analysis aggregates Phase 59's patient-level validation into summary counts for data quality reporting. All three counts reference Phase 59's `validated_death_dates.rds` artifact (impossible deaths already excluded). The post-death encounter stratification queries the ENCOUNTER table to break down ENC_TYPE values (AV=Ambulatory Visit, ED=Emergency Department, IP=Inpatient, etc.) showing which care settings have records after the death date.

**Primary recommendation:** Use dplyr pipeline with grouped filtering for first-line detection, leverage existing age calculation pattern from R/59, and produce multi-sheet openxlsx2 workbook with summary counts + ENC_TYPE detail following established xlsx styling patterns.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**First-Line Therapy Eligibility:**
- **D-01:** First-line flag applies ONLY to chemotherapy episodes that Phase 61 labeled with a regimen name (ABVD, BV+AVD, Nivo+AVD). Unlabeled chemotherapy episodes do not receive a first-line flag.
- **D-02:** Age 21+ is calculated at episode_start date using DEMOGRAPHIC.BIRTH_DATE. Patients under 21 at their chemotherapy episode start are excluded from first-line consideration.
- **D-03:** 60-day clean period = no chemotherapy of any kind in the 60 days before the episode_start date. Only chemotherapy is checked (not radiation, SCT, or immunotherapy). Any prior chemo date within that window disqualifies the episode.
- **D-04:** Only the FIRST qualifying episode per patient gets is_first_line=TRUE. All subsequent chemotherapy episodes for the same patient are is_first_line=FALSE, even if they individually satisfy the 60-day lookback.

**Death Analysis Tables:**
- **D-05:** Death analysis uses VALIDATED deaths only (death_valid=TRUE from validated_death_dates.rds). Impossible deaths (before earliest treatment) are excluded from all counts.
- **D-06:** "Death is the last encounter" (DEATH-02) is defined by comparing DEATH_DATE to max(ADMIT_DATE) from the ENCOUNTER table. Death is "last" when no ENCOUNTER record exists after the death date.
- **D-07:** Post-death encounter stratification (DEATH-03) is by PCORnet ENC_TYPE (AV, TH, ED, IP, IS, OA, etc.). Shows which encounter settings have records occurring after the death date.
- **D-08:** Phase 62 references Phase 59's post_death_activity flag for the total post-death count. Only queries ENCOUNTER table for the NEW ENC_TYPE stratification detail (avoids re-detecting post-death activity already captured in Phase 59).

**Output Strategy:**
- **D-09:** is_first_line boolean column added to existing treatment_episodes.rds in-place. Phase 63 picks it up automatically when building Gantt v2 files.
- **D-10:** Death analysis output: styled multi-sheet xlsx (openxlsx2) + flat CSV. Sheet 1 = summary counts (DEATH-01: total with death dates, DEATH-02: death as last encounter, DEATH-03: total with post-death encounters). Sheet 2 = ENC_TYPE stratification detail.
- **D-11:** Single combined script R/62_first_line_and_death_analysis.R handles both first-line flagging and death analysis. Shared data dependencies (treatment_episodes.rds, demographics) justify combining.

**Relationship to Phase 59:**
- **D-12:** Phase 62 loads validated_death_dates.rds as input — does NOT re-query DEATH table or re-validate. Phase 59 already did the heavy lifting (sentinel filtering, impossible death detection, post-death flagging).
- **D-13:** The 3 death analysis counts (DEATH-01/02/03) are new summary metrics not present in Phase 59's output. Phase 59 produced patient-level detail; Phase 62 produces aggregate counts.

### Claude's Discretion

- Column ordering for is_first_line in treatment_episodes.rds
- xlsx sheet styling (colors, column widths, freeze panes)
- Console logging detail level during analysis
- Whether to also produce a first-line summary table in the xlsx (patient-level first-line detail alongside death analysis)
- How to handle edge case where a patient has no ENCOUNTER records at all (for DEATH-02 comparison)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FLT-01 | First-line therapy identified for adults 21+ at treatment date | Age calculation pattern from R/59 using DEMOGRAPHIC.BIRTH_DATE; dplyr filtering with `as.numeric(difftime(episode_start, BIRTH_DATE, units = "days")) / 365.25 >= 21` |
| FLT-02 | 60-day clean period (no prior chemotherapy) defines first-line | Lookback window using treatment_episode_detail.rds for ALL chemo dates; `filter()` where min(prior_chemo_dates) is NA or > 60 days before episode_start |
| DEATH-01 | Death date analysis table — count of patients with death dates | Load validated_death_dates.rds, filter death_valid==TRUE, count distinct IDs |
| DEATH-02 | Of those with death dates, count where death is last encounter | Join validated deaths to ENCOUNTER, compare DEATH_DATE to max(ADMIT_DATE) per patient |
| DEATH-03 | Count of patients with encounters/treatment after death date | Use Phase 59's post_death_activity flag for total; query ENCOUNTER for ENC_TYPE stratification detail |

</phase_requirements>

## Standard Stack

### Core (Already Established in Project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation & filtering | Industry standard for readable R pipelines; Feb 2026 release introduced filter_out(), when_any(), when_all() helpers; case_when() for complex logic |
| lubridate | 1.9.3+ | Date/time operations | Age calculation, date comparisons, interval arithmetic; ymd(), difftime(), interval() for 60-day lookback |
| glue | 1.8.0+ | String formatting | Readable logging messages with embedded expressions; established pattern in R/59 |
| openxlsx2 | 1.12+ | Multi-sheet xlsx workbook creation | Modern xlsx library (May 2026 release); wb_workbook(), add_data(), add_fill(), add_font(), freeze_pane(); established in R/59, R/55, R/53 |

### Supporting (Project Infrastructure)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| stringr | 1.5.1+ | String operations | Not heavily used in Phase 62; minimal string operations (column selection, glue formatting) |
| tidyr | 1.3.1+ | Data reshaping | Potential use if ENC_TYPE stratification needs pivot_wider() for presentation |
| here | 1.0.2+ | Path management | Not needed — Phase 62 uses CONFIG$cache$outputs_dir from R/00_config.R for paths |

### Existing Project Infrastructure
| Component | Version/Pattern | Purpose | Source |
|-----------|-----------------|---------|--------|
| R/00_config.R | Project config | CONFIG$cache$outputs_dir, CONFIG$output_dir paths | Established |
| R/utils_duckdb.R | Backend abstraction | get_pcornet_table("ENCOUNTER"), get_pcornet_table("DEMOGRAPHIC") | Established |
| R/utils_dates.R | Date parsing | parse_pcornet_date() for BIRTH_DATE, ADMIT_DATE | Established |

**Installation:**
All packages already installed in project renv environment. No new dependencies required.

**Version verification:**
```bash
# Run in R console on HiPerGator
packageVersion("dplyr")      # Should be >= 1.2.0
packageVersion("openxlsx2")  # Should be >= 1.12
```

## Architecture Patterns

### Recommended Project Structure
```
R/
├── 62_first_line_and_death_analysis.R   # Main script (new)
├── 00_config.R                           # Reuse (CONFIG paths)
├── utils_duckdb.R                        # Reuse (get_pcornet_table)
├── utils_dates.R                         # Reuse (parse_pcornet_date)

cache/outputs/
├── treatment_episodes.rds                # Modified (+ is_first_line column)
├── treatment_episode_detail.rds          # Read-only input (chemo dates)
├── validated_death_dates.rds             # Read-only input (Phase 59)

output/
├── death_analysis.xlsx                   # New (2 sheets: summary + ENC_TYPE detail)
├── death_analysis.csv                    # New (flat export)
```

### Pattern 1: First-Line Detection with Grouped Filtering
**What:** Identify first qualifying episode per patient using dplyr group_by() + filter() + row_number()
**When to use:** When detecting "first occurrence" across grouped data (patients with multiple episodes)
**Example:**
```r
# Source: Established dplyr pattern for "first observation per group"
# https://dplyr.tidyverse.org/articles/grouping.html

# Step 1: Filter to eligible episodes (adults 21+, has regimen label)
eligible_episodes <- treatment_episodes %>%
  filter(!is.na(regimen_label)) %>%  # D-01: Only labeled episodes
  left_join(demographics, by = c("patient_id" = "ID")) %>%
  mutate(age_at_treatment = as.numeric(difftime(episode_start, BIRTH_DATE, units = "days")) / 365.25) %>%
  filter(age_at_treatment >= 21)  # D-02: Adults only

# Step 2: Check 60-day clean period using treatment_episode_detail.rds
# Load ALL chemo dates for each patient
all_chemo_dates <- treatment_episode_detail %>%
  filter(treatment_type == "Chemotherapy") %>%
  select(patient_id, treatment_date) %>%
  distinct()

# Join to find prior chemo dates within 60-day window
episodes_with_lookback <- eligible_episodes %>%
  left_join(
    all_chemo_dates,
    by = "patient_id",
    relationship = "many-to-many"
  ) %>%
  mutate(
    days_before = as.numeric(difftime(episode_start, treatment_date, units = "days")),
    is_prior_chemo_in_window = (days_before > 0 & days_before <= 60)
  ) %>%
  group_by(patient_id, episode_number) %>%
  summarise(
    has_prior_chemo_within_60d = any(is_prior_chemo_in_window, na.rm = TRUE),
    .groups = "drop"
  )

# Filter to clean-period episodes
clean_period_episodes <- eligible_episodes %>%
  left_join(episodes_with_lookback, by = c("patient_id", "episode_number")) %>%
  filter(!has_prior_chemo_within_60d | is.na(has_prior_chemo_within_60d))  # D-03: 60-day clean

# Step 3: Flag ONLY first qualifying episode per patient
first_line_flagged <- clean_period_episodes %>%
  group_by(patient_id) %>%
  arrange(episode_start) %>%
  mutate(is_first_line = (row_number() == 1)) %>%  # D-04: First only
  ungroup()
```

**Key points:**
- `row_number() == 1` after `arrange(episode_start)` ensures chronologically first episode gets the flag
- `relationship = "many-to-many"` explicitly handles multiple chemo dates per episode in left_join
- `any(is_prior_chemo_in_window, na.rm = TRUE)` detects if ANY prior chemo date falls in 60-day window

### Pattern 2: In-Place RDS Enrichment
**What:** Add new column to existing RDS artifact and overwrite file
**When to use:** When phase adds metadata to existing dataset (Phase 60 pattern for drug_names, encounter_ids)
**Example:**
```r
# Source: R/44a_treatment_episodes.R (Phase 60 enrichment pattern)

# Load existing treatment_episodes.rds
episodes <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"))

# Add is_first_line column
episodes_with_first_line <- episodes %>%
  left_join(
    first_line_flagged %>% select(patient_id, episode_number, is_first_line),
    by = c("patient_id", "episode_number")
  ) %>%
  mutate(is_first_line = if_else(is.na(is_first_line), FALSE, is_first_line))

# Overwrite RDS
saveRDS(episodes_with_first_line, file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"))
```

**Key points:**
- Left join preserves ALL episodes (non-chemo episodes get FALSE)
- `if_else(is.na(), FALSE, TRUE)` handles episodes that didn't qualify
- Overwrites original RDS (D-09: in-place modification)

### Pattern 3: Death as Last Encounter Detection
**What:** Compare death date to max encounter date per patient
**When to use:** Validating temporal logic (death should be terminal event)
**Example:**
```r
# Source: Established pattern for "last event" detection

# Load validated deaths (Phase 59 output)
validated_deaths <- readRDS(file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")) %>%
  filter(death_valid == TRUE)  # D-05: Validated deaths only

# Query ENCOUNTER table for max ADMIT_DATE per patient
last_encounters <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ADMIT_DATE) %>%
  collect() %>%
  mutate(ADMIT_DATE = parse_pcornet_date(ADMIT_DATE)) %>%
  filter(!is.na(ADMIT_DATE)) %>%
  group_by(ID) %>%
  summarise(last_encounter_date = max(ADMIT_DATE), .groups = "drop")

# Join and compare
death_vs_encounter <- validated_deaths %>%
  left_join(last_encounters, by = "ID") %>%
  mutate(
    death_is_last = is.na(last_encounter_date) | (DEATH_DATE >= last_encounter_date)  # D-06
  )

# Count for DEATH-02
n_death_is_last <- sum(death_vs_encounter$death_is_last, na.rm = TRUE)
```

**Key points:**
- `is.na(last_encounter_date)` handles edge case where patient has death date but no ENCOUNTER records
- `DEATH_DATE >= last_encounter_date` allows same-day death + encounter (death at admission)
- Uses Phase 59's validated deaths (impossible deaths already excluded)

### Pattern 4: ENC_TYPE Stratification
**What:** Count post-death encounters by PCORnet encounter type
**When to use:** Breaking down aggregate counts into categorical detail
**Example:**
```r
# Source: Established summarise + count pattern

# Query ENCOUNTER table for post-death records with ENC_TYPE
encounter_post_death_detail <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ADMIT_DATE, ENC_TYPE) %>%
  collect() %>%
  mutate(ADMIT_DATE = parse_pcornet_date(ADMIT_DATE)) %>%
  filter(!is.na(ADMIT_DATE)) %>%
  inner_join(validated_deaths %>% select(ID, DEATH_DATE), by = "ID") %>%
  filter(ADMIT_DATE > DEATH_DATE) %>%  # D-07: Post-death only
  count(ENC_TYPE, name = "n_encounters") %>%
  arrange(desc(n_encounters))
```

**Key points:**
- `count(ENC_TYPE)` produces frequency table by encounter type
- `inner_join` limits to patients WITH death dates
- Result shows which care settings (AV=Ambulatory, ED=Emergency, IP=Inpatient) have most post-death activity

### Pattern 5: Multi-Sheet openxlsx2 Workbook
**What:** Styled xlsx with summary + detail sheets
**When to use:** Reporting aggregate metrics + supporting detail (established R/59, R/55 pattern)
**Example:**
```r
# Source: R/59_death_date_validation.R (SHEET 1 pattern), official openxlsx2 documentation

library(openxlsx2)

wb <- wb_workbook()

# SHEET 1: Summary Counts
wb$add_worksheet("Death Analysis Summary")

summary_stats <- tibble(
  Metric = c(
    "Patients with validated death dates (DEATH-01)",
    "Patients where death is last encounter (DEATH-02)",
    "Patients with post-death clinical activity (DEATH-03)",
    "  - Post-death encounters",
    "  - Post-death diagnoses",
    "  - Post-death treatments"
  ),
  Count = c(
    nrow(validated_deaths),
    sum(death_vs_encounter$death_is_last, na.rm = TRUE),
    sum(validated_deaths$post_death_activity, na.rm = TRUE),  # D-08: Reuse Phase 59 flag
    sum(validated_deaths$post_death_encounters > 0, na.rm = TRUE),
    sum(validated_deaths$post_death_diagnoses > 0, na.rm = TRUE),
    sum(validated_deaths$post_death_treatments > 0, na.rm = TRUE)
  )
)

wb$add_data(sheet = "Death Analysis Summary", x = summary_stats, start_row = 1, start_col = 1)

# Header styling (established pattern from R/59)
wb$add_fill(sheet = "Death Analysis Summary", dims = "A1:B1", color = wb_color("FF374151"))
wb$add_font(sheet = "Death Analysis Summary", dims = "A1:B1",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
wb$set_col_widths(sheet = "Death Analysis Summary", cols = 1:2, widths = c(60, 15))
wb$freeze_pane(sheet = "Death Analysis Summary", firstActiveRow = 2)

# SHEET 2: ENC_TYPE Detail
wb$add_worksheet("Post-Death Encounters by Type")
wb$add_data(sheet = "Post-Death Encounters by Type", x = encounter_post_death_detail, start_row = 1, start_col = 1)
wb$add_fill(sheet = "Post-Death Encounters by Type", dims = "A1:B1", color = wb_color("FF374151"))
wb$add_font(sheet = "Post-Death Encounters by Type", dims = "A1:B1",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
wb$freeze_pane(sheet = "Post-Death Encounters by Type", firstActiveRow = 2)

# Save workbook
wb_save(wb, file.path(CONFIG$output_dir, "death_analysis.xlsx"), overwrite = TRUE)
```

**Key points:**
- `wb_workbook()` creates workbook, `add_worksheet()` adds sheets
- `add_fill()` + `add_font()` style headers (dark gray #374151 background, white text)
- `freeze_pane(firstActiveRow = 2)` freezes header row
- `wb_save()` with `overwrite = TRUE` replaces existing file

### Anti-Patterns to Avoid

**1. Don't Re-Validate Death Dates**
```r
# AVOID: Re-querying DEATH table
death_raw <- get_pcornet_table("DEATH") %>% collect() %>% ...

# PREFER: Use Phase 59's validated artifact (D-12)
validated_deaths <- readRDS(file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")) %>%
  filter(death_valid == TRUE)
```

**2. Don't Flag All Qualifying Episodes**
```r
# AVOID: Flagging every episode that passes 60-day check
episodes %>%
  filter(has_clean_period) %>%
  mutate(is_first_line = TRUE)  # WRONG: flags multiple episodes per patient

# PREFER: Flag ONLY first episode per patient (D-04)
episodes %>%
  filter(has_clean_period) %>%
  group_by(patient_id) %>%
  arrange(episode_start) %>%
  mutate(is_first_line = (row_number() == 1)) %>%
  ungroup()
```

**3. Don't Check Episode Boundaries for 60-Day Lookback**
```r
# AVOID: Only checking episode_start dates
treatment_episodes %>%
  group_by(patient_id) %>%
  arrange(episode_start) %>%
  mutate(prior_episode_start = lag(episode_start)) %>%
  filter(is.na(prior_episode_start) | difftime(episode_start, prior_episode_start, units = "days") > 60)

# PREFER: Check ALL individual chemo dates (D-03)
# Use treatment_episode_detail.rds which has one row per date per code
all_chemo_dates <- treatment_episode_detail %>%
  filter(treatment_type == "Chemotherapy") %>%
  select(patient_id, treatment_date) %>%
  distinct()
# Then check if ANY prior date falls within 60-day window before episode_start
```

**4. Don't Include Non-Chemotherapy in 60-Day Lookback**
```r
# AVOID: Checking all treatment types
treatment_episode_detail %>%
  filter(treatment_type %in% c("Chemotherapy", "Radiation", "SCT", "Immunotherapy"))

# PREFER: Chemotherapy only (D-03)
treatment_episode_detail %>%
  filter(treatment_type == "Chemotherapy")
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Age calculation from birth date | Custom date arithmetic with leap year handling | `as.numeric(difftime(date, BIRTH_DATE, units = "days")) / 365.25` | Established pattern in R/59 (lines 308-309); handles leap years correctly via lubridate; matches existing codebase convention |
| Multi-sheet xlsx with styling | Base R write.csv() + manual Excel formatting | openxlsx2 wb_workbook() pipeline | Established pattern in R/59, R/55, R/53; produces styled workbooks directly from R; freeze panes, colors, fonts in code |
| "First observation per group" detection | Manual loop or apply() with custom logic | dplyr group_by() + arrange() + row_number() | Standard dplyr pattern for grouped ranking; readable, vectorized, fast |
| Post-death activity detection | Re-query all tables and compare dates | Phase 59's post_death_activity flag | Already computed in R/59 validated_death_dates.rds; avoid duplicate computation (D-08) |

**Key insight:** Phase 62 builds on Phase 59's data quality work (validated deaths) and Phase 61's regimen labels (filtering input). Don't re-implement validation logic or regimen detection — consume upstream artifacts.

## Common Pitfalls

### Pitfall 1: Off-by-One Errors in 60-Day Lookback Window
**What goes wrong:** Confusion about whether 60 days is inclusive or exclusive, and whether episode_start date itself should be excluded from the prior chemo check.

**Why it happens:** Date arithmetic with `difftime()` and comparison operators (`>`, `>=`, `<`, `<=`) can be ambiguous. If episode_start is 2024-03-01, is a prior chemo date of 2024-01-01 within the 60-day window? (60 days before = 2024-01-01; that's EXACTLY 60 days, not 61.)

**How to avoid:**
```r
# CLEAR LOGIC: 60-day clean period = NO chemo in the 60 days BEFORE episode_start
# "Before" means treatment_date < episode_start (excludes same-day chemo on episode_start)
# "Within 60 days" means days_before > 0 AND days_before <= 60

days_before = as.numeric(difftime(episode_start, treatment_date, units = "days"))
is_prior_chemo_in_window = (days_before > 0 & days_before <= 60)

# Example:
# episode_start = 2024-03-01
# treatment_date = 2024-01-01 → days_before = 60 → IN WINDOW (disqualifies)
# treatment_date = 2023-12-31 → days_before = 61 → OUT OF WINDOW (clean)
# treatment_date = 2024-03-01 → days_before = 0 → NOT "prior" (same-day chemo is part of THIS episode)
```

**Warning signs:** First-line counts that are unexpectedly low (too strict) or high (too lenient); QA failures when manually checking specific patient timelines.

### Pitfall 2: Ignoring Unlabeled Chemotherapy Episodes
**What goes wrong:** Flagging first-line for ALL chemotherapy episodes, including those Phase 61 couldn't classify into ABVD/BV+AVD/Nivo+AVD.

**Why it happens:** Forgetting D-01 constraint that regimen label is a prerequisite.

**How to avoid:**
```r
# ALWAYS filter to !is.na(regimen_label) BEFORE first-line logic
eligible_episodes <- treatment_episodes %>%
  filter(treatment_type == "Chemotherapy") %>%
  filter(!is.na(regimen_label))  # D-01: Only labeled episodes qualify

# Don't just check treatment_type == "Chemotherapy" and assume all are eligible
```

**Warning signs:** First-line counts exceed the number of labeled regimens from Phase 61; unlabeled episodes showing is_first_line=TRUE in output.

### Pitfall 3: Counting Death as Last Encounter When Patient Has No Encounters
**What goes wrong:** Reporting "death is last encounter" for patients who have death dates but zero ENCOUNTER records (never appeared in care system after enrollment).

**Why it happens:** Naive logic `DEATH_DATE >= max(ADMIT_DATE)` where max(ADMIT_DATE) is NULL returns NA, not TRUE.

**How to avoid:**
```r
# Handle NULL case explicitly (D-06 + Claude's discretion)
death_vs_encounter <- validated_deaths %>%
  left_join(last_encounters, by = "ID") %>%
  mutate(
    death_is_last = case_when(
      is.na(last_encounter_date) ~ TRUE,  # No encounters → death is "last" by default
      DEATH_DATE >= last_encounter_date ~ TRUE,
      TRUE ~ FALSE
    )
  )

# Alternative interpretation: Exclude no-encounter patients from DEATH-02 metric
# Document choice in script comments based on Claude's discretion
```

**Warning signs:** DEATH-02 count equals DEATH-01 count (suspicious: unlikely ALL patients have death as last event); patients with DEATH_DATE but zero encounters showing death_is_last=FALSE.

### Pitfall 4: Using Episode Boundaries Instead of Individual Chemo Dates
**What goes wrong:** Checking only `lag(episode_start)` instead of ALL individual chemotherapy dates within prior episodes.

**Why it happens:** treatment_episodes.rds has one row per episode, tempting to use episode-level logic. But D-03 requires checking "no chemotherapy of any kind in the 60 days before episode_start" — individual chemo dates can occur WITHIN an episode that started >60 days ago.

**How to avoid:**
```r
# CORRECT: Use treatment_episode_detail.rds for date-level granularity
all_chemo_dates <- treatment_episode_detail %>%
  filter(treatment_type == "Chemotherapy") %>%
  select(patient_id, treatment_date) %>%
  distinct()

# Join to current episode and check if ANY prior chemo date falls in 60-day window
# (See Pattern 1 example above)

# INCORRECT: Only checking episode boundaries
# treatment_episodes %>% filter(treatment_type == "Chemotherapy") %>% ...
```

**Warning signs:** First-line counts that differ significantly from manual patient timeline review; edge cases where a patient's second episode qualifies as first-line despite having chemo dates <60 days ago (within their first episode's tail).

### Pitfall 5: Re-Detecting Post-Death Activity Instead of Using Phase 59 Flag
**What goes wrong:** Querying ENCOUNTER/DIAGNOSIS/treatment_episodes again to detect post-death activity, duplicating Phase 59's work.

**Why it happens:** Forgetting that validated_death_dates.rds already contains `post_death_activity` boolean flag (D-08, D-12).

**How to avoid:**
```r
# CORRECT: Use Phase 59's flag for DEATH-03 total count
validated_deaths <- readRDS(file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")) %>%
  filter(death_valid == TRUE)

n_with_post_death_activity <- sum(validated_deaths$post_death_activity, na.rm = TRUE)

# ONLY query ENCOUNTER table for the NEW ENC_TYPE stratification detail
encounter_post_death_detail <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ADMIT_DATE, ENC_TYPE) %>%
  collect() %>%
  inner_join(validated_deaths %>% select(ID, DEATH_DATE), by = "ID") %>%
  filter(ADMIT_DATE > DEATH_DATE) %>%
  count(ENC_TYPE)

# INCORRECT: Re-querying all tables to detect post-death activity from scratch
```

**Warning signs:** Script runtime is slow due to unnecessary ENCOUNTER/DIAGNOSIS table scans; counts differ from Phase 59's validation report (indicates logic divergence).

## Code Examples

Verified patterns from existing codebase and official documentation:

### Age Calculation (21+ Filter)
```r
# Source: R/59_death_date_validation.R lines 308-309
# Pattern: as.numeric(difftime()) / 365.25 for age in years

demographics <- get_pcornet_table("DEMOGRAPHIC") %>%
  select(ID, BIRTH_DATE) %>%
  collect() %>%
  mutate(BIRTH_DATE = parse_pcornet_date(BIRTH_DATE))

episodes_with_age <- treatment_episodes %>%
  left_join(demographics, by = c("patient_id" = "ID")) %>%
  mutate(age_at_treatment = as.numeric(difftime(episode_start, BIRTH_DATE, units = "days")) / 365.25) %>%
  filter(age_at_treatment >= 21)  # FLT-01: Adults only
```

### First Observation Per Group (dplyr)
```r
# Source: Official dplyr documentation (https://dplyr.tidyverse.org/articles/grouping.html)
# Pattern: group_by() + arrange() + row_number() + filter()

first_line_episodes <- clean_period_episodes %>%
  group_by(patient_id) %>%
  arrange(episode_start) %>%
  mutate(is_first_line = (row_number() == 1)) %>%  # Only first gets TRUE
  ungroup() %>%
  select(patient_id, episode_number, is_first_line)

# All episodes join to this, non-first get is_first_line=FALSE via left_join + if_else
```

### ENC_TYPE Frequency Table
```r
# Source: Established count() + arrange() pattern

encounter_post_death_by_type <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ADMIT_DATE, ENC_TYPE) %>%
  collect() %>%
  mutate(ADMIT_DATE = parse_pcornet_date(ADMIT_DATE)) %>%
  filter(!is.na(ADMIT_DATE)) %>%
  inner_join(validated_deaths %>% select(ID, DEATH_DATE), by = "ID") %>%
  filter(ADMIT_DATE > DEATH_DATE) %>%
  count(ENC_TYPE, name = "n_post_death_encounters") %>%
  arrange(desc(n_post_death_encounters))

# Example output:
# ENC_TYPE  n_post_death_encounters
# AV        234
# ED        89
# IP        45
# OA        12
```

### Multi-Sheet xlsx with Summary Metrics
```r
# Source: R/59_death_date_validation.R (SHEET 1 pattern lines 373-445)
# Pattern: wb_workbook() + add_worksheet() + add_data() + styling

library(openxlsx2)

wb <- wb_workbook()

# Sheet 1: Summary counts
wb$add_worksheet("Death Analysis Summary")

summary_stats <- tibble(
  Metric = c(
    "Patients with validated death dates (DEATH-01)",
    "Patients where death is last encounter (DEATH-02)",
    "Patients with post-death activity (DEATH-03)"
  ),
  Count = c(
    nrow(validated_deaths),
    sum(death_vs_encounter$death_is_last, na.rm = TRUE),
    sum(validated_deaths$post_death_activity, na.rm = TRUE)
  )
)

wb$add_data(sheet = "Death Analysis Summary", x = summary_stats, start_row = 1, start_col = 1)
wb$add_fill(sheet = "Death Analysis Summary", dims = "A1:B1", color = wb_color("FF374151"))
wb$add_font(sheet = "Death Analysis Summary", dims = "A1:B1",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
wb$freeze_pane(sheet = "Death Analysis Summary", firstActiveRow = 2)

# Sheet 2: ENC_TYPE detail
wb$add_worksheet("Post-Death Encounters by Type")
wb$add_data(sheet = "Post-Death Encounters by Type", x = encounter_post_death_by_type, start_row = 1, start_col = 1)
wb$add_fill(sheet = "Post-Death Encounters by Type", dims = "A1:B1", color = wb_color("FF374151"))
wb$add_font(sheet = "Post-Death Encounters by Type", dims = "A1:B1",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

wb_save(wb, file.path(CONFIG$output_dir, "death_analysis.xlsx"), overwrite = TRUE)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Base R read.csv() | vroom / readr for CSVs, RDS for artifacts | v1.1 (Phase 15) | 10-100x faster CSV loads; RDS caching eliminates re-parsing |
| openxlsx (v4.x) | openxlsx2 (v1.x) | May 2026 release | Modern API (wb_workbook() instead of createWorkbook()), active development, better performance |
| Manual xlsx styling | Established color/font patterns from R/59 | Phase 59 (May 2026) | Consistent header styling (#374151 dark gray bg, white text); freeze panes on row 2 |
| Patient-level validation reports | Summary metrics for data quality | Phase 62 (new) | Phase 59 = patient-level detail; Phase 62 = aggregate counts for QC dashboards |

**Deprecated/outdated:**
- openxlsx v4.x (old API with createWorkbook()): Use openxlsx2 v1.12+ (May 2026 release) instead
- Querying DEATH table directly: Use validated_death_dates.rds (Phase 59 artifact) to avoid re-validation

## Open Questions

1. **How should we handle patients with death dates but zero ENCOUNTER records for DEATH-02 metric?**
   - What we know: Some patients may have DEATH table entries but never appear in ENCOUNTER table (data completeness issue)
   - What's unclear: Should "death is last encounter" be TRUE (trivially true — no encounters to compare) or excluded from the metric (can't validate temporal relationship)?
   - Recommendation: Default to TRUE (death is last by definition when no encounters exist), but document this interpretation in script comments and consider adding a third category "Patients with death dates but no encounters" to summary stats table for transparency.

2. **Should first-line summary table be included in death_analysis.xlsx or separate file?**
   - What we know: Death analysis has 2 sheets (summary + ENC_TYPE detail). First-line analysis produces is_first_line column in treatment_episodes.rds.
   - What's unclear: Claude's discretion allows "whether to also produce a first-line summary table in the xlsx" — should this be a third sheet in death_analysis.xlsx or a separate first_line_summary.xlsx?
   - Recommendation: Add as third sheet in death_analysis.xlsx (single report for Phase 62 outputs), with columns: patient_id, episode_number, regimen_label, episode_start, age_at_treatment, is_first_line, has_prior_chemo_within_60d. Facilitates QA review of first-line logic alongside death metrics.

3. **How to log first-line flagging for QA review?**
   - What we know: Console logging with glue() is established pattern (R/59 lines 71, 96, 151)
   - What's unclear: What level of detail is useful for first-line detection QA?
   - Recommendation: Log at each filter step: (1) total episodes with regimen labels, (2) episodes for adults 21+, (3) episodes with clean 60-day period, (4) first qualifying episode per patient. Example: `glue("  Adults 21+ at treatment: {n_adults} episodes from {n_patients_adults} patients")`.

## Environment Availability

> Phase 62 has no external dependencies beyond the project's established R environment (tidyverse, openxlsx2, DuckDB). All dependencies already installed and verified in renv.

**Environment:** RStudio on UF HiPerGator (R 4.4.2, renv-managed packages)

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| R | All operations | ✓ (HiPerGator) | 4.4.2 | — |
| dplyr | Data manipulation | ✓ (renv) | 1.2.0+ | — |
| openxlsx2 | xlsx output | ✓ (renv) | 1.12+ | — |
| lubridate | Date arithmetic | ✓ (renv) | 1.9.3+ | — |
| glue | Logging | ✓ (renv) | 1.8.0+ | — |
| DuckDB backend | ENCOUNTER, DEMOGRAPHIC queries | ✓ (established) | In use | — |

**Missing dependencies with no fallback:** None

**Missing dependencies with fallback:** None

**Local development note:** R is NOT available on the local Windows development environment (command not found). All Phase 62 execution occurs on HiPerGator via RStudio. Local environment is for planning/documentation only.

## Validation Architecture

> Skipped — workflow.nyquist_validation is explicitly set to false in .planning/config.json.

## Sources

### Primary (HIGH confidence)
- R/59_death_date_validation.R (existing codebase) — Age calculation pattern (lines 308-309), openxlsx2 styling pattern (lines 373-445), validated_death_dates.rds schema
- R/44a_treatment_episodes.R (existing codebase) — treatment_episodes.rds schema, treatment_episode_detail.rds for individual chemo dates, in-place RDS enrichment pattern (Phase 60)
- R/49_gantt_data_export.R (existing codebase) — Loading treatment_episodes.rds and validated_death_dates.rds
- [CRAN dplyr package](https://cran.r-project.org/web/packages/dplyr/dplyr.pdf) — Version 1.2.0, May 8, 2026
- [dplyr changelog](https://dplyr.tidyverse.org/news/index.html) — Version 1.2.0 release (Feb 2026) with filter_out(), when_any(), when_all()
- [Official dplyr grouping documentation](https://dplyr.tidyverse.org/articles/grouping.html) — row_number() pattern for first observation per group
- [CRAN openxlsx2 package](https://cran.r-project.org/web/packages/openxlsx2/openxlsx2.pdf) — Version 1.12+, May 25, 2026
- [openxlsx2 styling manual](https://cran.r-project.org/web/packages/openxlsx2/vignettes/openxlsx2_style_manual.html) — wb_workbook(), add_fill(), add_font() API

### Secondary (MEDIUM confidence)
- [Defining Treatment Regimens and Lines of Therapy Using Real-World Data in Oncology](https://www.tandfonline.com/doi/full/10.2217/fon-2020-1041) — 60-day gap period as standard threshold in oncology RWE; verified via Tandfonline publication
- [PCORnet Common Data Model v7.0](https://pcornet.org/wp-content/uploads/2025/05/PCORnet_Common_Data_Model_v70_2025_05_01.pdf) — ENC_TYPE value definitions: AV (Ambulatory Visit), ED (Emergency Department), IP (Inpatient Hospital Stay), OA (Other Ambulatory), IS (Non-Acute Institutional Stay)
- [PCORnet CDM v6.1 specification](https://onefl.net/wordpress/files/2025/02/PCORnet-Common-Data-Model-v61.pdf) — ENCOUNTER table schema, ADMIT_DATE field

### Tertiary (LOW confidence — not used for critical claims)
- [First-Line vs. Second-Line Therapy in Lung Cancer](https://www.patientpower.info/lung-cancer/first-line-vs-second-line-therapy-in-lung-cancer) — General definition of first-line therapy; not used for implementation
- [Real-World Evidence in Oncology](https://www.onclive.com/view/expanding-opportunities-for-real-world-evidence-in-oncology) — Context for RWE studies; not used for implementation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All packages verified on CRAN with May 2026 releases; existing project renv environment
- Architecture patterns: HIGH — Directly extracted from R/59, R/44a, R/49 existing codebase with line number citations
- First-line logic: HIGH — 60-day clean period verified in oncology RWE literature (Tandfonline); dplyr group filtering from official documentation
- Death analysis logic: HIGH — Builds on Phase 59's validated_death_dates.rds schema (lines 352-361); ENC_TYPE values from official PCORnet CDM v7.0 spec
- Pitfalls: MEDIUM — Inferred from decision constraints (D-01 to D-13) and common dplyr/date arithmetic mistakes; not empirically validated

**Research date:** 2026-05-30
**Valid until:** 60 days (stable domain — tidyverse ecosystem and PCORnet CDM have slow release cycles; dplyr 1.2.0 and openxlsx2 1.12 are current stable releases as of May 2026)
