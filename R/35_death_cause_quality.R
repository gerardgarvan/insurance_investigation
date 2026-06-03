# ==============================================================================
# 35_death_cause_quality.R -- Death Cause Data Quality Profiling
# ==============================================================================
#
# Purpose:
#   Profile death cause completeness and quality to establish a baseline for
#   integrating cause-of-death data into treatment timeline outputs. Produces
#   console diagnostics and multi-sheet Excel workbook stratifying completeness
#   by payer category and partner site.
#
# Inputs:
#   - DuckDB DEATH table (DEATH_DATE, DEATH_CAUSE, DEATH_SOURCE)
#   - cache/outputs/treatment_episodes.rds (for payer extraction)
#   - R/00_config.R (DEATH_CAUSE_MAP, CONFIG paths)
#
# Outputs:
#   - output/death_cause_quality.xlsx (5-sheet workbook)
#   - cache/outputs/death_cause_quality_result.rds (quality decision artifact)
#
# Dependencies:
#   - R/00_config.R (DEATH_CAUSE_MAP, CONFIG)
#   - R/utils/utils_duckdb.R (open_pcornet_con, get_pcornet_table)
#   - R/utils/utils_dates.R (parse_pcornet_date)
#   - openxlsx2 (multi-sheet workbook with styling)
#
# Requirements:
#   - DEATH-01: Death cause quality profiling with payer/site stratification
#   - QUAL-01: Quality gates before data integration
#
# Decision Traceability:
#   - D-01: Follow R/35 (Phase 34) analysis script pattern (section structure, styling)
#   - D-02: Stratify by AMC payer category (from treatment_episodes.rds) and partner site (ID prefix or DEATH_SOURCE)
#   - D-03: Multi-sheet XLSX output using openxlsx2 wb_workbook() pipe-friendly API
#   - D-04: SOFT WARNING approach for missingness threshold (40% warning, 60% skip recommendation, document in RDS artifact)
#   - D-78-01: Guard against missing DEATH_CAUSE field — set death_cause_available flag, handle gracefully
#
# ==============================================================================

# --- SECTION 1: SETUP ----

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(lubridate)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")

OUTPUT_XLSX <- file.path(CONFIG$output_dir, "death_cause_quality.xlsx")
OUTPUT_RDS <- file.path(CONFIG$cache$outputs_dir, "death_cause_quality_result.rds")

message("=== Phase 78: Death Cause Quality Profiling ===\n")
message(glue("Output files:"))
message(glue("  XLSX: {OUTPUT_XLSX}"))
message(glue("  RDS:  {OUTPUT_RDS}\n"))


# --- SECTION 2: LOAD DEATH DATA ----

message("--- Loading DEATH table from DuckDB ---")

USE_DUCKDB <- TRUE
open_pcornet_con()

death_raw <- get_pcornet_table("DEATH") %>% collect()

message(glue("  Raw DEATH table: {nrow(death_raw)} rows"))

# Check if DEATH_CAUSE column exists (D-78-01 field availability guard)
death_cause_available <- FALSE
death_cause_col <- NULL

if ("DEATH_CAUSE" %in% names(death_raw)) {
  death_cause_col <- "DEATH_CAUSE"
  death_cause_available <- TRUE
  message("  Found DEATH_CAUSE column")
} else if ("DEATH_CAUSE_CODE" %in% names(death_raw)) {
  death_cause_col <- "DEATH_CAUSE_CODE"
  death_cause_available <- TRUE
  message("  Found DEATH_CAUSE_CODE column (alternative name)")
} else {
  message("  WARNING: DEATH_CAUSE field not available in DEATH table")
}

# Parse dates and filter sentinels
death_data <- death_raw %>%
  mutate(DEATH_DATE = parse_pcornet_date(DEATH_DATE)) %>%
  mutate(DEATH_DATE = if_else(year(DEATH_DATE) == 1900L, as.Date(NA), DEATH_DATE)) %>%
  filter(!is.na(DEATH_DATE))

# Add DEATH_CAUSE column if available, otherwise set to NA
if (death_cause_available) {
  death_data <- death_data %>%
    select(ID, DEATH_DATE, DEATH_SOURCE, DEATH_CAUSE = all_of(death_cause_col))
} else {
  death_data <- death_data %>%
    mutate(DEATH_CAUSE = NA_character_) %>%
    select(ID, DEATH_DATE, DEATH_SOURCE, DEATH_CAUSE)
}

