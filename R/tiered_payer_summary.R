# ==============================================================================
# tiered_payer_summary.R -- Tiered Payer Summary (Styled XLSX)
# ==============================================================================
#
# Produces a color-coded xlsx workbook summarizing payer distribution using
# the tiered same-day resolution hierarchy:
#   Medicaid > Medicare > Private > Other govt > Other > Self-pay > Uninsured > Missing
#
# Reads pre-computed CSVs from R/36_tiered_same_day_payer.R instead of
# materializing the full ENCOUNTER table.
#
# Sheets:
#   1. Patient Summary   -- patients per resolved payer tier (both scopes)
#   2. Before vs After   -- encounter-level vs resolved patient-date distribution
#   3. Resolution Detail -- breakdown by resolution reason
#   4. Code Frequency    -- raw payer codes with AMC category and counts
#
# Output: output/tiered_payer_summary.xlsx
#
# Usage:
#   Rscript R/tiered_payer_summary.R
#
# ==============================================================================

source("R/00_config.R")
library(dplyr)
library(readr)
library(glue)
library(openxlsx2)

OUTPUT_PATH <- file.path(CONFIG$output_dir, "tiered_payer_summary.xlsx")

# ==============================================================================
# SECTION 1: TIER CONFIGURATION AND COLORS
# ==============================================================================

TIER_MAPPING <- list(
  Medicaid     = 1L,
  Medicare     = 2L,
  Private      = 3L,
  "Other govt" = 4L,
  Other        = 5L,
  "Self-pay"   = 6L,
  Uninsured    = 7L,
  Missing      = 8L
)

TIER_ORDER <- names(TIER_MAPPING)

# Color scheme per payer category (fill + font for xlsx pills)
PAYER_COLORS <- list(
  Medicaid     = list(fill = "FFD5F5E3", font = "FF1E8449"),   # green
  Medicare     = list(fill = "FFD6EAF8", font = "FF1A5276"),   # blue
  Private      = list(fill = "FFE8DAEF", font = "FF6C3483"),   # purple
  "Other govt" = list(fill = "FFD1F2EB", font = "FF0E6655"),   # teal
  Other        = list(fill = "FFFDEBD0", font = "FF935116"),   # orange
  "Self-pay"   = list(fill = "FFFEF9E7", font = "FF7D6608"),   # yellow
  Uninsured    = list(fill = "FFFADBD8", font = "FF943126"),   # red
  Missing      = list(fill = "FFF2F3F4", font = "FF6B7280")    # gray
)

# ==============================================================================
# SECTION 2: READ PRE-COMPUTED CSVs FROM 36_tiered_same_day_payer.R
# ==============================================================================

message("=== Tiered Payer Summary ===")
message("")
message("Reading pre-computed CSVs from R/36_tiered_same_day_payer.R...")

tables_dir <- file.path(CONFIG$output_dir, "tables")

# Resolved detail (for resolution reasons) -- CSV A from script 36
resolved_all   <- read_csv(file.path(tables_dir, "payer_resolved_detail_all.csv"), show_col_types = FALSE)
resolved_av_th <- read_csv(file.path(tables_dir, "payer_resolved_detail_av_th.csv"), show_col_types = FALSE)
message(glue("  Resolved detail (all):   {format(nrow(resolved_all), big.mark = ',')} patient-dates"))
message(glue("  Resolved detail (AV+TH): {format(nrow(resolved_av_th), big.mark = ',')} patient-dates"))

# Patient-level modal summaries -- CSV B from script 36
modal_all   <- read_csv(file.path(tables_dir, "payer_resolved_patient_summary_all.csv"), show_col_types = FALSE)
modal_av_th <- read_csv(file.path(tables_dir, "payer_resolved_patient_summary_av_th.csv"), show_col_types = FALSE)
message(glue("  Patient summary (all):   {format(nrow(modal_all), big.mark = ',')} patients"))
message(glue("  Patient summary (AV+TH): {format(nrow(modal_av_th), big.mark = ',')} patients"))

