# ==============================================================================
# 76_treatment_source_coverage.R -- Treatment Source Coverage Analysis
# ==============================================================================
# Purpose: Quantify tumor registry (TR) treatment coverage before removal (Phase 76).
#          Produces per-treatment-type breakdown of TR-only, claims-only, and
#          dual-source treatment dates to assess data loss risk from TR removal.
#
# Inputs:  PCORnet tables (TUMOR_REGISTRY_ALL, PROCEDURES, PRESCRIBING,
#          DIAGNOSIS, ENCOUNTER, DISPENSING, MED_ADMIN) via R/01_load_pcornet.R
#
# Outputs: output/source_coverage_analysis.csv
#          output/source_coverage_analysis.xlsx
#
# Dependencies: R/00_config.R, R/01_load_pcornet.R
#
# Requirements: TREAT-01 (Phase 76 -- pre-removal coverage analysis)
#
# Decision traceability:
#   D-76-COV-01: Coverage analysis runs BEFORE TR source removal
#   D-76-COV-02: Uses dplyr anti_join/semi_join for set operations (per RESEARCH.md)
#   D-76-COV-03: Output format matches openxlsx2 audit pattern from R/26
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND CONFIGURATION ----
# ==============================================================================
# WHY: Load required packages and project configuration. tidyr needed for
# pivot_longer in TR date extraction. openxlsx2 for multi-sheet styled output.
# checkmate for runtime assertion of output completeness.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(glue)
  library(openxlsx2)
  library(checkmate)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

# Output paths
COVERAGE_CSV <- file.path(CONFIG$output_dir, "source_coverage_analysis.csv")
COVERAGE_XLSX <- file.path(CONFIG$output_dir, "source_coverage_analysis.xlsx")


# ==============================================================================
# SECTION 2: TR DATE EXTRACTION HELPERS ----
# ==============================================================================
# WHY: Extract tumor registry dates separately from claims dates so we can
# quantify overlap. These mirror the TR blocks in R/26_treatment_episodes.R
# (chemo lines 195-223, radiation lines 277-305, SCT lines 341-372) but return
# only (ID, treatment_date) for set-operation comparison.

#' Extract TR dates for chemotherapy
#' @return tibble with columns ID, treatment_date (distinct pairs)
extract_tr_chemo_dates <- function() {
  if (is.null(get_pcornet_table("TUMOR_REGISTRY_ALL"))) {
    return(tibble(ID = character(0), treatment_date = as.Date(character(0))))
  }

  tr_chemo_cols <- intersect(
    c("CHEMO_START_DATE_SUMMARY", "DT_CHEMO"),
    colnames(get_pcornet_table("TUMOR_REGISTRY_ALL"))
  )

  if (length(tr_chemo_cols) == 0) {
    return(tibble(ID = character(0), treatment_date = as.Date(character(0))))
  }

  tr_data <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
    select(ID, all_of(tr_chemo_cols)) %>%
    collect() %>%
    filter(if_any(all_of(tr_chemo_cols), ~ !is.na(.)))

  if (nrow(tr_data) == 0) {
    return(tibble(ID = character(0), treatment_date = as.Date(character(0))))
  }

  tr_data %>%
    pivot_longer(
      cols = all_of(tr_chemo_cols),
      names_to = "date_source",
      values_to = "treatment_date"
    ) %>%
    filter(!is.na(treatment_date)) %>%
    mutate(treatment_date = as.Date(treatment_date)) %>%
    distinct(ID, treatment_date)
}

#' Extract TR dates for radiation
#' @return tibble with columns ID, treatment_date (distinct pairs)
extract_tr_radiation_dates <- function() {
  if (is.null(get_pcornet_table("TUMOR_REGISTRY_ALL"))) {
    return(tibble(ID = character(0), treatment_date = as.Date(character(0))))
  }

  tr_rad_cols <- intersect(
    c("RAD_START_DATE_SUMMARY", "DT_RAD"),
    colnames(get_pcornet_table("TUMOR_REGISTRY_ALL"))
  )

  if (length(tr_rad_cols) == 0) {
    return(tibble(ID = character(0), treatment_date = as.Date(character(0))))
  }

  tr_data <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
    select(ID, all_of(tr_rad_cols)) %>%
    collect() %>%
    filter(if_any(all_of(tr_rad_cols), ~ !is.na(.)))

  if (nrow(tr_data) == 0) {
    return(tibble(ID = character(0), treatment_date = as.Date(character(0))))
  }

  tr_data %>%
    pivot_longer(
      cols = all_of(tr_rad_cols),
      names_to = "date_source",
      values_to = "treatment_date"
    ) %>%
    filter(!is.na(treatment_date)) %>%
    mutate(treatment_date = as.Date(treatment_date)) %>%
    distinct(ID, treatment_date)
}

