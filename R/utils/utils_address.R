# ==============================================================================
# utils/utils_address.R -- ZIP9/ZIP5 normalization and date-keyed address lookup
# ==============================================================================
#
# Purpose:
#   Shared ZIP normalization and temporal lookup functions for LDS_ADDRESS_HISTORY.
#   get_zip9_at_date() resolves the ZIP9 (and ZIP5) active for a patient at a
#   given query date using interval overlap with a most-recent-before fallback.
#
# Inputs:
#   - ids:   character vector of patient IDs (project convention: column "ID")
#   - dates: Date vector of query dates (parallel to ids)
#   - CONFIG$data_dir must be set (via R/00_config.R) before calling get_zip9_at_date()
#
# Outputs:
#   - get_zip9_at_date() returns a tibble: ID, query_date, ZIP9, ZIP5, match_type
#     match_type values: "interval" | "most_recent_before" | "none"
#
# Dependencies:
#   - dplyr, vroom, stringr, glue (project standard stack)
#   - parse_pcornet_date() from R/utils/utils_dates.R (auto-loaded via R/00_config.R)
#
# Requirements: Phase 137 -- D-01 through D-06
#
# ==============================================================================

# Normalize ZIP9: strip hyphen, then accept ONLY 8- or 9-digit numeric strings
# (8 = a genuine ZIP9 that dropped its single leading zero). Left-pad 8 -> 9.
# Anything else (bare ZIP5, too-short, non-numeric) -> NA rather than being mangled.
normalize_zip9 <- function(zip) {
  z <- str_remove_all(str_trim(zip), "-")
  z <- if_else(str_detect(z, "^[0-9]{8,9}$"), str_pad(z, 9, pad = "0"), NA_character_)
  if_else(str_detect(z, "^[0-9]{9}$"), z, NA_character_)
}

# Normalize ZIP5: first 5 characters of a clean ZIP9.
normalize_zip5 <- function(zip9_clean) {
  str_sub(zip9_clean, 1, 5)
}

# Normalize a raw ZIP5 column: strip non-digits, extract leading 5, left-pad 4-digit
# inputs, validate ^[0-9]{5}$. Rewritten per Phase 139 AMEND-01 / Step 0b:
#   Previous logic padded BEFORE validating length, causing strings longer than 5
#   characters (e.g. "123456") to be padded to "1234560" and then fail ^[0-9]{5}$,
#   returning NA instead of "12345". Correct order: strip, slice, maybe-pad, validate.
normalize_zip5_raw <- function(zip) {
  z <- str_remove_all(str_trim(zip), "[^0-9]")    # strip non-digits (including hyphens)
  z <- if_else(nchar(z) >= 5, str_sub(z, 1, 5), z) # take first 5 when >= 5 digits present
  z <- if_else(nchar(z) == 4, str_pad(z, 5, pad = "0"), z) # left-pad only genuine 4-digit ZIPs
  if_else(str_detect(z, "^[0-9]{5}$"), z, NA_character_)
}

