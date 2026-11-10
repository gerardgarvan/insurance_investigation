# ==============================================================================
# utils/utils_distance_cbc.R -- Phase 165 shared helpers for distance-CBC analysis
# ==============================================================================
#
# Purpose:
#   Pure-function helpers shared by R/163 (prototype) and R/165 (production).
#   Builds the encounter- and patient-level analysis sets for the far_from_care_100mi
#   indicator and CBC association analysis. Auto-sourced by 00_config.R via the
#   utils glob (list.files("R/utils")).
#
# Inputs (all provided by callers; no global state read here):
#   con          -- DBI/DuckDB connection (open, read-only)
#   enc_distance -- tibble from readRDS(enc_distance RDS); R/122 output
#   cbc_events   -- tibble(ID, cbc_date) returned by build_cbc_events()
#   anchors      -- tibble(ID, hl_anchor_date) from get_hl_any_dx_ids()
#   enc_dates    -- tibble(ENCOUNTERID, ADMIT_DATE, DISCHARGE_DATE, SOURCE)
#                   pulled from ENCOUNTER via DuckDB by the caller
#   cutoff       -- numeric scalar (CONFIG$far_from_care_cutoff_mi)
#
# Outputs (returned values, no I/O):
#   build_cbc_events()   -> tibble(ID, cbc_date)
#   build_enc_analysis() -> tibble with encounter-level analysis set
#   build_pat_analysis() -> tibble with patient-level analysis set
#   suppress_small_vec() -> integer vector with 1-10 replaced by NA_integer_
#   suppress_display()   -> character vector with 1-10 replaced by "<11"
#   naive_or_se()        -> list(log_or, se, haldane)
#
# Dependencies:
#   dplyr, lubridate (both loaded via 00_config -> library chain)
#   DBI (for DuckDB queries in build_cbc_events)
#   utils_duckdb.R (auto-sourced: safe_table())
#
# Requirements: ACC-01, ACC-02 (Phase 165)
#
# ==============================================================================

# ------------------------------------------------------------------------------
# suppress_small_vec() -- vectorized integer suppression (analysis use)
# Returns NA_integer_ for counts 1-10; 0 and counts > 10 are unchanged.
# WHY separate from utils_surveillance::suppress_small(): that version returns
# the "<11" string for HIPAA table display. This version preserves integer type
# for arithmetic while masking small cells before tabulation.
# ------------------------------------------------------------------------------
suppress_small_vec <- function(n) {
  ifelse(!is.na(n) & n >= 1L & n <= 10L, NA_integer_, as.integer(n))
}

# ------------------------------------------------------------------------------
# suppress_display() -- vectorized display suppression (table output use)
# Returns "<11" string for counts 1-10; 0 and counts > 10 returned as character.
# Matches the pipeline convention in utils_surveillance::suppress_small().
# ------------------------------------------------------------------------------
suppress_display <- function(n) {
  ifelse(!is.na(n) & n >= 1L & n <= 10L, "<11", as.character(n))
}

# ------------------------------------------------------------------------------
# naive_or_se() -- Woolf log-OR and SE from a 2x2 contingency table
#
# @param ct  2x2 matrix: rows = exposure (0 = not far, 1 = far), cols = outcome
#            (0 = no CBC, 1 = CBC). Produced by table(far, cbc) with those levels.
# @return    list(log_or, se, haldane)
#              log_or  -- log odds ratio (Woolf)
#              se      -- SE of log_or
#              haldane -- TRUE if any cell was zero (Haldane 0.5 correction applied)
#
# WHY Haldane correction: a zero cell makes the log-OR undefined. Adding 0.5 to
# all cells is the standard continuity correction when expected cells are small.
# The flag ensures the correction is visible in printed output and the memo.
# ------------------------------------------------------------------------------
naive_or_se <- function(ct) {
  stopifnot(
    "ct must be a 2x2 matrix" = is.matrix(ct),
    "ct must have dim c(2,2)"  = all(dim(ct) == c(2L, 2L))
  )
  # Convert to double before any arithmetic: integer overflow occurs at scale
  # (e.g., 120000L * 65000L = 7.8e9, which exceeds .Machine$integer.max = 2.1e9).
  m <- matrix(as.numeric(ct), nrow = 2)
  haldane <- any(m == 0)
  if (haldane) m <- m + 0.5
  log_or <- log((m[2L, 2L] * m[1L, 1L]) / (m[2L, 1L] * m[1L, 2L]))
  se     <- sqrt(sum(1 / m))
  list(log_or = log_or, se = se, haldane = haldane)
}

