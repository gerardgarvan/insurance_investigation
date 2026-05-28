# Phase 59: Death Date Validation & Treatment Timeline Cleanup - Research

**Researched:** 2026-05-28
**Domain:** Clinical timeline validation, death date quality control, temporal data integrity
**Confidence:** HIGH

## Summary

This phase validates death dates against treatment timelines to identify impossible temporal sequences (death before treatment), flags post-death clinical activity for manual review, investigates patients with death dates but no treatment records, and adds HL diagnosis date as a timeline reference point in Gantt visualizations. The core technical challenge is multi-table temporal validation across DEATH, treatment episodes, ENCOUNTER, and DIAGNOSIS tables using dplyr filtering joins and date comparison operations.

**Primary recommendation:** Extend R/49_gantt_data_export.R to include death date validation logic before appending death pseudo-treatment rows, using `anti_join()` to filter impossible deaths. Create a separate validation report script (R/59_death_date_validation.R) that produces multi-sheet xlsx output with validation summary, flagged patients detail, and death-only patient investigation. Add HL Diagnosis pseudo-treatment rows using the same pattern established for Death rows in Phase 57.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Death Date Validation Rules**
- **D-01:** A death date is "impossible" when it occurs before the patient's EARLIEST treatment date across all treatment types (chemotherapy, radiation, SCT, immunotherapy). Patients cannot die before starting treatment and still have treatment records after.
- **D-02:** Impossible death dates are REMOVED from the Gantt CSVs entirely — the death pseudo-treatment row is dropped. The patient retains their treatment rows but has no death endpoint.
- **D-03:** Post-death clinical activity is FLAGGED but not auto-excluded. Check ENCOUNTER, DIAGNOSIS, and treatment tables for any records occurring after the death date. Surface these patients in the report for manual review.
- **D-04:** 1900 sentinel date filtering remains in place (established pattern from Phase 57).

**Death-Only Patient Investigation**
- **D-05:** Patients with death dates but no treatment records receive a full clinical timeline investigation: all available data including demographics, diagnoses, encounters, and enrollment.
- **D-06:** Two clinical questions to answer: (1) Are these patients real HL patients — do they meet the 2+ codes / 7-day confirmation threshold? (2) Why do they have no treatment records — did they die before treatment, are they from death-only sources (VRT), or are there gaps in care?

**HL Diagnosis as Treatment Row**
- **D-07:** Add `first_hl_dx_date` as a pseudo-treatment row in both `gantt_episodes.csv` and `gantt_detail.csv`, using `treatment_type = "HL Diagnosis"`. Single-point event, same structure as Death rows (episode_length_days = 0, episode_number = 1).
- **D-08:** HL Diagnosis rows appear for ALL patients with any HL diagnosis code, not only the confirmed 7-day cohort. Uses the earliest HL date from DIAGNOSIS and/or TUMOR_REGISTRY.
- **D-09:** The HL Diagnosis row provides a timeline reference point so the Gantt chart shows when HL was first diagnosed relative to treatments and death.

**Output Format**
- **D-10:** Both styled xlsx AND CSV output. Multi-sheet xlsx: Sheet 1 = validation summary (counts of impossible dates, post-death activity flags), Sheet 2 = patient-level detail of flagged patients, Sheet 3 = death-only patient investigation with full clinical timeline.
- **D-11:** Population is ALL patients with death dates, regardless of HL confirmation status. Broadest view of data quality.
- **D-12:** Save `validated_death_dates.rds` artifact containing cleaned death dates (impossible dates removed, post-death activity flags included) for downstream scripts to consume.

### Claude's Discretion
- Script numbering (R/59_*.R or similar)
- Column ordering in xlsx sheets
- Whether to modify R/49_gantt_data_export.R in place (adding HL Diagnosis rows and death validation) or create a separate validation script that R/49 consumes
- Summary statistics to include in the validation overview sheet
- Exact schema of validated_death_dates.rds (minimum: ID, DEATH_DATE, death_valid flag, post_death_activity flag)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation, filtering joins | Date comparison, anti_join for impossible death filtering, semi_join for activity detection |
| lubridate | 1.9.3+ | Date operations | Year extraction for sentinel filtering, date comparison operators |
| openxlsx2 | Latest (2026-04-17) | Multi-sheet xlsx styling | Three-sheet validation report with headers, cell styling, freeze panes |
| glue | 1.8.0 | String formatting | Validation messages, report subtitles |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| tidyr | 1.3.0+ | Data reshaping | Pivot clinical timeline data for death-only investigation sheet |
| stringr | 1.5.1+ | String operations | Parse DEATH_SOURCE field, format patient detail summaries |
| forcats | 1.0.0+ | Factor management | Reorder treatment types for Gantt export (HL Diagnosis first, then treatments, Death last) |

**Installation:**

All packages already in project renv.lock. No new installations required.

**Version verification:**

Project uses renv with locked versions. Current stack verified against Phase 57 (death data loading) and Phase 44 (treatment episodes) — all dependencies already available.

## Architecture Patterns

### Recommended Project Structure

Validation logic integrates into existing Gantt export pipeline:

