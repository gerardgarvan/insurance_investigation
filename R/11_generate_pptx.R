# ==============================================================================
# 11_generate_pptx.R -- Generate insurance tables PowerPoint
# ==============================================================================
#
# Produces insurance_tables_YYYY-MM-DD.pptx matching the Python pipeline's
# 15-slide output, computed entirely from R pipeline data.
#
# Slides:
#   1. Definitions & Glossary
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
#  15. Missing Post-Treatment Payer - Encounter Breakdown
#  16. Insurance After Last Treatment - Dataset Retention (still in dataset vs missing)
#  17. Encounters per Person by Payer Category (histogram)
#  18. Summary Statistics: Encounters per Payer Category (table)
#  19. Mean Post-Treatment Encounters by Year of Diagnosis
#  20. Mean Total Encounters by Year of Diagnosis
#  21. Post-Treatment Encounter Presence by Age Group
#  22. Unique Encounter Dates per Person by Payer Category (histogram)
#  23. Summary Statistics: Unique Dates per Payer Category (table)
#  24. Mean Post-Treatment Unique Dates by Year of Diagnosis
#  25. Mean Total Unique Dates by Year of Diagnosis
#
# Dependencies:
#   - 04_build_cohort.R must be sourced first (produces hl_cohort, pcornet,
#     encounters, payer_summary in the global environment)
#   - 16_encounter_analysis.R is sourced automatically to regenerate PNG figures
#     in output/figures/ (slides 17-20, 22-25 will be skipped if PNGs are absent)
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

# Payer category display order -- 6 categories + Missing (consolidates Other/Unavailable/Unknown)
PAYER_ORDER <- c(
  "Medicare", "Medicaid", "Dual eligible", "Private",
  "Other government", "No payment / Self-pay", "Missing"
)

# Map R pipeline category names to PPTX display names
# Collapses Other, Unavailable, Unknown, and NA all into "Missing"
rename_payer <- function(x) {
  case_when(
    x %in% c("Other", "Unavailable", "Unknown") ~ "Missing",
    is.na(x)                                      ~ "Missing",
    TRUE ~ x
  )
}

# HIPAA small-cell suppression: counts 1-10 replaced with "<11"
format_count_pct <- function(n, total) {
  pct <- round(100 * n / total, 1)
  count_str <- format(n, big.mark = ",")
  pct_str <- paste0(pct, "%")
  paste0(count_str, " (", pct_str, ")")
}

# Treatment window (days)
WINDOW_DAYS <- CONFIG$analysis$treatment_window_days  # 30

# UF Health brand colors (matches Python pipeline)
UF_BLUE    <- "#003087"
UF_ORANGE  <- "#FA4616"
LIGHT_BLUE <- "#CCD5EA"   # Alternating row color (odd rows)
LIGHT_ORANGE <- "#FDD9CC" # Alternating row color (even rows)
DARK_TEXT  <- "#333333"

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