# Before vs after impact -- CSV C from script 36
impact_all_csv   <- read_csv(file.path(tables_dir, "payer_resolved_impact_all.csv"), show_col_types = FALSE)
impact_av_th_csv <- read_csv(file.path(tables_dir, "payer_resolved_impact_av_th.csv"), show_col_types = FALSE)

# Code frequency
code_freq_all_csv   <- read_csv(file.path(tables_dir, "payer_primary_code_freq_all.csv"), show_col_types = FALSE)
code_freq_av_th_csv <- read_csv(file.path(tables_dir, "payer_primary_code_freq_av_th_v2.csv"), show_col_types = FALSE)

# ==============================================================================
# SECTION 3: BUILD SUMMARY DATA FRAMES
# ==============================================================================

message("")
message("Building summary tables from CSVs...")

# --- Patient-level modal payer ---
build_patient_summary <- function(modal_df, scope_label) {
  total <- nrow(modal_df)
  modal_df %>%
    count(modal_resolved_payer, name = "patients") %>%
    mutate(
      rank = unlist(TIER_MAPPING[modal_resolved_payer]),
      pct  = patients / total,
      scope = scope_label
    ) %>%
    arrange(rank) %>%
    select(scope, tier = modal_resolved_payer, rank, patients, pct)
}

patient_summary <- bind_rows(
  build_patient_summary(modal_all, "All Encounters"),
  build_patient_summary(modal_av_th, "AV+TH Only")
)

# --- Before vs After impact ---
build_impact <- function(impact_csv, modal_df, scope_label) {
  patient_counts <- modal_df %>%
    count(modal_resolved_payer, name = "patients") %>%
    mutate(pt_pct = patients / sum(patients))

  tibble(category = TIER_ORDER) %>%
    left_join(impact_csv, by = "category") %>%
    left_join(patient_counts, by = c("category" = "modal_resolved_payer")) %>%
    mutate(
      encounters    = coalesce(as.integer(n_encounters_before), 0L),
      enc_pct       = coalesce(pct_encounters_before / 100, 0),
      patient_dates = coalesce(as.integer(n_patient_dates_after), 0L),
      pd_pct        = coalesce(pct_patient_dates_after / 100, 0),
      patients      = coalesce(patients, 0L),
      pt_pct        = coalesce(pt_pct, 0),
      scope         = scope_label
    ) %>%
    select(scope, category, encounters, enc_pct, patient_dates, pd_pct, patients, pt_pct)
}

impact <- bind_rows(
  build_impact(impact_all_csv, modal_all, "All Encounters"),
  build_impact(impact_av_th_csv, modal_av_th, "AV+TH Only")
)

# --- Resolution reason breakdown ---
build_resolution_reasons <- function(resolved, scope_label) {
  total <- nrow(resolved)
  resolved %>%
    count(resolution_reason, name = "patient_dates") %>%
    mutate(pct = patient_dates / total, scope = scope_label) %>%
    arrange(desc(patient_dates)) %>%
    select(scope, resolution_reason, patient_dates, pct)
}

reasons <- bind_rows(
  build_resolution_reasons(resolved_all, "All Encounters"),
  build_resolution_reasons(resolved_av_th, "AV+TH Only")
)

# --- Code frequency (CSV pct is 0-100, convert to fraction for xlsx "0.0%" format) ---
code_freq <- bind_rows(
  code_freq_all_csv %>% mutate(scope = "All Encounters", pct = pct / 100),
  code_freq_av_th_csv %>% mutate(scope = "AV+TH Only", pct = pct / 100)
) %>%
  select(scope, code, amc_category, n, pct)

# ==============================================================================
# SECTION 4: XLSX OUTPUT
# ==============================================================================

message("")
message("Writing xlsx workbook...")
wb <- wb_workbook()