# Aggregate to patient level (one death date per patient)
death_data <- death_data %>%
  group_by(ID) %>%
  summarise(
    DEATH_DATE = min(DEATH_DATE),
    DEATH_SOURCE = first(DEATH_SOURCE),
    DEATH_CAUSE = first(DEATH_CAUSE),
    .groups = "drop"
  )

message(glue("  Patients with valid death dates: {nrow(death_data)}"))

close_pcornet_con()


# --- SECTION 3: OVERALL COMPLETENESS ----

message("\n--- Computing overall death cause completeness ---")

n_deaths <- nrow(death_data)
pct_complete <- 0.0
missingness_rate <- 100.0
n_with_cause <- 0

if (!death_cause_available) {
  message("  DEATH_CAUSE field not available -- 100% missingness")
} else {
  n_with_cause <- sum(!is.na(death_data$DEATH_CAUSE) & death_data$DEATH_CAUSE != "", na.rm = TRUE)
  pct_complete <- round(100 * n_with_cause / n_deaths, 1)
  missingness_rate <- 100 - pct_complete
  message(glue("  Overall: {n_with_cause}/{n_deaths} ({pct_complete}%) have cause of death coded"))
}

# Map DEATH_CAUSE to categories via DEATH_CAUSE_MAP
cause_category_dist <- NULL
if (death_cause_available && n_with_cause > 0) {
  death_data <- death_data %>%
    mutate(
      prefix_3char = str_sub(DEATH_CAUSE, 1, 3),
      cause_category = ifelse(!is.na(prefix_3char) & prefix_3char %in% names(DEATH_CAUSE_MAP),
                               DEATH_CAUSE_MAP[prefix_3char],
                               "Unknown or Unspecified")
    )

  cause_category_dist <- death_data %>%
    filter(!is.na(cause_category)) %>%
    count(cause_category, name = "n_deaths") %>%
    mutate(percent = round(100 * n_deaths / sum(n_deaths), 1)) %>%
    arrange(desc(n_deaths))

  message(glue("  Mapped {nrow(cause_category_dist)} distinct cause categories"))
}

# Overall summary table
overall_stats <- tibble(
  Metric = c("Total deaths", "Deaths with cause coded", "Completeness (%)", "Missingness (%)"),
  Value = c(n_deaths, n_with_cause, pct_complete, missingness_rate)
)


# --- SECTION 4: STRATIFICATION BY AMC PAYER ----

message("\n--- Stratifying by AMC payer category ---")

payer_stats <- NULL
EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")

if (file.exists(EPISODES_RDS)) {
  episodes <- readRDS(EPISODES_RDS)

  # Extract patient_id -> payer mapping (most common payer per patient)
  if ("payer_category" %in% names(episodes)) {
    patient_payer <- episodes %>%
      count(patient_id, payer_category) %>%
      group_by(patient_id) %>%
      slice_max(n, n = 1, with_ties = FALSE) %>%
      ungroup() %>%
      select(patient_id, payer_category)

    # Join to death data
    death_with_payer <- death_data %>%
      left_join(patient_payer, by = c("ID" = "patient_id"))

    payer_stats <- death_with_payer %>%
      filter(!is.na(payer_category)) %>%
      group_by(payer_category) %>%
      summarise(
        n_deaths = n(),
        n_with_cause = if (death_cause_available) sum(!is.na(DEATH_CAUSE) & DEATH_CAUSE != "", na.rm = TRUE) else 0,
        .groups = "drop"
      ) %>%
      mutate(pct_complete = round(100 * n_with_cause / n_deaths, 1)) %>%
      arrange(desc(n_deaths))

    message(glue("  By payer: {nrow(payer_stats)} categories"))
    for (i in 1:min(nrow(payer_stats), 5)) {
      row <- payer_stats[i, ]
      message(glue("    {row$payer_category}: {row$n_with_cause}/{row$n_deaths} ({row$pct_complete}%)"))
    }
  } else {
    message("  WARNING: payer_category column not found in treatment_episodes.rds")
    message("  Skipping payer stratification")
  }
} else {
  message("  WARNING: treatment_episodes.rds not found")
  message("  Skipping payer stratification")
}


# --- SECTION 5: STRATIFICATION BY PARTNER SITE ----

message("\n--- Stratifying by partner site ---")

# Extract 3-char site prefix from patient ID
death_data <- death_data %>%
  mutate(site = str_sub(ID, 1, 3))

