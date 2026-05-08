# ==============================================================================
# tiered_payer_summary.R -- Tiered Payer Summary (Styled XLSX)
# ==============================================================================
#
# Produces a color-coded xlsx workbook summarizing payer distribution using
# the tiered same-day resolution hierarchy:
#   Medicaid > Medicare > Private > Other govt > Other > Self-pay > Uninsured > Missing
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
library(glue)
library(openxlsx2)

# Load tables
if (!USE_DUCKDB && !exists("pcornet")) source("R/01_load_pcornet.R")
if (USE_DUCKDB && !exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}

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

CODE_TO_TIER <- function(payer_category) {
  case_when(
    payer_category == "Medicaid"   ~ "Medicaid",
    payer_category == "Medicare"   ~ "Medicare",
    payer_category == "Private"    ~ "Private",
    payer_category == "Other govt" ~ "Other govt",
    payer_category == "Other"      ~ "Other",
    payer_category == "Self-pay"   ~ "Self-pay",
    payer_category == "Uninsured"  ~ "Uninsured",
    payer_category == "Missing"    ~ "Missing",
    is.na(payer_category)          ~ "Missing",
    TRUE                           ~ "Missing"
  )
}

# ==============================================================================
# SECTION 2: LOAD AND PREPARE ENCOUNTER DATA
# ==============================================================================

message("=== Tiered Payer Summary ===")
message("")
message("Loading ENCOUNTER table...")

enc_raw <- get_pcornet_table("ENCOUNTER") %>% materialize()
message(glue("  {format(nrow(enc_raw), big.mark = ',')} encounters loaded"))

enc <- enc_raw %>%
  mutate(
    PAYER_TYPE_PRIMARY   = as.character(PAYER_TYPE_PRIMARY),
    PAYER_TYPE_SECONDARY = as.character(PAYER_TYPE_SECONDARY),
    SOURCE               = as.character(SOURCE),
    admit_date_parsed    = as.Date(ADMIT_DATE, format = "%Y-%m-%d"),
    effective_payer = case_when(
      !is.na(PAYER_TYPE_PRIMARY) & nchar(trimws(PAYER_TYPE_PRIMARY)) > 0 &
        !PAYER_TYPE_PRIMARY %in% PAYER_MAPPING$sentinel_values ~ PAYER_TYPE_PRIMARY,
      !is.na(PAYER_TYPE_SECONDARY) & nchar(trimws(PAYER_TYPE_SECONDARY)) > 0 &
        !PAYER_TYPE_SECONDARY %in% PAYER_MAPPING$sentinel_values ~ PAYER_TYPE_SECONDARY,
      TRUE ~ NA_character_
    ),
    payer_category = {
      looked_up <- AMC_PAYER_LOOKUP[effective_payer]
      prefix_cat <- case_when(
        startsWith(effective_payer, "1") ~ "Medicare",
        startsWith(effective_payer, "2") ~ "Medicaid",
        startsWith(effective_payer, "5") | startsWith(effective_payer, "6") ~ "Private",
        startsWith(effective_payer, "3") | startsWith(effective_payer, "4") ~ "Other govt",
        startsWith(effective_payer, "7") ~ "Private",
        startsWith(effective_payer, "8") ~ "Uninsured",
        startsWith(effective_payer, "9") ~ "Other",
        TRUE ~ "Other"
      )
      result <- if_else(!is.na(looked_up), looked_up, prefix_cat)
      if_else(is.na(effective_payer), "Missing", result)
    },
    tier = CODE_TO_TIER(payer_category),
    tier = coalesce(
      case_when(
        PAYER_TYPE_PRIMARY %in% c("93", "14") ~ "Medicaid",
        PAYER_TYPE_SECONDARY %in% c("93", "14") ~ "Medicaid",
        TRUE ~ NA_character_
      ),
      tier
    ),
    tier = if_else(is.na(tier), "Missing", tier),
    tier_rank = unlist(TIER_MAPPING[tier]),
    tier_rank = if_else(is.na(tier_rank), 8L, tier_rank)
  )

enc_all   <- enc
enc_av_th <- enc %>% filter(ENC_TYPE %in% c("AV", "TH"))

message(glue("  All scope:   {format(nrow(enc_all), big.mark = ',')} encounters, {format(n_distinct(enc_all$ID), big.mark = ',')} patients"))
message(glue("  AV+TH scope: {format(nrow(enc_av_th), big.mark = ',')} encounters, {format(n_distinct(enc_av_th$ID), big.mark = ',')} patients"))

# ==============================================================================
# SECTION 3: SAME-DAY RESOLUTION
# ==============================================================================