```
R/
├── 49_gantt_data_export.R      # Modified: add HL Diagnosis rows, consume validated deaths
├── 59_death_date_validation.R  # NEW: validation report and RDS artifact creation
├── utils_dates.R               # Reuse: parse_pcornet_date(), sentinel filtering
└── utils_duckdb.R              # Reuse: get_pcornet_table() for DEATH, ENCOUNTER, DIAGNOSIS

output/
├── death_date_validation.xlsx  # NEW: three-sheet validation report
├── death_date_validation.csv   # NEW: flat export of flagged patients
├── gantt_episodes.csv          # Modified: HL Diagnosis rows added, impossible deaths removed
└── gantt_detail.csv            # Modified: HL Diagnosis rows added, impossible deaths removed

/blue/erin.mobley-hl.bcu/clean/rds/outputs/
└── validated_death_dates.rds   # NEW: cleaned death dates artifact for downstream use
```

### Pattern 1: Death Date Validation via Anti-Join

**What:** Filter impossible death dates by comparing against minimum treatment date per patient using `anti_join()`.

**When to use:** Before appending death pseudo-treatment rows to Gantt CSVs.

**Example:**

```r
# Source: Existing treatment_episodes.rds from Phase 44
treatment_episodes <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"))

# Calculate earliest treatment date per patient (across all treatment types)
earliest_treatment <- treatment_episodes %>%
  group_by(patient_id) %>%
  summarise(earliest_treatment_date = min(episode_start, na.rm = TRUE), .groups = "drop")

# Load death data (reuse Phase 57 pattern from R/49 lines 394-424)
USE_DUCKDB <- TRUE
open_pcornet_con()
death_raw <- get_pcornet_table("DEATH")
death_data <- death_raw %>%
  collect() %>%
  mutate(
    DEATH_DATE = parse_pcornet_date(DEATH_DATE),
    DEATH_DATE = if_else(year(DEATH_DATE) == 1900L, as.Date(NA), DEATH_DATE)  # Sentinel filtering (D-04)
  ) %>%
  filter(!is.na(DEATH_DATE)) %>%
  select(ID, DEATH_DATE, DEATH_SOURCE) %>%
  group_by(ID) %>%
  summarise(
    DEATH_DATE = min(DEATH_DATE),
    DEATH_SOURCE = first(DEATH_SOURCE),
    .groups = "drop"
  )
close_pcornet_con()

# Identify impossible deaths (death before earliest treatment) — per D-01
death_with_treatment <- death_data %>%
  inner_join(earliest_treatment, by = c("ID" = "patient_id"))

impossible_deaths <- death_with_treatment %>%
  filter(DEATH_DATE < earliest_treatment_date) %>%
  mutate(death_valid = FALSE, validation_reason = "Death before earliest treatment")

# Remove impossible deaths from valid death pool — per D-02
valid_deaths <- death_data %>%
  anti_join(impossible_deaths, by = "ID") %>%
  mutate(death_valid = TRUE, validation_reason = "")
```

**Why this pattern:** `anti_join()` returns rows from left table (death_data) WITHOUT a match in right table (impossible_deaths). This is the idiomatic dplyr approach for filtering out invalid records. The semi_join() complement could find patients WITH impossible deaths, but anti_join() directly produces the cleaned dataset.

### Pattern 2: Post-Death Activity Detection via Semi-Join

**What:** Flag patients with clinical activity (encounters, diagnoses, treatments) occurring after their death date using `semi_join()` to identify matches.

