# ==============================================================================
# 168_survivorship_workbook.R -- Phase 166 Survivorship Workbook Assembler
# ==============================================================================
# INTERNAL — contains patient IDs; not for release outside the secure enclave.
#
# Purpose:
#   Assembles survivorship_modality_rates_<run_date>.xlsx plus per-patient
#   exports from the Plan 02 (R/166) and Plan 03 (R/167) part files. Both
#   part files must exist before running this script. If their run_dates differ
#   a warning is issued; execution continues.
#
# Inputs (CONFIG$cache$outputs_dir):
#   survivorship_modality_rates_parts_<date>.rds  (Plan 02 parts)
#   survivorship_echo_parts_<date>.rds            (Plan 03 parts)
#   R/00_config.R                                 (CONFIG, utilities)
#
# Outputs (CONFIG$cache$outputs_dir):
#   survivorship_modality_rates_long_<run_date>.rds       INTERNAL, unsuppressed
#   survivorship_modality_rates_patient_<run_date>.rds    INTERNAL, unsuppressed
#   survivorship_modality_rates_patient_<run_date>.csv    INTERNAL, unsuppressed
#   survivorship_modality_rates_<run_date>.xlsx           workbook (suppressed)
#
# Dependencies: openxlsx, dplyr, readr, glue, here, tidyr
# Requirements: SRATE-02, SRATE-03, SRATE-04
# Decisions: 166-CONTEXT.md D-01..D-14c; 166-AUDIT.md
# ==============================================================================

suppressPackageStartupMessages({
  library(openxlsx)
  library(dplyr)
  library(readr)
  library(glue)
  library(here)
  library(tidyr)
})

source(here::here("R/00_config.R"))

run_date  <- format(Sys.Date(), "%Y%m%d")
out_dir   <- CONFIG$cache$outputs_dir

# ==============================================================================
# SECTION 1: LOAD PARTS ----
# ==============================================================================

message(strrep("=", 70))
message("R/168: Survivorship Workbook Assembler")
message(strrep("=", 70))

# Load most recent Plan 02 parts -------------------------------------------
rates_files <- sort(list.files(out_dir,
                               pattern = "^survivorship_modality_rates_parts_.*\\.rds$",
                               full.names = TRUE), decreasing = TRUE)
if (length(rates_files) == 0L) {
  stop("[R/168] No 'survivorship_modality_rates_parts_*.rds' found in '", out_dir,
       "'.\nRun R/166_survivorship_modality_rates.R first.")
}
rates_parts_path <- rates_files[[1L]]
message("  Loading rates parts: ", basename(rates_parts_path))
p02 <- readRDS(rates_parts_path)

# Load most recent Plan 03 parts -------------------------------------------
echo_files <- sort(list.files(out_dir,
                              pattern = "^survivorship_echo_parts_.*\\.rds$",
                              full.names = TRUE), decreasing = TRUE)
if (length(echo_files) == 0L) {
  stop("[R/168] No 'survivorship_echo_parts_*.rds' found in '", out_dir,
       "'.\nRun R/167_anthracycline_echo.R first.")
}
echo_parts_path <- echo_files[[1L]]
message("  Loading echo parts:  ", basename(echo_parts_path))
p03 <- readRDS(echo_parts_path)

# Extract run_date from filenames and warn if they differ ------------------
rates_date <- sub(".*survivorship_modality_rates_parts_([0-9]{8})\\.rds", "\\1",
                  basename(rates_parts_path))
echo_date  <- sub(".*survivorship_echo_parts_([0-9]{8})\\.rds", "\\1",
                  basename(echo_parts_path))

if (rates_date != echo_date) {
  warning(
    "[R/168] Plan 02 parts date (", rates_date, ") differs from ",
    "Plan 03 parts date (", echo_date, "). ",
    "Results are from different runs. Review before releasing the workbook."
  )
}