#' Resolve ZIP9 (and ZIP5) for each (ID, query_date) pair using temporal lookup.
#'
#' Loads LDS_ADDRESS_HISTORY on demand (D-06: no caching), joins on ID, then
#' applies a two-tier match: (1) interval overlap — the query date falls within
#' [ADDRESS_PERIOD_START, ADDRESS_PERIOD_END); (2) most-recent-before fallback
#' for queries not covered by any interval; (3) "none" for patients with no
#' address record before or on the query date.
#'
#' NA ADDRESS_PERIOD_END is coerced to 9999-12-31 so open-ended periods are
#' included in interval matching (Pitfall 2: without this, open-ended addresses
#' are silently excluded).
#'
#' When multiple interval-covering records exist for the same (ID, query_date),
#' non-NA ZIP9 records are preferred; ties are broken by most-recent
#' ADDRESS_PERIOD_START (D-02, D-04).
#'
#' @param ids   Character vector of patient IDs (project convention: column "ID").
#' @param dates Date vector of query dates (parallel to ids).
#' @return A tibble with ONE row per DISTINCT (ID, query_date) pair, sorted by
#'   (ID, query_date): columns ID, query_date, ZIP9, ZIP5, match_type
#'   ("interval" | "most_recent_before" | "none").
#'   IMPORTANT: the result is NOT parallel to the input vectors — duplicate
#'   (ID, date) pairs are returned once. Callers MUST join on c("ID","query_date");
#'   do NOT cbind the result back onto a source frame.
get_zip9_at_date <- function(ids, dates) {
  stopifnot(length(ids) == length(dates))
  queries <- tibble(ID = as.character(ids), query_date = as.Date(dates))

  ADDR_FILENAME <- "LDS_ADDRESS_HISTORY_Mailhot_V1.csv"
  addr_path <- file.path(CONFIG$data_dir, ADDR_FILENAME)

  # D-06: load on demand — NOT precomputed/cached
  addr_raw <- tryCatch(
    vroom::vroom(addr_path, col_types = vroom::cols(.default = "c"), progress = FALSE),
    error = function(e) {
      message(glue("[utils_address] vroom failed ({conditionMessage(e)}); falling back to read.csv"))
      read.csv(addr_path, colClasses = "character", na.strings = c("", "NA"))
    }
  )

  # Validate ID column (Pitfall 3: project convention is ID not PATID)
  if (!"ID" %in% names(addr_raw)) {
    stop(glue("[utils_address] LDS_ADDRESS_HISTORY missing required column 'ID'. Found: {paste(names(addr_raw), collapse=', ')}"))
  }

  addr <- addr_raw %>%
    mutate(
      zip9_norm       = normalize_zip9(ADDRESS_ZIP9),
      # Phase 139 AMEND-01 / Step 0c: coalesce ZIP5 from two sources:
      #   (1) normalize_zip5() of a valid 9-digit ZIP9 (existing path)
      #   (2) normalize_zip5_raw() applied directly to ADDRESS_ZIP9 for rows where
      #       ADDRESS_ZIP9 holds a bare 5-digit string that normalize_zip9() rejects
      # No separate ADDRESS_ZIP5 column exists in LDS_ADDRESS_HISTORY (confirmed from
      # plan analysis: ADDRESS_ZIP9 holds bare ZIP5s for some records -- Step 0a case 2).
      zip5_norm       = coalesce(normalize_zip5(zip9_norm), normalize_zip5_raw(ADDRESS_ZIP9)),
      period_start_dt = parse_pcornet_date(ADDRESS_PERIOD_START),
      # D (Claude's Discretion): NA ADDRESS_PERIOD_END = open-ended; coerce to 9999-12-31
      # so that interval filter (date < period_end_dt) includes open periods correctly.
      # Pitfall 2: without this, open-ended addresses are silently excluded from matching.
      period_end_dt   = if_else(
        is.na(ADDRESS_PERIOD_END) | trimws(ADDRESS_PERIOD_END) == "",
        as.Date("9999-12-31"),
        parse_pcornet_date(ADDRESS_PERIOD_END)
      )
    ) %>%
    filter(!is.na(period_start_dt))

  # Pitfall 5: inner_join on ID first — restrict candidates to queried patients only
  # before any date computation to avoid O(n_queries x n_addr_rows) cross-join.
  candidates <- queries %>%
    inner_join(
      addr %>% select(ID, zip9_norm, zip5_norm, period_start_dt, period_end_dt),
      by = "ID"
    ) %>%
    mutate(
      is_interval = period_start_dt <= query_date & query_date < period_end_dt,
      is_before   = period_start_dt <= query_date
    )

  # D-02, D-04: interval matches — prefer non-NA ZIP9 first, then most-recent ADDRESS_PERIOD_START on ties.
  # Falls back to strict recency only when every covering record's ZIP9 is NA (avoidable data loss otherwise).
  interval_hits <- candidates %>%
    filter(is_interval) %>%
    group_by(ID, query_date) %>%
    arrange(is.na(zip9_norm), desc(period_start_dt), .by_group = TRUE) %>%
    slice(1) %>%
    ungroup() %>%
    mutate(match_type = "interval") %>%
    select(ID, query_date, ZIP9 = zip9_norm, ZIP5 = zip5_norm, match_type)

  # D-03: most-recent-before fallback for queries not covered by any interval
  covered   <- interval_hits %>% select(ID, query_date)
  uncovered <- queries %>% anti_join(covered, by = c("ID", "query_date"))

  fallback_hits <- candidates %>%
    semi_join(uncovered, by = c("ID", "query_date")) %>%
    filter(is_before) %>%
    group_by(ID, query_date) %>%
    arrange(is.na(zip9_norm), desc(period_start_dt), .by_group = TRUE) %>%
    slice(1) %>%
    ungroup() %>%
    mutate(match_type = "most_recent_before") %>%
    select(ID, query_date, ZIP9 = zip9_norm, ZIP5 = zip5_norm, match_type)

  # D-03: no match at all — return NA for both ZIP9 and ZIP5
  still_uncovered <- uncovered %>%
    anti_join(fallback_hits %>% select(ID, query_date), by = c("ID", "query_date"))

  none_rows <- still_uncovered %>%
    mutate(ZIP9 = NA_character_, ZIP5 = NA_character_, match_type = "none")

  matched <- bind_rows(interval_hits, fallback_hits, none_rows)
  # Return one row per DISTINCT (ID, query_date) — NOT parallel to input vectors.
  # Callers MUST join on c("ID","query_date"); do NOT cbind the result back onto a source frame.
  queries %>%
    distinct(ID, query_date) %>%
    left_join(matched, by = c("ID", "query_date")) %>%
    arrange(ID, query_date)
}