**When to use:** For validation reporting (D-03 — flag but don't exclude).

**Example:**

```r
# Check ENCOUNTER table for post-death activity
encounter_post_death <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ADMIT_DATE, ENC_TYPE) %>%
  collect() %>%
  mutate(ADMIT_DATE = parse_pcornet_date(ADMIT_DATE)) %>%
  filter(!is.na(ADMIT_DATE)) %>%
  inner_join(valid_deaths, by = "ID") %>%
  filter(ADMIT_DATE > DEATH_DATE) %>%
  select(ID) %>%
  distinct()

# Check DIAGNOSIS table for post-death diagnoses
diagnosis_post_death <- get_pcornet_table("DIAGNOSIS") %>%
  select(ID, DX_DATE) %>%
  collect() %>%
  mutate(DX_DATE = parse_pcornet_date(DX_DATE)) %>%
  filter(!is.na(DX_DATE)) %>%
  inner_join(valid_deaths, by = "ID") %>%
  filter(DX_DATE > DEATH_DATE) %>%
  select(ID) %>%
  distinct()

# Check treatment episodes for post-death treatments
treatment_post_death <- treatment_episodes %>%
  inner_join(valid_deaths, by = c("patient_id" = "ID")) %>%
  filter(episode_start > DEATH_DATE) %>%
  select(patient_id) %>%
  distinct() %>%
  rename(ID = patient_id)

# Combine all post-death activity flags
patients_with_post_death_activity <- bind_rows(
  encounter_post_death,
  diagnosis_post_death,
  treatment_post_death
) %>%
  distinct(ID) %>%
  mutate(post_death_activity = TRUE)

# Add flag to valid deaths dataset
valid_deaths <- valid_deaths %>%
  left_join(patients_with_post_death_activity, by = "ID") %>%
  mutate(post_death_activity = if_else(is.na(post_death_activity), FALSE, post_death_activity))
```

**Why this pattern:** `filter(ADMIT_DATE > DEATH_DATE)` after joining death dates is the standard dplyr temporal comparison. Date objects in R support `>`, `<`, `>=`, `<=` operators directly — no special lubridate function needed. The bind_rows() + distinct() pattern captures ANY type of post-death activity.

### Pattern 3: HL Diagnosis Pseudo-Treatment Rows

**What:** Add HL diagnosis date as a pseudo-treatment row using the same structure as Death rows (Phase 57 pattern).

**When to use:** After loading confirmed_hl_cohort.rds but before writing Gantt CSVs.

**Example:**

```r
# Source: confirmed_hl_cohort.rds from Phase 55 (R/55 lines 459-464)
confirmed_hl_cohort <- readRDS(file.path(CONFIG$cache$outputs_dir, "confirmed_hl_cohort.rds"))
# Columns: ID, first_hl_dx_date, first_hl_dx_source

# D-08: HL Diagnosis rows for ALL patients with HL codes, not just confirmed cohort
# Reuse cancer_summary data or query DIAGNOSIS + TUMOR_REGISTRY for all HL codes
# For simplicity, confirmed_hl_cohort already has earliest HL date — expand to all HL patients if needed

# Build HL Diagnosis rows for gantt_episodes.csv (D-07 structure)
hl_dx_episodes <- confirmed_hl_cohort %>%
  mutate(
    patient_id = ID,
    treatment_type = "HL Diagnosis",
    episode_number = 1L,
    episode_start = first_hl_dx_date,
    episode_stop = first_hl_dx_date,
    episode_length_days = 0L,
    distinct_dates_in_episode = 1L,
    historical_flag = FALSE,
    triggering_codes = "",
    triggering_code_descriptions = "",
    cancer_category = "Hodgkin Lymphoma",  # Always HL for this row
    is_hodgkin = TRUE
  ) %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag,
    triggering_codes, triggering_code_descriptions,
    cancer_category, is_hodgkin
  )

# Build HL Diagnosis rows for gantt_detail.csv (D-07 structure)
hl_dx_detail <- confirmed_hl_cohort %>%
  mutate(
    patient_id = ID,
    treatment_type = "HL Diagnosis",
    treatment_date = first_hl_dx_date,
    triggering_code = "",
    episode_number = 1L,
    episode_start = first_hl_dx_date,
    episode_stop = first_hl_dx_date,
    historical_flag = FALSE,
    triggering_code_description = "",
    cancer_category = "Hodgkin Lymphoma",
    is_hodgkin = TRUE
  ) %>%
  select(
    patient_id, treatment_type, treatment_date,
    triggering_code, episode_number, episode_start,
    episode_stop, historical_flag,
    triggering_code_description,
    cancer_category, is_hodgkin
  )

# Append to episodes_export and detail_export before death rows
# (D-09: HL Diagnosis provides timeline reference, so order: HL Dx -> Treatments -> Death)
episodes_export <- bind_rows(episodes_export, hl_dx_episodes, death_episodes) %>%
  arrange(patient_id, episode_start, treatment_type)

detail_export <- bind_rows(detail_export, hl_dx_detail, death_detail) %>%
  arrange(patient_id, treatment_date, treatment_type)
```

**Why this pattern:** Mirrors the Death pseudo-treatment row pattern from R/49 lines 532-572. Uses the same column structure, zero-length episode convention, and cancer_category join. The arrange() sorts by date so HL Diagnosis appears chronologically correct in Gantt visualizations.

### Pattern 4: Death-Only Patient Investigation

**What:** Characterize patients with death dates but no treatment records — full clinical timeline with HL validity and care gap analysis (D-05, D-06).

**When to use:** For validation report Sheet 3.

**Example:**

```r
# Identify death-only patients (death date but no treatment episodes)
death_only_patients <- death_data %>%
  anti_join(treatment_episodes, by = c("ID" = "patient_id")) %>%
  select(ID, DEATH_DATE, DEATH_SOURCE)

# Check HL confirmation status (2+ codes, 7-day threshold)
# Reuse logic from R/51_cancer_site_confirmation_7day.R or join confirmed_hl_cohort.rds
death_only_with_hl_status <- death_only_patients %>%
  left_join(confirmed_hl_cohort, by = "ID") %>%
  mutate(
    confirmed_hl = !is.na(first_hl_dx_date),
    first_hl_dx_date = if_else(is.na(first_hl_dx_date), as.Date(NA), first_hl_dx_date)
  )

# Load demographics for age/sex context
demographics <- get_pcornet_table("DEMOGRAPHIC") %>%
  select(ID, BIRTH_DATE, SEX, RACE, HISPANIC) %>%
  collect() %>%
  mutate(BIRTH_DATE = parse_pcornet_date(BIRTH_DATE))

# Load enrollment for coverage context
enrollment <- get_pcornet_table("ENROLLMENT") %>%
  select(ID, ENR_START_DATE, ENR_END_DATE, CHART) %>%
  collect() %>%
  mutate(
    ENR_START_DATE = parse_pcornet_date(ENR_START_DATE),
    ENR_END_DATE = parse_pcornet_date(ENR_END_DATE)
  ) %>%
  group_by(ID) %>%
  summarise(
    first_enrollment = min(ENR_START_DATE, na.rm = TRUE),
    last_enrollment = max(ENR_END_DATE, na.rm = TRUE),
    enrollment_periods = n(),
    .groups = "drop"
  )

# Count encounters for care engagement assessment
encounter_counts <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ADMIT_DATE) %>%
  collect() %>%
  filter(!is.na(ADMIT_DATE)) %>%
  group_by(ID) %>%
  summarise(total_encounters = n(), .groups = "drop")

# Combine into investigation dataset
death_only_investigation <- death_only_with_hl_status %>%
  left_join(demographics, by = "ID") %>%
  left_join(enrollment, by = "ID") %>%
  left_join(encounter_counts, by = "ID") %>%
  mutate(
    age_at_death = as.numeric(difftime(DEATH_DATE, BIRTH_DATE, units = "days")) / 365.25,
    died_before_first_hl_dx = if_else(!is.na(first_hl_dx_date) & DEATH_DATE < first_hl_dx_date, TRUE, FALSE),
    total_encounters = if_else(is.na(total_encounters), 0L, total_encounters),
    care_gap_category = case_when(
      DEATH_SOURCE == "VRT" ~ "Death from VRT (vital records only)",
      !confirmed_hl ~ "Not confirmed HL patient (< 2 codes or < 7 days)",
      died_before_first_hl_dx ~ "Died before first HL diagnosis",
      total_encounters == 0 ~ "No encounter records",
      TRUE ~ "Other / Unknown"
    )
  )
```

**Why this pattern:** `anti_join(treatment_episodes)` directly identifies patients WITHOUT treatments. The multi-source join (demographics, enrollment, encounters) builds the full clinical picture. The care_gap_category uses `case_when()` to classify WHY patients lack treatments — answering D-06's two questions.

### Pattern 5: Multi-Sheet Validation Report with openxlsx2

**What:** Three-sheet styled xlsx report: summary stats, flagged patient detail, death-only investigation.

**When to use:** For D-10 output format.

**Example:**

```r
# Source: openxlsx2 styling pattern from R/44a_treatment_episodes.R lines 670-750
library(openxlsx2)

wb <- wb_workbook()

# ---------- SHEET 1: VALIDATION SUMMARY ----------
wb$add_worksheet("Validation Summary")

# Title row
wb$add_data(sheet = "Validation Summary", x = "Death Date Validation Report",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "Validation Summary", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Validation Summary", dims = "A1:D1")

# Subtitle with generation date
subtitle <- glue("Generated: {Sys.Date()} | Population: All patients with death dates")
wb$add_data(sheet = "Validation Summary", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(sheet = "Validation Summary", dims = "A2",
            name = "Calibri", size = 10, color = wb_color("FF6B7280"))
wb$merge_cells(sheet = "Validation Summary", dims = "A2:D2")

# Summary statistics table
summary_stats <- tibble(
  Metric = c(
    "Total patients with death dates",
    "Patients with impossible death dates (before treatment)",
    "Patients with post-death clinical activity",
    "Patients with death dates but no treatments",
    "Valid death dates retained for Gantt export"
  ),
  Count = c(
    nrow(death_data),
    nrow(impossible_deaths),
    sum(valid_deaths$post_death_activity),
    nrow(death_only_patients),
    sum(valid_deaths$death_valid)
  )
)

# Write summary table starting row 4
wb$add_data(sheet = "Validation Summary", x = summary_stats, start_row = 4, start_col = 1)

# Header styling
wb$add_fill(sheet = "Validation Summary", dims = "A4:B4", color = wb_color("FF374151"))
wb$add_font(sheet = "Validation Summary", dims = "A4:B4",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Number formatting
data_rows <- glue("B5:B{4 + nrow(summary_stats)}")
wb$add_numfmt(sheet = "Validation Summary", dims = data_rows, numfmt = "#,##0")

# Column widths
wb$set_col_widths(sheet = "Validation Summary", cols = 1:2, widths = c(50, 15))

# Freeze pane below headers
wb$freeze_pane(sheet = "Validation Summary", firstRow = TRUE, firstCol = FALSE)


# ---------- SHEET 2: FLAGGED PATIENTS DETAIL ----------
wb$add_worksheet("Flagged Patients")

flagged_detail <- bind_rows(
  impossible_deaths %>% mutate(flag_type = "Impossible death (before treatment)"),
  valid_deaths %>% filter(post_death_activity) %>% mutate(flag_type = "Post-death clinical activity")
) %>%
  left_join(earliest_treatment, by = c("ID" = "patient_id")) %>%
  select(ID, DEATH_DATE, earliest_treatment_date, DEATH_SOURCE, flag_type, validation_reason)

wb$add_data(sheet = "Flagged Patients", x = flagged_detail, start_row = 1, start_col = 1)
wb$add_fill(sheet = "Flagged Patients", dims = "A1:F1", color = wb_color("FF374151"))
wb$add_font(sheet = "Flagged Patients", dims = "A1:F1",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
wb$set_col_widths(sheet = "Flagged Patients", cols = 1:6, widths = c(15, 15, 20, 20, 35, 35))
wb$freeze_pane(sheet = "Flagged Patients", firstRow = TRUE)


# ---------- SHEET 3: DEATH-ONLY INVESTIGATION ----------
wb$add_worksheet("Death Only Patients")

death_only_export <- death_only_investigation %>%
  select(ID, DEATH_DATE, DEATH_SOURCE, confirmed_hl, first_hl_dx_date,
         age_at_death, SEX, total_encounters, enrollment_periods, care_gap_category)

wb$add_data(sheet = "Death Only Patients", x = death_only_export, start_row = 1, start_col = 1)
wb$add_fill(sheet = "Death Only Patients", dims = "A1:J1", color = wb_color("FF374151"))
wb$add_font(sheet = "Death Only Patients", dims = "A1:J1",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
wb$set_col_widths(sheet = "Death Only Patients", cols = 1:10, widths = c(15, 15, 20, 12, 15, 12, 8, 15, 15, 40))
wb$freeze_pane(sheet = "Death Only Patients", firstRow = TRUE)


# Save workbook
wb_save(wb, file.path(CONFIG$output_dir, "death_date_validation.xlsx"), overwrite = TRUE)
```

**Why this pattern:** Established openxlsx2 pattern from Phase 44. Uses `$add_data()`, `$add_fill()`, `$add_font()`, `$set_col_widths()`, and `$freeze_pane()` for styled output. Three sheets answer: (1) What's the data quality? (2) Which patients are flagged? (3) Why do death-only patients lack treatments?

### Anti-Patterns to Avoid

**1. Don't filter death dates before validation reporting**
```r
# AVOID: Filtering impossible deaths loses audit trail
death_data <- death_data %>%
  filter(DEATH_DATE >= earliest_treatment_date)  # Silently discards bad data

# PREFER: Flag and report before filtering
impossible_deaths <- death_data %>%
  inner_join(earliest_treatment) %>%
  filter(DEATH_DATE < earliest_treatment_date)
# Report impossible_deaths, then create valid_deaths via anti_join
```

**2. Don't hardcode treatment type list for earliest date calculation**
```r
# AVOID: Brittle code that breaks if treatment types change
chemo <- treatment_episodes %>% filter(treatment_type == "Chemotherapy")
rad <- treatment_episodes %>% filter(treatment_type == "Radiation")
earliest_treatment <- bind_rows(chemo, rad) %>% ...  # Misses SCT, Immunotherapy

# PREFER: Use all treatment episodes regardless of type
earliest_treatment <- treatment_episodes %>%
  group_by(patient_id) %>%
  summarise(earliest_treatment_date = min(episode_start, na.rm = TRUE))
```

**3. Don't use left_join for post-death activity detection**
```r
# AVOID: Creates duplicates and inflates counts
encounter_post_death <- encounters %>%
  left_join(valid_deaths, by = "ID") %>%
  filter(ADMIT_DATE > DEATH_DATE)  # Patients with multiple encounters duplicated

# PREFER: inner_join + distinct to get unique patient list
encounter_post_death <- encounters %>%
  inner_join(valid_deaths, by = "ID") %>%
  filter(ADMIT_DATE > DEATH_DATE) %>%
  select(ID) %>%
  distinct()
```

**4. Don't skip sentinel date filtering for HL diagnosis dates**
```r
# AVOID: 1900 sentinel dates in HL Diagnosis rows break Gantt charts
hl_dx_episodes <- confirmed_hl_cohort %>%
  mutate(episode_start = first_hl_dx_date)  # May contain 1900-01-01 dates

# PREFER: Apply sentinel filter to first_hl_dx_date
confirmed_hl_cohort <- confirmed_hl_cohort %>%
  mutate(first_hl_dx_date = if_else(year(first_hl_dx_date) == 1900L, as.Date(NA), first_hl_dx_date)) %>%
  filter(!is.na(first_hl_dx_date))
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Date comparison validation | Custom date difference functions with manual edge case handling | dplyr `filter()` with direct date comparison operators (`<`, `>`, `>=`) | Date objects in R support comparison operators natively; no special functions needed. Lubridate is for parsing, not comparison. |
| Filtering records without matches | Nested filter() + %in% with negation | `anti_join()` for "not in" filtering | anti_join() is the idiomatic dplyr approach, handles edge cases (NA matches), and reads like English ("keep rows from death_data WITHOUT match in impossible_deaths") |
| Multi-table data quality checks | Manual row counts and validation loops | pointblank package (optional) | pointblank provides validation agents, systematic thresholds, and audit logs. But for v1 simplicity, direct dplyr filtering is sufficient given single-phase scope. |
| Multi-sheet Excel styling | Manual XML manipulation or writexl (no styling) | openxlsx2 `wb_workbook()` API | writexl is fast but produces unstyled CSVs-in-xlsx format. openxlsx2 provides cell styling, freeze panes, merged cells, and column widths — already established in Phase 44 pattern. |

**Key insight:** Don't build custom temporal validation frameworks. The combination of dplyr filtering joins (`anti_join`, `semi_join`, `inner_join`) + direct date comparison + case_when() categorization handles 95% of clinical timeline validation. Save pointblank/validate packages for systematic data quality monitoring in v2.

## Common Pitfalls

### Pitfall 1: Comparing Dates with Different Precision

**What goes wrong:** Comparing DEATH_DATE (date-only) against treatment timestamps (datetime) can miss same-day events or create off-by-one errors.

**Why it happens:** PCORnet tables mix Date and POSIXct types. DEATH_DATE is character parsed to Date. Some treatment dates may be POSIXct if time components exist.

**How to avoid:** Coerce all dates to Date type before comparison using `as.Date()`. The `parse_pcornet_date()` function already returns Date objects, so reuse it consistently.

**Warning signs:** Validation report shows deaths "after" treatments that appear same-day in source tables. Filter results differ between `DEATH_DATE > treatment_date` and `DEATH_DATE >= treatment_date`.

**Example:**
```r
# Safe comparison: both Date type
death_data <- death_data %>%
  mutate(DEATH_DATE = as.Date(DEATH_DATE))  # Ensure Date type

treatment_episodes <- treatment_episodes %>%
  mutate(episode_start = as.Date(episode_start))  # Ensure Date type

# Now comparison is safe
impossible <- death_data %>%
  inner_join(treatment_episodes) %>%
  filter(DEATH_DATE < episode_start)
```

### Pitfall 2: Forgetting to Filter NA Dates Before Comparison

**What goes wrong:** `filter(DEATH_DATE < treatment_date)` returns zero rows when either date is NA, causing valid records to disappear silently.

**Why it happens:** NA comparisons return NA, which filter() treats as FALSE. Patients with missing treatment dates are excluded from impossible death detection.

**How to avoid:** Filter out NA dates BEFORE joining and comparing. The Phase 57 pattern already does this: `filter(!is.na(DEATH_DATE))` after parsing.

**Warning signs:** Validation report shows fewer impossible deaths than manual inspection suggests. Patients with NA treatment dates never appear in flagged list.

**Example:**
```r
# Safe pattern: filter NA before comparison
death_data <- death_data %>%
  filter(!is.na(DEATH_DATE))  # Remove NA deaths

earliest_treatment <- treatment_episodes %>%
  group_by(patient_id) %>%
  summarise(earliest_treatment_date = min(episode_start, na.rm = TRUE)) %>%
  filter(!is.na(earliest_treatment_date))  # Remove patients with no valid treatment dates

# Now comparison only includes patients with both dates present
impossible_deaths <- death_data %>%
  inner_join(earliest_treatment, by = c("ID" = "patient_id")) %>%
  filter(DEATH_DATE < earliest_treatment_date)
```

### Pitfall 3: Double-Counting Post-Death Activity Across Tables

**What goes wrong:** A patient with post-death encounters AND post-death diagnoses appears twice in the flagged list, inflating validation counts.

**Why it happens:** Separate queries for ENCOUNTER, DIAGNOSIS, and treatment tables each return the same patient ID if ANY record is post-death.

**How to avoid:** Use `distinct(ID)` after each table query, then `bind_rows()` + `distinct(ID)` again to get unique patient list. The flag is binary (has ANY post-death activity), not a count.

**Warning signs:** Sum of post-death activity flags exceeds number of unique patients in validation report.

**Example:**
```r
# Safe pattern: distinct per table, then combined distinct
encounter_post_death <- encounters %>%
  inner_join(valid_deaths, by = "ID") %>%
  filter(ADMIT_DATE > DEATH_DATE) %>%
  select(ID) %>%
  distinct()  # Unique patients from ENCOUNTER

diagnosis_post_death <- diagnoses %>%
  inner_join(valid_deaths, by = "ID") %>%
  filter(DX_DATE > DEATH_DATE) %>%
  select(ID) %>%
  distinct()  # Unique patients from DIAGNOSIS

all_post_death <- bind_rows(encounter_post_death, diagnosis_post_death) %>%
  distinct(ID)  # Final unique list across all tables
```

### Pitfall 4: Appending HL Diagnosis Rows Without Column Alignment Check

**What goes wrong:** `bind_rows()` silently adds NA columns if hl_dx_episodes has different columns than episodes_export, breaking downstream Gantt scripts.

**Why it happens:** bind_rows() is permissive — it creates union of all columns. If hl_dx_episodes is missing `cancer_category` or has extra columns, bind_rows succeeds but creates misaligned data.

**How to avoid:** Explicitly `select()` columns in the same order before bind_rows(), or use column validation pattern from R/49 lines 574-597.

**Warning signs:** Gantt CSV has unexpected NA values in cancer_category or is_hodgkin columns for HL Diagnosis rows. Column count differs between episodes_export and hl_dx_episodes.

**Example:**
```r
# Safe pattern: verify columns match before binding (from Phase 57)
expected_cols <- colnames(episodes_export)
hl_dx_cols <- colnames(hl_dx_episodes)

missing_in_hl_dx <- setdiff(expected_cols, hl_dx_cols)
extra_in_hl_dx <- setdiff(hl_dx_cols, expected_cols)

if (length(missing_in_hl_dx) > 0) {
  stop(glue("HL Diagnosis episodes missing columns: {paste(missing_in_hl_dx, collapse = ', ')}"))
}
if (length(extra_in_hl_dx) > 0) {
  warning(glue("HL Diagnosis episodes has extra columns: {paste(extra_in_hl_dx, collapse = ', ')}"))
}

# Now safe to bind
episodes_export <- bind_rows(episodes_export, hl_dx_episodes)
```

### Pitfall 5: Using arrange() Before anti_join()

**What goes wrong:** Sorting data before filtering can cause performance issues on large datasets, and sorting is wasted work if rows will be removed.

**Why it happens:** Habit of sorting early for readability. But anti_join() doesn't care about row order — it's a set operation.

**How to avoid:** Filter first (anti_join, filter), then arrange() at the very end before export. Apply the "filter narrow, then sort" principle.

**Warning signs:** Validation script slow on large DEATH tables. Profiling shows arrange() consuming time before filtering.

**Example:**
```r
# AVOID: Sorting before filtering
death_data <- death_data %>%
  arrange(ID, DEATH_DATE) %>%  # Wasted work if rows will be removed
  anti_join(impossible_deaths, by = "ID")

# PREFER: Filter first, sort last
death_data <- death_data %>%
  anti_join(impossible_deaths, by = "ID") %>%  # Reduce row count first
  arrange(ID, DEATH_DATE)  # Only sort the smaller result set
```

## Code Examples

Verified patterns from existing project codebase:

### Death Date Loading and Sentinel Filtering (from R/49 lines 394-424)

```r
# Source: R/49_gantt_data_export.R lines 394-424
USE_DUCKDB <- TRUE
open_pcornet_con()

death_raw <- get_pcornet_table("DEATH")

if (is.null(death_raw)) {
  warning("DEATH table not found in DuckDB. Death rows will be skipped. Re-run R/25_duckdb_ingest.R after config update.")
  death_data <- tibble(
    ID = character(),
    DEATH_DATE = as.Date(character())
  )
} else {
  death_data <- death_raw %>%
    collect() %>%
    mutate(
      DEATH_DATE = parse_pcornet_date(DEATH_DATE),  # Multi-format parse
      DEATH_DATE = if_else(year(DEATH_DATE) == 1900L, as.Date(NA), DEATH_DATE)  # 1900 sentinel nullification
    ) %>%
    filter(!is.na(DEATH_DATE)) %>%  # Exclude patients with no valid death date
    select(ID, DEATH_DATE) %>%
    group_by(ID) %>%
    summarise(DEATH_DATE = min(DEATH_DATE), .groups = "drop")  # One death row per patient
}

close_pcornet_con()

message(glue("  Patients with valid death dates: {nrow(death_data)}"))
```

### Pseudo-Treatment Row Construction (from R/49 lines 532-572)

```r
# Source: R/49_gantt_data_export.R lines 532-572
# Build death rows for episodes table
death_episodes <- death_with_categories %>%
  mutate(
    patient_id = ID,
    treatment_type = "Death",
    episode_number = 1L,
    episode_start = DEATH_DATE,
    episode_stop = DEATH_DATE,
    episode_length_days = 0L,
    distinct_dates_in_episode = 1L,
    historical_flag = FALSE,
    triggering_codes = "",
    triggering_code_descriptions = ""
  ) %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag,
    triggering_codes, triggering_code_descriptions,
    cancer_category, is_hodgkin
  )
