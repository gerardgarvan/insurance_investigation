# =============================================================================
# Phase 44: Treatment Episode Start/Stop Dates
# =============================================================================
# Extracts per-patient, per-episode treatment start and stop dates with episode
# length and historical date flagging. This is a NEW detail-level output
# alongside Phase 43's existing per-patient summary.
#
# Decision traceability:
#   D-01: historical episodes included with historical_flag boolean column
#   D-02: historical cutoff = before 2012-01-01
#   D-03: episode flagged historical when ALL dates < 2012-01-01 (using episode_stop)
#   D-04: single-date historical episodes get start=stop, length=0
#   D-05: new script alongside Phase 43 (Phase 43 unchanged)
#   D-06: new file R/44_treatment_episodes.R
#   D-07: outputs RDS + styled xlsx + per-type CSVs
#   D-08: columns: patient_id, treatment_type, episode_number, episode_start,
#          episode_stop, episode_length_days, distinct_dates_in_episode, historical_flag
#   D-09: one row per patient per treatment type per episode
#   D-10: 90-day gap threshold (from Phase 43)
#   D-11: all chemo codes pooled (from Phase 43)
#   D-12: four treatment types (from Phase 43)
#   D-13: pre-2000 dates are real tumor registry data
#
# Outputs:
#   - RDS artifact: one row per patient per treatment type per episode
#   - Styled xlsx: Summary sheet + per-type detail sheets + Historical Summary
#   - Per-type CSVs: chemotherapy_episodes.csv, radiation_episodes.csv,
#                    sct_episodes.csv, immunotherapy_episodes.csv
# =============================================================================


# --- SECTION 1: SETUP AND CONFIGURATION ---

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(purrr)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

# Reuse Phase 43's extraction functions, constants, and color scheme
source("R/43_treatment_durations.R")

# Output paths
OUTPUT_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "treatment_episodes.xlsx")

# Per D-02: historical cutoff date (matches OneFlorida+ data extraction period start)
HISTORICAL_CUTOFF <- as.Date("2012-01-01")


# --- SECTION 2: EPISODE CALCULATION FUNCTION ---

#' Calculate detailed episode-level data (stops at per-episode instead of per-patient)
#'
#' Adapted from R/43_treatment_durations.R calculate_durations_and_episodes()
#' lines 476-492, but stops BEFORE the per-patient collapse at line 495.
#'
#' @param dates_df Tibble with columns ID and treatment_date
#' @param gap_threshold Integer. Days between consecutive dates to split episodes
#' @return Tibble with one row per patient per episode: patient_id, episode_number,
#'   episode_start, episode_stop, episode_length_days, distinct_dates_in_episode,
#'   historical_flag
calculate_episodes_detailed <- function(dates_df, gap_threshold = GAP_THRESHOLD) {
  # Empty input guard
  if (nrow(dates_df) == 0) {
    return(tibble(
      patient_id = character(0),
      episode_number = integer(0),
      episode_start = as.Date(character(0)),
      episode_stop = as.Date(character(0)),
      episode_length_days = numeric(0),
      distinct_dates_in_episode = integer(0),
      historical_flag = logical(0)
    ))
  }

  # Core pipeline: adapted from R/43 lines 476-492, stopping BEFORE per-patient collapse
  dates_df %>%
    group_by(ID) %>%
    arrange(treatment_date, .by_group = TRUE) %>%
    mutate(
      days_since_prev = as.numeric(treatment_date - lag(treatment_date)),
      new_episode = is.na(days_since_prev) | days_since_prev >= gap_threshold,
      episode_id = cumsum(new_episode)
    ) %>%
    # Per-episode summary (THIS is the output level for Phase 44)
    group_by(ID, episode_id) %>%
    summarise(
      episode_start = min(treatment_date),
      episode_stop = max(treatment_date),
      episode_length_days = as.numeric(max(treatment_date) - min(treatment_date)),
      distinct_dates_in_episode = n(),
      .groups = "drop"
    ) %>%
    # Add episode_number per patient (per D-08, D-09)
    group_by(ID) %>%
    mutate(episode_number = row_number()) %>%
    ungroup() %>%
    # Add historical_flag per D-02/D-03
    # (using episode_stop < HISTORICAL_CUTOFF because if the LAST date is pre-2012,
    #  ALL dates are pre-2012)
    mutate(historical_flag = episode_stop < HISTORICAL_CUTOFF) %>%
    # Final select to match D-08 schema exactly
    select(
      patient_id = ID,
      episode_number,
      episode_start,
      episode_stop,
      episode_length_days,
      distinct_dates_in_episode,
      historical_flag
    )
}


