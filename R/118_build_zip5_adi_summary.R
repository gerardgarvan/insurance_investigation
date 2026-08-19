# R/118_build_zip5_adi_summary.R
# Build zip5_adi_summary.csv — ZIP5-level ADI summary (Route B, D-02).
#
# Phase 148 D-02: Route B chosen over Route A (centroid crosswalk) because
# neighborhood_atlas_zip9_adi.csv is already staged and joinable on ZIP9.
# Grouping by ZIP5 prefix gives a median + IQR without coordinates or geocoding.
# See 148-DISCOVERY.md §2 for full reasoning.
#
# Output: data/reference/zip5_adi_summary.csv
#   ZIP5                  character(5), zero-padded
#   adi_natrank_median    numeric, median ADI national rank across ZIP9s in ZIP5
#   adi_natrank_p25       numeric, 25th percentile
#   adi_natrank_p75       numeric, 75th percentile
#   n_zip9_in_zip5        integer, ZIP9 rows considered (before NA suppression)
#   n_zip9_with_adi       integer, ZIP9 rows with non-NA ADI_NATRANK
#   adi_coverage          numeric, share of ZIP+4s with a non-NA ADI (n_zip9_with_adi / n_zip9_in_zip5)
#   vintage               character, e.g. "Neighborhood Atlas 2024 v4.0.1"
#   method                character, "zip5_adi_summary_route_b"
#   source                character, citation
#
# Run on HiPerGator: Rscript R/118_build_zip5_adi_summary.R
# Prerequisites: tidyverse, vroom (already in renv.lock)
# ADI_INPUT_PATH is gitignored (478 MB); must be scp'd to HiPerGator first.
# ==============================================================================

library(here)
library(dplyr)
library(vroom)
library(readr)
library(glue)

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------

ADI_INPUT_PATH      <- here::here("data", "reference", "neighborhood_atlas_zip9_adi.csv")
ADI_OUTPUT_PATH     <- here::here("data", "reference", "zip5_adi_summary.csv")
ADI_SUPPRESSION_CODES <- c("GQ", "GQ-PH", "PH", "QDI")
VINTAGE             <- "Neighborhood Atlas 2024 v4.0.1"
METHOD              <- "zip5_adi_summary_route_b; median/IQR of ADI_NATRANK over Neighborhood Atlas ZIP+4 records within each ZIP5 (denominator = ZIP+4 segments present in the Atlas file, which is beneficiary-based, NOT all USPS delivery segments)"
SOURCE              <- "University of Wisconsin Neighborhood Atlas (neighborhoodatlas.medicine.wisc.edu). Registration required. Redistribution: file gitignored per project policy."

# Below this share of ZIP+4s carrying a usable ADI, the ZIP5 median is not reported.
# A median over 3 of 400 segments is not the same quantity as one over 400, and the
# reader cannot tell them apart without this.
ADI_COVERAGE_FLOOR <- 0.50

# ------------------------------------------------------------------------------
# Step 1 — Guard: confirm input file is present
# ------------------------------------------------------------------------------

if (!file.exists(ADI_INPUT_PATH)) {
  stop(
    "ADI input file not found: ", ADI_INPUT_PATH, "\n",
    "Transfer to HiPerGator: scp data/reference/neighborhood_atlas_zip9_adi.csv ",
    "{user}@hpg.rc.ufl.edu:/blue/erin.mobley-hl.bcu/insurance_investigation/data/reference/"
  )
}

# ------------------------------------------------------------------------------
# Step 2 — Load: read all columns as character to avoid type guessing
# ------------------------------------------------------------------------------

raw <- vroom::vroom(
  ADI_INPUT_PATH,
  col_types = vroom::cols(.default = "c"),
  progress  = FALSE
)
message(glue::glue("Loaded {format(nrow(raw), big.mark=',')} rows from neighborhood_atlas_zip9_adi.csv"))

# ------------------------------------------------------------------------------
# Step 3 — Clean: filter to well-formed ZIP9s, derive ZIP5, convert ADI to numeric
# ------------------------------------------------------------------------------