# Extract Plan 02 objects
long_rates             <- p02$long_rates
wide_rates             <- p02$wide_rates
A_rates_summary        <- p02$A_rates_summary
B_rates_by_fu_year     <- p02$B_rates_by_fu_year
qc_interval_recon_summary <- p02$qc_interval_recon_summary
qc_interval_fail       <- p02$qc_interval_fail
n_zero_py_patients     <- p02$n_zero_py_patients

# Extract Plan 03 objects
C_anthracycline_echo       <- p03$C_anthracycline_echo
cif_km_by_variant          <- p03$cif_km_by_variant
echo_rate_patient          <- p03$echo_rate_patient
qc_echo                    <- p03$qc_echo
qc_anthracycline_drug_counts <- p03$qc_anthracycline_drug_counts
d_166_01_record            <- p03$d_166_01_record
episode_file_used          <- p03$episode_file_used
caveat_d14c                <- p03$caveat_d14c

# ==============================================================================
# SECTION 2: PER-PATIENT EXPORTS ----
# ==============================================================================

message("\n  Building per-patient exports...")

# Long: bind modality rates + echo_post_anthracycline rate
long_all <- dplyr::bind_rows(long_rates, echo_rate_patient)

# Wide: one row per patient, one column per rate
# echo_post_anthracycline_rate_per_py will be among the columns
wide_all <- long_all |>
  tidyr::pivot_wider(
    id_cols     = "ID",
    names_from  = "modality",
    values_from = "rate_per_py",
    names_glue  = "{modality}_rate_per_py"
  )

# Save INTERNAL unsuppressed per-patient objects
long_out <- file.path(out_dir,
  glue("survivorship_modality_rates_long_{run_date}.rds"))
patient_rds_out <- file.path(out_dir,
  glue("survivorship_modality_rates_patient_{run_date}.rds"))
patient_csv_out <- file.path(out_dir,
  glue("survivorship_modality_rates_patient_{run_date}.csv"))

saveRDS(long_all, long_out)
saveRDS(wide_all, patient_rds_out)
readr::write_csv(wide_all, patient_csv_out)

message("  INTERNAL per-patient long RDS:  ", basename(long_out))
message("  INTERNAL per-patient wide RDS:  ", basename(patient_rds_out))
message("  INTERNAL per-patient wide CSV:  ", basename(patient_csv_out))

# ==============================================================================
# SECTION 3: DISPLAY SUPPRESSION HELPERS ----
# ==============================================================================

# suppress_small from utils_surveillance.R is auto-sourced via R/00_config.R
# Pairs: count columns 1-10 -> "<11"; paired rate column blanked when count suppressed.

#' Apply display suppression to a data frame
#'
#' Counts 1-10 become "<11". For each count column with a paired rate column,
#' when the count is suppressed the rate is set to NA (prevents back-calculation).
#' Person-years are never suppressed.
#'
#' @param df         Data frame to suppress.
#' @param count_cols Character vector of column names holding integer counts.
#' @param rate_cols  Named character vector mapping count_col -> rate_col to blank
#'                   when the count is suppressed. Use a named list or parallel vectors.
#' @return Data frame with display suppression applied.
display_counts <- function(df, count_cols = character(0),
                           rate_pairs = list()) {
  # Suppress count columns (1-10 -> "<11")
  for (col in count_cols) {
    if (col %in% names(df)) {
      df[[col]] <- suppress_small(df[[col]])
    }
  }
  # Blank paired rate when count is suppressed
  for (pair in rate_pairs) {
    cnt_col  <- pair[[1L]]
    rate_col <- pair[[2L]]
    if (cnt_col %in% names(df) && rate_col %in% names(df)) {
      suppressed_rows <- !is.na(df[[cnt_col]]) & df[[cnt_col]] == "<11"
      if (any(suppressed_rows, na.rm = TRUE)) {
        df[[rate_col]][suppressed_rows] <- NA_real_
      }
    }
  }
  df
}