#' Extract TR dates for SCT
#' @return tibble with columns ID, treatment_date (distinct pairs)
extract_tr_sct_dates <- function() {
  if (is.null(get_pcornet_table("TUMOR_REGISTRY_ALL"))) {
    return(tibble(ID = character(0), treatment_date = as.Date(character(0))))
  }

  tr_sct_cols <- intersect(
    c(
      "DT_HTE", "DT_SCT", "SCT_DATE", "BMT_DATE",
      "TRANSPLANT_DATE", "HCT_DATE", "DT_TRANSPLANT"
    ),
    colnames(get_pcornet_table("TUMOR_REGISTRY_ALL"))
  )

  if (length(tr_sct_cols) == 0) {
    return(tibble(ID = character(0), treatment_date = as.Date(character(0))))
  }

  tr_data <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
    select(ID, all_of(tr_sct_cols)) %>%
    collect() %>%
    filter(if_any(all_of(tr_sct_cols), ~ !is.na(.)))

  if (nrow(tr_data) == 0) {
    return(tibble(ID = character(0), treatment_date = as.Date(character(0))))
  }

  tr_data %>%
    pivot_longer(
      cols = all_of(tr_sct_cols),
      names_to = "date_source",
      values_to = "treatment_date"
    ) %>%
    filter(!is.na(treatment_date)) %>%
    mutate(treatment_date = as.Date(treatment_date)) %>%
    distinct(ID, treatment_date)
}


# ==============================================================================
# SECTION 3: CLAIMS DATE EXTRACTION HELPERS ----
# ==============================================================================
# WHY: Extract claims-only dates (excluding TR) for each treatment type. Reuses
# the SAME extraction logic as R/26's functions but WITHOUT the TR block.
# Each function stacks all non-TR sources and deduplicates to (ID, treatment_date).

