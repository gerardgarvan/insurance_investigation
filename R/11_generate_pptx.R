# ==============================================================================
# 11_generate_pptx.R -- Generate insurance tables PowerPoint
# ==============================================================================
#
# Produces insurance_tables_YYYY-MM-DD.pptx matching the Python pipeline's
# 15-slide output, computed entirely from R pipeline data.
#
# Slides:
#   1. Title: Insurance Coverage by Treatment Type (cohort counts)
#   2. Insurance Coverage Overview (Primary + First Dx, all patients)
#   3. Post-Treatment Insurance (all patients)
#   4. Chemotherapy Insurance (Primary + First + Last Chemo)
#   5. Chemotherapy Post-Treatment Insurance
#   6. Radiation Insurance (Primary + First + Last Radiation)
#   7. Radiation Post-Treatment Insurance
#   8. SCT Insurance (Primary + First + Last SCT)
#   9. SCT Post-Treatment Insurance
#  10. Diagnosis - Insurance by Enrollment Coverage
#  11. Chemotherapy - Insurance by Enrollment Coverage
#  12. Radiation - Insurance by Enrollment Coverage
#  13. SCT - Insurance by Enrollment Coverage
#  14. Last Treatment = Last Encounter (±30 day window)
#  15. Unknown Post-Treatment Payer - Encounter Breakdown
#  16. Insurance After Last Treatment - Dataset Retention (still in dataset vs missing)
#
# Dependencies:
#   - 04_build_cohort.R must be sourced first (produces hl_cohort, pcornet,
#     encounters, payer_summary in the global environment)
#   - Packages: officer, flextable, dplyr, glue, lubridate, purrr, scales
#
# Usage:
#   source("R/04_build_cohort.R")  # Build cohort first
#   source("R/11_generate_pptx.R") # Generate PPTX
#
# ==============================================================================

library(officer)
library(flextable)
library(dplyr)
library(glue)
library(lubridate)
library(purrr)
library(scales)
library(stringr)

message("\n", strrep("=", 60))
message("Generating Insurance Tables PowerPoint")
message(strrep("=", 60))

# ==============================================================================
# SECTION 1: CONFIGURATION
# ==============================================================================

# Payer category display order (matches Python PPTX)
PAYER_ORDER <- c(
  "Medicare", "Medicaid", "Dual eligible", "Private",
  "Other government", "Self-pay", "Other", "Unavailable", "Unknown"
)

# Map R pipeline category names to PPTX display names
rename_payer <- function(x) {
  case_when(
    x == "No payment / Self-pay" ~ "Self-pay",
    is.na(x) ~ "Unknown",
    TRUE ~ x
  )
}

# HIPAA small-cell suppression: counts 1-10 replaced with "<11"
format_count_pct <- function(n, total) {
  pct <- round(100 * n / total, 1)
  count_str <- ifelse(n >= 1 & n <= 10, "<11", format(n, big.mark = ","))
  pct_str <- ifelse(n >= 1 & n <= 10, "*", paste0(pct, "%"))
  paste0(count_str, " (", pct_str, ")")
}

# Treatment window (days)
WINDOW_DAYS <- CONFIG$analysis$treatment_window_days  # 30

# ==============================================================================
# SECTION 2: COMPUTE ADDITIONAL DATA (last treatment, post-treatment, enrollment)
# ==============================================================================

message("\n--- Computing additional payer data for PPTX ---")

# ---- 2a. Last treatment dates (max across all sources, mirrors 10_treatment_payer.R) ----