# ------------------------------------------------------------------------------
# build_cbc_events() -- derive CBC events (whole record) from DuckDB
#
# A CBC event = WBC (6690-2) + Hgb (718-7) + PLT (777-3) resulted on the SAME
# calendar date for the SAME patient. This matches R/147's locked definition
# (D-22 sensitivity tier; CONTEXT.md D-05).
#
# Date column priority matches R/147 (line 183):
#   coalesce(RESULT_DATE, SPECIMEN_DATE, LAB_ORDER_DATE)
#
# Pre-anchor events are included (whole-record coverage per CONTEXT.md D-06a).
# R/147's saved RDS files are post-anchor only, so we always re-derive here.
#
# @param con  Open DBI/DuckDB connection (read-only; caller opens and closes)
# @param ids  Character vector of patient IDs to scope the query (HL cohort)
#
# @return tibble(ID chr, cbc_date Date) — DISTINCT rows; one row per patient x date
#         that had all three CBC components resulted.
#
# WHY DuckDB SQL push-down: LAB_RESULT_CM is large; filtering by ID and LOINC
# before collect() avoids pulling millions of rows into R memory.
# ------------------------------------------------------------------------------
build_cbc_events <- function(con, ids) {
  stopifnot(
    "con must be a DBI connection" = inherits(con, "DBIConnection"),
    "ids must be a non-empty character vector" = is.character(ids) && length(ids) > 0
  )

  cbc_loincs <- c("6690-2", "718-7", "777-3")  # WBC, Hgb, PLT (R/147 D-22)

  # Build a parameterised IN clause. DuckDB handles up to ~65k values safely.
  id_list    <- paste(sprintf("'%s'", ids),    collapse = ", ")
  loinc_list <- paste(sprintf("'%s'", cbc_loincs), collapse = ", ")

  sql <- sprintf("
    SELECT
      ID,
      LAB_LOINC,
      COALESCE(
        TRY_CAST(RESULT_DATE   AS DATE),
        TRY_CAST(SPECIMEN_DATE AS DATE),
        TRY_CAST(LAB_ORDER_DATE AS DATE)
      ) AS cbc_date
    FROM LAB_RESULT_CM
    WHERE ID       IN (%s)
      AND LAB_LOINC IN (%s)
  ", id_list, loinc_list)

  raw <- DBI::dbGetQuery(con, sql)
  raw$cbc_date <- as.Date(raw$cbc_date)

  # Keep only dates where all three LOINC codes are present for the same ID x date
  # (matches R/147 D-22 "all same calendar date" rule).
  three_present <- raw |>
    dplyr::filter(!is.na(cbc_date)) |>
    dplyr::distinct(ID, LAB_LOINC, cbc_date) |>
    dplyr::count(ID, cbc_date, name = "n_loincs") |>
    dplyr::filter(n_loincs == 3L) |>  # all three components on the same day
    dplyr::select(ID, cbc_date)

  three_present
}

# ------------------------------------------------------------------------------
# assign_analytic_source() -- Reassign claims-sourced encounters for stratification
# (Phase 192.3)
#
# Temporal rule (matches get_zip9_at_date() exactly):
#   1. Address lookup: select the in-effect LDS_ADDRESS_HISTORY row at ADMIT_DATE.
#      Pass 1 — exact interval: ADDRESS_PERIOD_START <= ADMIT_DATE < ADDRESS_PERIOD_END
#      (missing/blank ADDRESS_PERIOD_END treated as 9999-12-31).
#      Pass 2 — most-recent-before: largest ADDRESS_PERIOD_START <= ADMIT_DATE.
#      Interval match wins over recency fallback for the same encounter.
#      THEN check the selected row's SOURCE: accept only when SOURCE is non-blank
#      and NOT in config$claims_source_codes. If the selected row's SOURCE is unusable,
#      fall through to Step 2 — do NOT look at a different address row.
#   2. Modal non-claims SOURCE: modal SOURCE from enc_all (whole-record) where
#      SOURCE_all is NOT in config$claims_source_codes. Modal computed from enc_all rows
#      where `SOURCE %in% config$claims_source_codes` is FALSE. Ties: most recent
#      ADMIT_DATE (from enc_all), then alphabetical SOURCE. enc_all MUST be the
#      unfiltered cohort ENCOUNTER table — not derived from enc.
#   3. Unresolved: SOURCE_analytic = "Claims_unresolved". Kept; not dropped.
#
# CRITICAL ORDER: Temporal rule applied first, THEN SOURCE quality check.
# Never skip to an older/different address row based on SOURCE quality.
# After the in-effect row is identified, THEN check whether its SOURCE is usable.
#
# enc_all MUST be the unfiltered cohort ENCOUNTER data passed from the caller,
# NOT derived from enc (which may already be restricted to encounters with
# computed distances). Modal SOURCE computed from enc_all rows where
# `SOURCE %in% config$claims_source_codes` is FALSE.
#
# @param enc       tibble: ID (chr), ENCOUNTERID (chr), ADMIT_DATE (Date), SOURCE (chr).
# @param enc_all   tibble: ID (chr), ADMIT_DATE (Date), SOURCE (chr) — ALL cohort ENCOUNTER rows.
# @param addr_full LDS_ADDRESS_HISTORY tibble (character columns):
#                  ID, ADDRESS_PERIOD_START, ADDRESS_PERIOD_END, SOURCE.
# @param config    list with element `claims_source_codes` (character vector).
#
# @return enc with four new columns:
#   SOURCE_raw             -- original SOURCE (never modified)
#   SOURCE_analytic        -- reassigned value for stratification
#   source_reassigned      -- 0L/1L flag (1 for address or modal_encounter)
#   source_reassign_method -- "not_reassigned", "address", "modal_encounter", "unresolved"
# ------------------------------------------------------------------------------
assign_analytic_source <- function(enc, enc_all, addr_full, config) {
  stopifnot(
    "enc must be a data.frame"                 = is.data.frame(enc),
    "enc_all must be a data.frame"             = is.data.frame(enc_all),
    "addr_full must be a data.frame"           = is.data.frame(addr_full),
    "enc must have ID"                         = "ID" %in% names(enc),
    "enc must have ENCOUNTERID"                = "ENCOUNTERID" %in% names(enc),
    "enc must have ADMIT_DATE"                 = "ADMIT_DATE" %in% names(enc),
    "enc must have SOURCE"                     = "SOURCE" %in% names(enc),
    "enc_all must have ID"                     = "ID" %in% names(enc_all),
    "enc_all must have ADMIT_DATE"             = "ADMIT_DATE" %in% names(enc_all),
    "enc_all must have SOURCE"                 = "SOURCE" %in% names(enc_all),
    "addr_full must have ID"                   = "ID" %in% names(addr_full),
    "addr_full must have ADDRESS_PERIOD_START" = "ADDRESS_PERIOD_START" %in% names(addr_full),
    "addr_full must have ADDRESS_PERIOD_END"   = "ADDRESS_PERIOD_END" %in% names(addr_full),
    "addr_full must have SOURCE"               = "SOURCE" %in% names(addr_full),
    "config must have claims_source_codes"     = !is.null(config$claims_source_codes)
  )

  # Rename SOURCE to SOURCE_raw
  enc <- enc |> dplyr::rename(SOURCE_raw = SOURCE)

  # Split into claims-sourced and non-claims rows
  enc_claims    <- enc |> dplyr::filter( SOURCE_raw %in% config$claims_source_codes)
  enc_nonclaims <- enc |> dplyr::filter(!SOURCE_raw %in% config$claims_source_codes)
  enc_nonclaims <- enc_nonclaims |>
    dplyr::mutate(
      SOURCE_analytic        = SOURCE_raw,
      source_reassigned      = 0L,
      source_reassign_method = "not_reassigned"
    )

  # Step 1: Address lookup for claims rows (temporal rule first, THEN SOURCE quality)
  addr <- addr_full |>
    dplyr::mutate(
      period_start = lubridate::ymd(ADDRESS_PERIOD_START, quiet = TRUE),
      period_end   = dplyr::if_else(
        is.na(ADDRESS_PERIOD_END) | trimws(as.character(ADDRESS_PERIOD_END)) == "",
        as.Date("9999-12-31"),
        lubridate::ymd(ADDRESS_PERIOD_END, quiet = TRUE)
      ),
      addr_source  = trimws(SOURCE)
    )

  # Pass 1: exact interval match (ADDRESS_PERIOD_START <= ADMIT_DATE < ADDRESS_PERIOD_END)
  claims_addr_interval <- enc_claims |>
    dplyr::select(ID, ENCOUNTERID, ADMIT_DATE) |>
    dplyr::left_join(
      addr |> dplyr::select(ID, period_start, period_end, addr_source),
      by = "ID", relationship = "many-to-many"
    ) |>
    dplyr::filter(
      !is.na(period_start),
      period_start <= ADMIT_DATE,
      ADMIT_DATE < period_end
    ) |>
    dplyr::arrange(ID, ENCOUNTERID, dplyr::desc(period_start), dplyr::desc(period_end)) |>
    dplyr::group_by(ENCOUNTERID) |>
    dplyr::slice_head(n = 1L) |>
    dplyr::ungroup() |>
    dplyr::select(ENCOUNTERID, addr_source_interval = addr_source)

  # Pass 2: most-recent-before fallback (only for encounters with no interval match)
  claims_addr_recency <- enc_claims |>
    dplyr::select(ID, ENCOUNTERID, ADMIT_DATE) |>
    dplyr::anti_join(claims_addr_interval, by = "ENCOUNTERID") |>
    dplyr::left_join(
      addr |> dplyr::select(ID, period_start, addr_source),
      by = "ID", relationship = "many-to-many"
    ) |>
    dplyr::filter(!is.na(period_start), period_start <= ADMIT_DATE) |>
    dplyr::arrange(ID, ENCOUNTERID, dplyr::desc(period_start)) |>
    dplyr::group_by(ENCOUNTERID) |>
    dplyr::slice_head(n = 1L) |>
    dplyr::ungroup() |>
    dplyr::select(ENCOUNTERID, addr_source_recency = addr_source)

  # Coalesce interval over recency, then check SOURCE quality
  enc_claims_step1 <- enc_claims |>
    dplyr::left_join(claims_addr_interval, by = "ENCOUNTERID") |>
    dplyr::left_join(claims_addr_recency,  by = "ENCOUNTERID") |>
    dplyr::mutate(
      addr_source_effective = dplyr::coalesce(addr_source_interval, addr_source_recency),
      # Accept only non-blank, non-claims address SOURCE (quality check AFTER temporal rule)
      addr_resolved = dplyr::if_else(
        !is.na(addr_source_effective) &
          trimws(addr_source_effective) != "" &
          !addr_source_effective %in% config$claims_source_codes,
        addr_source_effective,
        NA_character_
      )
    )

  # Step 2: Whole-record modal non-claims SOURCE from enc_all
  # enc_all is the unfiltered cohort ENCOUNTER table — not derived from enc.
  # Modal SOURCE computed from enc_all rows where `SOURCE %in% config$claims_source_codes` is FALSE.
  # Tiebreak: most recent ADMIT_DATE (from enc_all), then alphabetical SOURCE.
  modal_tbl <- enc_all |>
    dplyr::filter(!SOURCE %in% config$claims_source_codes,
                  !is.na(SOURCE), trimws(SOURCE) != "") |>
    dplyr::group_by(ID, SOURCE) |>
    dplyr::summarise(n = dplyr::n(),
                     last_date = if (all(is.na(ADMIT_DATE))) as.Date(NA_character_) else max(ADMIT_DATE, na.rm = TRUE),
                     .groups = "drop") |>
    dplyr::group_by(ID) |>
    dplyr::slice_max(order_by = n, n = 1L, with_ties = TRUE) |>
    dplyr::arrange(ID, dplyr::desc(last_date), SOURCE) |>
    dplyr::slice_head(n = 1L) |>
    dplyr::ungroup() |>
    dplyr::rename(modal_source = SOURCE)

  # Step 3: Resolve all three steps in priority order
  enc_claims_resolved <- enc_claims_step1 |>
    dplyr::left_join(modal_tbl |> dplyr::select(ID, modal_source), by = "ID") |>
    dplyr::mutate(
      SOURCE_analytic = dplyr::case_when(
        !is.na(addr_resolved) ~ addr_resolved,
        !is.na(modal_source)  ~ modal_source,
        TRUE                  ~ "Claims_unresolved"
      ),
      source_reassign_method = dplyr::case_when(
        !is.na(addr_resolved) ~ "address",
        !is.na(modal_source)  ~ "modal_encounter",
        TRUE                  ~ "unresolved"
      ),
      source_reassigned = dplyr::if_else(
        source_reassign_method %in% c("address", "modal_encounter"), 1L, 0L
      )
    ) |>
    dplyr::select(-addr_source_interval, -addr_source_recency, -addr_source_effective,
                  -addr_resolved, -modal_source)

  # Per-method count messages (added for P1.1 — previously silent)
  n_address  <- sum(enc_claims_resolved$source_reassign_method == "address")
  n_modal    <- sum(enc_claims_resolved$source_reassign_method == "modal_encounter")
  n_unresol  <- sum(enc_claims_resolved$source_reassign_method == "unresolved")
  n_notreass <- nrow(enc_nonclaims)
  message(glue::glue(
    "assign_analytic_source: claims={nrow(enc_claims_resolved)} ",
    "| address={n_address} | modal_encounter={n_modal} ",
    "| unresolved={n_unresol} | not_reassigned={n_notreass}"
  ))

  # Stop if address reassignment yielded 0 while address history has FLM patient rows
  n_flm_pats_in_addr <- sum(unique(enc_claims$ID) %in% unique(addr_full$ID))
  if (n_address == 0L && n_flm_pats_in_addr > 0L) {
    stop(glue::glue(
      "assign_analytic_source: 0 claims encounters reassigned via address, ",
      "but {n_flm_pats_in_addr} claims patient(s) appear in addr_full. ",
      "Check ID class/format and date class of ADDRESS_PERIOD_START/END vs ADMIT_DATE."
    ))
  }

  # Restore caller's row order: bind, then re-index by the original ENCOUNTERID sequence.
  out <- dplyr::bind_rows(enc_nonclaims, enc_claims_resolved) |>
    dplyr::slice(match(enc$ENCOUNTERID, ENCOUNTERID))

  # Guard: no rows gained or lost after recombine (no duplicate ENCOUNTERIDs)
  stopifnot("assign_analytic_source: duplicate ENCOUNTERIDs in output" =
              nrow(out) == nrow(enc))

  out
}

# ------------------------------------------------------------------------------
# suppress_by_source_row() -- display-only suppression for a single BY_SOURCE row
#
# Applied AFTER stats are computed (MH and all statistics use true counts).
# Any row with a suppressed count cell gets its OR/CI/p/stat blanked and
# test_method set to "suppressed". Percent cells are blanked when their
# numerator or denominator is suppressed, or when pct is 0%/100% and the
# denominator is small (<11).
#
# @param row  Single-row data.frame produced by build_by_source_sheet() or
#             build_by_source_pat_sheet(). Must contain:
#             n_far, n_not_far, n_cbc_far, n_cbc_not_far (character, possibly "<11"),
#             pct_far_with_cbc, pct_not_far_with_cbc (character, possibly NA),
#             chi_stat (or F_stat), p_value, OR, CI_lo, CI_hi, test_method.
#
# @return Modified row with stats blanked where required.
# ------------------------------------------------------------------------------
suppress_by_source_row <- function(row) {
  suppressed_cells <- c("n_far", "n_not_far", "n_cbc_far", "n_cbc_not_far")
  is_supp <- function(x) !is.na(x) && trimws(as.character(x)) == "<11"

  any_count_suppressed <- any(vapply(suppressed_cells, function(col) {
    if (col %in% names(row)) is_supp(row[[col]]) else FALSE
  }, logical(1L)))

  if (any_count_suppressed) {
    # Blank OR, CI, stat, p; mark as suppressed
    for (col in intersect(names(row), c("chi_stat", "F_stat", "p_value",
                                         "OR", "CI_lo", "CI_hi"))) {
      row[[col]] <- NA_character_
    }
    row[["test_method"]] <- "suppressed"
  }

  # Blank pct when numerator or denominator is suppressed
  if (is_supp(row[["n_cbc_far"]]) || is_supp(row[["n_far"]]))
    row[["pct_far_with_cbc"]] <- NA_character_
  if (is_supp(row[["n_cbc_not_far"]]) || is_supp(row[["n_not_far"]]))
    row[["pct_not_far_with_cbc"]] <- NA_character_

  # Blank pct == "0.0%" or "100.0%" when denominator small (<11)
  blank_extreme_pct <- function(pct_col, denom_col) {
    pct <- row[[pct_col]]
    den <- row[[denom_col]]
    if (!is.na(pct) && !is.na(den) && !is_supp(den)) {
      den_num <- suppressWarnings(as.integer(gsub(",", "", den)))
      if (!is.na(den_num) && den_num < 11L) {
        pv <- trimws(as.character(pct))
        if (pv %in% c("0.0%", "100.0%")) row[[pct_col]] <<- NA_character_
      }
    }
    row
  }
  if (all(c("pct_far_with_cbc", "n_far") %in% names(row)))
    row <- blank_extreme_pct("pct_far_with_cbc", "n_far")
  if (all(c("pct_not_far_with_cbc", "n_not_far") %in% names(row)))
    row <- blank_extreme_pct("pct_not_far_with_cbc", "n_not_far")

  row
}

# ------------------------------------------------------------------------------
# assert_no_back_calculable() -- stop() if any visible cell determines a suppressed one
#
# Checks a single BY_SOURCE row: if the row has exactly one suppressed count cell
# among {n_far, n_not_far, n_cbc_far, n_cbc_not_far} but the remaining cells plus
# the visible totals allow back-calculation, we stop. In practice the row-level
# 2x2 is: n_cbc_far, n_cbc_not_far, n_far-n_cbc_far (=n_notcbc_far),
# n_not_far-n_cbc_not_far. Exactly one suppressed cell is determinable from the
# others + row total. This function stops in that case.
# ------------------------------------------------------------------------------
assert_no_back_calculable <- function(row) {
  count_cols <- c("n_far", "n_not_far", "n_cbc_far", "n_cbc_not_far")
  is_supp <- function(x) !is.na(x) && trimws(as.character(x)) == "<11"
  suppressed <- vapply(count_cols, function(col) {
    if (col %in% names(row)) is_supp(row[[col]]) else FALSE
  }, logical(1L))
  n_supp <- sum(suppressed)
  if (n_supp == 0L) return(invisible(NULL))  # nothing suppressed; fine

  # Parse visible counts (non-suppressed, non-NA)
  vals <- vapply(count_cols, function(col) {
    if (!suppressed[[col]] && col %in% names(row)) {
      v <- suppressWarnings(as.integer(gsub(",", "", as.character(row[[col]]))))
      if (is.na(v)) NA_integer_ else v
    } else NA_integer_
  }, integer(1L))
  names(vals) <- count_cols

  # Back-calculation check: n_cbc_far + (n_far - n_cbc_far) = n_far, etc.
  # If exactly 1 is suppressed and all 3 others are visible integers:
  if (n_supp == 1L && sum(!is.na(vals)) == 3L) {
    nf <- vals["n_far"]; nnf <- vals["n_not_far"]
    ncf <- vals["n_cbc_far"]; ncnf <- vals["n_cbc_not_far"]
    recoverable <- FALSE
    # Can we derive n_cbc_far from n_far + (n_far - n_cbc_far)? Only if n_far - n_cbc_far visible.
    # Equivalent: all three non-suppressed counts determine the fourth through row or col totals.
    # Row totals: n_far = n_cbc_far + n_notcbc_far; n_not_far = n_cbc_not_far + n_notcbc_not_far
    # Col totals: n_cbc_far + n_cbc_not_far = total_cbc; (n_far - n_cbc_far) + (n_not_far - n_cbc_not_far) = total_notcbc
    if (suppressed["n_cbc_far"]    && !is.na(nf) && !is.na(ncnf)) {
      # n_cbc_far = n_far - (n_far - n_cbc_far). We don't have n_notcbc_far separately but
      # if n_far and n_not_far are both visible and n_cbc_not_far visible, we can get n_cbc_far
      # from: n_cbc_far = (n_far + n_not_far - n_cbc_not_far) - n_not_far? No — but
      # if n_far is visible AND n_notcbc_far can be derived: not directly.
      # Simpler: if any two of the four cells are visible in the SAME row-group, the third
      # interior cell in that group can be derived if we know the marginal.
      # We DON'T expose n_far as separate from n_cbc_far here (they are distinct rows).
      # The 2x2: a=n_notcbc_far, b=n_cbc_far, c=n_notcbc_not_far, d=n_cbc_not_far
      # We have: n_far = a+b, n_not_far = c+d, n_cbc_far = b, n_cbc_not_far = d
      # Suppressed = b (n_cbc_far). Visible: n_far (a+b), n_not_far (c+d), n_cbc_not_far (d).
      # b = (a+b) - a. We know a+b but not a individually unless we know a from somewhere else.
      # However if only n_far, n_not_far, n_cbc_not_far are shown (not a or c explicitly),
      # b is NOT directly recoverable from visible cells alone.
      # BUT if any pct_far_with_cbc is visible (= b/(a+b)*100) and n_far is visible -> b recoverable.
      pct_far <- row[["pct_far_with_cbc"]]
      if (!is.na(pct_far) && nchar(trimws(pct_far)) > 0 && trimws(pct_far) != "") {
        recoverable <- TRUE
      }
    }
    if (suppressed["n_cbc_not_far"] && !is.na(nnf)) {
      pct_nf <- row[["pct_not_far_with_cbc"]]
      if (!is.na(pct_nf) && nchar(trimws(pct_nf)) > 0 && trimws(pct_nf) != "") {
        recoverable <- TRUE
      }
    }
    if (recoverable) {
      stop(glue::glue(
        "assert_no_back_calculable: suppressed count is recoverable from visible pct+marginal ",
        "in row SOURCE_analytic={if ('SOURCE_analytic' %in% names(row)) row[['SOURCE_analytic']] else '?'} ",
        "window={if ('window' %in% names(row)) row[['window']] else '?'}. ",
        "Blank the pct cell before writing."
      ))
    }
  }
  invisible(NULL)
}

# ------------------------------------------------------------------------------
# build_flm_sensitivity_set() -- Sensitivity set for BY_SOURCE_flm sheets
# (Phase 192.3, D-192.3-05)
#
# Tests the "CBC captured outside our system" hypothesis directly.
# Takes the full enc_with_source (output of assign_analytic_source) and returns a
# copy where rows with SOURCE_raw %in% config$claims_source_codes have SOURCE_analytic
# overwritten to SOURCE_raw (effectively un-reassigning FLM encounters — keeping FLM
# as its own stratum). All other SOURCE strata keep their SOURCE_analytic value.
#
# Pass the returned object to the same build_by_source_sheet() helper used for the
# main BY_SOURCE sheets.
# ------------------------------------------------------------------------------
build_flm_sensitivity_set <- function(enc_with_source, config) {
  stopifnot(
    "enc_with_source must be a data.frame"      = is.data.frame(enc_with_source),
    "enc_with_source must have SOURCE_raw"      = "SOURCE_raw" %in% names(enc_with_source),
    "enc_with_source must have SOURCE_analytic" = "SOURCE_analytic" %in% names(enc_with_source),
    "config must have claims_source_codes"      = !is.null(config$claims_source_codes)
  )
  enc_with_source |>
    dplyr::mutate(
      SOURCE_analytic = dplyr::if_else(
        SOURCE_raw %in% config$claims_source_codes,
        SOURCE_raw,       # un-reassign: FLM stays as FLM (tests CBC-outside-system hypothesis)
        SOURCE_analytic   # all others keep their analytic SOURCE
      )
    )
}

# ------------------------------------------------------------------------------
# build_enc_analysis() -- encounter-level analysis set (both windows as columns)
#
# Constructs the primary analysis tibble for R/163 and R/165. Carries
# far_from_care_100mi and post_anchor as 0/1 integer columns so the caller can
# subset by window (post_anchor == 1) without a separate build step.
#
# Encounter-level CBC definition (CONTEXT.md D-06):
#   cbc_in_encounter = 1 if any cbc_date falls in [ADMIT_DATE, coalesce(DISCHARGE_DATE, ADMIT_DATE)]
#   Non-equi join via dplyr::join_by(between()). De-duplicated to ONE row per
#   ENCOUNTERID after the join (stopifnot guard enforced).
#
# @param enc_distance tibble from readRDS(enc_distance path) — R/122 output.
#          Must contain: ID, ENCOUNTERID, ADMIT_DATE (Date), distance_mi, distance_status
# @param cbc_events   tibble(ID, cbc_date) from build_cbc_events()
# @param anchors      tibble(ID, hl_anchor_date) from get_hl_any_dx_ids()
# @param enc_dates    tibble(ENCOUNTERID, DISCHARGE_DATE (Date or NA), SOURCE)
#          pulled from ENCOUNTER by caller (DuckDB query, cohort-scoped)
# @param cutoff       numeric scalar — CONFIG$far_from_care_cutoff_mi
#
# @return tibble (one row per ENCOUNTERID with distance_status == "computed" and
#           known anchor date):
#   ID, ENCOUNTERID, ADMIT_DATE, ENC_TYPE, SOURCE,
#   distance_mi, far_from_care_100mi (int 0/1), post_anchor (int 0/1),
#   cbc_in_encounter (int 0/1)
#
# WHY distance_status == "computed" filter: only computed distances support the
# binary indicator; other statuses (facility_zip_missing, patient_zip_missing,
# zip_not_in_db) would produce NA distance_mi and meaningless indicators.
#
# WHY anchor-date drop: encounters for patients without an anchor date cannot be
# assigned to a window. The count is logged by the caller (QC).
# ------------------------------------------------------------------------------
build_enc_analysis <- function(enc_distance, cbc_events, anchors, enc_dates, cutoff,
                               addr_full = NULL, enc_all = NULL, config = NULL) {
  stopifnot(
    "enc_distance must be a data.frame" = is.data.frame(enc_distance),
    "cbc_events must be a data.frame"   = is.data.frame(cbc_events),
    "anchors must be a data.frame"      = is.data.frame(anchors),
    "enc_dates must be a data.frame"    = is.data.frame(enc_dates),
    "cutoff must be a positive numeric" = is.numeric(cutoff) && length(cutoff) == 1L && cutoff > 0
  )
  if (!is.null(addr_full)) {
    stopifnot(
      "addr_full must be a data.frame"               = is.data.frame(addr_full),
      "config must be provided when addr_full is non-NULL" = !is.null(config),
      "config must have claims_source_codes"         = !is.null(config$claims_source_codes),
      "enc_all must be provided when addr_full is non-NULL" = !is.null(enc_all),
      "enc_all must be a data.frame"                 = is.data.frame(enc_all)
    )
  }

  # Step 1: Keep only computed-distance encounters
  enc_computed <- enc_distance |>
    dplyr::filter(distance_status == "computed")

  # Step 2: Attach DISCHARGE_DATE and SOURCE from ENCOUNTER
  enc_with_dates <- enc_computed |>
    dplyr::left_join(
      enc_dates |> dplyr::select(ENCOUNTERID, DISCHARGE_DATE, SOURCE),
      by = "ENCOUNTERID"
    )

  # Step 2b (Phase 192.3): Reassign claims SOURCE when addr_full + enc_all provided
  if (!is.null(addr_full)) {
    enc_with_dates <- assign_analytic_source(enc_with_dates, enc_all, addr_full, config)
  } else {
    # Legacy path: rename SOURCE to SOURCE_raw; SOURCE_analytic mirrors SOURCE_raw
    enc_with_dates <- enc_with_dates |>
      dplyr::rename(SOURCE_raw = SOURCE) |>
      dplyr::mutate(
        SOURCE_analytic        = SOURCE_raw,
        source_reassigned      = 0L,
        source_reassign_method = "not_reassigned"
      )
  }

  # Step 3: Compute far_from_care_100mi
  enc_with_dates <- enc_with_dates |>
    dplyr::mutate(
      far_from_care_100mi = as.integer(distance_mi > cutoff),
      enc_end              = dplyr::coalesce(DISCHARGE_DATE, ADMIT_DATE)
    )

  # Step 4: Join anchor dates; drop patients with no anchor (logged by caller)
  n_before_anchor <- nrow(enc_with_dates)
  enc_anchored <- enc_with_dates |>
    dplyr::inner_join(
      anchors |> dplyr::select(ID, hl_anchor_date),
      by = "ID"
    )
  n_dropped_no_anchor <- n_before_anchor - nrow(enc_anchored)
  if (n_dropped_no_anchor > 0)
    message(glue::glue(
      "  build_enc_analysis(): {n_dropped_no_anchor} encounters dropped ",
      "(patient has no anchor date)."
    ))

  # Step 5: Compute post_anchor (anchor day = pre, per CONTEXT.md D-13 / R/147 D-25)
  enc_anchored <- enc_anchored |>
    dplyr::mutate(post_anchor = as.integer(ADMIT_DATE > hl_anchor_date))

  # Step 6: CBC-in-encounter flag.
  # Join enc_anchored (with ID) to cbc_events on ID + date range.
  cbc_flag <- enc_anchored |>
    dplyr::select(ID, ENCOUNTERID, ADMIT_DATE, enc_end) |>
    dplyr::left_join(cbc_events, by = "ID",
                     relationship = "many-to-many") |>
    dplyr::filter(is.na(cbc_date) | (cbc_date >= ADMIT_DATE & cbc_date <= enc_end)) |>
    dplyr::group_by(ENCOUNTERID) |>
    dplyr::summarise(cbc_in_encounter = as.integer(any(!is.na(cbc_date))),
                     .groups = "drop")

  # Step 7: Attach CBC flag back to the encounter set
  out <- enc_anchored |>
    dplyr::left_join(cbc_flag, by = "ENCOUNTERID") |>
    dplyr::mutate(cbc_in_encounter = dplyr::coalesce(cbc_in_encounter, 0L))

  # Guard: one row per ENCOUNTERID (no fan-out from the join)
  stopifnot(
    "build_enc_analysis(): duplicate ENCOUNTERIDs in output (fan-out)" =
      !anyDuplicated(out$ENCOUNTERID)
  )

  # Step 8: Select and return canonical columns (Phase 192.3: SOURCE_raw/SOURCE_analytic added)
  out |>
    dplyr::select(
      ID, ENCOUNTERID, ADMIT_DATE, ENC_TYPE, SOURCE_raw, SOURCE_analytic,
      source_reassigned, source_reassign_method,
      distance_mi, far_from_care_100mi, post_anchor, cbc_in_encounter
    )
}

# ------------------------------------------------------------------------------
# build_pat_analysis() -- patient-level analysis set for one window
#
# Aggregates the encounter-level set to one row per patient. Denominator =
# patients with >= 1 computed-distance encounter in the chosen window.
#
# @param enc_analysis tibble returned by build_enc_analysis()
# @param cbc_events   tibble(ID, cbc_date) from build_cbc_events()
# @param anchors      tibble(ID, hl_anchor_date) from get_hl_any_dx_ids()
# @param window       "whole" (all encounters) or "post" (post_anchor == 1)
#
# @return tibble (one row per patient with >= 1 encounter in window):
#   ID, any_far (int 0/1), any_cbc (int 0/1), n_encounters (int)
#
# Definitions:
#   whole window:  any_far = max(far_from_care_100mi) across all encounters
#                  any_cbc = 1 if any CBC event in the whole record (any date)
#   post window:   any_far = max(far_from_care_100mi) among post_anchor == 1 encounters
#                  any_cbc = 1 if any cbc_date > hl_anchor_date
# ------------------------------------------------------------------------------
build_pat_analysis <- function(enc_analysis, cbc_events, anchors,
                               window = c("whole", "post")) {
  window <- match.arg(window)

  # Subset encounters by window
  enc_win <- if (window == "post") {
    enc_analysis |> dplyr::filter(post_anchor == 1L)
  } else {
    enc_analysis
  }

  # Patients in denominator (>= 1 encounter in window)
  pat_enc <- enc_win |>
    dplyr::group_by(ID) |>
    dplyr::summarise(
      any_far     = as.integer(any(far_from_care_100mi == 1L, na.rm = TRUE)),
      n_encounters = dplyr::n(),
      .groups = "drop"
    )

  # any_cbc: whole = any CBC in record; post = any CBC after anchor date
  if (window == "whole") {
    pat_cbc <- cbc_events |>
      dplyr::distinct(ID) |>
      dplyr::mutate(any_cbc = 1L)
  } else {
    # post: need anchor dates to determine post-anchor CBC
    pat_cbc <- cbc_events |>
      dplyr::inner_join(anchors |> dplyr::select(ID, hl_anchor_date), by = "ID") |>
      dplyr::filter(cbc_date > hl_anchor_date) |>
      dplyr::distinct(ID) |>
      dplyr::mutate(any_cbc = 1L)
  }

  # Combine: patients in denominator with CBC flag (0 if no CBC in window)
  pat_enc |>
    dplyr::left_join(pat_cbc |> dplyr::select(ID, any_cbc), by = "ID") |>
    dplyr::mutate(any_cbc = dplyr::coalesce(any_cbc, 0L)) |>
    dplyr::select(ID, any_far, any_cbc, n_encounters)
}