#' Extract claims-only dates for chemotherapy (PX, RX, DX, DRG, DISP, MA)
#' @return tibble with columns ID, treatment_date (distinct pairs)
extract_claims_chemo_dates <- function() {
  chemo_icd10pcs_rx <- paste0(
    "^(", paste(TREATMENT_CODES$chemo_icd10pcs_prefixes, collapse = "|"), ")"
  )
  sources <- list()

  # 1. PROCEDURES: CPT/HCPCS, ICD-9-CM, ICD-10-PCS, revenue
  if (!is.null(get_pcornet_table("PROCEDURES"))) {
    sources$PX <- get_pcornet_table("PROCEDURES") %>%
      filter(
        (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
          (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
          (PX_TYPE == "10" & str_detect(PX, chemo_icd10pcs_rx)) |
          (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue)
      ) %>%
      filter(!is.na(PX_DATE)) %>%
      select(ID, treatment_date = PX_DATE) %>%
      collect()
  }

  # 2. PRESCRIBING: RXNORM_CUI
  if (!is.null(get_pcornet_table("PRESCRIBING")) &&
    "RXNORM_CUI" %in% colnames(get_pcornet_table("PRESCRIBING"))) {
    sources$RX <- get_pcornet_table("PRESCRIBING") %>%
      filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
      mutate(treatment_date = coalesce(RX_ORDER_DATE, RX_START_DATE)) %>%
      filter(!is.na(treatment_date)) %>%
      select(ID, treatment_date) %>%
      collect()
  }

  # 3. DIAGNOSIS: Z51.11/Z51.12 (ICD-10), V58.11/V58.12 (ICD-9)
  if (!is.null(get_pcornet_table("DIAGNOSIS"))) {
    sources$DX <- get_pcornet_table("DIAGNOSIS") %>%
      filter(
        (DX_TYPE == "10" & DX %in% TREATMENT_CODES$chemo_dx_icd10) |
          (DX_TYPE == "09" & DX %in% TREATMENT_CODES$chemo_dx_icd9)
      ) %>%
      filter(!is.na(DX_DATE)) %>%
      select(ID, treatment_date = DX_DATE) %>%
      collect()
  }

  # 4. ENCOUNTER: chemo DRGs
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    sources$DRG <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$chemo_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      select(ID, treatment_date = ADMIT_DATE) %>%
      collect()
  }

  # 5. DISPENSING: NDC->RxNorm crosswalk (D-12 revised Phase 122: NDC->RxNorm crosswalk used)
  ndc_crosswalk_76 <- load_ndc_crosswalk()
  disp_hits_76 <- get_chemo_hits("DISPENSING", TREATMENT_CODES$chemo_rxnorm, ndc_crosswalk_76)
  if (!is.null(disp_hits_76)) {
    sources$DISP <- disp_hits_76 %>% select(ID, treatment_date)
  }

  # 6. MED_ADMIN: MEDADMIN_CODE+MEDADMIN_TYPE (D-12 revised Phase 122: RX-typed=RxNorm CUI, ND-typed=NDC via crosswalk)
  ma_hits_76 <- get_chemo_hits("MED_ADMIN", TREATMENT_CODES$chemo_rxnorm, ndc_crosswalk_76)
  if (!is.null(ma_hits_76)) {
    sources$MA <- ma_hits_76 %>% select(ID, treatment_date)
  }

  # Stack and deduplicate
  non_null <- purrr::compact(sources)
  if (length(non_null) == 0) {
    return(tibble(ID = character(0), treatment_date = as.Date(character(0))))
  }
  bind_rows(non_null) %>%
    mutate(treatment_date = as.Date(treatment_date)) %>%
    filter(!is.na(treatment_date)) %>%
    distinct(ID, treatment_date)
}

#' Extract claims-only dates for radiation (PX, DX, DRG)
#' @return tibble with columns ID, treatment_date (distinct pairs)
extract_claims_radiation_dates <- function() {
  rad_icd10pcs_rx <- paste0(
    "^(", paste(TREATMENT_CODES$radiation_icd10pcs_prefixes, collapse = "|"), ")"
  )
  sources <- list()

  # 1. PROCEDURES: CPT, ICD-9-CM, ICD-10-PCS, revenue
  if (!is.null(get_pcornet_table("PROCEDURES"))) {
    sources$PX <- get_pcornet_table("PROCEDURES") %>%
      filter(
        (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) |
          (PX_TYPE == "09" & PX %in% TREATMENT_CODES$radiation_icd9) |
          (PX_TYPE == "10" & str_detect(PX, rad_icd10pcs_rx)) |
          (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$radiation_revenue)
      ) %>%
      filter(!is.na(PX_DATE)) %>%
      select(ID, treatment_date = PX_DATE) %>%
      collect()
  }

  # 2. DIAGNOSIS: Z51.0 (ICD-10), V58.0 (ICD-9)
  if (!is.null(get_pcornet_table("DIAGNOSIS"))) {
    sources$DX <- get_pcornet_table("DIAGNOSIS") %>%
      filter(
        (DX_TYPE == "10" & DX %in% TREATMENT_CODES$radiation_dx_icd10) |
          (DX_TYPE == "09" & DX %in% TREATMENT_CODES$radiation_dx_icd9)
      ) %>%
      filter(!is.na(DX_DATE)) %>%
      select(ID, treatment_date = DX_DATE) %>%
      collect()
  }

  # 3. ENCOUNTER: DRG 849
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    sources$DRG <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$radiation_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      select(ID, treatment_date = ADMIT_DATE) %>%
      collect()
  }

  # Stack and deduplicate
  non_null <- purrr::compact(sources)
  if (length(non_null) == 0) {
    return(tibble(ID = character(0), treatment_date = as.Date(character(0))))
  }
  bind_rows(non_null) %>%
    mutate(treatment_date = as.Date(treatment_date)) %>%
    filter(!is.na(treatment_date)) %>%
    distinct(ID, treatment_date)
}

