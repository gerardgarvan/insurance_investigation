# ==============================================================================
# 59_death_date_summary.R -- Death Date Cross-Tab Summary
# ==============================================================================
#
# Purpose:
#   Produce a meeting-ready death date cross-tab summary answering three team
#   questions: (i) how many patients have a death date, (ii) of those how many
#   have death as their last encounter, (iii) how many have encounters after
#   their death date. Standalone investigation script -- no upstream modification.
#
# Inputs:
#   - cache/outputs/validated_death_dates.rds (from R/53 Phase 59)
#     Columns: ID, DEATH_DATE, DEATH_SOURCE, death_valid, post_death_activity
#   - output/confirmed_hl_cohort.rds (from R/55)
#     Columns: ID, first_hl_dx_date, first_hl_dx_source
#   - DuckDB ENCOUNTER table (for last encounter dates per patient)
#
# Outputs:
#   - output/death_date_summary.xlsx (single xlsx, meeting-presentable)
#     Sheet: "Death Date Summary" with Metric, Count, Pct of Cohort columns
#
# Phase 103 Decisions (Death Date Cross-Tab Summary):
#   D-01: New standalone script (investigation pattern like R/30, R/58)
#   D-02: Reads validated_death_dates.rds + confirmed_hl_cohort.rds + DuckDB ENCOUNTER
#   D-03: Cascading summary: total cohort > death date > death is last > post-death
#   D-04: Total confirmed HL cohort as denominator (not death date subset)
#   D-05: Verification logging against R/29 Section 4 metrics (DEATH-01/02/03)
#   D-06: Raw counts -- NO automatic HIPAA suppression (manual before sharing)
#   D-07: Single xlsx "Death Date Summary" sheet, meeting-presentable styling
#   D-08: Styled headers (dark gray FF374151, white bold text, freeze panes)
#
# Dependencies:
#   - R/00_config.R (CONFIG paths)
#   - R/utils/utils_assertions.R (assert_rds_exists, assert_df_valid)
#   - R/utils/utils_duckdb.R (get_pcornet_table, open/close_pcornet_con)
#   - R/utils/utils_dates.R (parse_pcornet_date)
#   - openxlsx2 (styled xlsx output)
#
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND CONFIGURATION ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/utils/utils_assertions.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")

# --- Define file paths ---
DEATH_RDS <- file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")
COHORT_RDS <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "death_date_summary.xlsx")

message("=== Phase 103: Death Date Cross-Tab Summary ===")
message()
message(glue("  Death RDS:  {DEATH_RDS}"))
message(glue("  Cohort RDS: {COHORT_RDS}"))
message(glue("  Output:     {OUTPUT_XLSX}"))
message()


# ==============================================================================
# SECTION 2: INPUT VALIDATION ----
# ==============================================================================

message("--- Input validation ---")

assert_rds_exists(DEATH_RDS, script_name = "R/59")
assert_rds_exists(COHORT_RDS, script_name = "R/59")

message("  Both input RDS files validated.")
message()


# ==============================================================================
# SECTION 3: LOAD DATA ----
# ==============================================================================

message("--- Loading data ---")

# Load validated death dates (from R/53 Phase 59)
# Columns: ID, DEATH_DATE, DEATH_SOURCE, death_valid, post_death_activity
validated_deaths <- readRDS(DEATH_RDS)
message(glue("  Loaded validated_death_dates.rds: {nrow(validated_deaths)} patients"))

# Load confirmed HL cohort (from R/55 via R/20) for total cohort denominator
# Columns: ID, first_hl_dx_date, first_hl_dx_source
cohort <- readRDS(COHORT_RDS)
message(glue("  Loaded confirmed_hl_cohort.rds: {nrow(cohort)} patients"))

# Query DuckDB ENCOUNTER for last encounter dates per patient
# Replicates R/29 Section 4b EXACTLY
open_pcornet_con()
last_encounters <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ADMIT_DATE) %>%
  collect() %>%
  mutate(ADMIT_DATE = parse_pcornet_date(ADMIT_DATE)) %>%
  filter(!is.na(ADMIT_DATE)) %>%
  group_by(ID) %>%
  summarise(last_encounter_date = max(ADMIT_DATE), .groups = "drop")
close_pcornet_con()

message(glue("  Loaded last encounter dates for {nrow(last_encounters)} patients"))
message()


# ==============================================================================
# SECTION 4: COMPUTE SUMMARY METRICS ----
# ==============================================================================

message("--- Computing summary metrics ---")

# Metric 1: Total confirmed HL cohort (per D-04 -- denominator)
total_cohort <- nrow(cohort)
message(glue("  Total confirmed HL cohort: {total_cohort}"))

# Metric 2: Patients with validated death date
# MUST filter death_valid == TRUE (Pitfall 2 avoidance)
valid_deaths <- validated_deaths %>%
  filter(death_valid == TRUE)