# --- SECTION 3: CONSOLE SUMMARY FUNCTION ---

#' Log episode statistics for a treatment type
#' @param episodes_df Tibble from calculate_episodes_detailed()
#' @param type_name Character. Treatment type name for logging
log_episode_stats <- function(episodes_df, type_name) {
  if (nrow(episodes_df) == 0) {
    message(glue("\n  {type_name} Summary: 0 episodes (no data)"))
    return(invisible(NULL))
  }

  n_patients <- n_distinct(episodes_df$patient_id)
  n_episodes <- nrow(episodes_df)
  n_historical <- sum(episodes_df$historical_flag)
  pct_historical <- round(100 * mean(episodes_df$historical_flag), 1)
  median_length <- median(episodes_df$episode_length_days)
  median_dates <- median(episodes_df$distinct_dates_in_episode)

  message(glue("\n  {type_name} Summary:"))
  message(glue("    Patients: {n_patients}"))
  message(glue("    Episodes: {n_episodes} ({n_historical} historical, {pct_historical}%)"))
  message(glue("    Episode length (days): median={median_length}"))
  message(glue("    Dates per episode: median={median_dates}"))

  invisible(NULL)
}


# --- SECTION 4: MAIN EXECUTION LOOP ---

message("=== Phase 44: Treatment Episode Start/Stop Dates ===\n")

episodes_list <- list()

for (type in TREATMENT_TYPES) {
  # Reuse Phase 43's extract_all_dates() function (via source("R/43_treatment_durations.R"))
  dates_df <- extract_all_dates(type)

  # Calculate per-episode detail
  episodes_df <- calculate_episodes_detailed(dates_df)

  # Add treatment type column
  episodes_df <- episodes_df %>%
    mutate(treatment_type = type)

  # Log summary stats
  log_episode_stats(episodes_df, type)

  episodes_list[[type]] <- episodes_df
}

# Combine all types into single dataset
all_episodes <- bind_rows(episodes_list) %>%
  select(patient_id, treatment_type, episode_number, episode_start, episode_stop,
         episode_length_days, distinct_dates_in_episode, historical_flag)

# Save RDS artifact
saveRDS(all_episodes, OUTPUT_RDS)
message(glue("\nRDS saved: {OUTPUT_RDS} ({nrow(all_episodes)} rows)"))


# --- SECTION 5: PER-TYPE CSV OUTPUT ---

message("\n--- Writing per-type CSV files ---")

for (type in TREATMENT_TYPES) {
  type_data <- episodes_list[[type]]
  csv_name <- paste0(tolower(gsub(" ", "_", type)), "_episodes.csv")
  csv_path <- file.path(CONFIG$output_dir, csv_name)

  write_df <- type_data %>%
    select(patient_id, episode_number, episode_start, episode_stop,
           episode_length_days, distinct_dates_in_episode, historical_flag)

  write.csv(write_df, csv_path, row.names = FALSE)
  message(glue("  Wrote {csv_path} ({nrow(write_df)} episodes)"))
}


# --- SECTION 6: STYLED XLSX REPORT ---

message("\n--- Creating styled xlsx report ---")

wb <- wb_workbook()

# ---------- SHEET 1: SUMMARY ----------
wb$add_worksheet("Summary")

# Title row (merged A1:H1)
wb$add_data("Summary", x = "Treatment Episodes by Type", startCol = 1, startRow = 1)
wb$merge_cells("Summary", rows = 1, cols = 1:8)
wb$add_cell_style("Summary", dims = "A1",
                  fontSize = 16, fontName = "Calibri", bold = TRUE,
                  fontColour = wb_colour("FF1F2937"))

# Subtitle row (merged A2:H2)
subtitle <- glue("Generated: {Sys.Date()} | Gap threshold: {GAP_THRESHOLD} days | Historical cutoff: 2012-01-01")
wb$add_data("Summary", x = subtitle, startCol = 1, startRow = 2)
wb$merge_cells("Summary", rows = 2, cols = 1:8)
wb$add_cell_style("Summary", dims = "A2",
                  fontSize = 10, fontName = "Calibri",
                  fontColour = wb_colour("FF6B7280"))

# Headers (row 4) with dark fill and white font
headers <- c("Treatment Type", "Patients", "Episodes", "Historical Episodes",
             "% Historical", "Median Length (days)", "Median Dates/Episode", "Max Episodes")
wb$add_data("Summary", x = as.data.frame(t(headers)), startCol = 1, startRow = 4,
            colNames = FALSE)