#' Extract claims-only dates for SCT (PX, DRG)
#' @return tibble with columns ID, treatment_date (distinct pairs)
extract_claims_sct_dates <- function() {
  sources <- list()

  # 1. PROCEDURES: CPT/HCPCS, ICD-9-CM, ICD-10-PCS, revenue
  if (!is.null(get_pcornet_table("PROCEDURES"))) {
    sources$PX <- get_pcornet_table("PROCEDURES") %>%
      filter(
        (PX_TYPE == "CH" & PX %in% c(TREATMENT_CODES$sct_cpt, TREATMENT_CODES$sct_hcpcs)) |
          (PX_TYPE == "09" & PX %in% TREATMENT_CODES$sct_icd9) |
          (PX_TYPE == "10" & PX %in% TREATMENT_CODES$sct_icd10pcs) |
          (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$sct_revenue)
      ) %>%
      filter(!is.na(PX_DATE)) %>%
      select(ID, treatment_date = PX_DATE) %>%
      collect()
  }

  # 2. ENCOUNTER: DRGs 014, 016, 017
  if (!is.null(get_pcornet_table("ENCOUNTER"))) {
    sources$DRG <- get_pcornet_table("ENCOUNTER") %>%
      filter(DRG %in% TREATMENT_CODES$sct_drg) %>%
      filter(!is.na(ADMIT_DATE)) %>%
      select(ID, treatment_date = ADMIT_DATE) %>%
      collect()
  }

  # Stack and deduplicate
  non_null <- purrr::compact(sources)
  if (length(non_null) == 0) {
    return(tibble(ID = character(0), treatment_date = as.Date(character(0))))
  }
  bind_rows(non_null) %>%
    mutate(treatment_date = as.Date(treatment_date)) %>%
    filter(!is.na(treatment_date)) %>%
    distinct(ID, treatment_date)
}


# ==============================================================================
# SECTION 4: COVERAGE ANALYSIS LOOP ----
# ==============================================================================
# WHY: For each treatment type with TR sources (Chemo, Radiation, SCT), extract
# TR dates and claims dates separately, then use anti_join/semi_join to classify
# each (ID, treatment_date) pair as TR-only, claims-only, or both-sources.
# Per D-76-COV-01: This runs BEFORE TR removal.
# Per D-76-COV-02: Uses dplyr anti_join/semi_join for set operations.

message("\n=== Treatment Source Coverage Analysis (Phase 76) ===\n")

# Dispatch helpers for TR and claims extraction
extract_tr_dates <- function(type) {
  switch(type,
    "Chemotherapy" = extract_tr_chemo_dates(),
    "Radiation"    = extract_tr_radiation_dates(),
    "SCT"          = extract_tr_sct_dates(),
    stop(glue("Unknown treatment type for TR extraction: {type}"))
  )
}

extract_claims_dates <- function(type) {
  switch(type,
    "Chemotherapy" = extract_claims_chemo_dates(),
    "Radiation"    = extract_claims_radiation_dates(),
    "SCT"          = extract_claims_sct_dates(),
    stop(glue("Unknown treatment type for claims extraction: {type}"))
  )
}

# Storage for per-type results and detail data
coverage_results <- list()
tr_only_detail <- list()

for (type in c("Chemotherapy", "Radiation", "SCT")) {
  message(glue("\n--- {type} ---"))

  tr_dates <- extract_tr_dates(type)
  claims_dates <- extract_claims_dates(type)

  message(glue("  TR dates: {nrow(tr_dates)} (ID, date) pairs from {n_distinct(tr_dates$ID)} patients"))
  message(glue("  Claims dates: {nrow(claims_dates)} (ID, date) pairs from {n_distinct(claims_dates$ID)} patients"))

  # Set operations per RESEARCH.md Pattern 2 (D-76-COV-02)
  tr_only <- anti_join(tr_dates, claims_dates, by = c("ID", "treatment_date"))
  claims_only <- anti_join(claims_dates, tr_dates, by = c("ID", "treatment_date"))
  both_sources <- semi_join(tr_dates, claims_dates, by = c("ID", "treatment_date"))

  pct_tr_only <- round(100 * nrow(tr_only) / max(nrow(tr_dates), 1), 1)
  pct_redundant <- round(100 * nrow(both_sources) / max(nrow(tr_dates), 1), 1)

  message(glue("  {type}: {nrow(tr_only)} TR-only dates ({pct_tr_only}%), {nrow(both_sources)} dates in both sources ({pct_redundant}%)"))

  # Build summary row
  coverage_results[[type]] <- tibble(
    treatment_type    = type,
    tr_total_dates    = nrow(tr_dates),
    claims_total_dates = nrow(claims_dates),
    tr_only_dates     = nrow(tr_only),
    claims_only_dates = nrow(claims_only),
    both_sources_dates = nrow(both_sources),
    pct_tr_only       = pct_tr_only,
    pct_redundant     = pct_redundant,
    tr_only_patients  = n_distinct(tr_only$ID),
    both_patients     = n_distinct(both_sources$ID)
  )

  # Store TR-only detail for XLSX detail sheets
  tr_only_detail[[type]] <- tr_only %>%
    arrange(ID, treatment_date)
}

