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
#   D-10: 90-day window from episode start (not gap between consecutive dates)
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

# assign_episode_ids() is defined in R/43_treatment_durations.R (sourced above)

#' Calculate detailed episode-level data (stops at per-episode instead of per-patient)
#'
#' Adapted from R/43_treatment_durations.R calculate_durations_and_episodes()
#' but uses window-based episode splitting (90-day window from episode start)
#' instead of gap-based splitting.
#'
#' @param dates_df Tibble with columns ID and treatment_date
#' @param gap_threshold Integer. Max days from episode start to define cycle boundary
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

  # Core pipeline: window-based episode splitting (date - episode_start >= threshold)
  dates_df %>%
    group_by(ID) %>%
    arrange(treatment_date, .by_group = TRUE) %>%
    mutate(
      episode_id = assign_episode_ids(treatment_date, gap_threshold)
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

# Row 1: Title
wb$add_data(sheet = "Summary", x = "Treatment Episodes by Type",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Summary", dims = "A1:H1")

# Row 2: Subtitle
subtitle <- as.character(glue("Generated: {Sys.Date()} | Gap threshold: {GAP_THRESHOLD} days | Historical cutoff: 2012-01-01"))
wb$add_data(sheet = "Summary", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A2",
            name = "Calibri", size = 10, color = wb_color("FF6B7280"))
wb$merge_cells(sheet = "Summary", dims = "A2:H2")

# Row 4: Headers with dark fill and white font
headers <- c("Treatment Type", "Patients", "Episodes", "Historical Episodes",
             "% Historical", "Median Length (days)", "Median Dates/Episode", "Max Episodes")
for (i in seq_along(headers)) {
  wb$add_data(sheet = "Summary", x = headers[i], start_row = 4, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A4:H4", color = wb_color("FF374151"))
wb$add_font(sheet = "Summary", dims = "A4:H4",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Data rows (5-8): one per treatment type
for (i in seq_along(TREATMENT_TYPES)) {
  type <- TREATMENT_TYPES[i]
  type_data <- episodes_list[[type]]
  row_num <- 4 + i

  if (nrow(type_data) == 0) {
    wb$add_data(sheet = "Summary", x = type, start_row = row_num, start_col = 1)
    for (col in 2:8) wb$add_data(sheet = "Summary", x = 0L, start_row = row_num, start_col = col)
  } else {
    wb$add_data(sheet = "Summary", x = type, start_row = row_num, start_col = 1)
    wb$add_data(sheet = "Summary", x = as.integer(n_distinct(type_data$patient_id)),
                start_row = row_num, start_col = 2)
    wb$add_data(sheet = "Summary", x = as.integer(nrow(type_data)),
                start_row = row_num, start_col = 3)
    wb$add_data(sheet = "Summary", x = as.integer(sum(type_data$historical_flag)),
                start_row = row_num, start_col = 4)
    wb$add_data(sheet = "Summary", x = round(100 * mean(type_data$historical_flag), 1),
                start_row = row_num, start_col = 5)
    wb$add_data(sheet = "Summary", x = median(type_data$episode_length_days),
                start_row = row_num, start_col = 6)
    wb$add_data(sheet = "Summary", x = median(type_data$distinct_dates_in_episode),
                start_row = row_num, start_col = 7)
    wb$add_data(sheet = "Summary", x = as.integer(max(type_data$episode_number)),
                start_row = row_num, start_col = 8)
  }

  # Apply type-specific fill color to the type name cell
  type_dims <- glue("A{row_num}")
  wb$add_fill(sheet = "Summary", dims = type_dims,
              color = wb_color(TREATMENT_TYPE_COLORS[[type]]$fill))
  wb$add_font(sheet = "Summary", dims = type_dims,
              name = "Calibri", size = 11, bold = TRUE,
              color = wb_color(TREATMENT_TYPE_COLORS[[type]]$font))
}

# Number formatting
wb$add_numfmt(sheet = "Summary", dims = "B5:D8", numfmt = "#,##0")
wb$add_numfmt(sheet = "Summary", dims = "E5:E8", numfmt = "#,##0.0")
wb$add_numfmt(sheet = "Summary", dims = "F5:H8", numfmt = "#,##0")

# Column widths
wb$set_col_widths(sheet = "Summary", cols = 1:8, widths = c(20, 12, 12, 18, 14, 22, 20, 16))


# ---------- SHEETS 2-5: PER-TYPE DETAIL SHEETS ----------
for (type in TREATMENT_TYPES) {
  type_data <- episodes_list[[type]]
  sheet_name <- as.character(glue("{type} Episodes"))
  wb$add_worksheet(sheet_name)

  n_episodes <- nrow(type_data)
  n_patients <- if (n_episodes > 0) n_distinct(type_data$patient_id) else 0

  # Row 1: Title
  title_text <- as.character(glue("{type} Treatment Episodes ({n_episodes} episodes, {n_patients} patients)"))
  wb$add_data(sheet = sheet_name, x = title_text, start_row = 1, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A1",
              name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
  wb$merge_cells(sheet = sheet_name, dims = "A1:G1")

  # Row 2: Headers with type-specific colors
  detail_headers <- c("Patient ID", "Episode #", "Start Date", "Stop Date",
                      "Length (days)", "Distinct Dates", "Historical")
  for (j in seq_along(detail_headers)) {
    wb$add_data(sheet = sheet_name, x = detail_headers[j], start_row = 2, start_col = j)
  }

  colors <- TREATMENT_TYPE_COLORS[[type]]
  wb$add_fill(sheet = sheet_name, dims = "A2:G2", color = wb_color(colors$fill))
  wb$add_font(sheet = sheet_name, dims = "A2:G2",
              name = "Calibri", size = 11, bold = TRUE, color = wb_color(colors$font))

  # Data rows (row 3+)
  if (n_episodes > 0) {
    write_df <- data.frame(
      Patient_ID = type_data$patient_id,
      Episode_Num = type_data$episode_number,
      Start_Date = as.character(type_data$episode_start),
      Stop_Date = as.character(type_data$episode_stop),
      Length_Days = type_data$episode_length_days,
      Distinct_Dates = type_data$distinct_dates_in_episode,
      Historical = type_data$historical_flag,
      stringsAsFactors = FALSE
    )

    wb$add_data(sheet = sheet_name, x = write_df, start_row = 3, col_names = FALSE)

    # Apply gray fill to historical rows
    historical_rows <- which(type_data$historical_flag)
    if (length(historical_rows) > 0) {
      for (row_idx in historical_rows) {
        row_num <- 2 + row_idx  # +2 because data starts at row 3
        wb$add_fill(sheet = sheet_name, dims = glue("A{row_num}:G{row_num}"),
                    color = wb_color("FFE5E5E5"))
      }
    }

    # Number formatting
    last_row <- 2 + n_episodes
    wb$add_numfmt(sheet = sheet_name, dims = glue("E3:F{last_row}"), numfmt = "#,##0")
  }

  # Column widths
  wb$set_col_widths(sheet = sheet_name, cols = 1:7, widths = c(20, 12, 15, 15, 15, 15, 12))
}


# ---------- SHEET 6: HISTORICAL SUMMARY ----------
wb$add_worksheet("Historical Summary")

# Row 1: Title
wb$add_data(sheet = "Historical Summary", x = "Historical Episodes (pre-2012)",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "Historical Summary", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Historical Summary", dims = "A1:E1")

historical_episodes <- all_episodes %>% filter(historical_flag)

if (nrow(historical_episodes) == 0) {
  wb$add_data(sheet = "Historical Summary", x = "No historical episodes found",
              start_row = 3, start_col = 1)
} else {
  # By type
  message_text <- as.character(glue("{nrow(historical_episodes)} historical episodes found"))
  wb$add_data(sheet = "Historical Summary", x = message_text, start_row = 3, start_col = 1)

  # Headers (row 5)
  hist_headers <- c("Treatment Type", "Episodes", "Patients", "Earliest Date", "Latest Date")
  for (i in seq_along(hist_headers)) {
    wb$add_data(sheet = "Historical Summary", x = hist_headers[i], start_row = 5, start_col = i)
  }
  wb$add_fill(sheet = "Historical Summary", dims = "A5:E5", color = wb_color("FF374151"))
  wb$add_font(sheet = "Historical Summary", dims = "A5:E5",
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

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

  wb$add_data(sheet = "Historical Summary", x = hist_summary, start_row = 6, col_names = FALSE)

  # Decade distribution (row 10+)
  wb$add_data(sheet = "Historical Summary", x = "Decade Distribution:",
              start_row = 10, start_col = 1)

  decade_dist <- historical_episodes %>%
    mutate(decade = 10 * (as.integer(format(episode_start, "%Y")) %/% 10)) %>%
    count(decade, name = "n_episodes") %>%
    arrange(decade) %>%
    mutate(decade_label = paste0(decade, "s"))

  decade_headers <- c("Decade", "Episodes")
  for (i in seq_along(decade_headers)) {
    wb$add_data(sheet = "Historical Summary", x = decade_headers[i], start_row = 12, start_col = i)
  }
  wb$add_fill(sheet = "Historical Summary", dims = "A12:B12", color = wb_color("FF374151"))
  wb$add_font(sheet = "Historical Summary", dims = "A12:B12",
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  decade_out <- decade_dist %>% select(decade_label, n_episodes)
  wb$add_data(sheet = "Historical Summary", x = decade_out, start_row = 13, col_names = FALSE)
}

wb$set_col_widths(sheet = "Historical Summary", cols = 1:5, widths = c(20, 12, 12, 15, 15))


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