by_site <- death_data %>%
  group_by(site) %>%
  summarise(
    n_deaths = n(),
    n_with_cause = if (death_cause_available) sum(!is.na(DEATH_CAUSE) & DEATH_CAUSE != "", na.rm = TRUE) else 0,
    .groups = "drop"
  ) %>%
  mutate(pct_complete = round(100 * n_with_cause / n_deaths, 1)) %>%
  arrange(desc(n_deaths))

message(glue("  By site: {nrow(by_site)} sites"))
for (i in 1:nrow(by_site)) {
  row <- by_site[i, ]
  message(glue("    {row$site}: {row$n_with_cause}/{row$n_deaths} ({row$pct_complete}%)"))
}


# --- SECTION 6: MISSINGNESS THRESHOLD CHECK ----

message("\n--- Missingness threshold evaluation (D-04 soft warning approach) ---")

recommendation <- if (missingness_rate <= 40) {
  "Proceed with cause of death integration -- completeness acceptable"
} else if (missingness_rate <= 60) {
  "Document limitations -- cause of death data has notable missingness"
} else {
  "SKIP cause of death integration -- missingness too high for reliable analysis"
}

if (missingness_rate > 60) {
  message(glue("  WARNING: Cause of death {missingness_rate}% missing -- recommend SKIPPING cause_of_death column in Gantt exports"))
} else if (missingness_rate > 40) {
  message(glue("  WARNING: Cause of death missing/unmapped for {missingness_rate}% -- recommend documenting limitations"))
} else {
  message(glue("  Cause of death completeness acceptable ({pct_complete}%)"))
}

message(glue("  Recommendation: {recommendation}"))

# Save quality decision artifact for Plan 02 consumption
quality_result <- list(
  missingness_rate = missingness_rate,
  death_cause_available = death_cause_available,
  recommendation = recommendation,
  n_deaths = n_deaths,
  n_with_cause = n_with_cause,
  pct_complete = pct_complete
)

saveRDS(quality_result, OUTPUT_RDS)
message(glue("  Saved quality decision artifact: {OUTPUT_RDS}"))


# --- SECTION 7: MULTI-SHEET XLSX OUTPUT ----

message("\n--- Creating multi-sheet Excel workbook ---")

wb <- wb_workbook()

# Helper function for consistent header styling (R/28 pattern)
style_sheet_header <- function(wb, sheet_name, title, subtitle) {
  # Title row (A1)
  wb$add_data(sheet = sheet_name, x = title, start_row = 1, start_col = 1)
  wb$add_font(
    sheet = sheet_name, dims = "A1",
    name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
  )
  wb$merge_cells(sheet = sheet_name, dims = "A1:C1")

  # Subtitle row (A2)
  wb$add_data(sheet = sheet_name, x = subtitle, start_row = 2, start_col = 1)
  wb$add_font(
    sheet = sheet_name, dims = "A2",
    name = "Calibri", size = 10, color = wb_color("FF6B7280")
  )
  wb$merge_cells(sheet = sheet_name, dims = "A2:C2")
}

# Sheet 1: Overall Completeness
wb$add_worksheet("Overall Completeness")
style_sheet_header(wb, "Overall Completeness",
                   "Death Cause Quality: Overall Completeness",
                   glue("Generated: {Sys.Date()} | Total deaths: {n_deaths}"))

wb$add_data(sheet = "Overall Completeness", x = overall_stats, start_row = 4, start_col = 1)
wb$add_font(sheet = "Overall Completeness", dims = "A4:B4", bold = TRUE, color = wb_color("FFFFFFFF"))
wb$add_fill(sheet = "Overall Completeness", dims = "A4:B4", color = wb_color("FF1F2937"))
wb$set_col_widths(sheet = "Overall Completeness", cols = 1:2, widths = c(25, 15))
wb$add_border(sheet = "Overall Completeness", dims = wb_dims(rows = 4:(4 + nrow(overall_stats)), cols = 1:2), top_color = wb_color("black"))

# Sheet 2: By Payer Category
wb$add_worksheet("By Payer Category")
if (!is.null(payer_stats) && nrow(payer_stats) > 0) {
  style_sheet_header(wb, "By Payer Category",
                     "Death Cause Quality: By Payer Category",
                     glue("Generated: {Sys.Date()} | {nrow(payer_stats)} payer categories"))

  wb$add_data(sheet = "By Payer Category", x = payer_stats, start_row = 4, start_col = 1)
  wb$add_font(sheet = "By Payer Category", dims = "A4:D4", bold = TRUE, color = wb_color("FFFFFFFF"))
  wb$add_fill(sheet = "By Payer Category", dims = "A4:D4", color = wb_color("FF1F2937"))
  wb$set_col_widths(sheet = "By Payer Category", cols = 1:4, widths = c(20, 12, 12, 12))
  wb$add_border(sheet = "By Payer Category", dims = wb_dims(rows = 4:(4 + nrow(payer_stats)), cols = 1:4), top_color = wb_color("black"))
} else {
  wb$add_data(sheet = "By Payer Category", x = "Payer data not available", start_row = 4, start_col = 1)
}

