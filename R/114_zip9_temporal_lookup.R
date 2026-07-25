# ==============================================================================
# 114_zip9_temporal_lookup.R -- ZIP9 Temporal Lookup Validation (Phase 137)
# ==============================================================================
# Purpose:     Investigation script that validates get_zip9_at_date() (defined
#              in R/utils/utils_address.R) with a sample call, computes
#              per-patient address timeline diagnostics (gaps between periods,
#              overlapping periods, missing ADDRESS_PERIOD_END), logs headline
#              statistics to console, and appends an "Address Timeline
#              Diagnostics" sheet to the existing output/zip_change_frequency.xlsx
#              workbook produced by R/106.
#
#              Probe-first gate: exits gracefully if LDS_ADDRESS_HISTORY or the
#              existing xlsx is absent.
#
# Inputs:      LDS_ADDRESS_HISTORY_Mailhot_V1.csv  (probed in CONFIG$data_dir)
#              output/zip_change_frequency.xlsx      (probed — produced by R/106)
#              R/00_config.R                         (auto-loads utils_address.R)
#
# Outputs:     output/zip_change_frequency.xlsx  (new sheet appended:
#                "Address Timeline Diagnostics")
#              (Console) Headline stats: patients with gaps, overlaps, open ends
#
# Dependencies: R/00_config.R (auto-sources utils_address.R, which provides
#               get_zip9_at_date, normalize_zip9, normalize_zip5, normalize_zip5_raw;
#               also provides CONFIG, parse_pcornet_date)
#               dplyr, glue, stringr, openxlsx2, tibble
#               vroom (primary CSV loader; base read.csv fallback)
#
# Requirements: Phase 137 -- D-07 (sample validation), D-08 (probe gate),
#               D-09 (per-patient diagnostics), D-10 (xlsx append),
#               D-11 (headline stats), ZIP-04 (registration in R/39)
#
# Usage:       Rscript R/114_zip9_temporal_lookup.R
#              source("R/114_zip9_temporal_lookup.R")
#
# Note:        READ-ONLY investigation (appends a new sheet; does NOT overwrite
#              existing R/106 sheets). The CSV load and xlsx append require
#              HiPerGator with both LDS_ADDRESS_HISTORY and zip_change_frequency.xlsx
#              present. Structural verification (R/88 Section 15ab) is runnable
#              locally via grep-based checks.
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND LIBRARIES ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(openxlsx2)
  library(tibble)
})

source("R/00_config.R")   # auto-loads utils_address.R (get_zip9_at_date, normalize_zip*)

message("=== Phase 137: ZIP9 Temporal Lookup Validation ===")


# ==============================================================================
# SECTION 2: CONSTANTS AND DUAL PROBE GATE (D-08) ----
# ==============================================================================

ADDR_FILENAME <- "LDS_ADDRESS_HISTORY_Mailhot_V1.csv"
OUTPUT_XLSX   <- file.path(CONFIG$output_dir, "zip_change_frequency.xlsx")
addr_path     <- file.path(CONFIG$data_dir, ADDR_FILENAME)

message(glue("  CSV probe: {addr_path}"))
if (!file.exists(addr_path)) {
  message(glue(
    "\n[R/114] LDS_ADDRESS_HISTORY not found at expected path.\n",
    "  Expected: {addr_path}\n",
    "  This script requires HiPerGator with LDS_ADDRESS_HISTORY present.\n",
    "  If the file is named differently, update ADDR_FILENAME at the top of this script.\n"
  ))
  if (identical(environment(), globalenv())) {
    quit(status = 0)
  } else {
    stop("[R/114] LDS_ADDRESS_HISTORY not found -- skipped (not a real failure)", call. = FALSE)
  }
}

# Second gate: xlsx must exist (produced by R/106) before we can append to it
message(glue("  xlsx probe: {OUTPUT_XLSX}"))
if (!file.exists(OUTPUT_XLSX)) {
  message(glue(
    "\n[R/114] zip_change_frequency.xlsx not found.\n",
    "  Expected: {OUTPUT_XLSX}\n",
    "  Run R/106_zip_change_frequency.R first to create the workbook.\n"
  ))
  if (identical(environment(), globalenv())) {
    quit(status = 0)
  } else {
    stop("[R/114] zip_change_frequency.xlsx not found -- skipped", call. = FALSE)
  }
}


# ==============================================================================
# SECTION 3: LOAD ADDRESS TABLE AND SAMPLE-VALIDATE get_zip9_at_date (D-07) ----
# ==============================================================================

# LDS_ADDRESS_HISTORY is NOT in PCORNET_TABLES -- read directly by path.
# Load addr_full once; reused in Section 4 (do NOT read the file a second time).
message("--- Loading LDS_ADDRESS_HISTORY ---")