# --- Helper: apply payer color to a column based on category values ---
apply_payer_colors <- function(wb, sheet, col_letter, categories, start_row) {
  for (i in seq_along(categories)) {
    cat <- categories[i]
    colors <- PAYER_COLORS[[cat]]
    if (!is.null(colors)) {
      row <- start_row + i - 1
      dims <- glue("{col_letter}{row}")
      wb$add_fill(sheet = sheet, dims = dims, color = wb_color(colors$fill))
      wb$add_font(sheet = sheet, dims = dims,
                  name = "Calibri", size = 10, bold = TRUE, color = wb_color(colors$font))
    }
  }
}

# --- Sheet 1: Patient Summary ---
sheet1 <- "Patient Summary"
wb$add_worksheet(sheet1)

wb$add_data(sheet = sheet1, x = "Tiered Payer Summary -- Patients by Resolved Payer",
            start_row = 1, start_col = 1)
wb$add_font(sheet = sheet1, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = sheet1, dims = "A1:E1")

wb$add_data(sheet = sheet1,
            x = "Modal resolved payer per patient after same-day tier hierarchy resolution.",
            start_row = 2, start_col = 1)
wb$add_font(sheet = sheet1, dims = "A2",
            name = "Calibri", size = 10, color = wb_color("FF6B7280"))
wb$merge_cells(sheet = sheet1, dims = "A2:E2")

