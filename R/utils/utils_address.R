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
#   - normalize_zip9() / normalize_zip5() / normalize_zip5_raw(): ZIP normalization
#     helpers (see function definitions below for exact contracts)
#   - is_sentinel_zip5(zip5): TRUE for placeholder ZIP5 values (00000, 99999, and
#     any other single-repeated-digit ZIP5), FALSE for genuine ZIP5s, NA for NA
#     input (Phase 139, Pitfall 2)
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

# Normalize a raw ZIP5 column: trim, pad to 5, validate ^[0-9]{5}$.
normalize_zip5_raw <- function(zip) {
  z <- str_remove_all(str_trim(zip), "-")
  z <- str_pad(z, 5, pad = "0")
  if_else(str_detect(z, "^[0-9]{5}$"), z, NA_character_)
}

# Sentinel/placeholder ZIP5 filter (Pitfall 2, Phase 139): 00000, 99999, and any
# other single-repeated-digit ZIP5 are known placeholder/data-quality artifacts,
# not real addresses. Applied by callers (e.g. R/115) BEFORE counting ZIP
# transitions, so placeholder values don't inflate change counts. NOT called by
# get_zip9_at_date() itself -- that function is Out of Scope for modification
# in Phase 139; sentinel filtering is applied by callers on its output/inputs.
is_sentinel_zip5 <- function(zip5) {
  str_detect(zip5, "^(\\d)\\1{4}$")
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
      zip5_norm       = normalize_zip5(zip9_norm),
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