resolve_scope <- function(enc_scope) {
  enc_scope %>%
    filter(!is.na(admit_date_parsed)) %>%
    group_by(ID, admit_date_parsed) %>%
    summarise(
      n_encounters     = n(),
      n_distinct_tiers = n_distinct(tier),
      has_flm          = any(SOURCE == "FLM", na.rm = TRUE),
      has_special_code = any(PAYER_TYPE_PRIMARY %in% c("93", "14") |
                             PAYER_TYPE_SECONDARY %in% c("93", "14"), na.rm = TRUE),
      original_tiers   = paste(sort(unique(tier)), collapse = "+"),
      resolved_payer   = case_when(
        any(SOURCE == "FLM", na.rm = TRUE) ~ "Medicaid",
        any(PAYER_TYPE_PRIMARY %in% c("93", "14") |
            PAYER_TYPE_SECONDARY %in% c("93", "14"), na.rm = TRUE) ~ "Medicaid",
        TRUE ~ tier[which.min(tier_rank)]
      ),
      resolution_reason = case_when(
        n() == 1 ~ "single encounter",
        any(SOURCE == "FLM", na.rm = TRUE) ~ "FLM source override",
        any(PAYER_TYPE_PRIMARY %in% c("93", "14") |
            PAYER_TYPE_SECONDARY %in% c("93", "14"), na.rm = TRUE) ~ "special code override (93/14)",
        n_distinct(tier) == 1 ~ "all encounters same tier",
        TRUE ~ paste0("tier hierarchy (", n_distinct(tier), " tiers)")
      ),
      .groups = "drop"
    )
}

message("")
message("Resolving same-day payer conflicts...")
resolved_all   <- resolve_scope(enc_all)
resolved_av_th <- resolve_scope(enc_av_th)
message(glue("  All scope:   {format(nrow(resolved_all), big.mark = ',')} patient-dates"))
message(glue("  AV+TH scope: {format(nrow(resolved_av_th), big.mark = ',')} patient-dates"))

# ==============================================================================
# SECTION 4: BUILD SUMMARY TABLES
# ==============================================================================

# --- Patient-level modal payer ---
patient_modal <- function(resolved) {
  resolved %>%
    count(ID, resolved_payer, name = "n_dates") %>%
    arrange(ID, desc(n_dates), resolved_payer) %>%
    group_by(ID) %>%
    slice(1) %>%
    ungroup() %>%
    rename(modal_payer = resolved_payer)
}

modal_all   <- patient_modal(resolved_all)
modal_av_th <- patient_modal(resolved_av_th)

# --- Patient summary by tier ---
build_patient_summary <- function(modal_df, scope_label) {
  total <- nrow(modal_df)
  modal_df %>%
    count(modal_payer, name = "patients") %>%
    mutate(
      rank = unlist(TIER_MAPPING[modal_payer]),
      pct  = patients / total,
      scope = scope_label
    ) %>%
    arrange(rank) %>%
    select(scope, tier = modal_payer, rank, patients, pct)
}

patient_summary <- bind_rows(
  build_patient_summary(modal_all, "All Encounters"),
  build_patient_summary(modal_av_th, "AV+TH Only")
)

# --- Before vs After impact ---
build_impact <- function(enc_scope, resolved, scope_label) {
  before <- enc_scope %>%
    filter(!is.na(admit_date_parsed)) %>%
    count(tier, name = "encounters") %>%
    mutate(enc_pct = encounters / sum(encounters))

  after <- resolved %>%
    count(resolved_payer, name = "patient_dates") %>%
    mutate(pd_pct = patient_dates / sum(patient_dates))

  # Patient-level modal
  modal <- patient_modal(resolved)
  patient_counts <- modal %>%
    count(modal_payer, name = "patients") %>%
    mutate(pt_pct = patients / sum(patients))

  # Full join across all 3
  tibble(category = TIER_ORDER) %>%
    left_join(before, by = c("category" = "tier")) %>%
    left_join(after, by = c("category" = "resolved_payer")) %>%
    left_join(patient_counts, by = c("category" = "modal_payer")) %>%
    mutate(
      across(c(encounters, patient_dates, patients), ~coalesce(.x, 0L)),
      across(c(enc_pct, pd_pct, pt_pct), ~coalesce(.x, 0)),
      scope = scope_label
    ) %>%
    select(scope, category, encounters, enc_pct, patient_dates, pd_pct, patients, pt_pct)
}

impact <- bind_rows(
  build_impact(enc_all, resolved_all, "All Encounters"),
  build_impact(enc_av_th, resolved_av_th, "AV+TH Only")
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

# --- Code frequency ---
build_code_freq <- function(enc_scope, scope_label) {
  total <- nrow(enc_scope)
  enc_scope %>%
    mutate(
      code = case_when(
        is.na(PAYER_TYPE_PRIMARY) ~ "<NA>",
        PAYER_TYPE_PRIMARY == "" ~ "<EMPTY>",
        TRUE ~ PAYER_TYPE_PRIMARY
      )
    ) %>%
    count(code, payer_category, name = "n") %>%
    mutate(pct = n / total, scope = scope_label) %>%
    arrange(desc(n)) %>%
    select(scope, code, amc_category = payer_category, n, pct)
}

code_freq <- bind_rows(
  build_code_freq(enc_all, "All Encounters"),
  build_code_freq(enc_av_th, "AV+TH Only")
)

# ==============================================================================
# SECTION 5: XLSX OUTPUT
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
# SECTION 6: SAVE AND SUMMARY
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