# ==============================================================================
# SECTION 4: OPENXLSX WORKBOOK SETUP ----
# ==============================================================================

message("\n  Building workbook...")

wb <- openxlsx::createWorkbook()

UF_BLUE   <- "#0021A5"
UF_ORANGE <- "#FA4616"

hdr_style <- openxlsx::createStyle(
  fgFill    = UF_BLUE,
  fontColour = "white",
  textDecoration = "bold",
  fontName  = "Arial",
  fontSize  = 11,
  halign    = "left",
  border    = "Bottom",
  borderColour = "white"
)

flag_style <- openxlsx::createStyle(
  fgFill    = UF_ORANGE,
  fontColour = "white",
  textDecoration = "bold"
)

# Helper: add a sheet and write a data frame with the header style
add_sheet <- function(wb, sheet_name, df, header_style = hdr_style,
                       start_row = 1L, ...) {
  openxlsx::addWorksheet(wb, sheet_name)
  if (!is.null(df) && nrow(df) > 0L) {
    openxlsx::writeData(wb, sheet_name, df, startRow = start_row,
                        headerStyle = header_style, ...)
    openxlsx::setColWidths(wb, sheet_name, cols = seq_len(ncol(df)),
                           widths = "auto")
  }
  invisible(wb)
}

# Helper: write a single key-value pair list as a two-column table
kv_frame <- function(...) {
  args <- list(...)
  data.frame(
    Field = names(args),
    Value = unlist(args, use.names = FALSE),
    stringsAsFactors = FALSE
  )
}

# ==============================================================================
# SECTION 5: KEY SHEET ----
# ==============================================================================

message("  Writing KEY sheet...")

echo_modality_name <- "Echocardiogram"  # confirmed in 166-AUDIT.md

key_rows <- data.frame(
  Field = c(
    "Run date",
    "Rates script",
    "Echo-timing script",
    "Workbook script",
    "Echocardiogram modality name",
    "Follow-up definition",
    "Follow-up end source",
    "n_dates_col",
    "Reconciliation contract",
    "Interval boundaries",
    "D-166-01",
    "D-166-02 (episode file)",
    "Mitoxantrone note",
    "D-14c caveat",
    "Rate formula",
    "CIF method",
    "1 - KM note",
    "Person-years note",
    "Sheet guide"
  ),
  Value = c(
    run_date,
    "R/166_survivorship_modality_rates.R",
    "R/167_anthracycline_echo.R",
    "R/168_survivorship_workbook.R",
    echo_modality_name,
    "compute_followup() from utils_surveillance.R (Phase 161): follow_end = min(death_date_resolved, obs_end, cutoff, na.rm=TRUE); person_years = fu_days / 365.25, floored at 0",
    "death_date_resolved from resolve_death_date() (Phase 161 grace-period plausibility and source-priority resolution)",
    "n_dates_post_primary — tier == 'primary', window == 'post' (event_date strictly after hl_anchor_date AND <= follow_end), distinct ID x modality x event_date",
    "Dated events rebuilt via option-a function chain from 166-AUDIT.md §5. 1363/1363 matching on 200-patient sample (PASS).",
    "(0, 365] = Y1; (365, 730] = Y2; (730, 1825] = Y3-5; (1825, Inf) = 5+",
    if (!is.null(d_166_01_record)) d_166_01_record else
      "Primary anthracycline clock: Doxorubicin (incl. liposomal, via DRUG_NAME_ALIASES). Class-effect extension: Daunorubicin, Epirubicin, Idarubicin also included (see D-07). Counts confirmed at Plan 03 runtime.",
    if (!is.null(episode_file_used)) episode_file_used else
      "180-day episode file (treatment_episode_detail_180.rds). D-08a fallback: first_line column absent from file; last_dose_firstline_dt computed as max admin_date over all episodes (functionally equivalent to last_dose_ever_dt in this dataset).",
    "Mitoxantrone excluded from the primary anthracycline clock — an anthracenedione rather than an anthracycline and rarely used in HL; it is also cardiotoxic and is counted in QC (see D-07a). If cohort patients received it, a sensitivity row with Mitoxantrone included appears in C_anthracycline_echo.",
    if (!is.null(caveat_d14c)) caveat_d14c else
      "D-14c: Echoes done outside OneFlorida+ partner sites are not captured; cumulative incidence and rates are lower bounds on echo receipt.",
    "rate_per_py = n_dates_post / person_years. NA when person_years is 0 or NA. Zero-event patients appear with rate 0 (person_years > 0).",
    "Aalen-Johansen estimator (proper competing-risk CIF) with death as competing event, via survival::survfit(Surv(time, event_factor) ~ 1) with factor event levels: censored / echo / death.",
    "1 - Kaplan-Meier: deaths treated as censored at the death date. This OVERESTIMATES echo receipt because competing deaths are censored. Shown alongside CIF for transparency.",
    "Person-years are not suppressed. Counts 1-10 are shown as '<11'. Rates whose paired count is '<11' are blanked (prevents back-calculation from rate x person-years).",
    "KEY (this sheet) | A_rates_summary (per-modality summary, counts suppressed) | B_rates_by_fu_year (interval rates, suppression applied) | C_anthracycline_echo (echo timing CIF/KM/rate by variant) | QC (interval reconciliation, echo QC, per-drug counts)"
  ),
  stringsAsFactors = FALSE
)