compute_last_dates <- function(treatment_type) {
  # Reuses the same source-extraction logic as 10_treatment_payer.R
  # but takes max() instead of min()

  if (treatment_type == "chemo") {
    sources <- list()
    if (!is.null(pcornet$PROCEDURES)) {
      sources$px <- pcornet$PROCEDURES %>%
        filter(
          (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
          (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
          (PX_TYPE == "10" & PX %in% TREATMENT_CODES$chemo_icd10pcs_prefixes)
        ) %>% filter(!is.na(PX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(PX_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$PRESCRIBING)) {
      sources$rx <- pcornet$PRESCRIBING %>%
        filter(!is.na(RX_ORDER_DATE) | !is.na(RX_START_DATE)) %>%
        mutate(d = coalesce(RX_ORDER_DATE, RX_START_DATE)) %>%
        filter(!is.na(d)) %>%
        group_by(ID) %>% summarise(d = max(d, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$DIAGNOSIS)) {
      sources$dx <- pcornet$DIAGNOSIS %>%
        filter(
          (DX_TYPE == "10" & DX %in% TREATMENT_CODES$chemo_dx_icd10) |
          (DX_TYPE == "09" & DX %in% TREATMENT_CODES$chemo_dx_icd9)
        ) %>% filter(!is.na(DX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(DX_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$ENCOUNTER)) {
      sources$drg <- pcornet$ENCOUNTER %>%
        filter(DRG %in% TREATMENT_CODES$chemo_drg) %>%
        filter(!is.na(ADMIT_DATE)) %>%
        group_by(ID) %>% summarise(d = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$DISPENSING) && "RXNORM_CUI" %in% names(pcornet$DISPENSING)) {
      sources$disp <- pcornet$DISPENSING %>%
        filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
        filter(!is.na(DISPENSE_DATE)) %>%
        group_by(ID) %>% summarise(d = max(DISPENSE_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$MED_ADMIN) && "RXNORM_CUI" %in% names(pcornet$MED_ADMIN)) {
      sources$ma <- pcornet$MED_ADMIN %>%
        filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
        filter(!is.na(MEDADMIN_START_DATE)) %>%
        group_by(ID) %>% summarise(d = max(MEDADMIN_START_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$PROCEDURES)) {
      sources$rev <- pcornet$PROCEDURES %>%
        filter(PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue) %>%
        filter(!is.na(PX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(PX_DATE, na.rm = TRUE), .groups = "drop")
    }

  } else if (treatment_type == "radiation") {
    sources <- list()
    if (!is.null(pcornet$PROCEDURES)) {
      sources$px <- pcornet$PROCEDURES %>%
        filter(
          (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) |
          (PX_TYPE == "09" & PX %in% TREATMENT_CODES$radiation_icd9) |
          (PX_TYPE == "10" & (
            str_starts(PX, "D70") | str_starts(PX, "D71") |
            str_starts(PX, "D72") | str_starts(PX, "D7Y")
          ))
        ) %>% filter(!is.na(PX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(PX_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$DIAGNOSIS)) {
      sources$dx <- pcornet$DIAGNOSIS %>%
        filter(
          (DX_TYPE == "10" & DX %in% TREATMENT_CODES$radiation_dx_icd10) |
          (DX_TYPE == "09" & DX %in% TREATMENT_CODES$radiation_dx_icd9)
        ) %>% filter(!is.na(DX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(DX_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$ENCOUNTER)) {
      sources$drg <- pcornet$ENCOUNTER %>%
        filter(DRG %in% TREATMENT_CODES$radiation_drg) %>%
        filter(!is.na(ADMIT_DATE)) %>%
        group_by(ID) %>% summarise(d = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$PROCEDURES)) {
      sources$rev <- pcornet$PROCEDURES %>%
        filter(PX_TYPE == "RE" & PX %in% TREATMENT_CODES$radiation_revenue) %>%
        filter(!is.na(PX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(PX_DATE, na.rm = TRUE), .groups = "drop")
    }

  } else if (treatment_type == "sct") {
    sources <- list()
    if (!is.null(pcornet$PROCEDURES)) {
      sources$px <- pcornet$PROCEDURES %>%
        filter(
          (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$sct_cpt) |
          (PX_TYPE == "09" & PX %in% TREATMENT_CODES$sct_icd9) |
          (PX_TYPE == "10" & PX %in% TREATMENT_CODES$sct_icd10pcs)
        ) %>% filter(!is.na(PX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(PX_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$DIAGNOSIS)) {
      sources$dx <- pcornet$DIAGNOSIS %>%
        filter(DX_TYPE == "10" & DX %in% TREATMENT_CODES$sct_dx_icd10) %>%
        filter(!is.na(DX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(DX_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$ENCOUNTER)) {
      sources$drg <- pcornet$ENCOUNTER %>%
        filter(DRG %in% TREATMENT_CODES$sct_drg) %>%
        filter(!is.na(ADMIT_DATE)) %>%
        group_by(ID) %>% summarise(d = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$PROCEDURES)) {
      sources$rev <- pcornet$PROCEDURES %>%
        filter(PX_TYPE == "RE" & PX %in% TREATMENT_CODES$sct_revenue) %>%
        filter(!is.na(PX_DATE)) %>%
        group_by(ID) %>% summarise(d = max(PX_DATE, na.rm = TRUE), .groups = "drop")
    }
  }

  non_null <- compact(sources)
  if (length(non_null) == 0) return(tibble(ID = character(0), last_date = as.Date(character(0))))

  bind_rows(non_null) %>%
    group_by(ID) %>%
    summarise(last_date = max(d, na.rm = TRUE), .groups = "drop") %>%
    filter(!is.infinite(last_date))
}

# Compute last treatment dates
last_chemo_dates <- compute_last_dates("chemo") %>% rename(LAST_CHEMO_DATE = last_date)
last_rad_dates <- compute_last_dates("radiation") %>% rename(LAST_RADIATION_DATE = last_date)
last_sct_dates <- compute_last_dates("sct") %>% rename(LAST_SCT_DATE = last_date)

message(glue("  Last chemo dates: {nrow(last_chemo_dates)} patients"))
message(glue("  Last radiation dates: {nrow(last_rad_dates)} patients"))
message(glue("  Last SCT dates: {nrow(last_sct_dates)} patients"))

# ---- 2b. Payer at LAST treatment (mode in ±30 day window around last date) ----

compute_payer_at_last <- function(last_dates, payer_col_name) {
  if (nrow(last_dates) == 0) {
    return(tibble(ID = character(0), !!payer_col_name := character(0)))
  }
  compute_payer_mode_in_window(last_dates, payer_col_name = payer_col_name)
}

payer_at_last_chemo <- last_chemo_dates %>%
  compute_payer_at_last("PAYER_AT_LAST_CHEMO")
payer_at_last_rad <- last_rad_dates %>%
  compute_payer_at_last("PAYER_AT_LAST_RADIATION")
payer_at_last_sct <- last_sct_dates %>%
  compute_payer_at_last("PAYER_AT_LAST_SCT")

message(glue("  Payer at last chemo: {sum(!is.na(payer_at_last_chemo$PAYER_AT_LAST_CHEMO))} matched"))
message(glue("  Payer at last radiation: {sum(!is.na(payer_at_last_rad$PAYER_AT_LAST_RADIATION))} matched"))
message(glue("  Payer at last SCT: {sum(!is.na(payer_at_last_sct$PAYER_AT_LAST_SCT))} matched"))

# ---- 2c. Post-treatment payer (most prevalent after ANY last treatment) ----

# For each patient, find the latest treatment date across all types
# Then find the mode payer from encounters AFTER that date

all_last_dates <- hl_cohort %>%
  select(ID) %>%
  left_join(last_chemo_dates, by = "ID") %>%
  left_join(last_rad_dates, by = "ID") %>%
  left_join(last_sct_dates, by = "ID") %>%
  rowwise() %>%
  mutate(
    LAST_ANY_TREATMENT_DATE = {
      dates <- c(LAST_CHEMO_DATE, LAST_RADIATION_DATE, LAST_SCT_DATE)
      dates <- dates[!is.na(dates)]
      if (length(dates) == 0) NA_Date_ else max(dates)
    }
  ) %>%
  ungroup() %>%
  select(ID, LAST_ANY_TREATMENT_DATE)

# Compute post-treatment payer: mode of encounters AFTER last treatment
post_treatment_payer <- all_last_dates %>%
  filter(!is.na(LAST_ANY_TREATMENT_DATE)) %>%
  inner_join(
    encounters %>%
      filter(!is.na(effective_payer) &
             nchar(trimws(effective_payer)) > 0 &
             !effective_payer %in% PAYER_MAPPING$sentinel_values),
    by = "ID"
  ) %>%
  filter(ADMIT_DATE > LAST_ANY_TREATMENT_DATE) %>%
  group_by(ID, payer_category) %>%
  summarise(n = n(), .groups = "drop") %>%
  arrange(ID, desc(n), payer_category) %>%
  group_by(ID) %>%
  slice(1) %>%
  ungroup() %>%
  select(ID, POST_TREATMENT_PAYER = payer_category)

message(glue("  Post-treatment payer: {nrow(post_treatment_payer)} patients with encounters after treatment"))

# ---- 2d. Enrollment coverage analysis ----

# Check if enrollment covers ±30 day window around a given date
# Returns TRUE if any enrollment span covers [date - 30, date + 30]
enrollment_primary <- pcornet$ENROLLMENT %>%
  inner_join(
    pcornet$DEMOGRAPHIC %>% select(ID, SOURCE),
    by = c("ID", "SOURCE")
  )

check_enr_covers_window <- function(patient_dates, date_col) {
  patient_dates %>%
    rename(anchor_date = !!date_col) %>%
    filter(!is.na(anchor_date)) %>%
    left_join(
      enrollment_primary %>% select(ID, ENR_START_DATE, ENR_END_DATE),
      by = "ID",
      relationship = "many-to-many"
    ) %>%
    mutate(
      window_start = anchor_date - days(WINDOW_DAYS),
      window_end = anchor_date + days(WINDOW_DAYS),
      enr_covers = ENR_START_DATE <= window_start & ENR_END_DATE >= window_end
    ) %>%
    group_by(ID) %>%
    summarise(enr_covers_window = any(enr_covers, na.rm = TRUE), .groups = "drop")
}

# ---- 2e. Join all additional data to cohort ----

cohort_full <- hl_cohort %>%
  left_join(last_chemo_dates, by = "ID") %>%
  left_join(last_rad_dates, by = "ID") %>%
  left_join(last_sct_dates, by = "ID") %>%
  left_join(payer_at_last_chemo, by = "ID") %>%
  left_join(payer_at_last_rad, by = "ID") %>%
  left_join(payer_at_last_sct, by = "ID") %>%
  left_join(all_last_dates, by = "ID") %>%
  left_join(post_treatment_payer, by = "ID")

# Rename payer categories to match Python PPTX display names
cohort_full <- cohort_full %>%
  mutate(
    across(
      c(PAYER_CATEGORY_PRIMARY, PAYER_CATEGORY_AT_FIRST_DX,
        PAYER_AT_CHEMO, PAYER_AT_RADIATION, PAYER_AT_SCT,
        PAYER_AT_LAST_CHEMO, PAYER_AT_LAST_RADIATION, PAYER_AT_LAST_SCT,
        POST_TREATMENT_PAYER),
      rename_payer
    )
  )

message(glue("\n  Full cohort assembled: {nrow(cohort_full)} patients, {ncol(cohort_full)} columns"))

# ==============================================================================
# SECTION 3: TABLE BUILDING FUNCTIONS
# ==============================================================================

# Build a payer distribution table for one or more columns
build_payer_table <- function(data, col_specs, total_n = NULL) {
  # col_specs: named list of list(col = "column_name", label = "Display Label")
  if (is.null(total_n)) total_n <- nrow(data)

  rows <- lapply(PAYER_ORDER, function(cat) {
    row <- list(`Payer Category` = cat)
    for (spec in col_specs) {
      vals <- data[[spec$col]]
      n <- sum(vals == cat, na.rm = TRUE)
      row[[spec$label]] <- format_count_pct(n, total_n)
    }
    as_tibble(row)
  })
  bind_rows(rows)
}

# Build a payer table with an extra "N/A" row for patients without data
build_payer_table_with_na <- function(data, col_specs, na_label = "N/A (No Treatment)", total_n = NULL) {
  if (is.null(total_n)) total_n <- nrow(data)

  tbl <- build_payer_table(data, col_specs, total_n)

  # Add N/A row
  na_row <- list(`Payer Category` = na_label)
  for (spec in col_specs) {
    n_na <- sum(is.na(data[[spec$col]]))
    na_row[[spec$label]] <- format_count_pct(n_na, total_n)
  }
  bind_rows(tbl, as_tibble(na_row))
}

# Build enrollment coverage split table
build_enr_coverage_table <- function(data, payer_col, enr_covers_col, total_n = NULL) {
  if (is.null(total_n)) total_n <- nrow(data)

  covers_data <- data %>% filter(!!sym(enr_covers_col) == TRUE)
  gap_data <- data %>% filter(!!sym(enr_covers_col) == FALSE)
  n_covers <- nrow(covers_data)
  n_gap <- nrow(gap_data)

  rows <- lapply(PAYER_ORDER, function(cat) {
    n_c <- sum(covers_data[[payer_col]] == cat, na.rm = TRUE)
    n_g <- sum(gap_data[[payer_col]] == cat, na.rm = TRUE)
    tibble(
      `Payer Category` = cat,
      `ENR Covers Window` = format_count_pct(n_c, n_covers),
      `ENR Does Not Cover` = format_count_pct(n_g, n_gap)
    )
  })
  tbl <- bind_rows(rows)

  # Add N/A row for patients without the payer assignment
  n_na_c <- sum(is.na(covers_data[[payer_col]]))
  n_na_g <- sum(is.na(gap_data[[payer_col]]))
  bind_rows(tbl, tibble(
    `Payer Category` = "N/A",
    `ENR Covers Window` = format_count_pct(n_na_c, n_covers),
    `ENR Does Not Cover` = format_count_pct(n_na_g, n_gap)
  ))
}

# Build treatment enrollment coverage table (first + last, covers + gap)
build_treatment_enr_table <- function(data, first_payer_col, last_payer_col,
                                       first_enr_col, last_enr_col,
                                       first_label, last_label) {
  fc <- data %>% filter(!!sym(first_enr_col) == TRUE)
  fg <- data %>% filter(!!sym(first_enr_col) == FALSE)
  lc <- data %>% filter(!!sym(last_enr_col) == TRUE)
  lg <- data %>% filter(!!sym(last_enr_col) == FALSE)

  rows <- lapply(PAYER_ORDER, function(cat) {
    tibble(
      `Payer Category` = cat,
      !!paste0("First ", first_label, " ENR Covers") :=
        format_count_pct(sum(fc[[first_payer_col]] == cat, na.rm = TRUE), nrow(fc)),
      !!paste0("First ", first_label, " ENR Gap") :=
        format_count_pct(sum(fg[[first_payer_col]] == cat, na.rm = TRUE), nrow(fg)),
      !!paste0("Last ", last_label, " ENR Covers") :=
        format_count_pct(sum(lc[[last_payer_col]] == cat, na.rm = TRUE), nrow(lc)),
      !!paste0("Last ", last_label, " ENR Gap") :=
        format_count_pct(sum(lg[[last_payer_col]] == cat, na.rm = TRUE), nrow(lg))
    )
  })
  tbl <- bind_rows(rows)

  # N/A row
  bind_rows(tbl, tibble(
    `Payer Category` = "N/A",
    !!paste0("First ", first_label, " ENR Covers") :=
      format_count_pct(sum(is.na(fc[[first_payer_col]])), nrow(fc)),
    !!paste0("First ", first_label, " ENR Gap") :=
      format_count_pct(sum(is.na(fg[[first_payer_col]])), nrow(fg)),
    !!paste0("Last ", last_label, " ENR Covers") :=
      format_count_pct(sum(is.na(lc[[last_payer_col]])), nrow(lc)),
    !!paste0("Last ", last_label, " ENR Gap") :=
      format_count_pct(sum(is.na(lg[[last_payer_col]])), nrow(lg))
  ))
}

# ==============================================================================
# SECTION 4: FLEXTABLE STYLING
# ==============================================================================

style_table <- function(ft) {
  ft %>%
    fontsize(size = 10, part = "all") %>%
    font(fontname = "Calibri", part = "all") %>%
    bold(part = "header") %>%
    bg(bg = "#2C3E50", part = "header") %>%
    color(color = "white", part = "header") %>%
    align(align = "center", part = "header") %>%
    align(j = 1, align = "left", part = "body") %>%
    align(j = -1, align = "center", part = "body") %>%
    border_remove() %>%
    hline(part = "header", border = fp_border(color = "white", width = 1)) %>%
    hline_top(part = "header", border = fp_border(color = "#2C3E50", width = 2)) %>%
    hline_bottom(part = "body", border = fp_border(color = "#2C3E50", width = 2)) %>%
    hline(part = "body", border = fp_border(color = "#BDC3C7", width = 0.5)) %>%
    padding(padding = 4, part = "all") %>%
    autofit()
}

# ==============================================================================
# SECTION 5: BUILD PPTX SLIDES
# ==============================================================================

message("\n--- Building PowerPoint slides ---")

pptx <- read_pptx()

# Helper to add a slide with title, subtitle, and table
add_table_slide <- function(pptx, title, subtitle, tbl_data) {
  ft <- flextable(tbl_data) %>% style_table()

  pptx <- pptx %>%
    add_slide(layout = "Blank") %>%
    ph_with(
      value = fpar(ftext(title, prop = fp_text(font.size = 22, bold = TRUE,
                                                font.family = "Calibri",
                                                color = "#2C3E50"))),
      location = ph_location(left = 0.5, top = 0.3, width = 9, height = 0.5)
    ) %>%
    ph_with(
      value = fpar(ftext(subtitle, prop = fp_text(font.size = 12, italic = TRUE,
                                                   font.family = "Calibri",
                                                   color = "#7F8C8D"))),
      location = ph_location(left = 0.5, top = 0.8, width = 9, height = 0.4)
    ) %>%
    ph_with(
      value = ft,
      location = ph_location(left = 0.5, top = 1.3, width = 9, height = 5)
    )

  pptx
}

# ---- Counts for title slide ----
N_TOTAL <- nrow(cohort_full)
N_CHEMO <- sum(cohort_full$HAD_CHEMO == 1)
N_RAD <- sum(cohort_full$HAD_RADIATION == 1)
N_SCT <- sum(cohort_full$HAD_SCT == 1)

# ---- Slide 1: Title ----
message("  Slide 1: Title")
pptx <- pptx %>%
  add_slide(layout = "Blank") %>%
  ph_with(
    value = fpar(ftext("Insurance Coverage by Treatment Type",
                       prop = fp_text(font.size = 28, bold = TRUE,
                                      font.family = "Calibri", color = "#2C3E50"))),
    location = ph_location(left = 0.5, top = 1.0, width = 9, height = 1)
  ) %>%
  ph_with(
    value = block_list(
      fpar(ftext("Hodgkin Lymphoma Cohort \u2014 UF Health",
                 prop = fp_text(font.size = 16, italic = TRUE,
                                font.family = "Calibri", color = "#7F8C8D")))
    ),
    location = ph_location(left = 0.5, top = 2.0, width = 9, height = 0.5)
  ) %>%
  ph_with(
    value = block_list(
      fpar(ftext(glue("Total Cohort: N = {format(N_TOTAL, big.mark = ',')}"),
                 prop = fp_text(font.size = 18, font.family = "Calibri"))),
      fpar(ftext(glue("Chemotherapy: N = {format(N_CHEMO, big.mark = ',')}"),
                 prop = fp_text(font.size = 18, font.family = "Calibri"))),
      fpar(ftext(glue("Radiation: N = {format(N_RAD, big.mark = ',')}"),
                 prop = fp_text(font.size = 18, font.family = "Calibri"))),
      fpar(ftext(glue("Stem Cell Transplant: N = {format(N_SCT, big.mark = ',')}"),
                 prop = fp_text(font.size = 18, font.family = "Calibri")))
    ),
    location = ph_location(left = 0.5, top = 3.0, width = 9, height = 3)
  )

# ---- Slide 2: Insurance Coverage Overview ----
message("  Slide 2: Insurance Coverage Overview")
tbl2 <- build_payer_table(cohort_full, list(
  list(col = "PAYER_CATEGORY_PRIMARY", label = "Primary Insurance"),
  list(col = "PAYER_CATEGORY_AT_FIRST_DX", label = "First Diagnosis")
))
pptx <- add_table_slide(pptx,
  "Insurance Coverage Overview",
  glue("All enrolled patients \u2014 N = {format(N_TOTAL, big.mark = ',')}"),
  tbl2)

# ---- Slide 3: Post-Treatment Insurance (all patients) ----
message("  Slide 3: Post-Treatment Insurance")
tbl3 <- build_payer_table_with_na(cohort_full, list(
  list(col = "POST_TREATMENT_PAYER", label = "Post-Treatment Insurance")
))
pptx <- add_table_slide(pptx,
  "Post-Treatment Insurance \u2014 All Patients",
  glue("Most prevalent payer after last treatment date \u2014 N = {format(N_TOTAL, big.mark = ',')}"),
  tbl3)

# ---- Slide 4: Chemotherapy Insurance ----
message("  Slide 4: Chemotherapy Insurance")
chemo_patients <- cohort_full %>% filter(HAD_CHEMO == 1)
tbl4 <- build_payer_table(chemo_patients, list(
  list(col = "PAYER_CATEGORY_PRIMARY", label = "Primary Insurance"),
  list(col = "PAYER_AT_CHEMO", label = "First Chemo"),
  list(col = "PAYER_AT_LAST_CHEMO", label = "Last Chemo")
))
pptx <- add_table_slide(pptx,
  "Chemotherapy Insurance",
  glue("Insurance at primary, first, and last chemotherapy \u2014 N = {format(N_CHEMO, big.mark = ',')}"),
  tbl4)

# ---- Slide 5: Chemotherapy Post-Treatment Insurance ----
message("  Slide 5: Chemo Post-Treatment Insurance")
# Post-treatment for chemo patients only
chemo_post <- chemo_patients %>%
  left_join(post_treatment_payer %>% rename(CHEMO_POST_TX = POST_TREATMENT_PAYER), by = "ID") %>%
  mutate(CHEMO_POST_TX = rename_payer(CHEMO_POST_TX))
tbl5 <- build_payer_table(chemo_post, list(
  list(col = "CHEMO_POST_TX", label = "Post-Treatment Insurance")
))
pptx <- add_table_slide(pptx,
  "Chemotherapy Post-Treatment Insurance",
  glue("Most prevalent payer after last treatment date \u2014 N = {format(N_CHEMO, big.mark = ',')}"),
  tbl5)

# ---- Slide 6: Radiation Insurance ----
message("  Slide 6: Radiation Insurance")
rad_patients <- cohort_full %>% filter(HAD_RADIATION == 1)
tbl6 <- build_payer_table(rad_patients, list(
  list(col = "PAYER_CATEGORY_PRIMARY", label = "Primary Insurance"),
  list(col = "PAYER_AT_RADIATION", label = "First Radiation"),
  list(col = "PAYER_AT_LAST_RADIATION", label = "Last Radiation")
))
pptx <- add_table_slide(pptx,
  "Radiation Insurance",
  glue("Insurance at primary, first, and last radiation \u2014 N = {format(N_RAD, big.mark = ',')}"),
  tbl6)

# ---- Slide 7: Radiation Post-Treatment Insurance ----
message("  Slide 7: Radiation Post-Treatment Insurance")
rad_post <- rad_patients %>%
  left_join(post_treatment_payer %>% rename(RAD_POST_TX = POST_TREATMENT_PAYER), by = "ID") %>%
  mutate(RAD_POST_TX = rename_payer(RAD_POST_TX))
tbl7 <- build_payer_table(rad_post, list(
  list(col = "RAD_POST_TX", label = "Post-Treatment Insurance")
))
pptx <- add_table_slide(pptx,
  "Radiation Post-Treatment Insurance",
  glue("Most prevalent payer after last treatment date \u2014 N = {format(N_RAD, big.mark = ',')}"),
  tbl7)

# ---- Slide 8: SCT Insurance ----
message("  Slide 8: SCT Insurance")
sct_patients <- cohort_full %>% filter(HAD_SCT == 1)
tbl8 <- build_payer_table(sct_patients, list(
  list(col = "PAYER_CATEGORY_PRIMARY", label = "Primary Insurance"),
  list(col = "PAYER_AT_SCT", label = "First SCT"),
  list(col = "PAYER_AT_LAST_SCT", label = "Last SCT")
))
pptx <- add_table_slide(pptx,
  "Stem Cell Transplant Insurance",
  glue("Insurance at primary, first, and last SCT \u2014 N = {format(N_SCT, big.mark = ',')}"),
  tbl8)

# ---- Slide 9: SCT Post-Treatment Insurance ----
message("  Slide 9: SCT Post-Treatment Insurance")
sct_post <- sct_patients %>%
  left_join(post_treatment_payer %>% rename(SCT_POST_TX = POST_TREATMENT_PAYER), by = "ID") %>%
  mutate(SCT_POST_TX = rename_payer(SCT_POST_TX))
tbl9 <- build_payer_table(sct_post, list(
  list(col = "SCT_POST_TX", label = "Post-Treatment Insurance")
))
pptx <- add_table_slide(pptx,
  "SCT Post-Treatment Insurance",
  glue("Most prevalent payer after last treatment date \u2014 N = {format(N_SCT, big.mark = ',')}"),
  tbl9)

# ---- Slide 10: Diagnosis - Enrollment Coverage ----
message("  Slide 10: Diagnosis Enrollment Coverage")
dx_enr <- check_enr_covers_window(
  cohort_full %>% select(ID, first_hl_dx_date) %>% filter(!is.na(first_hl_dx_date)),
  "first_hl_dx_date"
)
cohort_dx_enr <- cohort_full %>%
  left_join(dx_enr %>% rename(dx_enr_covers = enr_covers_window), by = "ID") %>%
  mutate(dx_enr_covers = coalesce(dx_enr_covers, FALSE))

tbl10 <- build_enr_coverage_table(cohort_dx_enr, "PAYER_CATEGORY_AT_FIRST_DX", "dx_enr_covers")
pptx <- add_table_slide(pptx,
  "Diagnosis \u2014 Insurance by Enrollment Coverage",
  glue("Payer at first HL diagnosis: patients with vs without enrollment covering \u00b130 day window"),
  tbl10)

# ---- Slide 11: Chemo - Enrollment Coverage ----
message("  Slide 11: Chemo Enrollment Coverage")
chemo_first_enr <- check_enr_covers_window(
  chemo_patients %>% select(ID, FIRST_CHEMO_DATE) %>% filter(!is.na(FIRST_CHEMO_DATE)),
  "FIRST_CHEMO_DATE"
) %>% rename(chemo_first_enr = enr_covers_window)

chemo_last_enr <- check_enr_covers_window(
  chemo_patients %>%
    select(ID, LAST_CHEMO_DATE) %>%
    filter(!is.na(LAST_CHEMO_DATE)),
  "LAST_CHEMO_DATE"
) %>% rename(chemo_last_enr = enr_covers_window)

chemo_enr <- chemo_patients %>%
  left_join(chemo_first_enr, by = "ID") %>%
  left_join(chemo_last_enr, by = "ID") %>%
  mutate(
    chemo_first_enr = coalesce(chemo_first_enr, FALSE),
    chemo_last_enr = coalesce(chemo_last_enr, FALSE)
  )

tbl11 <- build_treatment_enr_table(
  chemo_enr, "PAYER_AT_CHEMO", "PAYER_AT_LAST_CHEMO",
  "chemo_first_enr", "chemo_last_enr", "Chemo", "Chemo"
)
pptx <- add_table_slide(pptx,
  "Chemotherapy \u2014 Insurance by Enrollment Coverage",
  glue("Payer at first/last chemo: patients with vs without enrollment covering \u00b130 day window"),
  tbl11)

# ---- Slide 12: Radiation - Enrollment Coverage ----
message("  Slide 12: Radiation Enrollment Coverage")
rad_first_enr <- check_enr_covers_window(
  rad_patients %>% select(ID, FIRST_RADIATION_DATE) %>% filter(!is.na(FIRST_RADIATION_DATE)),
  "FIRST_RADIATION_DATE"
) %>% rename(rad_first_enr = enr_covers_window)

rad_last_enr <- check_enr_covers_window(
  rad_patients %>%
    select(ID, LAST_RADIATION_DATE) %>%
    filter(!is.na(LAST_RADIATION_DATE)),
  "LAST_RADIATION_DATE"
) %>% rename(rad_last_enr = enr_covers_window)

rad_enr <- rad_patients %>%
  left_join(rad_first_enr, by = "ID") %>%
  left_join(rad_last_enr, by = "ID") %>%
  mutate(
    rad_first_enr = coalesce(rad_first_enr, FALSE),
    rad_last_enr = coalesce(rad_last_enr, FALSE)
  )

tbl12 <- build_treatment_enr_table(
  rad_enr, "PAYER_AT_RADIATION", "PAYER_AT_LAST_RADIATION",
  "rad_first_enr", "rad_last_enr", "Radiation", "Radiation"
)
pptx <- add_table_slide(pptx,
  "Radiation \u2014 Insurance by Enrollment Coverage",
  glue("Payer at first/last radiation: patients with vs without enrollment covering \u00b130 day window"),
  tbl12)

# ---- Slide 13: SCT - Enrollment Coverage ----
message("  Slide 13: SCT Enrollment Coverage")
sct_first_enr <- check_enr_covers_window(
  sct_patients %>% select(ID, FIRST_SCT_DATE) %>% filter(!is.na(FIRST_SCT_DATE)),
  "FIRST_SCT_DATE"
) %>% rename(sct_first_enr = enr_covers_window)

sct_last_enr <- check_enr_covers_window(
  sct_patients %>%
    select(ID, LAST_SCT_DATE) %>%
    filter(!is.na(LAST_SCT_DATE)),
  "LAST_SCT_DATE"
) %>% rename(sct_last_enr = enr_covers_window)

sct_enr <- sct_patients %>%
  left_join(sct_first_enr, by = "ID") %>%
  left_join(sct_last_enr, by = "ID") %>%
  mutate(
    sct_first_enr = coalesce(sct_first_enr, FALSE),
    sct_last_enr = coalesce(sct_last_enr, FALSE)
  )

tbl13 <- build_treatment_enr_table(
  sct_enr, "PAYER_AT_SCT", "PAYER_AT_LAST_SCT",
  "sct_first_enr", "sct_last_enr", "SCT", "SCT"
)
pptx <- add_table_slide(pptx,
  "SCT \u2014 Insurance by Enrollment Coverage",
  glue("Payer at first/last SCT: patients with vs without enrollment covering \u00b130 day window"),
  tbl13)

# ---- Slide 14: Last Treatment = Last Encounter (±30 day window) ----
message("  Slide 14: Last Treatment = Last Encounter")

# For each patient, compute their last encounter date
last_encounter_per_patient <- encounters %>%
  filter(!is.na(ADMIT_DATE)) %>%
  group_by(ID) %>%
  summarise(LAST_ENCOUNTER_DATE = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop")

# Join to cohort with last treatment dates
last_tx_vs_enc <- cohort_full %>%
  filter(!is.na(LAST_ANY_TREATMENT_DATE)) %>%
  inner_join(last_encounter_per_patient, by = "ID") %>%
  mutate(
    days_last_enc_after_last_tx = as.numeric(LAST_ENCOUNTER_DATE - LAST_ANY_TREATMENT_DATE),
    last_tx_is_last_enc = abs(days_last_enc_after_last_tx) <= WINDOW_DAYS
  )

# Also compute per treatment type (LAST_*_DATE columns already in cohort_full)
last_tx_vs_enc <- last_tx_vs_enc %>%
  mutate(
    chemo_is_last_enc = if_else(
      !is.na(LAST_CHEMO_DATE),
      abs(as.numeric(LAST_ENCOUNTER_DATE - LAST_CHEMO_DATE)) <= WINDOW_DAYS,
      NA
    ),
    rad_is_last_enc = if_else(
      !is.na(LAST_RADIATION_DATE),
      abs(as.numeric(LAST_ENCOUNTER_DATE - LAST_RADIATION_DATE)) <= WINDOW_DAYS,
      NA
    ),
    sct_is_last_enc = if_else(
      !is.na(LAST_SCT_DATE),
      abs(as.numeric(LAST_ENCOUNTER_DATE - LAST_SCT_DATE)) <= WINDOW_DAYS,
      NA
    )
  )

# Build summary table
n_any_tx <- nrow(last_tx_vs_enc)
n_any_match <- sum(last_tx_vs_enc$last_tx_is_last_enc, na.rm = TRUE)

n_chemo_tx <- sum(!is.na(last_tx_vs_enc$LAST_CHEMO_DATE))
n_chemo_match <- sum(last_tx_vs_enc$chemo_is_last_enc, na.rm = TRUE)

n_rad_tx <- sum(!is.na(last_tx_vs_enc$LAST_RADIATION_DATE))
n_rad_match <- sum(last_tx_vs_enc$rad_is_last_enc, na.rm = TRUE)

n_sct_tx <- sum(!is.na(last_tx_vs_enc$LAST_SCT_DATE))
n_sct_match <- sum(last_tx_vs_enc$sct_is_last_enc, na.rm = TRUE)

tbl14 <- tibble(
  `Treatment Type` = c("Any Treatment", "Chemotherapy", "Radiation", "Stem Cell Transplant"),
  `N With Treatment` = c(
    format(n_any_tx, big.mark = ","),
    format(n_chemo_tx, big.mark = ","),
    format(n_rad_tx, big.mark = ","),
    format(n_sct_tx, big.mark = ",")
  ),
  `Last Tx = Last Encounter` = c(
    format_count_pct(n_any_match, n_any_tx),
    format_count_pct(n_chemo_match, n_chemo_tx),
    format_count_pct(n_rad_match, n_rad_tx),
    format_count_pct(n_sct_match, n_sct_tx)
  ),
  `Had Follow-up Encounters` = c(
    format_count_pct(n_any_tx - n_any_match, n_any_tx),
    format_count_pct(n_chemo_tx - n_chemo_match, n_chemo_tx),
    format_count_pct(n_rad_tx - n_rad_match, n_rad_tx),
    format_count_pct(n_sct_tx - n_sct_match, n_sct_tx)
  )
)

pptx <- add_table_slide(pptx,
  "Last Treatment = Last Encounter",
  glue("Patients whose last treatment was within \u00b130 days of their last encounter (no follow-up)"),
  tbl14)

# ---- Slide 15: Unknown Post-Treatment Payer - Encounter Breakdown ----
message("  Slide 15: Unknown Post-Treatment Encounter Breakdown")

# Patients with Unknown or NA post-treatment payer: how many encounters after last treatment?
unknown_post <- cohort_full %>%
  filter(!is.na(LAST_ANY_TREATMENT_DATE)) %>%
  filter(is.na(POST_TREATMENT_PAYER) | POST_TREATMENT_PAYER == "Unknown")

# Count encounters after last treatment for each patient
post_tx_encounter_counts <- unknown_post %>%
  select(ID, LAST_ANY_TREATMENT_DATE) %>%
  left_join(
    encounters %>% select(ID, ADMIT_DATE),
    by = "ID",
    relationship = "many-to-many"
  ) %>%
  filter(ADMIT_DATE > LAST_ANY_TREATMENT_DATE) %>%
  group_by(ID) %>%
  summarise(n_post_encounters = n(), .groups = "drop")

# Join back and fill 0 for patients with no post-treatment encounters
unknown_post_counts <- unknown_post %>%
  select(ID) %>%
  left_join(post_tx_encounter_counts, by = "ID") %>%
  mutate(n_post_encounters = coalesce(n_post_encounters, 0L))

# Bin into categories
n_unknown <- nrow(unknown_post_counts)
tbl15 <- unknown_post_counts %>%
  mutate(
    bin = case_when(
      n_post_encounters == 0 ~ "0",
      n_post_encounters <= 5 ~ "1-5",
      n_post_encounters <= 10 ~ "6-10",
      n_post_encounters <= 20 ~ "11-20",
      TRUE ~ "21+"
    ),
    bin = factor(bin, levels = c("0", "1-5", "6-10", "11-20", "21+"))
  ) %>%
  count(bin, name = "n") %>%
  mutate(`N Patients` = format_count_pct(n, n_unknown)) %>%
  select(`Payer Category` = bin, `N Patients`)

pptx <- add_table_slide(pptx,
  "Unknown Post-Treatment Payer \u2014 Encounter Breakdown",
  glue("Patients with Unknown post-treatment payer: how many encounters exist after last treatment?"),
  tbl15)

# ---- Slide 16: Insurance After Last Treatment & Dataset Retention ----
message("  Slide 16: Post-Last-Treatment Insurance & Retention")

# Compute payer at last treatment of any type (mode in ±30 day window)
payer_at_last_any <- all_last_dates %>%
  filter(!is.na(LAST_ANY_TREATMENT_DATE)) %>%
  compute_payer_mode_in_window(payer_col_name = "PAYER_AT_LAST_TX")

# Determine which treated patients have ANY encounter after their last treatment
treated_ids <- cohort_full %>%
  filter(!is.na(LAST_ANY_TREATMENT_DATE)) %>%
  select(ID, LAST_ANY_TREATMENT_DATE)

patients_with_post_enc <- treated_ids %>%
  inner_join(
    encounters %>% select(ID, ADMIT_DATE),
    by = "ID",
    relationship = "many-to-many"
  ) %>%
  filter(ADMIT_DATE > LAST_ANY_TREATMENT_DATE) %>%
  distinct(ID) %>%
  mutate(has_post_encounter = TRUE)

# Build retention dataset
tx_retention <- treated_ids %>%
  left_join(patients_with_post_enc, by = "ID") %>%
  mutate(has_post_encounter = coalesce(has_post_encounter, FALSE)) %>%
  left_join(post_treatment_payer, by = "ID") %>%
  left_join(payer_at_last_any, by = "ID") %>%
  mutate(
    POST_TREATMENT_PAYER = rename_payer(POST_TREATMENT_PAYER),
    PAYER_AT_LAST_TX = rename_payer(PAYER_AT_LAST_TX)
  )

n_treated <- nrow(tx_retention)
n_still_in <- sum(tx_retention$has_post_encounter)
n_missing <- n_treated - n_still_in
n_no_tx <- N_TOTAL - n_treated

still_data <- tx_retention %>% filter(has_post_encounter)
missing_data <- tx_retention %>% filter(!has_post_encounter)

message(glue("  Treated: {n_treated} | Still in dataset: {n_still_in} | Missing: {n_missing} | No treatment: {n_no_tx}"))

# Build payer breakdown: still in dataset (post-tx payer) vs missing (last known payer)
still_col <- glue("Still in Dataset (N={format(n_still_in, big.mark=',')})")
missing_col <- glue("No Longer in Dataset (N={format(n_missing, big.mark=',')})")

rows16 <- lapply(PAYER_ORDER, function(cat) {
  n_s <- sum(still_data$POST_TREATMENT_PAYER == cat, na.rm = TRUE)
  n_m <- sum(missing_data$PAYER_AT_LAST_TX == cat, na.rm = TRUE)
  tibble(
    `Payer Category` = cat,
    !!still_col := if (n_still_in > 0) format_count_pct(n_s, n_still_in) else "0 (0.0%)",
    !!missing_col := if (n_missing > 0) format_count_pct(n_m, n_missing) else "0 (0.0%)"
  )
})
tbl16 <- bind_rows(rows16)

# Add N/A row (no payer matched in window)
n_na_s <- sum(is.na(still_data$POST_TREATMENT_PAYER))
n_na_m <- sum(is.na(missing_data$PAYER_AT_LAST_TX))
tbl16 <- bind_rows(tbl16, tibble(
  `Payer Category` = "N/A (No Payer Match)",
  !!still_col := if (n_still_in > 0) format_count_pct(n_na_s, n_still_in) else "0 (0.0%)",
  !!missing_col := if (n_missing > 0) format_count_pct(n_na_m, n_missing) else "0 (0.0%)"
))

# Add No Treatment row to show completeness
tbl16 <- bind_rows(tbl16, tibble(
  `Payer Category` = "No Treatment Recorded",
  !!still_col := "\u2014",
  !!missing_col := format(n_no_tx, big.mark = ",")
))

pct_still <- if (n_treated > 0) round(100 * n_still_in / n_treated, 1) else 0
pct_missing <- if (n_treated > 0) round(100 * n_missing / n_treated, 1) else 0

pptx <- add_table_slide(pptx,
  "Insurance After Last Treatment \u2014 Dataset Retention",
  glue("{format(n_treated, big.mark=',')} treated patients: {format(n_still_in, big.mark=',')} ({pct_still}%) still in dataset, {format(n_missing, big.mark=',')} ({pct_missing}%) no longer in dataset | {format(n_no_tx, big.mark=',')} had no recorded treatment"),
  tbl16)

# ==============================================================================
# SECTION 6: SAVE PPTX
# ==============================================================================

output_filename <- glue("insurance_tables_{Sys.Date()}.pptx")
output_path <- file.path(output_filename)
print(pptx, target = output_path)

message(glue("\n  PowerPoint saved to: {output_path}"))
message(glue("  Slides: 16"))
message(glue("  Cohort: {format(N_TOTAL, big.mark = ',')} patients"))
message(glue("  Date: {Sys.Date()}"))

message("\n", strrep("=", 60))
message("PowerPoint generation complete")
message(strrep("=", 60))

# ==============================================================================
# End of 11_generate_pptx.R
# ==============================================================================
