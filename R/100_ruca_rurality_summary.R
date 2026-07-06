# ==============================================================================
# 100_ruca_rurality_summary.R -- RUCA Rurality Summary (Phase 116)
# ==============================================================================
# Purpose:     Enrich the HL cohort with USDA 2020 ZIP-code RUCA rurality
#              classification (derived from DEMOGRAPHIC.ZIP_CODE) and produce
#              a 4-sheet styled xlsx summarizing:
#                Sheet 1 (patient-level):    Rurality frequency (unique PATIDs)
#                Sheet 2 (encounter-level):  Rurality x AMC 8-category payer
#                Sheet 3 (encounter-level):  Rurality x Treatment type (5 cats)
#                Sheet 4 (episode-level):    Rurality x Cancer category
#
# Rurality taxonomy (from USDA ERS 2020 ZIP RUCA):
#   Primary codes 1-3 -> "Metropolitan"
#   Primary codes 4-6 -> "Micropolitan"
#   Primary codes 7-9 -> "Small town"
#   Primary code   10 -> "Rural"
#   Code 99 or unmatched ZIP -> NA (rendered as "Unknown" in cross-tabs)
#
# File structure notes (confirmed during Phase 116 Task 1 inspection):
#   Sheet name: "RUCA 2020 ZIP Code Data"
#   skip = 1  (row 1 is a title row; row 2 is the actual column header row)
#   Column 1:  ZIPCode  (character, 5-digit with leading zeros)
#   Column 5:  PrimaryRUCA (numeric, integer 1-10, 99)
#   The RUCA_code column is PrimaryRUCA (already an integer primary code;
#   no floor() needed but we apply it defensively for any decimal values)
#
# Inputs:      data/reference/RUCA-codes-2020-zipcode.xlsx (bundled reference)
#              DEMOGRAPHIC table (via get_pcornet_table)   -- PATID + ZIP_CODE
#              ENCOUNTER table   (via get_pcornet_table)   -- for Sheet 2 payer
#              cache/outputs/treatment_episode_detail.rds  -- for Sheet 3 treatment
#              cache/outputs/treatment_episodes.rds        -- for Sheet 4 cancer category
#
# Outputs:     output/ruca_rurality_summary.xlsx (4 styled sheets + metadata sheet)
#
# Dependencies: R/00_config.R, R/utils/utils_payer.R, R/utils/utils_treatment.R,
#               R/utils/utils_assertions.R
#
# Requirements: Phase 116 -- RUCA-01, RUCA-02, RUCA-03, RUCA-04, RUCA-05
#
# Usage:       Rscript R/100_ruca_rurality_summary.R
#              source("R/100_ruca_rurality_summary.R")
#
# Note:        Upstream scripts R/26 and R/28 must be run first to produce
#              treatment_episode_detail.rds and treatment_episodes.rds.
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND LIBRARIES ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(tidyr)
  library(readxl)
  library(openxlsx2)
  library(tibble)
})

source("R/00_config.R")
source("R/utils/utils_assertions.R")
source("R/utils/utils_treatment.R")  # get_hl_patient_ids, safe_table
source("R/utils/utils_payer.R")      # classify_payer_tier

message("=== Phase 116: RUCA Rurality Summary ===\n")


# ==============================================================================
# SECTION 2: CONSTANTS AND INPUT VALIDATION ----
# ==============================================================================

REFERENCE_XLSX <- file.path("data", "reference", "RUCA-codes-2020-zipcode.xlsx")
DETAIL_RDS     <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")
EPISODES_RDS   <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
OUTPUT_XLSX    <- file.path(CONFIG$output_dir, "ruca_rurality_summary.xlsx")

if (!file.exists(REFERENCE_XLSX)) {
  stop(glue("[R/100] RUCA reference file not found: {REFERENCE_XLSX}\n",
            "  Run Phase 116 Plan 01 Task 1 to download and bundle this file."))
}
assert_rds_exists(DETAIL_RDS,   script_name = "R/100")
assert_rds_exists(EPISODES_RDS, script_name = "R/100")
message("  All input files validated.\n")


# ==============================================================================
# SECTION 3: LOAD RUCA_LOOKUP ----
# ==============================================================================

message("--- Loading RUCA reference ---")