addr_full <- tryCatch(
  vroom::vroom(addr_path, col_types = vroom::cols(.default = "c"), progress = FALSE),
  error = function(e) {
    message(glue("  vroom failed ({conditionMessage(e)}); falling back to read.csv"))
    read.csv(addr_path, colClasses = "character", na.strings = c("", "NA"))
  }
)

message(glue("  Rows loaded: {nrow(addr_full)}"))

message("--- Validating get_zip9_at_date() with sample ---")
sample_ids    <- head(unique(addr_full$ID), 5)
sample_dates  <- rep(Sys.Date() - 365, length(sample_ids))
sample_result <- get_zip9_at_date(sample_ids, sample_dates)
message(glue("  Sample result rows: {nrow(sample_result)}"))
message(glue("  match_type distribution:\n{paste(capture.output(print(table(sample_result$match_type))), collapse='\n')}"))


# ==============================================================================
# SECTION 4: PER-PATIENT ADDRESS TIMELINE DIAGNOSTICS (D-09) ----
# ==============================================================================

# Reuse addr_full loaded in Section 3.
message("--- Computing per-patient address timeline diagnostics ---")

addr_parsed <- addr_full %>%
  mutate(
    period_start_dt = parse_pcornet_date(ADDRESS_PERIOD_START),
    period_end_dt   = if_else(
      is.na(ADDRESS_PERIOD_END) | trimws(ADDRESS_PERIOD_END) == "",
      as.Date("9999-12-31"),
      parse_pcornet_date(ADDRESS_PERIOD_END)
    ),
    has_open_end = is.na(ADDRESS_PERIOD_END) | trimws(ADDRESS_PERIOD_END) == ""
  ) %>%
  filter(!is.na(period_start_dt))

# Per-patient metrics
patient_timeline <- addr_parsed %>%
  group_by(ID) %>%
  arrange(period_start_dt, .by_group = TRUE) %>%
  mutate(
    next_start  = lead(period_start_dt),
    has_gap     = !is.na(next_start) & next_start > period_end_dt,
    has_overlap = !is.na(next_start) & next_start < period_end_dt & !has_open_end
  ) %>%
  summarise(
    n_periods    = n(),
    any_gap      = any(has_gap, na.rm = TRUE),
    any_overlap  = any(has_overlap, na.rm = TRUE),
    any_open_end = any(has_open_end, na.rm = TRUE),
    .groups = "drop"
  )

n_patients_total  <- n_distinct(addr_parsed$ID)
pct_with_gaps     <- round(100 * sum(patient_timeline$any_gap)     / n_patients_total, 1)
pct_with_overlaps <- round(100 * sum(patient_timeline$any_overlap) / n_patients_total, 1)
pct_with_open     <- round(100 * sum(patient_timeline$any_open_end) / n_patients_total, 1)

period_dist <- patient_timeline %>%
  mutate(bucket = case_when(
    n_periods == 1 ~ "1 period",
    n_periods == 2 ~ "2 periods",
    n_periods == 3 ~ "3 periods",
    TRUE           ~ "4+ periods"
  )) %>%
  group_by(bucket) %>%
  summarise(n_patients = n(), .groups = "drop") %>%
  mutate(pct = round(100 * n_patients / n_patients_total, 1))


# ==============================================================================
# SECTION 5: CONSOLE HEADLINE STATS (D-11) ----
# ==============================================================================

message("\n=== Phase 137: Address Timeline Diagnostics -- Headline Stats ===")
message(glue("  Patients in LDS_ADDRESS_HISTORY:      {n_patients_total}"))
message(glue("  % patients with gaps between periods: {pct_with_gaps}%"))
message(glue("  % patients with overlapping periods:  {pct_with_overlaps}%"))
message(glue("  % records with open ADDRESS_PERIOD_END: {pct_with_open}%"))
message("================================================================\n")


# ==============================================================================
# SECTION 6: BUILD DIAGNOSTICS TIBBLE FOR XLSX SHEET (D-09) ----
# ==============================================================================

diagnostics_tbl <- tibble::tribble(
  ~Metric,                                                     ~Value,
  "Patients in LDS_ADDRESS_HISTORY",                           as.character(n_patients_total),
  "% patients with gaps between periods",                      paste0(pct_with_gaps, "%"),
  "% patients with overlapping periods",                       paste0(pct_with_overlaps, "%"),
  "% records with open ADDRESS_PERIOD_END (treated as active)", paste0(pct_with_open, "%")
)

period_dist_tbl <- period_dist %>%
  select(
    `Period Count Bucket` = bucket,
    `N Patients`          = n_patients,
    Pct                   = pct
  )


# ==============================================================================
# SECTION 7: APPEND XLSX SHEET (D-10) ----
# ==============================================================================