wb$add_cell_style("Summary", dims = "A4:H4",
                  fontSize = 11, fontName = "Calibri", bold = TRUE,
                  fontColour = wb_colour("FFFFFFFF"),
                  fgFill = wb_colour("FF374151"))

# Data rows (5-8): one per treatment type
summary_data <- list()
for (i in seq_along(TREATMENT_TYPES)) {
  type <- TREATMENT_TYPES[i]
  type_data <- episodes_list[[type]]

  if (nrow(type_data) == 0) {
    summary_data[[i]] <- list(
      treatment_type = type,
      n_patients = 0,
      n_episodes = 0,
      n_historical = 0,
      pct_historical = 0,
      median_length = NA,
      median_dates = NA,
      max_episodes = 0
    )
  } else {
    summary_data[[i]] <- list(
      treatment_type = type,
      n_patients = n_distinct(type_data$patient_id),
      n_episodes = nrow(type_data),
      n_historical = sum(type_data$historical_flag),
      pct_historical = round(100 * mean(type_data$historical_flag), 1),
      median_length = median(type_data$episode_length_days),
      median_dates = median(type_data$distinct_dates_in_episode),
      max_episodes = max(type_data$episode_number)
    )
  }
}
summary_df <- bind_rows(summary_data)

wb$add_data("Summary", x = summary_df, startCol = 1, startRow = 5, colNames = FALSE)

# Apply type-specific colors to column A (treatment type names)
for (i in seq_along(TREATMENT_TYPES)) {
  type <- TREATMENT_TYPES[i]
  colors <- TREATMENT_TYPE_COLORS[[type]]
  row_num <- 4 + i
  wb$add_cell_style("Summary", dims = glue("A{row_num}"),
                    fgFill = wb_colour(colors$fill),
                    fontColour = wb_colour(colors$font),
                    bold = TRUE)
}

# Number formatting
wb$add_numfmt("Summary", dims = "B5:D8", numfmt = "#,##0")
wb$add_numfmt("Summary", dims = "E5:E8", numfmt = "#,##0.0")
wb$add_numfmt("Summary", dims = "F5:H8", numfmt = "#,##0")

# Column widths
wb$set_col_widths("Summary", cols = 1:8, widths = c(20, 12, 12, 18, 14, 22, 20, 16))


# ---------- SHEETS 2-5: PER-TYPE DETAIL SHEETS ----------
for (type in TREATMENT_TYPES) {
  type_data <- episodes_list[[type]]
  sheet_name <- glue("{type} Episodes")
  wb$add_worksheet(sheet_name)

  n_episodes <- nrow(type_data)
  n_patients <- if (n_episodes > 0) n_distinct(type_data$patient_id) else 0

  # Title row
  title_text <- glue("{type} Treatment Episodes ({n_episodes} episodes, {n_patients} patients)")
  wb$add_data(sheet_name, x = title_text, startCol = 1, startRow = 1)
  wb$merge_cells(sheet_name, rows = 1, cols = 1:7)
  wb$add_cell_style(sheet_name, dims = "A1",
                    fontSize = 16, fontName = "Calibri", bold = TRUE)

  # Headers (row 2) with type-specific colors
  detail_headers <- c("Patient ID", "Episode #", "Start Date", "Stop Date",
                      "Length (days)", "Distinct Dates", "Historical")
  wb$add_data(sheet_name, x = as.data.frame(t(detail_headers)), startCol = 1, startRow = 2,
              colNames = FALSE)

  colors <- TREATMENT_TYPE_COLORS[[type]]
  wb$add_cell_style(sheet_name, dims = "A2:G2",
                    fontSize = 11, fontName = "Calibri", bold = TRUE,
                    fontColour = wb_colour(colors$font),
                    fgFill = wb_colour(colors$fill))

  # Data rows (row 3+)
  if (n_episodes > 0) {
    write_df <- data.frame(
      Patient_ID = type_data$patient_id,
      Episode_Num = type_data$episode_number,
      Start_Date = as.character(type_data$episode_start),
      Stop_Date = as.character(type_data$episode_stop),
      Length_Days = type_data$episode_length_days,
      Distinct_Dates = type_data$distinct_dates_in_episode,
      Historical = type_data$historical_flag
    )

    wb$add_data(sheet_name, x = write_df, startCol = 1, startRow = 3, colNames = FALSE)

    # Apply gray fill to historical rows
    historical_rows <- which(type_data$historical_flag)
    if (length(historical_rows) > 0) {
      for (row_idx in historical_rows) {
        row_num <- 2 + row_idx  # +2 because data starts at row 3
        wb$add_cell_style(sheet_name, dims = glue("A{row_num}:G{row_num}"),
                          fgFill = wb_colour("FFE5E5E5"))
      }
    }

    # Number formatting
    last_row <- 2 + n_episodes
    wb$add_numfmt(sheet_name, dims = glue("E3:F{last_row}"), numfmt = "#,##0")
  }

  # Column widths
  wb$set_col_widths(sheet_name, cols = 1:7, widths = c(20, 12, 15, 15, 15, 15, 12))
}


