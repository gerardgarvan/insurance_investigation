# R/169_single_source_care.R
# =============================================================================
# Purpose:  Compute patient-level single_source_care flags from ENCOUNTER.SOURCE
#           in DuckDB. Delivers two windows (whole-record and post-HL-anchor)
#           as separate columns on every output row.
#
# Inputs:   DuckDB ENCOUNTER table (SOURCE, ADMIT_DATE, ID columns)
#           get_hl_any_dx_ids() anchor dates
#           CONFIG$analysis date range bounds
#
# Outputs:  output/internal/single_source_care_<YYYYMMDD>.csv      (IDs: internal)
#           output/internal/single_source_care_<YYYYMMDD>.rds      (IDs: internal)
#           output/internal/single_source_care_parts_<YYYYMMDD>.rds (for Plan 02)
#
# Requirements: SRC-01, SRC-02, SRC-03
# Phase: 167 — single-health-system-care-flag
# Plan:  167-01
# INTERNAL: outputs contain patient IDs — write only to output/internal/
# =============================================================================

source(here::here("R/00_config.R"))
suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(readr)
})
run_date <- format(Sys.Date(), "%Y%m%d")

# =============================================================================
# SECTION 1B — pure helper (defined before any DuckDB code)
# =============================================================================
#
# build_single_source_result()
#
# Accepts four tibbles produced by DuckDB queries and constructs the
# patient-level flag table.  No database access inside this function.
#
# @param whole_raw     tibble(ID, n_encounters, n_sources, any_blank_source 0/1 int)
# @param post_raw      tibble(ID, n_encounters_post, n_sources_post)
# @param anchors       tibble(ID, hl_anchor_date, ...)  — all cohort patients
# @param source_counts tibble(ID, SOURCE chr normalised, n_enc_at_source int)
#
# @return tibble with columns:
#   ID, n_encounters, n_sources, single_source_care, primary_source,
#   n_encounters_post, n_sources_post, single_source_care_post,
#   any_blank_source, hl_anchor_date
#
build_single_source_result <- function(whole_raw, post_raw, anchors, source_counts) {

  # primary_source: most common site (non-blank), alphabetical tiebreak on ties
  primary_tbl <- source_counts |>
    dplyr::group_by(ID) |>
    dplyr::arrange(dplyr::desc(n_enc_at_source), SOURCE, .by_group = TRUE) |>
    dplyr::slice_head(n = 1) |>
    dplyr::ungroup() |>
    dplyr::select(ID, primary_source = SOURCE)

  anchors |>
    dplyr::select(ID, hl_anchor_date) |>
    dplyr::left_join(whole_raw,    by = "ID") |>
    dplyr::left_join(post_raw,     by = "ID") |>
    dplyr::left_join(primary_tbl,  by = "ID") |>
    dplyr::mutate(
      # SRC-01: single_source_care over non-blank encounters only
      single_source_care = dplyr::case_when(
        is.na(n_sources) | n_sources == 0 ~ NA_integer_,
        n_sources == 1                     ~ 1L,
        TRUE                               ~ 0L
      ),
      # SRC-02: post-anchor flag BEFORE coalescing post counts (Pitfall 2)
      single_source_care_post = dplyr::case_when(
        is.na(hl_anchor_date)                              ~ NA_integer_,
        is.na(n_encounters_post) | n_encounters_post == 0  ~ NA_integer_,
        is.na(n_sources_post)    | n_sources_post == 0     ~ NA_integer_,
        n_sources_post == 1                                ~ 1L,
        TRUE                                               ~ 0L
      ),
      # Coalesce post counts to 0 for reporting AFTER flag computed
      n_encounters_post = dplyr::coalesce(as.integer(n_encounters_post), 0L),
      n_sources_post    = dplyr::coalesce(as.integer(n_sources_post),    0L),
      # SRC-03: any_blank_source coalesced to FALSE (not NA) for no-encounter patients
      any_blank_source  = dplyr::coalesce(as.logical(any_blank_source), FALSE)
    ) |>
    dplyr::select(
      ID, n_encounters, n_sources, single_source_care, primary_source,
      n_encounters_post, n_sources_post, single_source_care_post,
      any_blank_source, hl_anchor_date
    )
}