# Add Immunotherapy row with all zeros (no TR source -- per RESEARCH.md Open Question #3)
message(glue("\n--- Immunotherapy ---"))
message("  No TR source (expected 0% coverage)")

coverage_results[["Immunotherapy"]] <- tibble(
  treatment_type     = "Immunotherapy",
  tr_total_dates     = 0L,
  claims_total_dates = NA_integer_, # Not computed (no TR comparison needed)
  tr_only_dates      = 0L,
  claims_only_dates  = NA_integer_,
  both_sources_dates = 0L,
  pct_tr_only        = 0.0,
  pct_redundant      = 0.0,
  tr_only_patients   = 0L,
  both_patients      = 0L
)

# Combine all results
coverage_summary <- bind_rows(coverage_results)


# ==============================================================================
# SECTION 5: VALIDATION ----
# ==============================================================================
# WHY: Checkmate assertion ensures coverage analysis produced results for at
# least 3 treatment types (Chemo, Radiation, SCT). Immunotherapy is the 4th.

checkmate::assert_true(
  nrow(coverage_summary) >= 3,
  .var.name = "[R/76] Coverage analysis must produce results for at least 3 treatment types"
)


# ==============================================================================
# SECTION 6: CSV OUTPUT ----
# ==============================================================================

readr::write_csv(coverage_summary, COVERAGE_CSV)
message(glue("\nCoverage analysis saved: {COVERAGE_CSV}"))


# ==============================================================================
# SECTION 7: XLSX OUTPUT (MULTI-SHEET) ----
# ==============================================================================
# WHY: Multi-sheet workbook following R/26 audit pattern (D-76-COV-03).
# Sheet 1 = Summary table, Sheets 2-4 = TR-only date detail per treatment type.

wb <- wb_workbook()

# ---------- SHEET 1: SUMMARY ----------
wb$add_worksheet("Summary")

# Row 1: Title
wb$add_data(
  sheet = "Summary", x = "Treatment Source Coverage Analysis (Phase 76)",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Summary", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Summary", dims = "A1:J1")