n_with_death <- nrow(valid_deaths)
message(glue("  Patients with validated death date: {n_with_death}"))

# Metric 3: Death is last encounter (replicate R/29 case_when exactly)
death_vs_encounter <- valid_deaths %>%
  left_join(last_encounters, by = "ID") %>%
  mutate(
    death_is_last = case_when(
      is.na(last_encounter_date) ~ TRUE,
      DEATH_DATE >= last_encounter_date ~ TRUE,
      TRUE ~ FALSE
    )
  )
n_death_is_last <- sum(death_vs_encounter$death_is_last, na.rm = TRUE)
message(glue("  Death is last encounter: {n_death_is_last}"))

# Metric 4: Post-death activity (from Phase 59 flag -- NOT recomputed)
n_post_death <- sum(valid_deaths$post_death_activity, na.rm = TRUE)
message(glue("  Patients with post-death activity: {n_post_death}"))
message()


# ==============================================================================
# SECTION 5: VERIFICATION vs R/29 ----
# ==============================================================================

message("--- Verification vs R/29 Section 4 ---")
message(glue("  DEATH-01 (patients with death date): {n_with_death}"))
message(glue("  DEATH-02 (death is last encounter): {n_death_is_last}"))
message(glue("  DEATH-03 (post-death activity):     {n_post_death}"))
message("  [Run R/29 and compare above counts to its DEATH-01/02/03 output]")
message()


# ==============================================================================
# SECTION 6: BUILD SUMMARY TABLE AND CREATE STYLED XLSX ----
# ==============================================================================

message("--- Building summary table and creating xlsx ---")

# D-03: Cascading summary (rows flow top-to-bottom)
summary_table <- tibble(
  Metric = c(
    "Total confirmed HL cohort patients",
    "Patients with validated death date",
    "  Death is last encounter",
    "  Encounters after death date"
  ),
  Count = c(total_cohort, n_with_death, n_death_is_last, n_post_death),
  `Pct of Cohort` = c(
    "100.0%",
    sprintf("%.1f%%", 100 * n_with_death / total_cohort),
    sprintf("%.1f%%", 100 * n_death_is_last / total_cohort),
    sprintf("%.1f%%", 100 * n_post_death / total_cohort)
  )
)

# D-07, D-08: Create styled xlsx (meeting-presentable)
wb <- wb_workbook()
wb$add_worksheet("Death Date Summary")

# Title row
wb$add_data(
  sheet = "Death Date Summary",
  x = "Death Date Cross-Tab Summary",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Death Date Summary", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Death Date Summary", dims = "A1:C1")

# Subtitle row
subtitle <- glue("Generated: {Sys.Date()} | Cohort: Confirmed HL patients (OneFlorida+)")
wb$add_data(
  sheet = "Death Date Summary",
  x = subtitle,
  start_row = 2, start_col = 1
)
wb$add_font(
  sheet = "Death Date Summary", dims = "A2",
  name = "Calibri", size = 10, color = wb_color("FF6B7280")
)
wb$merge_cells(sheet = "Death Date Summary", dims = "A2:C2")

# Data table starting at row 4
wb$add_data(
  sheet = "Death Date Summary",
  x = summary_table,
  start_row = 4, start_col = 1
)

# Header row styling (row 4 -- dark gray background, white bold text)
wb$add_fill(
  sheet = "Death Date Summary", dims = "A4:C4",
  color = wb_color("FF374151")
)
wb$add_font(
  sheet = "Death Date Summary", dims = "A4:C4",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)

# Count column number formatting (#,##0)
wb$add_numfmt(
  sheet = "Death Date Summary", dims = "B5:B8",
  numfmt = "#,##0"
)

# Column widths (wide enough for labels)
wb$set_col_widths(
  sheet = "Death Date Summary",
  cols = 1:3, widths = c(45, 15, 15)
)

# Freeze pane below header
wb$freeze_pane(
  sheet = "Death Date Summary",
  firstActiveRow = 5
)

wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)

message(glue("  Saved: {OUTPUT_XLSX}"))
message()


# ==============================================================================
# SECTION 7: FINAL SUMMARY ----
# ==============================================================================

message("=== Phase 103 Complete ===")
message()
message(glue("  Output: {OUTPUT_XLSX}"))
message()
message("  Key metrics:")
message(glue("    Total cohort:             {total_cohort}"))
message(glue("    With death date:          {n_with_death} ({sprintf('%.1f%%', 100 * n_with_death / total_cohort)})"))
message(glue("    Death is last encounter:  {n_death_is_last} ({sprintf('%.1f%%', 100 * n_death_is_last / total_cohort)})"))
message(glue("    Post-death activity:      {n_post_death} ({sprintf('%.1f%%', 100 * n_post_death / total_cohort)})"))
message()
message("Done.")
