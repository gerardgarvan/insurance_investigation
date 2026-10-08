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
# SECTION 1 — DuckDB connection (opened_here pattern, never calls quit)
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

  # =============================================================================
  # SECTION 4 — workbook builder functions (computed on raw counts)
  # =============================================================================

  suppressPackageStartupMessages(library(openxlsx))

  UF_BLUE   <- "#0021A5"
  UF_ORANGE <- "#FA4616"

  hdr_style <- openxlsx::createStyle(
    fgFill         = UF_BLUE,
    fontColour     = "white",
    textDecoration = "bold",
    fontName       = "Arial",
    fontSize       = 11,
    halign         = "left",
    border         = "Bottom",
    borderColour   = "white"
  )

  flag_style <- openxlsx::createStyle(
    fgFill         = UF_ORANGE,
    fontColour     = "white",
    textDecoration = "bold"
  )

  #' display_counts(): suppress count columns and blank paired rate columns
  display_counts <- function(df, count_cols = character(0), rate_pairs = list()) {
    for (col in count_cols) {
      if (col %in% names(df)) df[[col]] <- suppress_small(df[[col]])
    }
    for (pair in rate_pairs) {
      cnt_col  <- pair[[1L]]
      rate_col <- pair[[2L]]
      if (cnt_col %in% names(df) && rate_col %in% names(df)) {
        suppressed_rows <- !is.na(df[[cnt_col]]) & df[[cnt_col]] == "<11"
        if (any(suppressed_rows, na.rm = TRUE)) df[[rate_col]][suppressed_rows] <- NA_real_
      }
    }
    df
  }

  #' sup(x): apply suppress_small; "<11" for counts 1-10
  sup <- function(x) suppress_small(x)

  #' pct_safe(num, den): percentage rounded to 1 dp; "" when num or den is 1-10
  pct_safe <- function(num, den) {
    n <- as.integer(num)
    d <- as.integer(den)
    ifelse(
      is.na(n) | is.na(d) | (n >= 1L & n <= 10L) | (d >= 1L & d <= 10L),
      "",
      paste0(round(100 * n / d, 1L), "%")
    )
  }

  #' sup_with_totals(tab): 2-way table with totals derived from RAW counts.
  #' Suppresses interior cells 1-10; if a row/column has exactly one suppressed
  #' interior cell, also suppresses that row's/column's total.
  #'
  #' @param tab data.frame: first column is row label; last column is row total;
  #'   last row is column totals row; interior = rows[1:(n-1)], cols[2:(m-1)].
  #'   All count cells are raw integers on entry; function applies sup() and
  #'   complementary suppression, then returns as character data.frame.
  sup_with_totals <- function(tab) {
    tab  <- as.data.frame(tab, stringsAsFactors = FALSE)
    nrow <- nrow(tab)
    ncol <- ncol(tab)
    if (nrow < 2L || ncol < 3L) return(tab)  # guard: need at least 1 interior cell

    # Interior rows = all but last; interior cols = 2..(ncol-1)
    interior_rows <- seq_len(nrow - 1L)
    interior_cols <- seq(2L, ncol - 1L)

    # Store raw counts for suppression decisions; convert all to character at end
    raw <- tab
    for (i in seq_len(nrow)) {
      for (j in seq_len(ncol)) {
        v <- suppressWarnings(as.integer(raw[i, j]))
        raw[i, j] <- if (!is.na(v)) v else raw[i, j]
      }
    }

    # Helper: is a cell suppressed?
    is_suppressed <- function(r, c) {
      v <- suppressWarnings(as.integer(raw[r, c]))
      !is.na(v) && v >= 1L && v <= 10L
    }

    # Build character output frame
    out <- tab
    for (i in seq_len(nrow)) {
      for (j in seq_len(ncol)) {
        v <- suppressWarnings(as.integer(raw[i, j]))
        if (!is.na(v)) out[i, j] <- as.character(sup(v))
      }
    }

    # Complementary suppression of row totals
    for (i in interior_rows) {
      n_supp <- sum(vapply(interior_cols, function(j) is_suppressed(i, j), logical(1L)))
      if (n_supp == 1L) out[i, ncol] <- "<11"
    }

    # Complementary suppression of column totals
    for (j in interior_cols) {
      n_supp <- sum(vapply(interior_rows, function(i) is_suppressed(i, j), logical(1L)))
      if (n_supp == 1L) out[nrow, j] <- "<11"
    }

    out
  }

  # ---------------------------------------------------------------------------
  # Builder: population_rows
  # Rows: cohort, no encounters, all-blank SOURCE, flagged denominator,
  # single-source, % single-source
  # ---------------------------------------------------------------------------
  population_rows <- function(df, n_enc_col, flag_col, n_src_col) {
    n_cohort   <- nrow(df)
    n_no_enc   <- sum(is.na(df[[n_enc_col]]) | df[[n_enc_col]] == 0L, na.rm = FALSE)
    # all-blank: had encounters but n_sources == 0 (all SOURCE blank after trim)
    n_all_blank <- sum(
      !is.na(df[[n_enc_col]]) & df[[n_enc_col]] > 0L &
        !is.na(df[[n_src_col]]) & df[[n_src_col]] == 0L,
      na.rm = TRUE
    )
    n_flagged  <- sum(!is.na(df[[flag_col]]), na.rm = TRUE)
    n_single   <- sum(df[[flag_col]] == 1L, na.rm = TRUE)
    pct_single <- pct_safe(n_single, n_flagged)

    data.frame(
      Metric = c(
        "Patients in cohort",
        "No encounters in window",
        "Encounters in window but SOURCE all blank",
        "Patients with a flag (denominator)",
        "Single-source",
        "% single-source"
      ),
      Value = c(
        sup(n_cohort),
        sup(n_no_enc),
        sup(n_all_blank),
        sup(n_flagged),
        sup(n_single),
        pct_single
      ),
      stringsAsFactors = FALSE
    )
  }

  # ---------------------------------------------------------------------------
  # Builder: band_crosstab
  # Bands: 1 | 2-4 | 5-9 | 10+; restricted to non-NA flag only
  # ---------------------------------------------------------------------------
  band_crosstab <- function(df, enc_col, flag_col) {
    df2 <- df[!is.na(df[[flag_col]]), , drop = FALSE]
    enc  <- df2[[enc_col]]
    flg  <- df2[[flag_col]]
    band <- cut(enc,
                breaks = c(0L, 1L, 4L, 9L, Inf),
                labels = c("1", "2-4", "5-9", "10+"),
                right  = TRUE)
    out <- data.frame(
      band             = levels(band),
      n_patients       = NA_integer_,
      n_single_source  = NA_integer_,
      pct_single_source = NA_character_,
      stringsAsFactors = FALSE
    )
    for (i in seq_along(levels(band))) {
      b <- levels(band)[i]
      mask <- !is.na(band) & band == b
      n_pat <- sum(mask)
      n_sng <- sum(flg[mask] == 1L, na.rm = TRUE)
      out$n_patients[i]        <- n_pat
      out$n_single_source[i]   <- n_sng
      out$pct_single_source[i] <- pct_safe(n_sng, n_pat)
    }
    out$n_patients      <- vapply(out$n_patients,     sup, character(1L))
    out$n_single_source <- vapply(out$n_single_source, sup, character(1L))
    out
  }

  # ---------------------------------------------------------------------------
  # Builder: n_sources_dist
  # n_sources >= 1; cap "4+"; "4+" sorts last
  # ---------------------------------------------------------------------------
  n_sources_dist <- function(df, nsrc_col) {
    vals <- df[[nsrc_col]]
    vals <- vals[!is.na(vals) & vals >= 1L]
    cats <- ifelse(vals >= 4L, "4+", as.character(vals))
    tab  <- sort(table(cats), decreasing = FALSE)
    # Ensure "4+" is last
    lvls <- c(setdiff(names(tab), "4+"), if ("4+" %in% names(tab)) "4+")
    tab  <- tab[lvls]
    out  <- data.frame(
      n_sources  = names(tab),
      n_patients = as.integer(tab),
      stringsAsFactors = FALSE
    )
    out$n_patients <- vapply(out$n_patients, sup, character(1L))
    out
  }

  # ---------------------------------------------------------------------------
  # Builder: by_source_single
  # Flag == 1 only; count primary_source; descending order
  # ---------------------------------------------------------------------------
  by_source_single <- function(df) {
    sub <- df[!is.na(df$single_source_care) & df$single_source_care == 1L, , drop = FALSE]
    if (nrow(sub) == 0L) {
      return(data.frame(primary_source = character(0),
                        n_patients     = character(0),
                        stringsAsFactors = FALSE))
    }
    counts <- sort(table(sub$primary_source), decreasing = TRUE)
    out <- data.frame(
      primary_source = names(counts),
      n_patients     = vapply(as.integer(counts), sup, character(1L)),
      stringsAsFactors = FALSE
    )
    out
  }

  # ---------------------------------------------------------------------------
  # by_source_single for post-anchor window (flag_col and primary_source differ)
  # For post: primary_source is still primary_source (whole-record most common site)
  # but filtering is on single_source_care_post == 1
  # ---------------------------------------------------------------------------
  by_source_single_post <- function(df) {
    sub <- df[!is.na(df$single_source_care_post) & df$single_source_care_post == 1L, , drop = FALSE]
    if (nrow(sub) == 0L) {
      return(data.frame(primary_source = character(0),
                        n_patients     = character(0),
                        stringsAsFactors = FALSE))
    }
    counts <- sort(table(sub$primary_source), decreasing = TRUE)
    out <- data.frame(
      primary_source = names(counts),
      n_patients     = vapply(as.integer(counts), sup, character(1L)),
      stringsAsFactors = FALSE
    )
    out
  }

  # =============================================================================
  # SECTION 5 — workbook assembly
  # Sheet order: KEY, A_summary, B_post_anchor, QC
  # =============================================================================

  message("[R/169] Building workbook...")
  wb <- openxlsx::createWorkbook()

  # Helper: add a sheet and write a data frame with the header style
  add_sheet <- function(wb, sheet_name, df, header_style = hdr_style,
                        start_row = 1L) {
    openxlsx::addWorksheet(wb, sheet_name)
    if (!is.null(df) && nrow(df) > 0L) {
      openxlsx::writeData(wb, sheet_name, df, startRow = start_row,
                          headerStyle = header_style)
      openxlsx::setColWidths(wb, sheet_name,
                             cols = seq_len(ncol(df)), widths = "auto")
    }
    invisible(wb)
  }

  # ---- KEY sheet ----
  message("[R/169] Writing KEY sheet...")
  key_rows <- data.frame(
    Field = c(
      "Run date",
      "Script",
      "D-167-01",
      "D-167-02",
      "D-167-03",
      "D-167-04",
      "D-167-05",
      "D-167-06",
      "D-167-07",
      "Date range",
      "Anchor source",
      "SOURCE normalisation",
      "Flag definition",
      "Whole-record window",
      "Post-anchor window",
      "Suppression rule",
      "Sheet guide",
      "Patient-level files note"
    ),
    Value = c(
      run_date,
      "R/169_single_source_care.R",
      "D-167-01: ENCOUNTER only. No other CDM tables unioned.",
      "D-167-02: Whole-record and post-HL-anchor delivered as separate columns on every output row.",
      "D-167-03: Whole-record window covers all cohort encounters with ADMIT_DATE within CONFIG$analysis date range (same bounds R/01 applies, Phase 136). Encounters with missing ADMIT_DATE excluded from both windows and counted in QC.",
      "D-167-04: Anchor dates from get_hl_any_dx_ids() — same source R/147, R/165, R/166 use. Post-anchor window: ADMIT_DATE > hl_anchor_date (anchor day = pre). No anchor: whole-record flag computed; post-anchor flag = NA. Anchor present, zero post-anchor encounters: post-anchor flag = NA (not 0).",
      "D-167-05: single_source_care and n_sources computed over non-blank SOURCE values only. Patients with any blank/NA SOURCE get any_blank_source = TRUE. QC counts patients with any_blank_source = TRUE. Sensitivity row treats blank as its own site.",
      "D-167-06: n/% single-source, n_sources distribution (4+ cap), by-SOURCE breakdown for single-source patients, encounter-count bands (1 | 2-4 | 5-9 | 10+), 2x2 whole vs post.",
      "D-167-07: Output columns: ID, n_encounters, n_sources, single_source_care, primary_source, n_encounters_post, n_sources_post, single_source_care_post, any_blank_source. primary_source = most common site (alphabetical tiebreak).",
      glue::glue("{dmin} to {dmax}"),
      "get_hl_any_dx_ids() (same as R/147 anchor source)",
      "UPPER(TRIM(SOURCE)); blank = empty string after trim; NULLified via NULLIF — excluded from n_sources count but flagged via any_blank_source",
      "1 = one distinct non-blank SOURCE site; 0 = two or more distinct non-blank SOURCE sites; NA = no encounters in window OR all SOURCE values blank",
      glue::glue("ADMIT_DATE BETWEEN {dmin} AND {dmax}"),
      glue::glue("ADMIT_DATE > hl_anchor_date AND <= {dmax} (anchor day counted as pre-anchor)"),
      "Counts 1-10 displayed as '<11'. Percentages blanked when derived from a suppressed count. Tables with row/column totals: if exactly one interior cell in a row/column is suppressed, that row's/column's total is also suppressed (complementary suppression).",
      "KEY (this sheet) | A_summary (whole-record window) | B_post_anchor (post-anchor window) | QC (data quality and sensitivity)",
      "Patient-level files (CSV + RDS with IDs) are in output/internal/ — not in output/ root."
    ),
    stringsAsFactors = FALSE
  )
  add_sheet(wb, "KEY", key_rows)

  # ---- A_summary sheet (whole-record window) ----
  message("[R/169] Writing A_summary sheet...")
  openxlsx::addWorksheet(wb, "A_summary")
  a_write_row <- 1L

  # Block 1: population rows
  a_title_pop <- data.frame(Section = "Population summary — whole-record window",
                            stringsAsFactors = FALSE)
  openxlsx::writeData(wb, "A_summary", a_title_pop, startRow = a_write_row,
                      headerStyle = hdr_style)
  a_write_row <- a_write_row + 2L
  a_pop <- population_rows(result, "n_encounters", "single_source_care", "n_sources")
  openxlsx::writeData(wb, "A_summary", a_pop, startRow = a_write_row,
                      headerStyle = hdr_style)
  openxlsx::setColWidths(wb, "A_summary", cols = 1:2, widths = "auto")
  a_write_row <- a_write_row + nrow(a_pop) + 2L

  # Block 2: encounter band crosstab
  a_title_band <- data.frame(Section = "Encounter count bands — whole-record window",
                             stringsAsFactors = FALSE)
  openxlsx::writeData(wb, "A_summary", a_title_band, startRow = a_write_row,
                      headerStyle = hdr_style)
  a_write_row <- a_write_row + 2L
  a_band <- band_crosstab(result, "n_encounters", "single_source_care")
  openxlsx::writeData(wb, "A_summary", a_band, startRow = a_write_row,
                      headerStyle = hdr_style)
  a_write_row <- a_write_row + nrow(a_band) + 2L

  # Block 3: n_sources distribution
  a_title_src <- data.frame(Section = "n_sources distribution (whole-record; n_sources >= 1)",
                            stringsAsFactors = FALSE)
  openxlsx::writeData(wb, "A_summary", a_title_src, startRow = a_write_row,
                      headerStyle = hdr_style)
  a_write_row <- a_write_row + 2L
  a_nsrc <- n_sources_dist(result, "n_sources")
  openxlsx::writeData(wb, "A_summary", a_nsrc, startRow = a_write_row,
                      headerStyle = hdr_style)
  a_write_row <- a_write_row + nrow(a_nsrc) + 2L

  # Block 4: by-SOURCE breakdown for single-source patients
  a_title_by_src <- data.frame(Section = "By-SOURCE breakdown — single-source patients (whole-record)",
                               stringsAsFactors = FALSE)
  openxlsx::writeData(wb, "A_summary", a_title_by_src, startRow = a_write_row,
                      headerStyle = hdr_style)
  a_write_row <- a_write_row + 2L
  a_by_src <- by_source_single(result)
  if (nrow(a_by_src) > 0L) {
    openxlsx::writeData(wb, "A_summary", a_by_src, startRow = a_write_row,
                        headerStyle = hdr_style)
  }

  # ---- B_post_anchor sheet (post-anchor window) ----
  message("[R/169] Writing B_post_anchor sheet...")
  openxlsx::addWorksheet(wb, "B_post_anchor")
  b_write_row <- 1L

  # Block 1: population rows (post)
  # Temporarily recast post columns to match population_rows expectations
  result_post_view <- result |>
    dplyr::mutate(
      n_enc_post_int = as.integer(n_encounters_post),
      n_src_post_int = as.integer(n_sources_post)
    )
  # For post: "no encounters" = n_encounters_post == 0 AND anchor present
  # population_rows treats NA n_enc_col as "no encounters"; we recode
  result_post_for_pop <- result_post_view |>
    dplyr::mutate(
      n_enc_post_disp = dplyr::if_else(
        is.na(hl_anchor_date), NA_integer_, n_enc_post_int
      )
    )

  b_title_pop <- data.frame(
    Section = "Population summary — post-anchor window (anchor present AND >= 1 post-anchor encounter with non-blank SOURCE)",
    stringsAsFactors = FALSE
  )
  openxlsx::writeData(wb, "B_post_anchor", b_title_pop, startRow = b_write_row,
                      headerStyle = hdr_style)
  b_write_row <- b_write_row + 2L
  b_pop <- population_rows(result_post_for_pop, "n_enc_post_disp",
                           "single_source_care_post", "n_src_post_int")
  openxlsx::writeData(wb, "B_post_anchor", b_pop, startRow = b_write_row,
                      headerStyle = hdr_style)
  openxlsx::setColWidths(wb, "B_post_anchor", cols = 1:2, widths = "auto")
  b_write_row <- b_write_row + nrow(b_pop) + 2L

  # Block 2: encounter band crosstab (post)
  b_title_band <- data.frame(
    Section = "Encounter count bands — post-anchor window",
    stringsAsFactors = FALSE
  )
  openxlsx::writeData(wb, "B_post_anchor", b_title_band, startRow = b_write_row,
                      headerStyle = hdr_style)
  b_write_row <- b_write_row + 2L
  b_band <- band_crosstab(result_post_for_pop, "n_enc_post_disp",
                          "single_source_care_post")
  openxlsx::writeData(wb, "B_post_anchor", b_band, startRow = b_write_row,
                      headerStyle = hdr_style)
  b_write_row <- b_write_row + nrow(b_band) + 2L

  # Block 3: n_sources distribution (post)
  b_title_src <- data.frame(
    Section = "n_sources distribution (post-anchor; n_sources_post >= 1)",
    stringsAsFactors = FALSE
  )
  openxlsx::writeData(wb, "B_post_anchor", b_title_src, startRow = b_write_row,
                      headerStyle = hdr_style)
  b_write_row <- b_write_row + 2L
  b_nsrc <- n_sources_dist(result_post_for_pop, "n_src_post_int")
  openxlsx::writeData(wb, "B_post_anchor", b_nsrc, startRow = b_write_row,
                      headerStyle = hdr_style)
  b_write_row <- b_write_row + nrow(b_nsrc) + 2L

  # Block 4: by-SOURCE breakdown for single-source patients (post)
  b_title_by_src <- data.frame(
    Section = "By-SOURCE breakdown — single-source patients (post-anchor)",
    stringsAsFactors = FALSE
  )
  openxlsx::writeData(wb, "B_post_anchor", b_title_by_src, startRow = b_write_row,
                      headerStyle = hdr_style)
  b_write_row <- b_write_row + 2L
  b_by_src <- by_source_single_post(result)
  if (nrow(b_by_src) > 0L) {
    openxlsx::writeData(wb, "B_post_anchor", b_by_src, startRow = b_write_row,
                        headerStyle = hdr_style)
  }

  # ---- QC sheet ----
  message("[R/169] Writing QC sheet...")
  openxlsx::addWorksheet(wb, "QC")
  qc_row <- 1L

  # QC block 1: missing ADMIT_DATE
  qc_admit_header <- data.frame(
    Section = "Data quality — missing ADMIT_DATE (D-167-03)",
    stringsAsFactors = FALSE
  )
  openxlsx::writeData(wb, "QC", qc_admit_header, startRow = qc_row,
                      headerStyle = hdr_style)
  qc_row <- qc_row + 2L
  qc_admit <- data.frame(
    Metric = "Encounters excluded for missing ADMIT_DATE",
    Value  = sup(as.integer(n_na_admit)),
    stringsAsFactors = FALSE
  )
  openxlsx::writeData(wb, "QC", qc_admit, startRow = qc_row,
                      headerStyle = hdr_style)
  qc_row <- qc_row + nrow(qc_admit) + 2L

  # QC block 2: blank SOURCE counts
  n_any_blank   <- sum(result$any_blank_source, na.rm = TRUE)
  n_all_blank_w <- sum(
    !is.na(result$n_encounters) & result$n_encounters > 0L &
      !is.na(result$n_sources) & result$n_sources == 0L,
    na.rm = TRUE
  )
  qc_blank_header <- data.frame(
    Section = "Blank SOURCE patients (D-167-05)",
    stringsAsFactors = FALSE
  )
  openxlsx::writeData(wb, "QC", qc_blank_header, startRow = qc_row,
                      headerStyle = hdr_style)
  qc_row <- qc_row + 2L
  qc_blank <- data.frame(
    Metric = c(
      "Patients with any blank SOURCE (whole-record)",
      "Patients with all-blank SOURCE (whole-record)"
    ),
    Value = c(sup(n_any_blank), sup(n_all_blank_w)),
    stringsAsFactors = FALSE
  )
  # Flag the any-blank row with flag_style
  openxlsx::writeData(wb, "QC", qc_blank, startRow = qc_row,
                      headerStyle = hdr_style)
  openxlsx::addStyle(wb, "QC", style = flag_style,
                     rows = qc_row + 1L, cols = 1:2, gridExpand = TRUE)
  qc_row <- qc_row + nrow(qc_blank) + 2L

  # QC block 3: post-anchor NA reasons
  n_na_no_anchor     <- sum(is.na(result$hl_anchor_date), na.rm = FALSE)
  n_na_no_post_enc   <- sum(
    !is.na(result$hl_anchor_date) & result$n_encounters_post == 0L,
    na.rm = TRUE
  )
  n_na_post_all_blank <- sum(
    !is.na(result$hl_anchor_date) & result$n_encounters_post > 0L &
      is.na(result$single_source_care_post),
    na.rm = TRUE
  )
  qc_na_header <- data.frame(
    Section = "Post-anchor flag NA reasons (D-167-04)",
    stringsAsFactors = FALSE
  )
  openxlsx::writeData(wb, "QC", qc_na_header, startRow = qc_row,
                      headerStyle = hdr_style)
  qc_row <- qc_row + 2L
  qc_na <- data.frame(
    NA_reason = c(
      "No anchor date (single_source_care_post = NA)",
      "Anchor present but no post-anchor encounters (n_encounters_post = 0)",
      "Post-anchor encounters present but all SOURCE blank (single_source_care_post = NA)"
    ),
    n_patients = c(
      sup(n_na_no_anchor),
      sup(n_na_no_post_enc),
      sup(n_na_post_all_blank)
    ),
    stringsAsFactors = FALSE
  )
  openxlsx::writeData(wb, "QC", qc_na, startRow = qc_row,
                      headerStyle = hdr_style)
  qc_row <- qc_row + nrow(qc_na) + 2L

  # QC block 4: SENSITIVITY — blank treated as own site
  # n_single_primary: single-source patients (primary classification)
  n_single_primary <- sum(result$single_source_care == 1L, na.rm = TRUE)
  # n_flip: single-source with any blank SOURCE (would become multi if blank counted)
  n_flip <- sum(
    !is.na(result$single_source_care) & result$single_source_care == 1L &
      result$any_blank_source,
    na.rm = TRUE
  )
  # n_all_blank_sense: patients with all-blank SOURCE (would become single-source
  # if blank counted as a site — they currently have NA flag)
  n_all_blank_sense <- sum(
    !is.na(result$n_encounters) & result$n_encounters > 0L &
      !is.na(result$n_sources) & result$n_sources == 0L,
    na.rm = TRUE
  )
  n_single_sensitivity <- n_single_primary - n_flip + n_all_blank_sense

  qc_sens_header <- data.frame(
    Section = "SENSITIVITY — blank SOURCE treated as own site (whole-record)",
    stringsAsFactors = FALSE
  )
  openxlsx::writeData(wb, "QC", qc_sens_header, startRow = qc_row,
                      headerStyle = hdr_style)
  # Apply flag_style to sensitivity header row
  openxlsx::addStyle(wb, "QC", style = flag_style,
                     rows = qc_row, cols = 1L, gridExpand = FALSE)
  qc_row <- qc_row + 2L
  qc_sens <- data.frame(
    Metric = c(
      "n_single_primary (primary classification, blank excluded)",
      "n_flip (single-source with any blank → would become multi-source)",
      "n_all_blank (currently NA flag → would become single-source)",
      "n_single_sensitivity = n_single_primary - n_flip + n_all_blank"
    ),
    Value = c(
      sup(n_single_primary),
      sup(n_flip),
      sup(n_all_blank_sense),
      sup(n_single_sensitivity)
    ),
    stringsAsFactors = FALSE
  )
  openxlsx::writeData(wb, "QC", qc_sens, startRow = qc_row,
                      headerStyle = hdr_style)
  qc_row <- qc_row + nrow(qc_sens) + 2L

  # QC block 5: 2x2 whole-record flag x post-anchor flag
  # Patients with both flags non-NA
  both_flagged <- result[
    !is.na(result$single_source_care) & !is.na(result$single_source_care_post),
  ]
  # Build 2x2 raw counts
  cross_tab <- with(both_flagged, table(
    whole_record = single_source_care,
    post_anchor  = single_source_care_post
  ))
  # Convert to data.frame with totals
  ct_mat  <- as.matrix(cross_tab)
  row_tot <- rowSums(ct_mat)
  col_tot <- colSums(ct_mat)
  grand   <- sum(ct_mat)
  # Build data.frame: rows = whole-record (0, 1, Total); cols = post-anchor (0, 1, Total)
  post_vals <- colnames(ct_mat)
  whole_vals <- rownames(ct_mat)
  twobytwo <- data.frame(
    whole_vs_post = c(paste0("whole=", whole_vals), "Total"),
    stringsAsFactors = FALSE
  )
  for (pv in post_vals) {
    col_vals <- c(ct_mat[, pv], col_tot[pv])
    twobytwo[[paste0("post=", pv)]] <- col_vals
  }
  twobytwo$Total <- c(row_tot, grand)

  twobytwo_sup <- sup_with_totals(twobytwo)

  qc_2x2_header <- data.frame(
    Section = "2x2: whole-record single_source_care x post-anchor single_source_care (patients with both non-NA)",
    stringsAsFactors = FALSE
  )
  openxlsx::writeData(wb, "QC", qc_2x2_header, startRow = qc_row,
                      headerStyle = hdr_style)
  qc_row <- qc_row + 2L
  openxlsx::writeData(wb, "QC", twobytwo_sup, startRow = qc_row,
                      headerStyle = hdr_style)
  openxlsx::setColWidths(wb, "QC", cols = seq_len(ncol(twobytwo_sup)),
                         widths = "auto")

  # ---- Save workbook ----
  xlsx_path <- file.path(CONFIG$output_dir,
                         glue::glue("single_source_care_{run_date}.xlsx"))
  openxlsx::saveWorkbook(wb, xlsx_path, overwrite = TRUE)
  message("[R/169] Workbook saved: ", xlsx_path)

  # ---------------------------------------------------------------------------
  # Cleanup — duckdb temp tables and connection
  # ---------------------------------------------------------------------------
  duckdb::duckdb_unregister(pcornet_con, "cohort_ids")
  duckdb::duckdb_unregister(pcornet_con, "hl_anchors")
  if (isTRUE(opened_here)) close_pcornet_con()

} # end if (duckdb_ok)