# Row 2: Subtitle
subtitle <- as.character(glue(
  "Generated: {Sys.Date()} | Pre-TR-removal analysis | D-76-COV-01"
))
wb$add_data(sheet = "Summary", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(
  sheet = "Summary", dims = "A2",
  name = "Calibri", size = 10, color = wb_color("FF6B7280")
)
wb$merge_cells(sheet = "Summary", dims = "A2:J2")

# Row 4: Headers with dark fill and white font
summary_headers <- c(
  "Treatment Type", "TR Total Dates", "Claims Total Dates",
  "TR-Only Dates", "Claims-Only Dates", "Both Sources Dates",
  "% TR-Only", "% Redundant (Both/TR)", "TR-Only Patients", "Both Patients"
)
for (i in seq_along(summary_headers)) {
  wb$add_data(sheet = "Summary", x = summary_headers[i], start_row = 4, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A4:J4", color = wb_color("FF374151"))
wb$add_font(
  sheet = "Summary", dims = "A4:J4",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)

# Data rows (5-8): one per treatment type
for (i in seq_len(nrow(coverage_summary))) {
  row_num <- 4 + i
  row_data <- coverage_summary[i, ]

  wb$add_data(sheet = "Summary", x = row_data$treatment_type, start_row = row_num, start_col = 1)
  wb$add_data(sheet = "Summary", x = as.integer(row_data$tr_total_dates), start_row = row_num, start_col = 2)
  wb$add_data(sheet = "Summary", x = ifelse(is.na(row_data$claims_total_dates), "N/A", as.integer(row_data$claims_total_dates)), start_row = row_num, start_col = 3)
  wb$add_data(sheet = "Summary", x = as.integer(row_data$tr_only_dates), start_row = row_num, start_col = 4)
  wb$add_data(sheet = "Summary", x = ifelse(is.na(row_data$claims_only_dates), "N/A", as.integer(row_data$claims_only_dates)), start_row = row_num, start_col = 5)
  wb$add_data(sheet = "Summary", x = as.integer(row_data$both_sources_dates), start_row = row_num, start_col = 6)
  wb$add_data(sheet = "Summary", x = row_data$pct_tr_only, start_row = row_num, start_col = 7)
  wb$add_data(sheet = "Summary", x = row_data$pct_redundant, start_row = row_num, start_col = 8)
  wb$add_data(sheet = "Summary", x = as.integer(row_data$tr_only_patients), start_row = row_num, start_col = 9)
  wb$add_data(sheet = "Summary", x = as.integer(row_data$both_patients), start_row = row_num, start_col = 10)
}

# Row 9: Note for Immunotherapy
note_row <- 4 + nrow(coverage_summary) + 1
wb$add_data(
  sheet = "Summary",
  x = "Note: Immunotherapy has no TR source. Claims-only counts are N/A (no TR comparison needed).",
  start_row = note_row, start_col = 1
)
wb$add_font(
  sheet = "Summary", dims = wb_dims(note_row, 1),
  name = "Calibri", size = 9, italic = TRUE, color = wb_color("FF6B7280")
)

# Set column widths
wb$set_col_widths(sheet = "Summary", cols = 1:10, widths = c(18, 16, 18, 16, 18, 18, 12, 20, 16, 14))

# ---------- DETAIL SHEETS: TR-only dates per treatment type ----------
for (type in c("Chemotherapy", "Radiation", "SCT")) {
  sheet_name <- paste(type, "Detail")
  wb$add_worksheet(sheet_name)

  # Title
  wb$add_data(
    sheet = sheet_name,
    x = glue("TR-Only Dates: {type}"),
    start_row = 1, start_col = 1
  )
  wb$add_font(
    sheet = sheet_name, dims = "A1",
    name = "Calibri", size = 14, bold = TRUE, color = wb_color("FF1F2937")
  )
  wb$merge_cells(sheet = sheet_name, dims = "A1:B1")

  # Subtitle with count
  detail_data <- tr_only_detail[[type]]
  n_total <- nrow(detail_data)
  truncated <- n_total > 1000
  display_data <- if (truncated) head(detail_data, 1000) else detail_data

  sub_text <- glue("Dates in TR but NOT in claims | {n_total} total dates")
  if (truncated) {
    sub_text <- glue("{sub_text} (showing first 1,000)")
  }
  wb$add_data(sheet = sheet_name, x = as.character(sub_text), start_row = 2, start_col = 1)
  wb$add_font(
    sheet = sheet_name, dims = "A2",
    name = "Calibri", size = 10, color = wb_color("FF6B7280")
  )
  wb$merge_cells(sheet = sheet_name, dims = "A2:B2")

  # Headers
  detail_headers <- c("Patient ID", "Treatment Date")
  for (j in seq_along(detail_headers)) {
    wb$add_data(sheet = sheet_name, x = detail_headers[j], start_row = 4, start_col = j)
  }
  wb$add_fill(sheet = sheet_name, dims = "A4:B4", color = wb_color("FF374151"))
  wb$add_font(
    sheet = sheet_name, dims = "A4:B4",
    name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
  )

  # Data rows
  if (nrow(display_data) > 0) {
    for (k in seq_len(nrow(display_data))) {
      wb$add_data(sheet = sheet_name, x = display_data$ID[k], start_row = 4 + k, start_col = 1)
      wb$add_data(sheet = sheet_name, x = as.character(display_data$treatment_date[k]), start_row = 4 + k, start_col = 2)
    }
  } else {
    wb$add_data(sheet = sheet_name, x = "No TR-only dates found", start_row = 5, start_col = 1)
  }

  wb$set_col_widths(sheet = sheet_name, cols = 1:2, widths = c(20, 16))
}

# Save workbook
wb$save(COVERAGE_XLSX)
message(glue("Coverage XLSX saved: {COVERAGE_XLSX}"))


# ==============================================================================
# SECTION 8: FINAL SUMMARY ----
# ==============================================================================

message("\n=== Coverage Analysis Complete ===")
message(glue("Total TR-only dates across all types: {sum(coverage_summary$tr_only_dates)}"))
message(glue("These dates will be LOST after TR removal"))
message(glue("Output: {COVERAGE_CSV}"))
message(glue("Output: {COVERAGE_XLSX}"))