clean <- raw |>
  dplyr::filter(nchar(ZIP9) == 9L, grepl("^[0-9]{9}$", ZIP9)) |>
  dplyr::mutate(
    ZIP5    = substr(ZIP9, 1, 5),
    adi_num = dplyr::if_else(
      ADI_NATRANK %in% ADI_SUPPRESSION_CODES,
      NA_real_,
      suppressWarnings(as.numeric(ADI_NATRANK))
    )
  )
message(glue::glue(
  "After format filter: {format(nrow(clean), big.mark=',')} rows; {format(dplyr::n_distinct(clean$ZIP5), big.mark=',')} unique ZIP5s"
))

# ------------------------------------------------------------------------------
# Step 4 — Summarise: median + IQR of ADI national rank per ZIP5
# ------------------------------------------------------------------------------

out <- clean |>
  dplyr::group_by(ZIP5) |>
  dplyr::summarise(
    # quantile() ERRORS on an all-NA vector even with na.rm = TRUE; median() only warns.
    # A ZIP5 whose every ZIP+4 is suppressed (GQ / GQ-PH / PH / QDI) has no usable values
    # and must emit NA, not abort the build.
    adi_natrank_median = if (any(!is.na(adi_num))) median(adi_num, na.rm = TRUE) else NA_real_,
    adi_natrank_p25    = if (any(!is.na(adi_num))) unname(quantile(adi_num, 0.25, na.rm = TRUE)) else NA_real_,
    adi_natrank_p75    = if (any(!is.na(adi_num))) unname(quantile(adi_num, 0.75, na.rm = TRUE)) else NA_real_,
    n_zip9_in_zip5     = dplyr::n(),
    n_zip9_with_adi    = sum(!is.na(adi_num)),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    adi_coverage = n_zip9_with_adi / n_zip9_in_zip5,
    adi_natrank_median = dplyr::if_else(adi_coverage < ADI_COVERAGE_FLOOR, NA_real_, adi_natrank_median),
    adi_natrank_p25    = dplyr::if_else(adi_coverage < ADI_COVERAGE_FLOOR, NA_real_, adi_natrank_p25),
    adi_natrank_p75    = dplyr::if_else(adi_coverage < ADI_COVERAGE_FLOOR, NA_real_, adi_natrank_p75),
    vintage = VINTAGE,
    method  = METHOD,
    source  = SOURCE
  )
message(glue::glue(
  "Summary: {format(nrow(out), big.mark=',')} ZIP5s; {format(sum(!is.na(out$adi_natrank_median)), big.mark=',')} with non-NA median ADI"
))
n_below <- sum(out$adi_coverage < ADI_COVERAGE_FLOOR, na.rm = TRUE)
message(glue::glue(
  "Coverage floor {ADI_COVERAGE_FLOOR}: {format(n_below, big.mark=',')} ZIP5s suppressed to NA ",
  "({round(100 * n_below / nrow(out), 1)}%)"
))

# ------------------------------------------------------------------------------
# Step 5 — Validation gates (all blocking; adapted for ADI summary schema)
# ------------------------------------------------------------------------------

stopifnot(
  "ZIP5 must be 5 characters"         = all(nchar(out$ZIP5) == 5L),
  "ZIP5 must be digits only"          = all(grepl("^[0-9]{5}$", out$ZIP5)),
  "ZIP5 must be unique"               = !any(duplicated(out$ZIP5)),
  "n_zip9_in_zip5 must be positive"   = all(out$n_zip9_in_zip5 > 0L)
)
message("All 4 validation gates passed.")

# ------------------------------------------------------------------------------
# Step 6 — Write output
# ------------------------------------------------------------------------------

readr::write_csv(out, ADI_OUTPUT_PATH)
message(glue::glue("Written: {ADI_OUTPUT_PATH}"))
message(glue::glue("ZIP5s resolved: {format(nrow(out), big.mark=',')}"))