add_sheet(wb, "KEY", key_rows)

# ==============================================================================
# SECTION 6: A_rates_summary SHEET ----
# ==============================================================================

message("  Writing A_rates_summary sheet...")

A_sup <- A_rates_summary |>
  display_counts(
    count_cols  = c("n_patients", "n_zero_event"),
    rate_pairs  = list()  # summary means/medians: no direct count pairing to blank
  )

add_sheet(wb, "A_rates_summary", A_sup)

# ==============================================================================
# SECTION 7: B_rates_by_fu_year SHEET ----
# ==============================================================================

message("  Writing B_rates_by_fu_year sheet...")

# Suppress dates_in_interval (count) and blank rate_per_py_interval when suppressed
B_sup <- B_rates_by_fu_year |>
  display_counts(
    count_cols = "dates_in_interval",
    rate_pairs = list(c("dates_in_interval", "rate_per_py_interval"))
  )

add_sheet(wb, "B_rates_by_fu_year", B_sup)

# ==============================================================================
# SECTION 8: C_anthracycline_echo SHEET ----
# ==============================================================================

message("  Writing C_anthracycline_echo sheet...")

openxlsx::addWorksheet(wb, "C_anthracycline_echo")

# Write caveat subtitle row first
caveat_text <- if (!is.null(caveat_d14c)) caveat_d14c else
  "D-14c: Echoes done outside OneFlorida+ partner sites are not captured; cumulative incidence and rates are lower bounds on echo receipt."

openxlsx::writeData(wb, "C_anthracycline_echo",
                    data.frame(Note = caveat_text),
                    startRow = 1L, headerStyle = hdr_style)

# Write C_anthracycline_echo below the caveat
if (!is.null(C_anthracycline_echo) && nrow(C_anthracycline_echo) > 0L) {
  C_sup <- C_anthracycline_echo |>
    display_counts(
      count_cols = c("n_dates_post", "n_echo_events"),
      rate_pairs = list(
        c("n_dates_post",  "rate_per_py"),
        c("n_echo_events", "echo_rate_per_py")
      )
    )
  openxlsx::writeData(wb, "C_anthracycline_echo", C_sup,
                      startRow = 3L, headerStyle = hdr_style)
  openxlsx::setColWidths(wb, "C_anthracycline_echo",
                         cols = seq_len(ncol(C_sup)), widths = "auto")
}