# Last encounter date per patient (reused in Slide 14)
last_encounter_per_patient <- encounters %>%
  filter(!is.na(ADMIT_DATE)) %>%
  group_by(ID) %>%
  summarise(LAST_ENCOUNTER_DATE = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop")

# Helper: compute post-treatment payer (most prevalent anytime after a given date)
# Patients whose treatment date = last encounter (±30 days) get N/A (no follow-up)
compute_post_tx_payer <- function(patient_dates, date_col, payer_col_name) {
  # Identify patients with no follow-up (last treatment = last encounter)
  no_followup_ids <- patient_dates %>%
    filter(!is.na(!!sym(date_col))) %>%
    inner_join(last_encounter_per_patient, by = "ID") %>%
    filter(abs(as.numeric(LAST_ENCOUNTER_DATE - !!sym(date_col))) <= WINDOW_DAYS) %>%
    pull(ID)

  result <- patient_dates %>%
    filter(!is.na(!!sym(date_col))) %>%
    filter(!ID %in% no_followup_ids) %>%
    inner_join(
      encounters %>%
        filter(!is.na(effective_payer) &
               nchar(trimws(effective_payer)) > 0 &
               !effective_payer %in% PAYER_MAPPING$sentinel_values),
      by = "ID"
    ) %>%
    filter(ADMIT_DATE > !!sym(date_col)) %>%
    group_by(ID, payer_category) %>%
    summarise(n = n(), .groups = "drop") %>%
    arrange(ID, desc(n), payer_category) %>%
    group_by(ID) %>%
    slice(1) %>%
    ungroup() %>%
    select(ID, !!payer_col_name := payer_category)

  message(glue("  {payer_col_name}: {nrow(result)} with follow-up, {length(no_followup_ids)} N/A (no follow-up)"))
  result
}

# Post-treatment payer: anytime after last treatment of ANY type
post_treatment_payer <- compute_post_tx_payer(
  all_last_dates, "LAST_ANY_TREATMENT_DATE", "POST_TREATMENT_PAYER"
)

# Post-treatment payer per treatment type
post_chemo_payer <- compute_post_tx_payer(
  last_chemo_dates %>% rename(LAST_DATE = LAST_CHEMO_DATE),
  "LAST_DATE", "POST_CHEMO_PAYER"
)
post_rad_payer <- compute_post_tx_payer(
  last_rad_dates %>% rename(LAST_DATE = LAST_RADIATION_DATE),
  "LAST_DATE", "POST_RAD_PAYER"
)
post_sct_payer <- compute_post_tx_payer(
  last_sct_dates %>% rename(LAST_DATE = LAST_SCT_DATE),
  "LAST_DATE", "POST_SCT_PAYER"
)

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
  left_join(post_treatment_payer, by = "ID") %>%
  left_join(post_chemo_payer, by = "ID") %>%
  left_join(post_rad_payer, by = "ID") %>%
  left_join(post_sct_payer, by = "ID")

# Rename payer categories to match Python PPTX display names
# POST_TREATMENT_PAYER excluded: NA must stay NA for the N/A row (no follow-up)
cohort_full <- cohort_full %>%
  mutate(
    across(
      c(PAYER_CATEGORY_PRIMARY, PAYER_CATEGORY_AT_FIRST_DX,
        PAYER_AT_CHEMO, PAYER_AT_RADIATION, PAYER_AT_SCT,
        PAYER_AT_LAST_CHEMO, PAYER_AT_LAST_RADIATION, PAYER_AT_LAST_SCT),
      rename_payer
    ),
    across(
      c(POST_TREATMENT_PAYER, POST_CHEMO_PAYER, POST_RAD_PAYER, POST_SCT_PAYER),
      ~ case_when(
          .x %in% c("Other", "Unavailable", "Unknown") ~ "Missing",
          TRUE ~ .x  # preserves NA as NA, preserves all other values
        )
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
  tbl <- bind_rows(rows)

  # Add totals row
  total_row <- list(`Payer Category` = "Total")
  for (spec in col_specs) {
    n_total <- sum(!is.na(data[[spec$col]]))
    total_row[[spec$label]] <- format_count_pct(n_total, total_n)
  }
  bind_rows(tbl, as_tibble(total_row))
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
  # Replace Total row to include N/A patients (so percentages sum to 100%)
  n_rows <- nrow(tbl)
  total_row <- list(`Payer Category` = "Total")
  for (spec in col_specs) {
    total_row[[spec$label]] <- format_count_pct(total_n, total_n)
  }

  bind_rows(tbl[1:(n_rows - 1), ], as_tibble(na_row), as_tibble(total_row))
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

  # Add No Payer Assigned row for patients without the payer assignment
  n_na_c <- sum(is.na(covers_data[[payer_col]]))
  n_na_g <- sum(is.na(gap_data[[payer_col]]))
  tbl <- bind_rows(tbl, tibble(
    `Payer Category` = "No Payer Assigned",
    `ENR Covers Window` = format_count_pct(n_na_c, n_covers),
    `ENR Does Not Cover` = format_count_pct(n_na_g, n_gap)
  ))

  # Add totals row
  bind_rows(tbl, tibble(
    `Payer Category` = "Total",
    `ENR Covers Window` = format_count_pct(n_covers, n_covers),
    `ENR Does Not Cover` = format_count_pct(n_gap, n_gap)
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

  # No Payer Assigned row
  tbl <- bind_rows(tbl, tibble(
    `Payer Category` = "No Payer Assigned",
    !!paste0("First ", first_label, " ENR Covers") :=
      format_count_pct(sum(is.na(fc[[first_payer_col]])), nrow(fc)),
    !!paste0("First ", first_label, " ENR Gap") :=
      format_count_pct(sum(is.na(fg[[first_payer_col]])), nrow(fg)),
    !!paste0("Last ", last_label, " ENR Covers") :=
      format_count_pct(sum(is.na(lc[[last_payer_col]])), nrow(lc)),
    !!paste0("Last ", last_label, " ENR Gap") :=
      format_count_pct(sum(is.na(lg[[last_payer_col]])), nrow(lg))
  ))

  # Totals row
  bind_rows(tbl, tibble(
    `Payer Category` = "Total",
    !!paste0("First ", first_label, " ENR Covers") :=
      format_count_pct(nrow(fc), nrow(fc)),
    !!paste0("First ", first_label, " ENR Gap") :=
      format_count_pct(nrow(fg), nrow(fg)),
    !!paste0("Last ", last_label, " ENR Covers") :=
      format_count_pct(nrow(lc), nrow(lc)),
    !!paste0("Last ", last_label, " ENR Gap") :=
      format_count_pct(nrow(lg), nrow(lg))
  ))
}

# ==============================================================================
# SECTION 4: FLEXTABLE STYLING
# ==============================================================================

style_table <- function(ft, total_row = integer(0)) {
  n_rows <- nrow_part(ft, "body")
  odd_rows <- seq(1, n_rows, by = 2)
  even_rows <- seq(2, n_rows, by = 2)

  ft <- ft %>%
    fontsize(size = 12, part = "body") %>%
    fontsize(size = 13, part = "header") %>%
    font(fontname = "Calibri", part = "all") %>%
    bold(part = "header") %>%
    bold(j = 1, part = "body") %>%
    bg(bg = UF_BLUE, part = "header") %>%
    color(color = "white", part = "header") %>%
    color(color = DARK_TEXT, part = "body") %>%
    align(align = "center", part = "header") %>%
    align(j = 1, align = "left", part = "body") %>%
    align(j = -1, align = "center", part = "body") %>%
    border_remove() %>%
    padding(padding.left = 6, padding.right = 6,
            padding.top = 3, padding.bottom = 3, part = "all")

  # Alternating row colors (light blue / light orange, matching Python)
  if (length(odd_rows) > 0) ft <- ft %>% bg(i = odd_rows, bg = LIGHT_BLUE, part = "body")
  if (length(even_rows) > 0) ft <- ft %>% bg(i = even_rows, bg = LIGHT_ORANGE, part = "body")

  # Bold the Total row with distinct styling
  if (length(total_row) > 0 && total_row[1] > 0) {
    ft <- ft %>%
      bold(i = total_row[1], part = "body") %>%
      bg(i = total_row[1], bg = UF_BLUE, part = "body") %>%
      color(i = total_row[1], color = "white", part = "body")
  }

  ft %>% autofit()
}

# ==============================================================================
# SECTION 5: BUILD PPTX SLIDES
# ==============================================================================

message("\n--- Building PowerPoint slides ---")

pptx <- read_pptx()

# Set 16:9 widescreen slide dimensions (matching Python pipeline: 10" x 5.625")
tryCatch({
  pres_node <- pptx$doc_obj$get()
  sld_sz <- xml2::xml_find_first(pres_node, "//p:sldSz", xml2::xml_ns(pres_node))
  xml2::xml_attr(sld_sz, "cx") <- "9144000"   # 10 inches * 914400 EMU/inch
  xml2::xml_attr(sld_sz, "cy") <- "5143500"    # 5.625 inches * 914400 EMU/inch
  message("  Set slide dimensions to 16:9 widescreen (10\" x 5.625\")")
}, error = function(e) {
  message(glue("  Note: Using default slide dimensions ({e$message})"))
})

# Helper to add a slide with title, subtitle, and table
add_table_slide <- function(pptx, title, subtitle, tbl_data) {
  # Find Total row index (if any) for bold styling
  total_row_idx <- which(tbl_data[[1]] == "Total")
  ft <- flextable(tbl_data) %>% style_table(total_row = total_row_idx)

  # Set column widths (Payer Category = 2.2", rest evenly distributed)
  n_cols <- ncol(tbl_data)
  if (n_cols > 1) {
    payer_width <- 2.2
    data_col_width <- (9.0 - payer_width) / (n_cols - 1)
    ft <- ft %>%
      width(j = 1, width = payer_width) %>%
      width(j = 2:n_cols, width = data_col_width)
  }

  pptx <- pptx %>%
    add_slide(layout = "Blank") %>%
    ph_with(
      value = fpar(ftext(title, prop = fp_text(font.size = 26, bold = TRUE,
                                                font.family = "Calibri",
                                                color = UF_BLUE))),
      location = ph_location(left = 0.5, top = 0.2, width = 9, height = 0.6)
    ) %>%
    ph_with(
      value = fpar(ftext(subtitle, prop = fp_text(font.size = 14, italic = TRUE,
                                                   font.family = "Calibri",
                                                   color = DARK_TEXT))),
      location = ph_location(left = 0.5, top = 0.85, width = 9, height = 0.4)
    ) %>%
    ph_with(
      value = ft,
      location = ph_location(left = 0.5, top = 1.4, width = 9, height = 5.0)
    )

  pptx
}

# Helper to add a slide with title, subtitle, and a centered PNG figure
add_image_slide <- function(pptx, title, subtitle, img_path,
                             img_width = 8.5, img_height = 5.0) {
  if (!file.exists(img_path)) {
    message(glue("  SKIPPED: {title} -- {img_path} not found. Run 16_encounter_analysis.R first."))
    return(pptx)
  }
  pptx %>%
    add_slide(layout = "Blank") %>%
    ph_with(
      value = fpar(ftext(title, prop = fp_text(font.size = 26, bold = TRUE,
                                               font.family = "Calibri", color = UF_BLUE))),
      location = ph_location(left = 0.5, top = 0.2, width = 9, height = 0.6)
    ) %>%
    ph_with(
      value = fpar(ftext(subtitle, prop = fp_text(font.size = 14, italic = TRUE,
                                                  font.family = "Calibri", color = DARK_TEXT))),
      location = ph_location(left = 0.5, top = 0.85, width = 9, height = 0.4)
    ) %>%
    ph_with(
      value = external_img(img_path, width = img_width, height = img_height),
      location = ph_location(left = (10 - img_width) / 2, top = 1.4,
                              width = img_width, height = img_height)
    )
}

# Footnote text formatting (10pt italic gray at bottom of slide)
footnote_prop <- fp_text(font.size = 10, italic = TRUE, font.family = "Calibri", color = "#666666")
footnote_location <- ph_location(left = 0.5, top = 6.9, width = 9, height = 0.5)

# Helper to add a footnote to the current (last-added) slide
add_footnote <- function(pptx, text) {
  pptx %>%
    ph_with(
      value = fpar(ftext(text, prop = footnote_prop)),
      location = footnote_location
    )
}

# ---- Counts for title slide ----
N_TOTAL <- nrow(cohort_full)
N_CHEMO <- sum(cohort_full$HAD_CHEMO == 1)
N_RAD <- sum(cohort_full$HAD_RADIATION == 1)
N_SCT <- sum(cohort_full$HAD_SCT == 1)

# ---- Slide 1: Definitions & Glossary ----
message("  Slide 1: Definitions & Glossary")

pptx <- pptx %>%
  add_slide(layout = "Blank") %>%
  ph_with(
    value = fpar(ftext("Definitions and Glossary",
                       prop = fp_text(font.size = 28, bold = TRUE,
                                      font.family = "Calibri", color = UF_BLUE))),
    location = ph_location(left = 0.5, top = 0.2, width = 9, height = 0.6)
  ) %>%
  ph_with(
    value = block_list(
      fpar(ftext("Primary Insurance: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Most prevalent payer across all encounters for the patient.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext("First Diagnosis: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Payer mode within \u00b130 days of first HL diagnosis date.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext("First Chemo / Radiation / SCT: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Payer mode within \u00b130 day window of first treatment date for that treatment type.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext("Last Chemo / Radiation / SCT: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Payer mode within \u00b130 day window of last treatment date for that treatment type.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext("Post-Treatment Insurance: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Most prevalent payer after last treatment of any type.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext(" ", prop = fp_text(font.size = 10))),
      fpar(ftext("Missing: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Consolidation of Unknown, Unavailable, Other, and No Information payer categories.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext("No Payer Assigned: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("No encounter with valid payer data found in the \u00b130 day window around the relevant date.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext("N/A (No Follow-up): ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Last treatment encounter was the patient's final encounter in the dataset (\u00b130 days).", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext("N/A (No Treatment): ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Patient had no recorded treatment of that type.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext(" ", prop = fp_text(font.size = 10))),
      fpar(ftext("ENR Covers Window: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Patient has enrollment records spanning the full \u00b130 day window around the event date.", prop = fp_text(font.size = 14, font.family = "Calibri"))),
      fpar(ftext("ENR Does Not Cover: ", prop = fp_text(bold = TRUE, font.size = 14, font.family = "Calibri")),
           ftext("Patient's enrollment records do not fully cover the \u00b130 day window.", prop = fp_text(font.size = 14, font.family = "Calibri")))
    ),
    location = ph_location(left = 0.5, top = 1.1, width = 9, height = 5.5)
  ) %>%
  ph_with(
    value = fpar(ftext(glue("Hodgkin Lymphoma Cohort -- N = {format(N_TOTAL, big.mark = ',')} | Chemo: {format(N_CHEMO, big.mark = ',')} | Radiation: {format(N_RAD, big.mark = ',')} | SCT: {format(N_SCT, big.mark = ',')}"),
                       prop = fp_text(font.size = 11, italic = TRUE,
                                      font.family = "Calibri", color = "#666666"))),
    location = ph_location(left = 0.5, top = 6.9, width = 9, height = 0.5)
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
  tbl2) %>%
  add_footnote("Primary Insurance = most prevalent payer across all encounters. First Diagnosis = payer mode within \u00b130 days of first HL diagnosis date.")

# ---- Slide 3: Post-Treatment Insurance (all patients) ----
message("  Slide 3: Post-Treatment Insurance")
tbl3 <- build_payer_table_with_na(cohort_full, list(
  list(col = "POST_TREATMENT_PAYER", label = "Post-Treatment Insurance")
), na_label = "N/A (No Follow-up)")
pptx <- add_table_slide(pptx,
  "Post-Treatment Insurance \u2014 All Patients",
  glue("Most prevalent payer after last treatment \u2014 N = {format(N_TOTAL, big.mark = ',')}"),
  tbl3) %>%
  add_footnote("Post-Treatment Insurance = most prevalent payer after last treatment of any type. N/A (No Follow-up) = last treatment was patient's final encounter (\u00b130 days).")

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
  tbl4) %>%
  add_footnote("Primary Insurance = most prevalent payer across all encounters. First/Last Chemo = payer mode within \u00b130 days of first/last chemotherapy date.")

# ---- Slide 5: Chemotherapy Post-Treatment Insurance ----
message("  Slide 5: Chemo Post-Treatment Insurance")
tbl5 <- build_payer_table_with_na(chemo_patients, list(
  list(col = "POST_CHEMO_PAYER", label = "Post-Treatment Insurance")
), na_label = "N/A (No Follow-up)")
pptx <- add_table_slide(pptx,
  "Chemotherapy Post-Treatment Insurance",
  glue("Most prevalent payer after last chemotherapy \u2014 N = {format(N_CHEMO, big.mark = ',')}"),
  tbl5) %>%
  add_footnote("Post-Treatment Insurance = most prevalent payer after last chemotherapy. N/A (No Follow-up) = last chemo was patient's final encounter (\u00b130 days).")

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
  tbl6) %>%
  add_footnote("Primary Insurance = most prevalent payer across all encounters. First/Last Radiation = payer mode within \u00b130 days of first/last radiation date.")

# ---- Slide 7: Radiation Post-Treatment Insurance ----
message("  Slide 7: Radiation Post-Treatment Insurance")
tbl7 <- build_payer_table_with_na(rad_patients, list(
  list(col = "POST_RAD_PAYER", label = "Post-Treatment Insurance")
), na_label = "N/A (No Follow-up)")
pptx <- add_table_slide(pptx,
  "Radiation Post-Treatment Insurance",
  glue("Most prevalent payer after last radiation \u2014 N = {format(N_RAD, big.mark = ',')}"),
  tbl7) %>%
  add_footnote("Post-Treatment Insurance = most prevalent payer after last radiation. N/A (No Follow-up) = last radiation was patient's final encounter (\u00b130 days).")

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
  tbl8) %>%
  add_footnote("Primary Insurance = most prevalent payer across all encounters. First/Last SCT = payer mode within \u00b130 days of first/last stem cell transplant date.")

# ---- Slide 9: SCT Post-Treatment Insurance ----
message("  Slide 9: SCT Post-Treatment Insurance")
tbl9 <- build_payer_table_with_na(sct_patients, list(
  list(col = "POST_SCT_PAYER", label = "Post-Treatment Insurance")
), na_label = "N/A (No Follow-up)")
pptx <- add_table_slide(pptx,
  "SCT Post-Treatment Insurance",
  glue("Most prevalent payer after last SCT \u2014 N = {format(N_SCT, big.mark = ',')}"),
  tbl9) %>%
  add_footnote("Post-Treatment Insurance = most prevalent payer after last SCT. N/A (No Follow-up) = last SCT was patient's final encounter (\u00b130 days).")

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
  tbl10) %>%
  add_footnote("ENR Covers Window = enrollment records span the full \u00b130 day window around first HL diagnosis. ENR Does Not Cover = enrollment gap in that window.")

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
  tbl11) %>%
  add_footnote("ENR Covers = enrollment records span the full \u00b130 day window around first/last chemotherapy. ENR Gap = enrollment gap in that window.")

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
  tbl12) %>%
  add_footnote("ENR Covers = enrollment records span the full \u00b130 day window around first/last radiation. ENR Gap = enrollment gap in that window.")

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
  tbl13) %>%
  add_footnote("ENR Covers = enrollment records span the full \u00b130 day window around first/last SCT. ENR Gap = enrollment gap in that window.")

# ---- Slide 14: Last Treatment = Last Encounter (±30 day window) ----
message("  Slide 14: Last Treatment = Last Encounter")

# Reuse last_encounter_per_patient computed in section 2c
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
  tbl14) %>%
  add_footnote("Last Tx = Last Encounter: patient's last treatment date is within \u00b130 days of their last encounter date in the dataset.")

# ---- Slide 15: Missing Post-Treatment Payer - Encounter Breakdown ----
message("  Slide 15: Missing Post-Treatment Encounter Breakdown")

# Patients with Missing or NA post-treatment payer: how many encounters after last treatment?
unknown_post <- cohort_full %>%
  filter(!is.na(LAST_ANY_TREATMENT_DATE)) %>%
  filter(is.na(POST_TREATMENT_PAYER) | POST_TREATMENT_PAYER == "Missing")

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
  select(`Payer Category` = bin, `N Patients`) %>%
  bind_rows(tibble(`Payer Category` = "Total", `N Patients` = format_count_pct(n_unknown, n_unknown)))

pptx <- add_table_slide(pptx,
  "Missing Post-Treatment Payer \u2014 Encounter Breakdown",
  glue("Patients with Missing post-treatment payer: how many encounters exist after last treatment?"),
  tbl15) %>%
  add_footnote("Shows how many post-treatment encounters exist for patients whose post-treatment payer is Missing or unassigned.")

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
    # POST_TREATMENT_PAYER: preserve NA so the "No Payer Assigned" row logic works
    POST_TREATMENT_PAYER = case_when(
      POST_TREATMENT_PAYER %in% c("Other", "Unavailable", "Unknown") ~ "Missing",
      TRUE ~ POST_TREATMENT_PAYER
    ),
    PAYER_AT_LAST_TX = rename_payer(PAYER_AT_LAST_TX)
  )

n_treated <- nrow(tx_retention)
n_still_in <- sum(tx_retention$has_post_encounter)
n_missing <- n_treated - n_still_in

still_data <- tx_retention %>% filter(has_post_encounter)
missing_data <- tx_retention %>% filter(!has_post_encounter)

message(glue("  Treated: {n_treated} | Still in dataset: {n_still_in} | Missing: {n_missing}"))

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

# Add No Payer Assigned row (no payer matched in window)
n_na_s <- sum(is.na(still_data$POST_TREATMENT_PAYER))
n_na_m <- sum(is.na(missing_data$PAYER_AT_LAST_TX))
tbl16 <- bind_rows(tbl16, tibble(
  `Payer Category` = "No Payer Assigned",
  !!still_col := if (n_still_in > 0) format_count_pct(n_na_s, n_still_in) else "0 (0.0%)",
  !!missing_col := if (n_missing > 0) format_count_pct(n_na_m, n_missing) else "0 (0.0%)"
))

# Add totals row for treated patients
tbl16 <- bind_rows(tbl16, tibble(
  `Payer Category` = "Total",
  !!still_col := if (n_still_in > 0) format_count_pct(n_still_in, n_still_in) else "0 (0.0%)",
  !!missing_col := if (n_missing > 0) format_count_pct(n_missing, n_missing) else "0 (0.0%)"
))

pct_still <- if (n_treated > 0) round(100 * n_still_in / n_treated, 1) else 0
pct_missing <- if (n_treated > 0) round(100 * n_missing / n_treated, 1) else 0

pptx <- add_table_slide(pptx,
  "Insurance After Last Treatment \u2014 Dataset Retention",
  glue("{format(n_treated, big.mark=',')} treated patients: {format(n_still_in, big.mark=',')} ({pct_still}%) still in dataset, {format(n_missing, big.mark=',')} ({pct_missing}%) no longer in dataset"),
  tbl16) %>%
  add_footnote("Still in Dataset = patient has encounters after last treatment. No Longer in Dataset = last treatment was final encounter (\u00b130 days). Payer shown is post-treatment (still) or at last treatment (no longer).")

# ==============================================================================
# SECTION 5b: ENCOUNTER ANALYSIS SLIDES (from 16_encounter_analysis.R figures)
# ==============================================================================

# Regenerate encounter analysis PNGs to ensure they reflect current cohort data.
# Without this, stale PNGs from a previous run get embedded in the pptx.
message("\n--- Regenerating encounter analysis figures ---")
source("R/16_encounter_analysis.R")

message("\n--- Encounter Analysis Slides ---")

# ---- Slide 17: Encounter histogram by payor ----
message("  Slide 17: Encounters per Person by Payer Category")
enc_hist_path <- "output/figures/encounters_per_person_by_payor.png"
pptx <- add_image_slide(pptx,
  "Encounters per Person by Payer Category",
  glue("Distribution of total encounter counts by primary payer -- N = {format(N_TOTAL, big.mark=',')}"),
  enc_hist_path
)
if (file.exists(enc_hist_path)) {
  pptx <- add_footnote(pptx, "Primary Insurance = most prevalent payer across all encounters. Payer categories consolidated to 6 + Missing.")
}

# ---- Slide 18 (new): Summary Statistics -- Encounters per Person by Payer ----
message("  Slide 18: Summary Statistics -- Encounters per Payer")

summary_stats <- cohort_full %>%
  filter(!is.na(N_ENCOUNTERS)) %>%
  mutate(PAYER_DISPLAY = rename_payer(PAYER_CATEGORY_PRIMARY)) %>%
  filter(!is.na(PAYER_DISPLAY)) %>%
  group_by(PAYER_DISPLAY) %>%
  summarise(
    N = n(),
    Mean = round(mean(N_ENCOUNTERS, na.rm = TRUE), 1),
    Median = round(median(N_ENCOUNTERS, na.rm = TRUE), 1),
    Min = min(N_ENCOUNTERS, na.rm = TRUE),
    Q1 = round(quantile(N_ENCOUNTERS, 0.25, na.rm = TRUE), 1),
    Q3 = round(quantile(N_ENCOUNTERS, 0.75, na.rm = TRUE), 1),
    Max = max(N_ENCOUNTERS, na.rm = TRUE),
    `500+` = sum(N_ENCOUNTERS > 500, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  rename(`Payer Category` = PAYER_DISPLAY)

# Add totals row
summary_totals <- cohort_full %>%
  filter(!is.na(N_ENCOUNTERS), !is.na(PAYER_CATEGORY_PRIMARY)) %>%
  summarise(
    `Payer Category` = "Total",
    N = n(),
    Mean = round(mean(N_ENCOUNTERS, na.rm = TRUE), 1),
    Median = round(median(N_ENCOUNTERS, na.rm = TRUE), 1),
    Min = min(N_ENCOUNTERS, na.rm = TRUE),
    Q1 = round(quantile(N_ENCOUNTERS, 0.25, na.rm = TRUE), 1),
    Q3 = round(quantile(N_ENCOUNTERS, 0.75, na.rm = TRUE), 1),
    Max = max(N_ENCOUNTERS, na.rm = TRUE),
    `500+` = sum(N_ENCOUNTERS > 500, na.rm = TRUE)
  )

summary_stats <- bind_rows(summary_stats, summary_totals)

# Format N with commas for display
summary_stats <- summary_stats %>%
  mutate(N = format(N, big.mark = ","))

pptx <- add_table_slide(pptx,
  "Summary Statistics: Encounters per Person by Payer Category",
  glue("Distribution of total encounter counts by primary insurance category -- N = {format(N_TOTAL, big.mark = ',')}"),
  summary_stats) %>%
  add_footnote("Primary Insurance = most prevalent payer across all encounters. 500+ = patients with more than 500 total encounters.")

# Count patients with missing DX_YEAR (includes nullified 1900 sentinels) for footnote
n_missing_dx_year <- sum(is.na(cohort_full$DX_YEAR))
masked_footnote <- if (n_missing_dx_year > 0) {
  glue("{n_missing_dx_year} patients with missing diagnosis date excluded from this analysis.")
} else {
  ""
}

# ---- Slide 19: Post-treatment encounters by DX year ----
message("  Slide 19: Post-Treatment Encounters by DX Year")
post_tx_dx_path <- "output/figures/post_tx_encounters_by_dx_year.png"
pptx <- add_image_slide(pptx,
  "Mean Post-Treatment Encounters by Year of Diagnosis",
  "Non-acute care encounters per person after last treatment, stratified by HL diagnosis year",
  post_tx_dx_path
)
if (file.exists(post_tx_dx_path) && nchar(masked_footnote) > 0) {
  pptx <- add_footnote(pptx, masked_footnote)
}

# ---- Slide 20: Total encounters by DX year ----
message("  Slide 20: Total Encounters by DX Year")
total_enc_dx_path <- "output/figures/total_encounters_by_dx_year.png"
pptx <- add_image_slide(pptx,
  "Mean Total Encounters by Year of Diagnosis",
  "All encounters per person across the full observation window, stratified by HL diagnosis year",
  total_enc_dx_path
)
if (file.exists(total_enc_dx_path) && nchar(masked_footnote) > 0) {
  pptx <- add_footnote(pptx, masked_footnote)
}

# ---- Slide 21: Post-treatment encounters by age group ----
message("  Slide 21: Post-Treatment Encounters by Age Group")
age_group_path <- "output/figures/post_tx_by_age_group.png"
pptx <- add_image_slide(pptx,
  "Post-Treatment Encounter Presence by Age Group at Diagnosis",
  "Proportion with any post-treatment encounter by age group (0-17, 18-39, 40-64, 65+)",
  age_group_path
)
if (file.exists(age_group_path)) {
  pptx <- add_footnote(pptx, "Age group determined at date of first HL diagnosis. Post-treatment = any encounter after last treatment of any type.")
}

# ==============================================================================
# SECTION 5c: UNIQUE DATES SLIDES (distinct encounter dates per patient)
# ==============================================================================

message("\n--- Unique Dates Slides ---")

# Compute unique encounter dates per patient from the encounters table
unique_dates_total <- encounters %>%
  filter(!is.na(ADMIT_DATE)) %>%
  group_by(ID) %>%
  summarise(N_UNIQUE_DATES = n_distinct(ADMIT_DATE), .groups = "drop")

# Compute unique post-treatment dates (AV+TH post-diagnosis, mirrors Level 1)
first_dx_map <- cohort_full %>%
  select(ID, first_hl_dx_date) %>%
  filter(!is.na(first_hl_dx_date))

unique_dates_post_tx <- pcornet$ENCOUNTER %>%
  filter(ENC_TYPE %in% c("AV", "TH")) %>%
  inner_join(first_dx_map, by = "ID") %>%
  filter(!is.na(ADMIT_DATE), ADMIT_DATE > first_hl_dx_date) %>%
  group_by(ID) %>%
  summarise(N_UNIQUE_DATES_POST_TX = n_distinct(ADMIT_DATE), .groups = "drop")

cohort_ud <- cohort_full %>%
  left_join(unique_dates_total, by = "ID") %>%
  left_join(unique_dates_post_tx, by = "ID") %>%
  mutate(
    N_UNIQUE_DATES = coalesce(N_UNIQUE_DATES, 0L),
    N_UNIQUE_DATES_POST_TX = coalesce(N_UNIQUE_DATES_POST_TX, 0L)
  )

# ---- Slide 22: Unique dates histogram by payor ----
message("  Slide 22: Unique Dates per Person by Payer Category")
ud_hist_path <- "output/figures/unique_dates_per_person_by_payor.png"
pptx <- add_image_slide(pptx,
  "Unique Encounter Dates per Person by Payer Category",
  glue("Distribution of distinct encounter dates by primary payer -- N = {format(N_TOTAL, big.mark=',')}"),
  ud_hist_path
)
if (file.exists(ud_hist_path)) {
  pptx <- add_footnote(pptx, "Unique dates = distinct ADMIT_DATEs per patient. Multiple encounters on the same day count as one date.")
}

# ---- Slide 23: Summary Statistics -- Unique Dates per Person by Payer ----
message("  Slide 23: Summary Statistics -- Unique Dates per Payer")

ud_summary_stats <- cohort_ud %>%
  filter(!is.na(N_UNIQUE_DATES)) %>%
  mutate(PAYER_DISPLAY = rename_payer(PAYER_CATEGORY_PRIMARY)) %>%
  filter(!is.na(PAYER_DISPLAY)) %>%
  group_by(PAYER_DISPLAY) %>%
  summarise(
    N = n(),
    Mean = round(mean(N_UNIQUE_DATES, na.rm = TRUE), 1),
    Median = round(median(N_UNIQUE_DATES, na.rm = TRUE), 1),
    Min = min(N_UNIQUE_DATES, na.rm = TRUE),
    Q1 = round(quantile(N_UNIQUE_DATES, 0.25, na.rm = TRUE), 1),
    Q3 = round(quantile(N_UNIQUE_DATES, 0.75, na.rm = TRUE), 1),
    Max = max(N_UNIQUE_DATES, na.rm = TRUE),
    `300+` = sum(N_UNIQUE_DATES > 300, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  rename(`Payer Category` = PAYER_DISPLAY)

ud_summary_totals <- cohort_ud %>%
  filter(!is.na(N_UNIQUE_DATES), !is.na(PAYER_CATEGORY_PRIMARY)) %>%
  summarise(
    `Payer Category` = "Total",
    N = n(),
    Mean = round(mean(N_UNIQUE_DATES, na.rm = TRUE), 1),
    Median = round(median(N_UNIQUE_DATES, na.rm = TRUE), 1),
    Min = min(N_UNIQUE_DATES, na.rm = TRUE),
    Q1 = round(quantile(N_UNIQUE_DATES, 0.25, na.rm = TRUE), 1),
    Q3 = round(quantile(N_UNIQUE_DATES, 0.75, na.rm = TRUE), 1),
    Max = max(N_UNIQUE_DATES, na.rm = TRUE),
    `300+` = sum(N_UNIQUE_DATES > 300, na.rm = TRUE)
  )

ud_summary_stats <- bind_rows(ud_summary_stats, ud_summary_totals) %>%
  mutate(N = format(N, big.mark = ","))

pptx <- add_table_slide(pptx,
  "Summary Statistics: Unique Dates per Person by Payer Category",
  glue("Distribution of distinct encounter dates by primary insurance category -- N = {format(N_TOTAL, big.mark = ',')}"),
  ud_summary_stats) %>%
  add_footnote("Unique dates = distinct ADMIT_DATEs per patient. 300+ = patients with more than 300 unique encounter dates.")

# ---- Slide 24: Post-treatment unique dates by DX year ----
message("  Slide 24: Post-Treatment Unique Dates by DX Year")
post_tx_ud_path <- "output/figures/post_tx_unique_dates_by_dx_year.png"
pptx <- add_image_slide(pptx,
  "Mean Post-Treatment Unique Dates by Year of Diagnosis",
  "Distinct encounter dates per person after last treatment, stratified by HL diagnosis year",
  post_tx_ud_path
)
if (file.exists(post_tx_ud_path) && nchar(masked_footnote) > 0) {
  pptx <- add_footnote(pptx, masked_footnote)
}

# ---- Slide 25: Total unique dates by DX year ----
message("  Slide 25: Total Unique Dates by DX Year")
total_ud_dx_path <- "output/figures/total_unique_dates_by_dx_year.png"
pptx <- add_image_slide(pptx,
  "Mean Total Unique Dates by Year of Diagnosis",
  "Distinct encounter dates per person across the full observation window, stratified by HL diagnosis year",
  total_ud_dx_path
)
if (file.exists(total_ud_dx_path) && nchar(masked_footnote) > 0) {
  pptx <- add_footnote(pptx, masked_footnote)
}

# ==============================================================================
# SECTION 6: SAVE PPTX
# ==============================================================================

output_filename <- glue("insurance_tables_{Sys.Date()}.pptx")
output_path <- file.path(output_filename)
print(pptx, target = output_path)

message(glue("\n  PowerPoint saved to: {output_path}"))
message(glue("  Slides: 25 (1 glossary + 16 tables + 4 encounter analysis + 4 unique dates)"))
message(glue("  Cohort: {format(N_TOTAL, big.mark = ',')} patients"))
message(glue("  Date: {Sys.Date()}"))

message("\n", strrep("=", 60))
message("PowerPoint generation complete")
message(strrep("=", 60))

# ==============================================================================
# End of 11_generate_pptx.R
# ==============================================================================