# Sheet: "RUCA 2020 ZIP Code Data" (confirmed during Task 1 inspection)
# skip = 1: row 1 is a long title string, row 2 is the actual header
# Column positions: 1 = ZIPCode, 5 = PrimaryRUCA (use by-name after skip for clarity)
ruca_raw <- readxl::read_excel(
  REFERENCE_XLSX,
  sheet = "RUCA 2020 ZIP Code Data",
  skip  = 1
)
message(glue("  RUCA reference columns detected: {paste(names(ruca_raw), collapse=', ')}"))

RUCA_LOOKUP <- ruca_raw %>%
  select(ZIP_CODE = ZIPCode, RUCA_code = PrimaryRUCA) %>%
  mutate(
    ZIP_CODE  = str_pad(as.character(ZIP_CODE), 5, pad = "0"),
    RUCA_code = suppressWarnings(as.numeric(RUCA_code))
  ) %>%
  filter(!is.na(ZIP_CODE), !is.na(RUCA_code))

stopifnot(nrow(RUCA_LOOKUP) > 30000)   # 2020 file has ~40k ZIP entries; sanity check
message(glue("  RUCA_LOOKUP: {format(nrow(RUCA_LOOKUP), big.mark=',')} ZIP codes loaded\n"))


# ==============================================================================
# SECTION 4: HELPER FUNCTIONS (ruca_tier_label, build_crosstab) ----
# ==============================================================================

#' Map decimal or integer RUCA code to 4-tier condensed rurality label
#'
#' Primary code = floor(decimal code). Primary codes map as:
#'   1-3 = Metropolitan, 4-6 = Micropolitan, 7-9 = Small town, 10 = Rural
#'   Code 99 (not coded: water-only / zero-population ZIPs) -> NA
#'
#' @param ruca_code Numeric. Raw RUCA code (e.g., 1.0, 4.1, 10.6, 99).
#' @return Character. One of: "Metropolitan", "Micropolitan", "Small town",
#'   "Rural", or NA_character_.
ruca_tier_label <- function(ruca_code) {
  primary <- floor(ruca_code)
  dplyr::case_when(
    primary %in% 1:3  ~ "Metropolitan",
    primary %in% 4:6  ~ "Micropolitan",
    primary %in% 7:9  ~ "Small town",
    primary == 10     ~ "Rural",
    TRUE              ~ NA_character_    # 99 (not coded), NA, unexpected -> Unknown
  )
}

#' Build a cross-tabulation with row totals and column totals
#'
#' Counts rows of df by (row_col, col_col), pivots wide, sorts both axes
#' ascending alphabetically, and appends row-total and column-total.
#'
#' @param df Data frame.
#' @param row_col Character. Name of the row grouping column.
#' @param col_col Character. Name of the column grouping variable (becomes columns).
#' @return Tibble with row_col as first column, one column per distinct col_col
#'   value (ascending alpha), a Total column, and a Total row.
build_crosstab <- function(df, row_col, col_col) {
  tidy <- df %>%
    count(.data[[row_col]], .data[[col_col]], name = "n")

  col_levels <- sort(unique(tidy[[col_col]]))
  row_levels <- sort(unique(tidy[[row_col]]))

  wide <- tidy %>%
    pivot_wider(
      names_from  = all_of(col_col),
      values_from = n,
      values_fill = 0L
    ) %>%
    select(all_of(row_col), all_of(col_levels))

  wide <- wide %>% arrange(match(.data[[row_col]], row_levels))

  # Row totals
  wide <- wide %>%
    rowwise() %>%
    mutate(Total = sum(c_across(where(is.numeric)), na.rm = TRUE)) %>%
    ungroup()

  # Column totals row (label 'Total' in the row_col column)
  totals_row <- wide %>%
    summarise(
      !!row_col := "Total",
      across(where(is.numeric), sum)
    )

  bind_rows(wide, totals_row)
}


# ==============================================================================
# SECTION 5: HL COHORT + PATIENT-LEVEL RURALITY ASSIGNMENT ----
# ==============================================================================

message("--- Building patient-level rurality assignment ---")

hl_ids <- get_hl_patient_ids()
message(glue("  HL cohort: {format(length(hl_ids), big.mark=',')} patients"))

demo_zip <- get_pcornet_table("DEMOGRAPHIC") %>%
  select(PATID = ID, ZIP_CODE) %>%
  collect() %>%
  filter(PATID %in% hl_ids) %>%
  mutate(
    ZIP_norm = str_trim(ZIP_CODE),
    ZIP_norm = str_sub(ZIP_norm, 1, 5),
    ZIP_norm = str_pad(ZIP_norm, 5, pad = "0"),
    ZIP_norm = if_else(str_detect(ZIP_norm, "^[0-9]{5}$"), ZIP_norm, NA_character_)
  )