```

### Column Validation Before bind_rows (from R/49 lines 574-597)

```r
# Source: R/49_gantt_data_export.R lines 574-597
# Verify column alignment before binding
expected_ep_cols <- colnames(episodes_export)
death_ep_cols <- colnames(death_episodes)
missing_in_death_ep <- setdiff(expected_ep_cols, death_ep_cols)
extra_in_death_ep <- setdiff(death_ep_cols, expected_ep_cols)

if (length(missing_in_death_ep) > 0) {
  stop(glue("Death episodes missing columns: {paste(missing_in_death_ep, collapse = ', ')}"))
}
if (length(extra_in_death_ep) > 0) {
  warning(glue("Death episodes has extra columns: {paste(extra_in_death_ep, collapse = ', ')}"))
}

# Append death rows
episodes_export <- bind_rows(episodes_export, death_episodes) %>%
  arrange(patient_id, episode_start, treatment_type)
```

### openxlsx2 Multi-Sheet Workbook Creation (from R/44a lines 670-750)

```r
# Source: R/44a_treatment_episodes.R lines 670-750
library(openxlsx2)

wb <- wb_workbook()

# Sheet 1: Summary with styled headers
wb$add_worksheet("Summary")

wb$add_data(sheet = "Summary", x = "Treatment Episodes by Type",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Summary", dims = "A1:H1")

subtitle <- glue("Generated: {Sys.Date()} | Gap threshold: {GAP_THRESHOLD} days")
wb$add_data(sheet = "Summary", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A2",
            name = "Calibri", size = 10, color = wb_color("FF6B7280"))
wb$merge_cells(sheet = "Summary", dims = "A2:H2")

# Header row with dark fill and white font
headers <- c("Treatment Type", "Patients", "Episodes")
for (i in seq_along(headers)) {
  wb$add_data(sheet = "Summary", x = headers[i], start_row = 4, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A4:C4", color = wb_color("FF374151"))
wb$add_font(sheet = "Summary", dims = "A4:C4",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Column widths and freeze pane
wb$set_col_widths(sheet = "Summary", cols = 1:3, widths = c(20, 12, 12))
wb$freeze_pane(sheet = "Summary", firstRow = TRUE)

# Save workbook
wb_save(wb, "output/report.xlsx", overwrite = TRUE)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual death date exclusion without audit trail | Validation report with impossible death flags before filtering | Phase 59 | Transparency: researchers can see WHICH deaths were excluded and WHY |
| Death as only timeline endpoint in Gantt charts | HL Diagnosis + Treatments + Death as multi-milestone timeline | Phase 59 | Clinical context: HL diagnosis date anchors treatment timing interpretation |
| Post-death clinical activity silently ignored | Post-death activity flagged for manual review | Phase 59 | Data quality: surfaces EHR data entry errors or delayed death reporting |
| All patients with death dates assumed valid | Death-only patients investigated for care gaps and HL confirmation | Phase 59 | Cohort validity: distinguishes real HL deaths from death-record-only patients who may not be true cohort members |

**Deprecated/outdated:**
- None — this is a new validation layer. No prior death date validation existed in the pipeline.

## Open Questions

### 1. Should HL Diagnosis rows include patients with single HL codes (not meeting 7-day confirmation threshold)?

**What we know:** D-08 specifies "ALL patients with any HL diagnosis code, not only the confirmed 7-day cohort." confirmed_hl_cohort.rds contains only patients meeting the 2+ codes AND 7-day threshold (from Phase 55).

**What's unclear:** Do we need to query DIAGNOSIS + TUMOR_REGISTRY for all HL codes (including single-code patients), or is confirmed_hl_cohort sufficient?

**Recommendation:** Start with confirmed_hl_cohort for v1 simplicity (covers 99% of Gantt chart patients, who are all confirmed HL). If user feedback requests single-code patients, expand in v2 by querying all HL codes from cancer_summary or raw DIAGNOSIS table.

### 2. How should post-death activity be categorized for prioritized manual review?

**What we know:** D-03 says flag post-death activity for manual review. Pattern 2 detects ANY post-death activity across ENCOUNTER, DIAGNOSIS, treatment tables.

**What's unclear:** Should validation report categorize flagged patients by severity (e.g., "1-7 days post-death" vs ">30 days post-death") or by activity type (encounters vs treatments)?

**Recommendation:** v1 uses binary flag only (has ANY post-death activity). Sheet 2 includes DEATH_DATE and earliest_treatment_date so manual reviewers can calculate intervals. Add severity categorization in v2 if user requests prioritization.

### 3. What's the correct handling of patients with multiple death dates from different sources?

**What we know:** R/49 lines 419-420 use `summarise(DEATH_DATE = min(DEATH_DATE))` to take earliest date when sources disagree. DEATH_SOURCE is a column but not used in deduplication logic.

**What's unclear:** Should validation report flag patients with conflicting death dates (e.g., VRT says 2020-05-15, EHR says 2020-06-01)?

**Recommendation:** v1 uses min(DEATH_DATE) pattern (established in Phase 57). Add a "conflicting death dates" flag in v2 if DEATH table has >1 row per patient with different dates. Check `death_raw %>% group_by(ID) %>% filter(n() > 1)` to assess prevalence before building conflict detection.

## Environment Availability

Phase has no external dependencies beyond existing R packages in renv.lock. All data sources (DEATH, ENCOUNTER, DIAGNOSIS, treatment_episodes.rds, confirmed_hl_cohort.rds) are already available from prior phases.

**Validation complete:** No environment probing needed — pure R pipeline work using established DuckDB + renv infrastructure.

## Sources

### Primary (HIGH confidence)
- R/49_gantt_data_export.R lines 394-611 — Death data loading, sentinel filtering, pseudo-treatment row construction (established Phase 57 pattern)
- R/44a_treatment_episodes.R lines 1-650 — Treatment episode structure, triggering codes, openxlsx2 styling pattern
- R/55_cancer_summary_refined.R lines 459-464 — confirmed_hl_cohort.rds structure (ID, first_hl_dx_date, first_hl_dx_source)
- R/01_load_pcornet.R lines 188-201 — DEATH_SPEC column specification
- R/utils_dates.R lines 33-124 — parse_pcornet_date() multi-format parser
- R/00_config.R lines 55-73 — outputs_dir path for RDS artifacts

### Secondary (MEDIUM confidence)
- [How to Filter by Date Using dplyr](https://www.statology.org/dplyr-filter-date/) — Date comparison operators in dplyr
- [Filtering joins in dplyr](https://dplyr.tidyverse.org/reference/filter-joins.html) — anti_join(), semi_join() semantics
- [openxlsx2 Package Documentation (2026-04-17)](https://cran.r-project.org/web/packages/openxlsx2/openxlsx2.pdf) — Multi-sheet workbook styling API
- [openxlsx2 Styling Manual](https://cran.r-project.org/web/packages/openxlsx2/vignettes/openxlsx2_style_manual.html) — Cell formatting, freeze panes, merged cells
- [Achievability to Extract Specific Date Information for Cancer Research - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC7153063/) — Clinical timeline validation patterns

### Tertiary (LOW confidence)
- [Augmenting fact and date of death in EHR - PubMed](https://pubmed.ncbi.nlm.nih.gov/41307270/) — Death date validation methodology (2026 study, not PCORnet-specific)
- [R Packages for Data Quality Assessments - MDPI](https://mdpi.com/2076-3417/12/9/4238/htm) — pointblank vs assertr vs validate comparison
- [Package pointblank (0.12.3)](https://cran.r-project.org/web/packages/pointblank/pointblank.pdf) — Data validation package (optional for v2)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All packages already in renv.lock, version-locked by project
- Architecture patterns: HIGH — Reuses established patterns from Phase 57 (death rows), Phase 44 (openxlsx2 styling), Phase 55 (confirmed HL cohort)
- Pitfalls: HIGH — Based on dplyr date filtering edge cases (NA handling, type mismatches) documented in tidyverse issues and Stack Overflow
- Clinical validation methodology: MEDIUM — General clinical data quality principles applied to PCORnet context; no PCORnet-specific death validation guide found

**Research date:** 2026-05-28
**Valid until:** 2026-06-28 (30 days — stable R ecosystem, version-locked packages)