# Sheet 3: By Partner Site
wb$add_worksheet("By Partner Site")
style_sheet_header(wb, "By Partner Site",
                   "Death Cause Quality: By Partner Site",
                   glue("Generated: {Sys.Date()} | {nrow(by_site)} sites"))

wb$add_data(sheet = "By Partner Site", x = by_site, start_row = 4, start_col = 1)
wb$add_font(sheet = "By Partner Site", dims = "A4:D4", bold = TRUE, color = wb_color("FFFFFFFF"))
wb$add_fill(sheet = "By Partner Site", dims = "A4:D4", color = wb_color("FF1F2937"))
wb$set_col_widths(sheet = "By Partner Site", cols = 1:4, widths = c(15, 12, 12, 12))
wb$add_border(sheet = "By Partner Site", dims = wb_dims(rows = 4:(4 + nrow(by_site)), cols = 1:4), top_color = wb_color("black"))

# Sheet 4: Cause Category Distribution
wb$add_worksheet("Cause Category Distribution")
if (!is.null(cause_category_dist) && nrow(cause_category_dist) > 0) {
  style_sheet_header(wb, "Cause Category Distribution",
                     "Death Cause Quality: Cause Category Distribution",
                     glue("Generated: {Sys.Date()} | {nrow(cause_category_dist)} categories"))

  wb$add_data(sheet = "Cause Category Distribution", x = cause_category_dist, start_row = 4, start_col = 1)
  wb$add_font(sheet = "Cause Category Distribution", dims = "A4:C4", bold = TRUE, color = wb_color("FFFFFFFF"))
  wb$add_fill(sheet = "Cause Category Distribution", dims = "A4:C4", color = wb_color("FF1F2937"))
  wb$set_col_widths(sheet = "Cause Category Distribution", cols = 1:3, widths = c(30, 12, 12))
  wb$add_border(sheet = "Cause Category Distribution", dims = wb_dims(rows = 4:(4 + nrow(cause_category_dist)), cols = 1:3), top_color = wb_color("black"))
} else {
  wb$add_data(sheet = "Cause Category Distribution", x = "Cause category data not available (field missing or no coded causes)", start_row = 4, start_col = 1)
}

# Sheet 5: Recommendations
wb$add_worksheet("Recommendations")
style_sheet_header(wb, "Recommendations",
                   "Death Cause Quality: Recommendations",
                   glue("Generated: {Sys.Date()}"))

recommendations_text <- tibble(
  Section = c("Missingness Rate", "Field Availability", "Recommendation", "Action", "Date Generated"),
  Value = c(
    glue("{missingness_rate}%"),
    if (death_cause_available) "Available" else "NOT AVAILABLE",
    recommendation,
    if (missingness_rate <= 40) "Proceed with integration" else if (missingness_rate <= 60) "Proceed with documented limitations" else "Skip cause of death integration",
    as.character(Sys.Date())
  )
)

wb$add_data(sheet = "Recommendations", x = recommendations_text, start_row = 4, start_col = 1)
wb$add_font(sheet = "Recommendations", dims = "A4:B4", bold = TRUE, color = wb_color("FFFFFFFF"))
wb$add_fill(sheet = "Recommendations", dims = "A4:B4", color = wb_color("FF1F2937"))
wb$set_col_widths(sheet = "Recommendations", cols = 1:2, widths = c(25, 50))
wb$add_border(sheet = "Recommendations", dims = wb_dims(rows = 4:(4 + nrow(recommendations_text)), cols = 1:2), top_color = wb_color("black"))

# Save workbook
wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
message(glue("  Saved: {OUTPUT_XLSX}"))


# --- SECTION 8: SUMMARY ----

message("\n=== Death Cause Quality Profiling Complete ===")
message(glue("Total deaths: {n_deaths}"))
message(glue("Deaths with cause coded: {n_with_cause} ({pct_complete}%)"))
message(glue("Recommendation: {recommendation}"))
message("")