rurality_patient_tbl <- demo_zip %>%
  left_join(RUCA_LOOKUP, by = c("ZIP_norm" = "ZIP_CODE")) %>%
  mutate(
    rurality_label = ruca_tier_label(RUCA_code)
  ) %>%
  select(PATID, ZIP_CODE, ZIP_norm, RUCA_code, rurality_label)

# LOG NA COUNT (RUCA-04): must appear in console before writing xlsx
n_total <- nrow(rurality_patient_tbl)
n_na    <- sum(is.na(rurality_patient_tbl$rurality_label))
message(glue("  Rurality assignment: {format(n_total, big.mark=',')} patients, ",
             "{format(n_na, big.mark=',')} with NA rurality ",
             "({round(100 * n_na / n_total, 1)}% unmatched or code 99)"))
message()


# ==============================================================================
# SECTION 6: SHEET 1 -- PATIENT-LEVEL FREQUENCY ----
# ==============================================================================

message("--- Building Sheet 1: Rurality Frequency (patient-level) ---")

sheet1 <- rurality_patient_tbl %>%
  mutate(rurality_label = if_else(is.na(rurality_label), "Unknown", rurality_label)) %>%
  distinct(PATID, rurality_label) %>%
  count(rurality_label, name = "n_patients") %>%
  mutate(
    pct_patients = round(100 * n_patients / sum(n_patients), 2)
  ) %>%
  arrange(rurality_label)   # ascending alphabetical (SORT-01)

# Append total row
sheet1 <- bind_rows(
  sheet1,
  tibble(
    rurality_label = "Total",
    n_patients     = sum(sheet1$n_patients),
    pct_patients   = 100.00
  )
)
message(glue("  Sheet 1 built: {nrow(sheet1)} rows"))


# ==============================================================================
# SECTION 7: SHEET 2 -- RURALITY x AMC 8-CATEGORY PAYER (encounter-level) ----
# ==============================================================================

message("--- Building Sheet 2: Rurality x Payer (encounter-level) ---")

enc_raw <- get_pcornet_table("ENCOUNTER") %>% collect()

# Filter to HL cohort, classify payer tier, join rurality by PATID (ID)
enc_hl <- enc_raw %>%
  filter(ID %in% hl_ids) %>%
  classify_payer_tier(include_dual = TRUE, flm_override = TRUE) %>%
  left_join(
    rurality_patient_tbl %>% select(PATID, rurality_label),
    by = c("ID" = "PATID")
  ) %>%
  mutate(
    rurality_label = if_else(is.na(rurality_label), "Unknown", rurality_label),
    payer_category = if_else(is.na(payer_category), "Unknown", payer_category)
  )

sheet2 <- build_crosstab(enc_hl, "rurality_label", "payer_category")
message(glue("  Sheet 2 built: {nrow(sheet2)} rows"))


# ==============================================================================
# SECTION 8: SHEET 3 -- RURALITY x TREATMENT TYPE (encounter-level) ----
# ==============================================================================

message("--- Building Sheet 3: Rurality x Treatment (encounter-level) ---")

detail <- readRDS(DETAIL_RDS)
message(glue("  treatment_episode_detail.rds: {format(nrow(detail), big.mark=',')} rows"))

# Deduplicate to (patient_id, ENCOUNTERID, treatment_type) grain for encounter-level count
detail_enc <- detail %>%
  filter(patient_id %in% hl_ids) %>%
  distinct(patient_id, ENCOUNTERID, treatment_type) %>%
  left_join(
    rurality_patient_tbl %>% select(PATID, rurality_label),
    by = c("patient_id" = "PATID")
  ) %>%
  mutate(
    rurality_label = if_else(is.na(rurality_label), "Unknown", rurality_label),
    treatment_type = if_else(is.na(treatment_type), "Unknown", treatment_type)
  )

sheet3 <- build_crosstab(detail_enc, "rurality_label", "treatment_type")
message(glue("  Sheet 3 built: {nrow(sheet3)} rows"))


# ==============================================================================
# SECTION 9: SHEET 4 -- RURALITY x CANCER CATEGORY (episode-level) ----
# ==============================================================================

message("--- Building Sheet 4: Rurality x Cancer Category (episode-level) ---")

episodes <- readRDS(EPISODES_RDS)
message(glue("  treatment_episodes.rds: {format(nrow(episodes), big.mark=',')} rows"))