# ==============================================================================
# approximate_zip9() -- Fill ZIP9 from modal ZIP9 for ZIP5-only address records
# ==============================================================================

# Memoisation cache for the ZIP5->modal-ZIP9 lookup table (AMEND-06).
# Keyed by (addr_path, mtime, size) to force rebuild when file changes.
.zip5_lookup_cache <- list(key = NULL, value = NULL)

#' Approximate ZIP9 for rows returned by get_zip9_at_date() that have ZIP9 = NA.
#'
#' For each row where ZIP9 is NA and match_type is not "none", looks up the
#' most frequent (modal) valid ZIP9 for that ZIP5 across the full
#' LDS_ADDRESS_HISTORY file. Returns the input tibble with ZIP9 filled in where
#' approximation succeeds, plus four provenance/confidence columns.
#'
#' Caller pattern:
#' \code{get_zip9_at_date(ids, dates) |> approximate_zip9()}
#'
#' @param result_tbl A tibble from \code{get_zip9_at_date()}: columns
#'   ID (chr), query_date (Date), ZIP9 (chr), ZIP5 (chr), match_type (chr).
#'
#' @return The input tibble with the same columns plus four new columns:
#'   \describe{
#'     \item{zip9_source}{Classification for each row:
#'       \code{"zip9_observed"} — ZIP9 was already present in the input;
#'       \code{"zip5_modal"} — ZIP9 was approximated as the modal ZIP9 for this ZIP5;
#'       \code{"zip5_no_zip9"} — ZIP5 exists but all LDS records for it have no valid ZIP9;
#'       \code{"no_zip5"} — ZIP9 was NA, ZIP5 was NA, match_type != "none";
#'       \code{"none"} — match_type was "none" (no address record found at all).
#'     }
#'     \item{zip5_modal_freq}{(int) Number of distinct patient IDs whose ZIP+4 modal
#'       count determined the winner for this ZIP5. NA for zip9_observed and none rows.}
#'     \item{zip5_n_candidates}{(int) Number of distinct ZIP+4 values seen for this ZIP5.
#'       NA for zip9_observed and none rows.}
#'     \item{zip5_modal_share}{(dbl) Approximate fraction of freq / sum(freq) across all
#'       ZIP+4 candidates for this ZIP5. Approximate because patients appearing at more
#'       than one ZIP+4 within the same ZIP5 are double-counted in sum(freq). NA for
#'       zip9_observed and none rows.}
#'   }
#'
#' @section match_type invariance:
#'   \code{match_type} is NEVER modified by this function. All rows retain their
#'   Phase 137 values ("interval", "most_recent_before", "none") unchanged.
#'
#' @section Selection bias caveat:
#'   The modal ZIP+4 is the most frequently \emph{recorded} address in the EHR,
#'   skewing toward congregate/institutional addresses (nursing facilities, large
#'   apartment complexes, shelters, student housing, facility-address placeholders).
#'   \code{n_distinct(ID)} reduces record-churn weighting but does not correct this
#'   bias. Downstream ADI/SVI/SDI consumers should treat approximated rows with
#'   \code{zip5_modal_share < 0.10} as especially uncertain.
#'   A future SES phase should restrict modal selection to valid ZIP+4s from the
#'   Neighborhood Atlas file — this eliminates transcription-error modal wins in
#'   sparse ZIP5s. (AMEND-08c)
#'
#' @section zip5_modal_share approximation:
#'   \code{sum(freq)} across a ZIP5's groups can double-count patients who appear
#'   at more than one ZIP+4 within the same ZIP5.
#'
#' # Requirements: Phase 139 -- D-01 through D-08
approximate_zip9 <- function(result_tbl) {

  ADDR_FILENAME <- "LDS_ADDRESS_HISTORY_Mailhot_V1.csv"
  addr_path     <- file.path(CONFIG$data_dir, ADDR_FILENAME)

  # D-08: Probe-first gate — return unchanged if file is absent (no stop())
  if (!file.exists(addr_path)) {
    message(glue(
      "[utils_address] approximate_zip9: LDS_ADDRESS_HISTORY not found at {addr_path}",
      " -- returning input unchanged"
    ))
    return(result_tbl)
  }

  # D-01 / D-02: identify rows that need approximation
  # match_type == "none" means no address record existed — no ZIP5 anchor, skip them.
  to_approx <- result_tbl %>%
    filter(is.na(ZIP9), !is.na(match_type) & match_type != "none")

  if (nrow(to_approx) == 0) {
    # Nothing to approximate — return input with provenance columns added (all zip9_observed)
    # but also handle the case where all rows already have ZIP9 or are "none"
    return(
      result_tbl %>%
        mutate(
          zip9_source       = if_else(!is.na(ZIP9), "zip9_observed", "none"),
          zip5_modal_freq   = NA_integer_,
          zip5_n_candidates = NA_integer_,
          zip5_modal_share  = NA_real_
        )
    )
  }

  # D-05: Load full LDS_ADDRESS_HISTORY (load on demand, same pattern as get_zip9_at_date())
  # AMEND-06: Memoisation keyed on path + mtime + size to avoid rebuilding on every call.
  cache_key <- paste0(
    normalizePath(addr_path, mustWork = FALSE), "|",
    as.numeric(file.mtime(addr_path)), "|",
    file.size(addr_path)
  )

  if (!is.null(.zip5_lookup_cache$key) && identical(.zip5_lookup_cache$key, cache_key)) {
    zip5_lookup <- .zip5_lookup_cache$value
  } else {
    addr_raw <- tryCatch(
      vroom::vroom(addr_path, col_types = vroom::cols(.default = "c"), progress = FALSE),
      error = function(e) {
        message(glue(
          "[utils_address] approximate_zip9: vroom failed ({conditionMessage(e)})",
          "; falling back to read.csv"
        ))
        # AMEND-05c: colClasses = "character" prevents leading-zero stripping
        read.csv(addr_path, colClasses = "character", na.strings = c("", "NA"))
      }
    )

    # AMEND-05a: column existence guard
    req     <- c("ID", "ADDRESS_ZIP9", "ADDRESS_PERIOD_START")
    missing <- setdiff(req, names(addr_raw))
    if (length(missing) > 0) {
      message(glue(
        "[utils_address] approximate_zip9: missing column(s) {paste(missing, collapse = ', ')}",
        " -- returning input unchanged"
      ))
      return(result_tbl)
    }

    # D-03 / D-04 (AMEND-04): Build ZIP5 -> modal-ZIP9 lookup
    # Modal frequency counts distinct patient IDs (not address-history rows).
    # Tie-break is total: freq desc, then recency desc, then ZIP9 string asc.
    zip5_lookup <- addr_raw %>%
      mutate(
        zip9_norm       = normalize_zip9(ADDRESS_ZIP9),
        zip5_norm       = normalize_zip5(zip9_norm),
        period_start_dt = parse_pcornet_date(ADDRESS_PERIOD_START)
      ) %>%
      filter(!is.na(zip9_norm), !is.na(zip5_norm), !is.na(period_start_dt)) %>%
      group_by(zip5_norm, zip9_norm) %>%
      summarise(
        freq        = n_distinct(ID),         # patients, not rows (AMEND-04a)
        latest_date = max(period_start_dt),   # na.rm not needed; NAs filtered above (AMEND-04c)
        .groups     = "drop"
      ) %>%
      group_by(zip5_norm) %>%
      mutate(
        n_candidates = n(),
        modal_share  = freq / sum(freq)       # approximate; patients may appear at >1 ZIP+4
      ) %>%
      arrange(desc(freq), desc(latest_date), zip9_norm, .by_group = TRUE) %>%  # total tie-break (AMEND-04b)
      slice(1) %>%
      ungroup() %>%
      select(
        ZIP5              = zip5_norm,
        modal_zip9        = zip9_norm,
        zip5_modal_freq   = freq,
        zip5_n_candidates = n_candidates,
        zip5_modal_share  = modal_share
      )

    # Store in memoisation cache
    .zip5_lookup_cache$key   <<- cache_key
    .zip5_lookup_cache$value <<- zip5_lookup
  }

  # D-06 / D-07 (AMEND-02, AMEND-03): Apply lookup and classify zip9_source
  # Split result_tbl into three subsets for clean classification:
  #   (a) rows with ZIP9 already present -> "zip9_observed"
  #   (b) rows with match_type == "none" -> "none"
  #   (c) rows needing approximation (to_approx) -> join against zip5_lookup
  already_filled <- result_tbl %>%
    filter(!is.na(ZIP9)) %>%
    mutate(
      zip9_source       = "zip9_observed",
      zip5_modal_freq   = NA_integer_,
      zip5_n_candidates = NA_integer_,
      zip5_modal_share  = NA_real_
    )

  none_rows <- result_tbl %>%
    filter(is.na(ZIP9), match_type == "none") %>%
    mutate(
      zip9_source       = "none",
      zip5_modal_freq   = NA_integer_,
      zip5_n_candidates = NA_integer_,
      zip5_modal_share  = NA_real_
    )

  # Join to_approx against zip5_lookup
  approx_joined <- to_approx %>%
    left_join(zip5_lookup, by = "ZIP5") %>%
    mutate(
      ZIP9 = if_else(!is.na(modal_zip9), modal_zip9, ZIP9),
      zip9_source = case_when(
        !is.na(modal_zip9) ~ "zip5_modal",
        !is.na(ZIP5)       ~ "zip5_no_zip9",
        TRUE               ~ "no_zip5"
      ),
      zip5_modal_freq   = if_else(zip9_source == "zip5_modal", as.integer(zip5_modal_freq), NA_integer_),
      zip5_n_candidates = if_else(zip9_source == "zip5_modal", as.integer(zip5_n_candidates), NA_integer_),
      zip5_modal_share  = if_else(zip9_source == "zip5_modal", zip5_modal_share, NA_real_)
    ) %>%
    select(-modal_zip9)  # AMEND-05b: drop join column from output

  # Reassemble and restore original sort order
  result_out <- bind_rows(already_filled, none_rows, approx_joined) %>%
    arrange(ID, query_date)

  # AMEND-08a: Diagnostic logging — zip9_source breakdown + modal_share distribution
  src_counts <- table(result_out$zip9_source)
  get_count  <- function(k) { v <- src_counts[k]; if (is.na(v)) 0L else as.integer(v) }

  modal_rows <- result_out %>% filter(zip9_source == "zip5_modal")
  if (nrow(modal_rows) > 0) {
    ms <- modal_rows$zip5_modal_share
    share_summary <- glue(
      "  modal_share among zip5_modal rows -- min: {round(min(ms, na.rm=TRUE), 3)}",
      "  median: {round(median(ms, na.rm=TRUE), 3)}",
      "  max: {round(max(ms, na.rm=TRUE), 3)}"
    )
  } else {
    share_summary <- "  modal_share among zip5_modal rows -- (none)"
  }

  message(glue(
    "[utils_address] approximate_zip9: zip9_source breakdown:\n",
    "  zip9_observed: {get_count('zip9_observed')}",
    "  zip5_modal: {get_count('zip5_modal')}",
    "  zip5_no_zip9: {get_count('zip5_no_zip9')}",
    "  no_zip5: {get_count('no_zip5')}",
    "  none: {get_count('none')}\n",
    share_summary
  ))

  result_out
}