# Append CIF/KM table below C_anthracycline_echo
if (!is.null(cif_km_by_variant) && nrow(cif_km_by_variant) > 0L) {
  c_rows  <- if (!is.null(C_anthracycline_echo)) nrow(C_anthracycline_echo) else 0L
  cif_row <- 3L + c_rows + 2L
  openxlsx::writeData(wb, "C_anthracycline_echo", cif_km_by_variant,
                      startRow = cif_row, headerStyle = hdr_style)
}

# ==============================================================================
# SECTION 9: QC SHEET ----
# ==============================================================================

message("  Writing QC sheet...")

openxlsx::addWorksheet(wb, "QC")
qc_write_row <- 1L

# Interval reconciliation summary
qc_recon_header <- data.frame(
  Section = "Interval reconciliation",
  stringsAsFactors = FALSE
)
openxlsx::writeData(wb, "QC", qc_recon_header, startRow = qc_write_row,
                    headerStyle = hdr_style)
qc_write_row <- qc_write_row + 2L

if (!is.null(qc_interval_recon_summary) && nrow(qc_interval_recon_summary) > 0L) {
  # Flag FAIL rows with orange
  openxlsx::writeData(wb, "QC", qc_interval_recon_summary,
                      startRow = qc_write_row, headerStyle = hdr_style)

  # Apply flag_style to any row where result == "FAIL"
  result_col_idx <- which(names(qc_interval_recon_summary) == "result")
  if (length(result_col_idx) > 0L) {
    fail_rows <- which(qc_interval_recon_summary$result == "FAIL")
    for (fr in fail_rows) {
      openxlsx::addStyle(wb, "QC", style = flag_style,
                         rows = qc_write_row + fr,  # +1 header
                         cols = result_col_idx,
                         gridExpand = FALSE)
    }
  }
  qc_write_row <- qc_write_row + nrow(qc_interval_recon_summary) + 2L
}

# n_zero_py_patients
openxlsx::writeData(wb, "QC",
                    data.frame(Metric = "n_zero_py_patients",
                               Value  = n_zero_py_patients),
                    startRow = qc_write_row, headerStyle = hdr_style)
qc_write_row <- qc_write_row + 3L

# Echo QC block
if (!is.null(qc_echo) && nrow(qc_echo) > 0L) {
  qc_echo_sup <- qc_echo |>
    display_counts(
      count_cols = grep("^n_", names(qc_echo), value = TRUE),
      rate_pairs = list()
    )
  openxlsx::writeData(wb, "QC", qc_echo_sup,
                      startRow = qc_write_row, headerStyle = hdr_style)
  qc_write_row <- qc_write_row + nrow(qc_echo_sup) + 2L
}

# Per-drug anthracycline counts
if (!is.null(qc_anthracycline_drug_counts) &&
    nrow(qc_anthracycline_drug_counts) > 0L) {
  openxlsx::writeData(wb, "QC",
                      data.frame(Section = "Per-drug anthracycline counts"),
                      startRow = qc_write_row, headerStyle = hdr_style)
  qc_write_row <- qc_write_row + 2L

  drug_sup <- qc_anthracycline_drug_counts |>
    display_counts(
      count_cols = grep("^n_", names(qc_anthracycline_drug_counts), value = TRUE),
      rate_pairs = list()
    )
  openxlsx::writeData(wb, "QC", drug_sup,
                      startRow = qc_write_row, headerStyle = hdr_style)
}

# ==============================================================================
# SECTION 10: SAVE WORKBOOK ----
# ==============================================================================

xlsx_out <- file.path(out_dir,
  glue("survivorship_modality_rates_{run_date}.xlsx"))

openxlsx::saveWorkbook(wb, xlsx_out, overwrite = TRUE)

message("\n  Outputs written:")
message("    ", long_out)
message("    ", patient_rds_out)
message("    ", patient_csv_out)
message("    ", xlsx_out)
message("\nR/168 complete.")