ep_hl <- episodes %>%
  filter(patient_id %in% hl_ids) %>%
  left_join(
    rurality_patient_tbl %>% select(PATID, rurality_label),
    by = c("patient_id" = "PATID")
  ) %>%
  mutate(
    rurality_label  = if_else(is.na(rurality_label),  "Unknown", rurality_label),
    cancer_category = if_else(is.na(cancer_category), "Unknown", cancer_category)
  )

sheet4 <- build_crosstab(ep_hl, "rurality_label", "cancer_category")
message(glue("  Sheet 4 built: {nrow(sheet4)} rows"))


# ==============================================================================
# SECTION 10: WRITE STYLED XLSX ----
# ==============================================================================

message("--- Writing styled xlsx ---")

DARK_GRAY <- wb_color("FF374151")
WHITE     <- wb_color("FFFFFFFF")
DARK_TEXT <- wb_color("FF1F2937")

#' Add a styled sheet to the workbook
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
add_styled_sheet <- function(wb, sheet_name, title_text, subtitle_text, data_tbl) {
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

  wb$freeze_pane(sheet = sheet_name, firstActiveRow = 5)
  wb$set_col_widths(sheet = sheet_name, cols = 1:n_cols, widths = "auto")
}

wb <- wb_workbook()

add_styled_sheet(
  wb, "Rurality Frequency",
  title_text    = "Rurality Frequency -- HL Cohort Patient-Level Counts",
  subtitle_text = "Grain: unique PATID. Rurality derived from USDA 2020 ZIP RUCA (Metropolitan / Micropolitan / Small town / Rural / Unknown).",
  data_tbl      = sheet1
)

add_styled_sheet(
  wb, "Rurality x Payer",
  title_text    = "Rurality x AMC 8-Category Payer -- Encounter-Level Counts",
  subtitle_text = "Grain: encounter. High-utilizer patients contribute more encounters. NOT comparable to Sheet 1 patient counts.",
  data_tbl      = sheet2
)

add_styled_sheet(
  wb, "Rurality x Treatment",
  title_text    = "Rurality x Treatment Type -- Encounter-Level Counts",
  subtitle_text = "Grain: unique (patient x encounter x treatment type) from treatment_episode_detail.rds. 5 treatment categories.",
  data_tbl      = sheet3
)

add_styled_sheet(
  wb, "Rurality x Cancer",
  title_text    = "Rurality x Cancer Category -- Episode-Level Counts",
  subtitle_text = "Grain: treatment episode from treatment_episodes.rds. cancer_category assigned by R/28 classify_codes() cascade.",
  data_tbl      = sheet4
)

# Optional metadata sheet (5th sheet) -- source version, run date, cohort size, NA count
metadata_tbl <- tibble(
  Field = c(
    "RUCA reference file",
    "RUCA reference row count",
    "Run date",
    "HL cohort size",
    "Patients with NA rurality",
    "NA rurality percent"
  ),
  Value = c(
    basename(REFERENCE_XLSX),
    format(nrow(RUCA_LOOKUP), big.mark = ","),
    as.character(Sys.Date()),
    format(length(hl_ids), big.mark = ","),
    format(n_na, big.mark = ","),
    paste0(round(100 * n_na / n_total, 1), "%")
  )
)

add_styled_sheet(
  wb, "Metadata",
  title_text    = "Run Metadata",
  subtitle_text = "Source data and coverage diagnostics for reproducibility.",
  data_tbl      = metadata_tbl
)

wb_save(wb, OUTPUT_XLSX)
message(glue("  Xlsx saved: {OUTPUT_XLSX}\n"))


# ==============================================================================
# SECTION 11: CONSOLE SUMMARY ----
# ==============================================================================

message("=== Phase 116: RUCA Rurality Summary Complete ===")
message(glue("  HL cohort:              {format(length(hl_ids), big.mark=',')} patients"))
message(glue("  Rurality unmatched:     {format(n_na, big.mark=',')} ({round(100*n_na/n_total,1)}%)"))
message(glue("  Sheet 1 (patient freq): {nrow(sheet1)} rows"))
message(glue("  Sheet 2 (payer):        {nrow(sheet2)} rows"))
message(glue("  Sheet 3 (treatment):    {nrow(sheet3)} rows"))
message(glue("  Sheet 4 (cancer):       {nrow(sheet4)} rows"))
message(glue("  Output:                 {OUTPUT_XLSX}"))