# =============================================================================
# SECTION 1 — DuckDB connection (no quit(); opened_here pattern)
# =============================================================================

opened_here <- FALSE
if (!exists("pcornet_con", envir = .GlobalEnv) ||
    !DBI::dbIsValid(get("pcornet_con", envir = .GlobalEnv))) {
  opened_here <- tryCatch(
    { open_pcornet_con(); TRUE },
    error = function(e) {
      message("R/169: DuckDB unavailable — skipping (", conditionMessage(e), ")")
      NA
    }
  )
}
duckdb_ok <- !is.na(opened_here)

if (duckdb_ok) {

  # ---------------------------------------------------------------------------
  # Anchor dates (D-167-04): canonical source — same as R/147, R/165, R/166
  # ---------------------------------------------------------------------------
  anchors <- get_hl_any_dx_ids()
  # tibble(ID chr, hl_anchor_date Date, in_confirmed_cohort lgl)

  cohort_ids_tbl <- dplyr::distinct(anchors, ID)
  anchors_tbl    <- dplyr::select(anchors, ID, hl_anchor_date)

  duckdb::duckdb_register(pcornet_con, "cohort_ids", cohort_ids_tbl)
  duckdb::duckdb_register(pcornet_con, "hl_anchors", anchors_tbl)

  dmin <- format(CONFIG$analysis$date_range_min, "%Y-%m-%d")
  dmax <- format(CONFIG$analysis$date_range_max, "%Y-%m-%d")

  # ---------------------------------------------------------------------------
  # sql_whole: whole-record aggregation
  # One CTE over in-range encounters; SOURCE normalised with NULLIF(UPPER(TRIM()))
  # Blank SOURCE rows counted for any_blank_source but excluded from n_sources
  # (D-167-05; Pitfall 1: COUNT(DISTINCT src) ignores NULLs automatically)
  # ---------------------------------------------------------------------------
  sql_whole <- glue::glue("
    WITH cohort_enc AS (
      SELECT e.ID,
             NULLIF(UPPER(TRIM(e.SOURCE)), '') AS src
      FROM   ENCOUNTER e
      JOIN   cohort_ids c ON c.ID = e.ID
      WHERE  e.ADMIT_DATE IS NOT NULL
        AND  e.ADMIT_DATE BETWEEN '{dmin}' AND '{dmax}'
    )
    SELECT ID,
           COUNT(*)                                    AS n_encounters,
           COUNT(DISTINCT src)                         AS n_sources,
           MAX(CASE WHEN src IS NULL THEN 1 ELSE 0 END) AS any_blank_source
    FROM   cohort_enc
    GROUP BY ID
  ")

  whole_raw <- DBI::dbGetQuery(pcornet_con, sql_whole) |>
    dplyr::mutate(
      n_encounters     = as.integer(n_encounters),
      n_sources        = as.integer(n_sources),
      any_blank_source = as.integer(any_blank_source)
    )

  # ---------------------------------------------------------------------------
  # sql_post: post-anchor window aggregation
  # ADMIT_DATE > hl_anchor_date (anchor day = pre, matching D-167-04 / R/147)
  # Upper bound = date_range_max (D-167-03)
  # ---------------------------------------------------------------------------
  sql_post <- glue::glue("
    WITH post_enc AS (
      SELECT e.ID,
             NULLIF(UPPER(TRIM(e.SOURCE)), '') AS src
      FROM   ENCOUNTER e
      JOIN   cohort_ids c ON c.ID = e.ID
      JOIN   hl_anchors a ON a.ID = e.ID
      WHERE  e.ADMIT_DATE IS NOT NULL
        AND  e.ADMIT_DATE > a.hl_anchor_date
        AND  e.ADMIT_DATE <= '{dmax}'
    )
    SELECT ID,
           COUNT(*)            AS n_encounters_post,
           COUNT(DISTINCT src) AS n_sources_post
    FROM   post_enc
    GROUP BY ID
  ")

  post_raw <- DBI::dbGetQuery(pcornet_con, sql_post) |>
    dplyr::mutate(
      n_encounters_post = as.integer(n_encounters_post),
      n_sources_post    = as.integer(n_sources_post)
    )

  # ---------------------------------------------------------------------------
  # sql_source_counts: per-patient, per-site encounter counts (non-blank only)
  # Used to derive primary_source in build_single_source_result()
  # ---------------------------------------------------------------------------
  sql_source_counts <- glue::glue("
    WITH cohort_enc AS (
      SELECT e.ID,
             NULLIF(UPPER(TRIM(e.SOURCE)), '') AS src
      FROM   ENCOUNTER e
      JOIN   cohort_ids c ON c.ID = e.ID
      WHERE  e.ADMIT_DATE IS NOT NULL
        AND  e.ADMIT_DATE BETWEEN '{dmin}' AND '{dmax}'
    )
    SELECT ID,
           src        AS SOURCE,
           COUNT(*) AS n_enc_at_source
    FROM   cohort_enc
    WHERE  src IS NOT NULL
    GROUP BY ID, src
  ")

  source_counts <- DBI::dbGetQuery(pcornet_con, sql_source_counts) |>
    dplyr::mutate(n_enc_at_source = as.integer(n_enc_at_source))

  # ---------------------------------------------------------------------------
  # sql_na_admit: QC count of cohort encounters with NULL ADMIT_DATE (D-167-03)
  # ---------------------------------------------------------------------------
  sql_na_admit <- glue::glue("
    SELECT COUNT(*) AS n_na_admit
    FROM   ENCOUNTER e
    JOIN   cohort_ids c ON c.ID = e.ID
    WHERE  e.ADMIT_DATE IS NULL
  ")

  n_na_admit <- DBI::dbGetQuery(pcornet_con, sql_na_admit)$n_na_admit[1]

  # =============================================================================
  # SECTION 2 — build result + invariant checks
  # =============================================================================

  result <- build_single_source_result(whole_raw, post_raw, anchors, source_counts)

  stopifnot(
    "one row per anchor patient" =
      dplyr::n_distinct(result$ID) == nrow(result) &&
      nrow(result) == dplyr::n_distinct(anchors$ID),

    "flag values in {0, 1, NA}" =
      all(result$single_source_care %in% c(0L, 1L, NA_integer_)),

    "post flag NA when no post encounters" =
      !any(!is.na(result$single_source_care_post) & result$n_encounters_post == 0),

    "all-blank patients flagged" =
      all(result$any_blank_source[
        !is.na(result$n_sources) & result$n_sources == 0
      ])
  )

  message(glue::glue(
    "[R/169] Cohort patients: {nrow(result)}  ",
    "single-source (whole): {sum(result$single_source_care == 1L, na.rm=TRUE)}  ",
    "any_blank: {sum(result$any_blank_source)}  ",
    "n_na_admit: {n_na_admit}"
  ))

  # =============================================================================
  # SECTION 3 — exports (all under output/internal/)
  # =============================================================================

  int_dir <- file.path(CONFIG$output_dir, "internal")
  dir.create(int_dir, showWarnings = FALSE, recursive = TRUE)

  readr::write_csv(
    result,
    file.path(int_dir, glue::glue("single_source_care_{run_date}.csv"))
  )
  message("[R/169] Wrote CSV: ", file.path(int_dir, glue::glue("single_source_care_{run_date}.csv")))

  saveRDS(
    result,
    file.path(int_dir, glue::glue("single_source_care_{run_date}.rds"))
  )
  message("[R/169] Wrote RDS: ", file.path(int_dir, glue::glue("single_source_care_{run_date}.rds")))

  saveRDS(
    list(
      result       = result,
      source_counts = source_counts,
      n_na_admit   = n_na_admit,
      run_date     = run_date,
      date_range   = c(dmin, dmax)
    ),
    file.path(int_dir, glue::glue("single_source_care_parts_{run_date}.rds"))
  )
  message("[R/169] Wrote parts RDS: ",
          file.path(int_dir, glue::glue("single_source_care_parts_{run_date}.rds")))

  # ---------------------------------------------------------------------------
  # Cleanup — Plan 02 inserts SECTIONS 4-5 (workbook) before this block
  # ---------------------------------------------------------------------------
  duckdb::duckdb_unregister(pcornet_con, "cohort_ids")
  duckdb::duckdb_unregister(pcornet_con, "hl_anchors")
  if (isTRUE(opened_here)) close_pcornet_con()

} # end if (duckdb_ok)