# ---------- SHEET 6: HISTORICAL SUMMARY ----------
wb$add_worksheet("Historical Summary")

# Title row
wb$add_data("Historical Summary", x = "Historical Episodes (pre-2012)", startCol = 1, startRow = 1)
wb$merge_cells("Historical Summary", rows = 1, cols = 1:5)
wb$add_cell_style("Historical Summary", dims = "A1",
                  fontSize = 16, fontName = "Calibri", bold = TRUE,
                  fontColour = wb_colour("FF1F2937"))

historical_episodes <- all_episodes %>% filter(historical_flag)

if (nrow(historical_episodes) == 0) {
  wb$add_data("Historical Summary", x = "No historical episodes found",
              startCol = 1, startRow = 3)
} else {
  # By type
  message_text <- glue("{nrow(historical_episodes)} historical episodes found")
  wb$add_data("Historical Summary", x = message_text, startCol = 1, startRow = 3)

  # Headers (row 5)
  hist_headers <- c("Treatment Type", "Episodes", "Patients", "Earliest Date", "Latest Date")
  wb$add_data("Historical Summary", x = as.data.frame(t(hist_headers)),
              startCol = 1, startRow = 5, colNames = FALSE)
  wb$add_cell_style("Historical Summary", dims = "A5:E5",
                    fontSize = 11, fontName = "Calibri", bold = TRUE,
                    fontColour = wb_colour("FFFFFFFF"),
                    fgFill = wb_colour("FF374151"))

  # By-type summary
  hist_summary <- historical_episodes %>%
    group_by(treatment_type) %>%
    summarise(
      n_episodes = n(),
      n_patients = n_distinct(patient_id),
      earliest = min(episode_start),
      latest = max(episode_stop),
      .groups = "drop"
    ) %>%
    mutate(
      earliest = as.character(earliest),
      latest = as.character(latest)
    )

  wb$add_data("Historical Summary", x = hist_summary, startCol = 1, startRow = 6, colNames = FALSE)

  # Decade distribution (row 10+)
  wb$add_data("Historical Summary", x = "\nDecade Distribution:", startCol = 1, startRow = 10)

  decade_dist <- historical_episodes %>%
    mutate(decade = 10 * (as.integer(format(episode_start, "%Y")) %/% 10)) %>%
    count(decade, name = "n_episodes") %>%
    arrange(decade) %>%
    mutate(decade_label = paste0(decade, "s"))

  decade_headers <- c("Decade", "Episodes")
  wb$add_data("Historical Summary", x = as.data.frame(t(decade_headers)),
              startCol = 1, startRow = 12, colNames = FALSE)
  wb$add_cell_style("Historical Summary", dims = "A12:B12",
                    fontSize = 11, fontName = "Calibri", bold = TRUE,
                    fontColour = wb_colour("FFFFFFFF"),
                    fgFill = wb_colour("FF374151"))

  decade_out <- decade_dist %>% select(decade_label, n_episodes)
  wb$add_data("Historical Summary", x = decade_out, startCol = 1, startRow = 13, colNames = FALSE)
}

wb$set_col_widths("Historical Summary", cols = 1:5, widths = c(20, 12, 12, 15, 15))


# Save workbook
wb$save(OUTPUT_XLSX)
message(glue("XLSX saved: {OUTPUT_XLSX}"))


# --- SECTION 7: FINAL SUMMARY ---

message("\n=== Phase 44 Complete ===")
message(glue("Total episodes: {nrow(all_episodes)}"))
message(glue("Unique patients: {n_distinct(all_episodes$patient_id)}"))
message(glue("Historical episodes: {sum(all_episodes$historical_flag)} ({round(100*mean(all_episodes$historical_flag), 1)}%)"))
message(glue("\nOutputs:"))
message(glue("  RDS:  {OUTPUT_RDS}"))
message(glue("  XLSX: {OUTPUT_XLSX}"))
message(glue("  CSVs: {CONFIG$output_dir}/*_episodes.csv"))