# Write each scope as a block
current_row <- 4
for (scope_name in c("All Encounters", "AV+TH Only")) {
  scope_data <- filter(patient_summary, scope == scope_name)

  # Scope header
  wb$add_data(sheet = sheet1, x = scope_name,
              start_row = current_row, start_col = 1)
  wb$add_font(sheet = sheet1, dims = glue("A{current_row}"),
              name = "Calibri", size = 12, bold = TRUE, color = wb_color("FF1F2937"))
  current_row <- current_row + 1

  # Column headers
  headers <- c("Tier", "Rank", "Patients", "% of Total")
  for (i in seq_along(headers)) {
    wb$add_data(sheet = sheet1, x = headers[i],
                start_row = current_row, start_col = i)
  }
  wb$add_fill(sheet = sheet1, dims = glue("A{current_row}:D{current_row}"),
              color = wb_color("FF374151"))
  wb$add_font(sheet = sheet1, dims = glue("A{current_row}:D{current_row}"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
  current_row <- current_row + 1

  # Data rows
  data_start <- current_row
  if (nrow(scope_data) > 0) {
    write_df <- data.frame(
      Tier     = scope_data$tier,
      Rank     = scope_data$rank,
      Patients = scope_data$patients,
      Pct      = scope_data$pct,
      stringsAsFactors = FALSE
    )
    wb$add_data(sheet = sheet1, x = write_df,
                start_row = data_start, col_names = FALSE)

    last_row <- data_start + nrow(scope_data) - 1

    # Color the Tier column
    apply_payer_colors(wb, sheet1, "A", scope_data$tier, data_start)

    # Number formatting
    wb$add_numfmt(sheet = sheet1, dims = glue("C{data_start}:C{last_row}"), numfmt = "#,##0")
    wb$add_numfmt(sheet = sheet1, dims = glue("D{data_start}:D{last_row}"), numfmt = "0.0%")

    current_row <- last_row + 1
  }

  # Total row
  total_patients <- sum(scope_data$patients)
  wb$add_data(sheet = sheet1, x = "Total", start_row = current_row, start_col = 1)
  wb$add_data(sheet = sheet1, x = total_patients, start_row = current_row, start_col = 3)
  wb$add_data(sheet = sheet1, x = 1.0, start_row = current_row, start_col = 4)
  wb$add_fill(sheet = sheet1, dims = glue("A{current_row}:D{current_row}"),
              color = wb_color("FF374151"))
  wb$add_font(sheet = sheet1, dims = glue("A{current_row}:D{current_row}"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
  wb$add_numfmt(sheet = sheet1, dims = glue("C{current_row}"), numfmt = "#,##0")
  wb$add_numfmt(sheet = sheet1, dims = glue("D{current_row}"), numfmt = "0.0%")

  current_row <- current_row + 2  # gap between scopes
}

wb$set_col_widths(sheet = sheet1, cols = 1:4, widths = c(16, 8, 12, 12))
wb$freeze_pane(sheet = sheet1, first_active_row = 6)

# --- Sheet 2: Before vs After ---
sheet2 <- "Before vs After"
wb$add_worksheet(sheet2)

wb$add_data(sheet = sheet2, x = "Payer Distribution: Before vs After Tiered Resolution",
            start_row = 1, start_col = 1)
wb$add_font(sheet = sheet2, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = sheet2, dims = "A1:H1")

wb$add_data(sheet = sheet2,
            x = "Compares raw encounter-level tier counts vs resolved patient-date counts vs patient-level modal payer.",
            start_row = 2, start_col = 1)
wb$add_font(sheet = sheet2, dims = "A2",
            name = "Calibri", size = 10, color = wb_color("FF6B7280"))
wb$merge_cells(sheet = sheet2, dims = "A2:H2")

current_row <- 4
for (scope_name in c("All Encounters", "AV+TH Only")) {
  scope_data <- filter(impact, scope == scope_name)

  wb$add_data(sheet = sheet2, x = scope_name,
              start_row = current_row, start_col = 1)
  wb$add_font(sheet = sheet2, dims = glue("A{current_row}"),
              name = "Calibri", size = 12, bold = TRUE, color = wb_color("FF1F2937"))
  current_row <- current_row + 1

  headers <- c("Category", "Encounters", "Enc %", "Patient-Dates", "PD %", "Patients", "Pt %")
  for (i in seq_along(headers)) {
    wb$add_data(sheet = sheet2, x = headers[i],
                start_row = current_row, start_col = i)
  }
  wb$add_fill(sheet = sheet2, dims = glue("A{current_row}:G{current_row}"),
              color = wb_color("FF374151"))
  wb$add_font(sheet = sheet2, dims = glue("A{current_row}:G{current_row}"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
  current_row <- current_row + 1

  data_start <- current_row
  if (nrow(scope_data) > 0) {
    write_df <- data.frame(
      Category     = scope_data$category,
      Encounters   = scope_data$encounters,
      Enc_Pct      = scope_data$enc_pct,
      Patient_Dates = scope_data$patient_dates,
      PD_Pct       = scope_data$pd_pct,
      Patients     = scope_data$patients,
      Pt_Pct       = scope_data$pt_pct,
      stringsAsFactors = FALSE
    )
    wb$add_data(sheet = sheet2, x = write_df,
                start_row = data_start, col_names = FALSE)

    last_row <- data_start + nrow(scope_data) - 1
    apply_payer_colors(wb, sheet2, "A", scope_data$category, data_start)
    wb$add_numfmt(sheet = sheet2, dims = glue("B{data_start}:B{last_row}"), numfmt = "#,##0")
    wb$add_numfmt(sheet = sheet2, dims = glue("C{data_start}:C{last_row}"), numfmt = "0.0%")
    wb$add_numfmt(sheet = sheet2, dims = glue("D{data_start}:D{last_row}"), numfmt = "#,##0")
    wb$add_numfmt(sheet = sheet2, dims = glue("E{data_start}:E{last_row}"), numfmt = "0.0%")
    wb$add_numfmt(sheet = sheet2, dims = glue("F{data_start}:F{last_row}"), numfmt = "#,##0")
    wb$add_numfmt(sheet = sheet2, dims = glue("G{data_start}:G{last_row}"), numfmt = "0.0%")

    current_row <- last_row + 1
  }

  # Total row
  wb$add_data(sheet = sheet2, x = "Total", start_row = current_row, start_col = 1)
  wb$add_data(sheet = sheet2, x = sum(scope_data$encounters), start_row = current_row, start_col = 2)
  wb$add_data(sheet = sheet2, x = 1.0, start_row = current_row, start_col = 3)
  wb$add_data(sheet = sheet2, x = sum(scope_data$patient_dates), start_row = current_row, start_col = 4)
  wb$add_data(sheet = sheet2, x = 1.0, start_row = current_row, start_col = 5)
  wb$add_data(sheet = sheet2, x = sum(scope_data$patients), start_row = current_row, start_col = 6)
  wb$add_data(sheet = sheet2, x = 1.0, start_row = current_row, start_col = 7)
  wb$add_fill(sheet = sheet2, dims = glue("A{current_row}:G{current_row}"),
              color = wb_color("FF374151"))
  wb$add_font(sheet = sheet2, dims = glue("A{current_row}:G{current_row}"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
  wb$add_numfmt(sheet = sheet2, dims = glue("B{current_row}"), numfmt = "#,##0")
  wb$add_numfmt(sheet = sheet2, dims = glue("C{current_row}"), numfmt = "0.0%")
  wb$add_numfmt(sheet = sheet2, dims = glue("D{current_row}"), numfmt = "#,##0")
  wb$add_numfmt(sheet = sheet2, dims = glue("E{current_row}"), numfmt = "0.0%")
  wb$add_numfmt(sheet = sheet2, dims = glue("F{current_row}"), numfmt = "#,##0")
  wb$add_numfmt(sheet = sheet2, dims = glue("G{current_row}"), numfmt = "0.0%")

  current_row <- current_row + 2
}

wb$set_col_widths(sheet = sheet2, cols = 1:7, widths = c(16, 14, 10, 14, 10, 12, 10))
wb$freeze_pane(sheet = sheet2, first_active_row = 6)

# --- Sheet 3: Resolution Detail ---
sheet3 <- "Resolution Detail"
wb$add_worksheet(sheet3)

wb$add_data(sheet = sheet3, x = "Same-Day Resolution Reasons",
            start_row = 1, start_col = 1)
wb$add_font(sheet = sheet3, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = sheet3, dims = "A1:D1")

wb$add_data(sheet = sheet3,
            x = "How same-day payer conflicts were resolved across patient-dates.",
            start_row = 2, start_col = 1)
wb$add_font(sheet = sheet3, dims = "A2",
            name = "Calibri", size = 10, color = wb_color("FF6B7280"))
wb$merge_cells(sheet = sheet3, dims = "A2:D2")

current_row <- 4
for (scope_name in c("All Encounters", "AV+TH Only")) {
  scope_data <- filter(reasons, scope == scope_name)

  wb$add_data(sheet = sheet3, x = scope_name,
              start_row = current_row, start_col = 1)
  wb$add_font(sheet = sheet3, dims = glue("A{current_row}"),
              name = "Calibri", size = 12, bold = TRUE, color = wb_color("FF1F2937"))
  current_row <- current_row + 1

  headers <- c("Resolution Reason", "Patient-Dates", "% of Total")
  for (i in seq_along(headers)) {
    wb$add_data(sheet = sheet3, x = headers[i],
                start_row = current_row, start_col = i)
  }
  wb$add_fill(sheet = sheet3, dims = glue("A{current_row}:C{current_row}"),
              color = wb_color("FF374151"))
  wb$add_font(sheet = sheet3, dims = glue("A{current_row}:C{current_row}"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
  current_row <- current_row + 1

  if (nrow(scope_data) > 0) {
    write_df <- data.frame(
      Reason       = scope_data$resolution_reason,
      Patient_Dates = scope_data$patient_dates,
      Pct          = scope_data$pct,
      stringsAsFactors = FALSE
    )
    wb$add_data(sheet = sheet3, x = write_df,
                start_row = current_row, col_names = FALSE)

    last_row <- current_row + nrow(scope_data) - 1
    wb$add_numfmt(sheet = sheet3, dims = glue("B{current_row}:B{last_row}"), numfmt = "#,##0")
    wb$add_numfmt(sheet = sheet3, dims = glue("C{current_row}:C{last_row}"), numfmt = "0.0%")
    current_row <- last_row + 1
  }

  current_row <- current_row + 1
}

wb$set_col_widths(sheet = sheet3, cols = 1:3, widths = c(36, 14, 12))
wb$freeze_pane(sheet = sheet3, first_active_row = 6)

# --- Sheet 4: Code Frequency ---
sheet4 <- "Code Frequency"
wb$add_worksheet(sheet4)

wb$add_data(sheet = sheet4, x = "Raw Payer Code Frequency (Primary Field)",
            start_row = 1, start_col = 1)
wb$add_font(sheet = sheet4, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = sheet4, dims = "A1:E1")

wb$add_data(sheet = sheet4,
            x = "Every distinct PAYER_TYPE_PRIMARY value with AMC category mapping and encounter count.",
            start_row = 2, start_col = 1)
wb$add_font(sheet = sheet4, dims = "A2",
            name = "Calibri", size = 10, color = wb_color("FF6B7280"))
wb$merge_cells(sheet = sheet4, dims = "A2:E2")

current_row <- 4
for (scope_name in c("All Encounters", "AV+TH Only")) {
  scope_data <- filter(code_freq, scope == scope_name)

  wb$add_data(sheet = sheet4, x = scope_name,
              start_row = current_row, start_col = 1)
  wb$add_font(sheet = sheet4, dims = glue("A{current_row}"),
              name = "Calibri", size = 12, bold = TRUE, color = wb_color("FF1F2937"))
  current_row <- current_row + 1

  headers <- c("Code", "AMC Category", "Encounters", "% of Total")
  for (i in seq_along(headers)) {
    wb$add_data(sheet = sheet4, x = headers[i],
                start_row = current_row, start_col = i)
  }
  wb$add_fill(sheet = sheet4, dims = glue("A{current_row}:D{current_row}"),
              color = wb_color("FF374151"))
  wb$add_font(sheet = sheet4, dims = glue("A{current_row}:D{current_row}"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
  current_row <- current_row + 1

  data_start <- current_row
  if (nrow(scope_data) > 0) {
    write_df <- data.frame(
      Code         = scope_data$code,
      AMC_Category = scope_data$amc_category,
      Encounters   = scope_data$n,
      Pct          = scope_data$pct,
      stringsAsFactors = FALSE
    )
    wb$add_data(sheet = sheet4, x = write_df,
                start_row = data_start, col_names = FALSE)

    last_row <- data_start + nrow(scope_data) - 1

    # Color the AMC Category column per-row
    for (i in seq_len(nrow(scope_data))) {
      cat <- scope_data$amc_category[i]
      colors <- PAYER_COLORS[[cat]]
      if (!is.null(colors)) {
        row <- data_start + i - 1
        wb$add_fill(sheet = sheet4, dims = glue("B{row}"), color = wb_color(colors$fill))
        wb$add_font(sheet = sheet4, dims = glue("B{row}"),
                    name = "Calibri", size = 10, bold = TRUE, color = wb_color(colors$font))
      }
    }

    wb$add_numfmt(sheet = sheet4, dims = glue("C{data_start}:C{last_row}"), numfmt = "#,##0")
    wb$add_numfmt(sheet = sheet4, dims = glue("D{data_start}:D{last_row}"), numfmt = "0.0%")
    current_row <- last_row + 1
  }

  current_row <- current_row + 1
}

wb$set_col_widths(sheet = sheet4, cols = 1:4, widths = c(12, 16, 14, 12))
wb$freeze_pane(sheet = sheet4, first_active_row = 6)

# ==============================================================================
# SECTION 5: SAVE AND SUMMARY
# ==============================================================================

dir.create(CONFIG$output_dir, showWarnings = FALSE, recursive = TRUE)
wb$save(OUTPUT_PATH)

message("")
message("--- Patient Summary (All Encounters) ---")
all_summary <- filter(patient_summary, scope == "All Encounters")
for (r in seq_len(nrow(all_summary))) {
  row <- all_summary[r, ]
  message(glue("  {row$tier}: {format(row$patients, big.mark = ',')} patients ({round(row$pct * 100, 1)}%)"))
}

message("")
message(glue("Output: {OUTPUT_PATH}"))
message("=== Tiered Payer Summary Complete ===")
