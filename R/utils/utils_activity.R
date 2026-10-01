# ==============================================================================
# utils/utils_activity.R -- Latest observed clinical activity per patient (Phase 161)
# ==============================================================================
#
# Purpose:
#   Defines get_last_activity(), the single canonical source for last-observed-date
#   across all person-time and time-to-event calculations (D4). Queries nine
#   PCORnet CDM tables via DuckDB; results are capped at the analysis cutoff.
#
# Inputs:
#   - con     DBI connection to pcornet.duckdb
#   - ids     data frame with column ID (the cohort)
#   - cutoff  Date; activity after cutoff is excluded
#
# Outputs:
#   - tibble: ID, last_enc_any, last_activity_any, last_activity_src, last_observed
#
# Dependencies:
#   - DBI, duckdb, dplyr, tibble
#
# Requirements: N/A (utility module)
#
# ==============================================================================

library(DBI)
library(duckdb)
library(dplyr)
library(tibble)

#' Latest observed clinical activity per patient (shared definition, Phase 161)
#'
#' @param con    DBI connection to pcornet.duckdb
#' @param ids    data frame with column ID (the cohort)
#' @param cutoff Date; activity after cutoff is ignored
#' @return tibble: ID, last_enc_any, last_activity_any, last_activity_src, last_observed
#'   last_enc_any      = latest ENCOUNTER discharge-or-admit date (<= cutoff)
#'   last_activity_any = latest date across ACTIVITY_SOURCES (<= cutoff)
#'   last_observed     = pmax of the two
ACTIVITY_SOURCES <- list(
  DIAGNOSIS     = c("DX_DATE", "ADMIT_DATE"),
  PROCEDURES    = c("PX_DATE", "ADMIT_DATE"),
  LAB_RESULT_CM = c("SPECIMEN_DATE", "RESULT_DATE"),
  PRESCRIBING   = c("RX_ORDER_DATE", "RX_START_DATE"),
  DISPENSING    = c("DISPENSE_DATE"),
  MED_ADMIN     = c("MEDADMIN_START_DATE"),
  VITAL         = c("MEASURE_DATE"),
  OBS_CLIN      = c("OBSCLIN_START_DATE"),
  IMMUNIZATION  = c("VX_ADMIN_DATE")
)

get_last_activity <- function(con, ids, cutoff) {
  cutoff <- as.Date(cutoff)
  cut    <- format(cutoff)
  ids    <- dplyr::distinct(tibble::tibble(ID = ids$ID))
  duckdb::duckdb_register(con, "la_ids", ids)
  on.exit(duckdb::duckdb_unregister(con, "la_ids"), add = TRUE)

  tbls      <- DBI::dbListTables(con)
  # Case-insensitive table lookup: PCORnet table names may differ in casing across
  # DuckDB versions; match by uppercasing both sides.
  real_name <- function(t) tbls[toupper(tbls) == toupper(t)][1]

  enc <- DBI::dbGetQuery(con, sprintf("
    SELECT e.ID,
           max(greatest(coalesce(TRY_CAST(e.ADMIT_DATE AS DATE), TRY_CAST(e.DISCHARGE_DATE AS DATE)),
                        coalesce(TRY_CAST(e.DISCHARGE_DATE AS DATE), TRY_CAST(e.ADMIT_DATE AS DATE))))
             FILTER (WHERE coalesce(TRY_CAST(e.ADMIT_DATE AS DATE),
                                    TRY_CAST(e.DISCHARGE_DATE AS DATE)) <= DATE '%s') AS last_enc_any
      FROM %s e JOIN la_ids i ON e.ID = i.ID
     GROUP BY e.ID", cut, real_name("ENCOUNTER"))) |>
    tibble::as_tibble() |>
    dplyr::mutate(last_enc_any = pmin(as.Date(last_enc_any), cutoff))

  parts <- character()
  for (tb in names(ACTIVITY_SOURCES)) {
    rn <- real_name(tb)
    if (is.na(rn)) next
    flds <- toupper(DBI::dbListFields(con, rn))
    for (col in intersect(ACTIVITY_SOURCES[[tb]], flds)) {
      parts <- c(parts, sprintf(
        "SELECT t.ID, '%s.%s' AS src,
                max(TRY_CAST(t.%s AS DATE)) FILTER (WHERE TRY_CAST(t.%s AS DATE) <= DATE '%s') AS d
           FROM %s t JOIN la_ids i ON t.ID = i.ID GROUP BY t.ID",
        tb, col, col, col, cut, rn))
    }
  }
  act <- DBI::dbGetQuery(con, paste(parts, collapse = "\nUNION ALL\n")) |>
    tibble::as_tibble() |>
    dplyr::mutate(d = as.Date(d)) |>
    dplyr::filter(!is.na(d)) |>
    dplyr::group_by(ID) |>
    dplyr::slice_max(d, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::transmute(ID, last_activity_any = d, last_activity_src = src)

  ids |>
    dplyr::left_join(enc, by = "ID") |>
    dplyr::left_join(act, by = "ID") |>
    dplyr::mutate(last_observed = pmax(last_enc_any, last_activity_any, na.rm = TRUE))
}