# Color constants -- copied verbatim from R/106 lines 735-737.
# NOT sourced via source("R/106...") -- Pitfall 7: sourcing R/106 would re-run
# all its data-loading, overwrite addr with R/106's local variable, and write
# the original 5 sheets again. Copy the constants inline instead.
DARK_GRAY <- wb_color("FF374151")
WHITE     <- wb_color("FFFFFFFF")
DARK_TEXT <- wb_color("FF1F2937")

#' Add a styled sheet to the workbook (copied verbatim from R/106 lines 750-797)
#'
#' Writes a data table to a new sheet with a title row (row 1), subtitle row
#' (row 2), dark-gray header row (row 4), and frozen top rows. Data starts at
#' row 4 so rows 1-2 are informational text above the header.
#'
#' @param wb An openxlsx2 workbook object (modified in place via reference).
#' @param sheet_name Character. Name for the new worksheet.
#' @param title_text Character. Title string written to A1.
#' @param subtitle_text Character. Subtitle / grain description written to A2.
#' @param data_tbl Data frame. Table to write starting at A4.
add_styled_sheet <- function(wb, sheet_name, title_text, subtitle_text, data_tbl,
                              extra_tbl = NULL, extra_label = NULL) {
  wb$add_worksheet(sheet_name)
  n_cols           <- ncol(data_tbl)
  last_col_letter  <- openxlsx2::int2col(n_cols)

  wb$add_data(sheet = sheet_name, x = title_text,    dims = "A1")
  wb$add_data(sheet = sheet_name, x = subtitle_text, dims = "A2")
  wb$add_data(sheet = sheet_name, x = data_tbl,      dims = "A4", col_names = TRUE)

  wb$merge_cells(sheet = sheet_name, dims = paste0("A1:", last_col_letter, "1"))
  wb$merge_cells(sheet = sheet_name, dims = paste0("A2:", last_col_letter, "2"))

  wb$add_font(sheet = sheet_name, dims = "A1",
              name = "Calibri", size = 14, bold = TRUE, color = DARK_TEXT)
  wb$add_font(sheet = sheet_name, dims = "A2",
              name = "Calibri", size = 10, italic = TRUE, color = DARK_TEXT)

  header_range <- paste0("A4:", last_col_letter, "4")
  wb$add_fill(sheet = sheet_name, dims = header_range, color = DARK_GRAY)
  wb$add_font(sheet = sheet_name, dims = header_range,
              name = "Calibri", size = 11, bold = TRUE, color = WHITE)

  # Optional second table, written a few rows below the first.
  if (!is.null(extra_tbl) && nrow(extra_tbl) > 0) {
    gap_rows_offset <- 4 + nrow(data_tbl) + 2      # blank row + label row
    label_row       <- gap_rows_offset
    header_row      <- gap_rows_offset + 1

    if (!is.null(extra_label)) {
      wb$add_data(sheet = sheet_name, x = extra_label, dims = paste0("A", label_row))
      wb$add_font(sheet = sheet_name, dims = paste0("A", label_row),
                  name = "Calibri", size = 11, bold = TRUE, color = DARK_TEXT)
    }

    wb$add_data(sheet = sheet_name, x = extra_tbl,
                dims = paste0("A", header_row), col_names = TRUE)

    extra_last_col <- openxlsx2::int2col(ncol(extra_tbl))
    extra_hdr_rng  <- paste0("A", header_row, ":", extra_last_col, header_row)
    wb$add_fill(sheet = sheet_name, dims = extra_hdr_rng, color = DARK_GRAY)
    wb$add_font(sheet = sheet_name, dims = extra_hdr_rng,
                name = "Calibri", size = 11, bold = TRUE, color = WHITE)
  }

  wb$freeze_pane(sheet = sheet_name, firstActiveRow = 5)
  wb$set_col_widths(sheet = sheet_name, cols = 1:max(n_cols, ncol(extra_tbl %||% data_tbl)),
                    widths = "auto")
}

message("--- Appending 'Address Timeline Diagnostics' sheet to zip_change_frequency.xlsx ---")
wb <- openxlsx2::wb_load(OUTPUT_XLSX)   # wb_load, NOT the new-workbook constructor -- Pitfall 1

add_styled_sheet(
  wb,
  sheet_name    = "Address Timeline Diagnostics",
  title_text    = "Address Timeline Diagnostics -- Per-Patient Period Structure (Phase 137)",
  subtitle_text = glue("Grain: unique patient (ID). Source: {ADDR_FILENAME}. Run: {Sys.Date()}."),
  data_tbl      = diagnostics_tbl,
  extra_tbl     = period_dist_tbl,
  extra_label   = "Period count distribution per patient"
)

openxlsx2::wb_save(wb, OUTPUT_XLSX)
message(glue("[R/114] Sheet appended. xlsx: {OUTPUT_XLSX}"))
message("[R/114] Phase 137 ZIP9 temporal lookup validation complete.")
