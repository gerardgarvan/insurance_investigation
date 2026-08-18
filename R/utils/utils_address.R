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
#   - approximate_zip9() returns the same tibble plus four provenance columns:
#     zip9_source, zip5_modal_freq, zip5_n_candidates, zip5_modal_share
#     Column set is identical on every exit path (probe gate, missing columns, normal run).
#
# Dependencies:
#   - dplyr, vroom, stringr, glue (project standard stack)
#   - parse_pcornet_date() from R/utils/utils_dates.R (auto-loaded via R/00_config.R)
#
# Requirements: Phase 137 -- D-01 through D-06
#               Phase 139 -- D-01 through D-08 (+ 139-01-PATCH, 139-02-PATCH)
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

# Five identical digits (00000, 11111, ... 99999) are placeholder values, not ZIPs.
# Note: 12345 is a real ZIP (Schenectady, NY) and is NOT in the sentinel set. (FIX-06)
is_sentinel_zip5 <- function(zip5) {
  !is.na(zip5) & str_detect(zip5, "^(\\d)\\1{4}$")
}

# Normalize a raw ZIP5 column: strip non-digits, extract leading 5, validate ^[0-9]{5}$.
# Rewritten per Phase 139 AMEND-01 / Step 0b.
# pad4: left-pad 4-digit strings to 5 (default FALSE). Off by default because the file is
# always read with character types, so a genuine leading zero was never at risk. A 4-digit
# value here is more likely truncation/damage than a New England ZIP -- silently relocating
# a Gainesville patient to Connecticut would corrupt downstream SES scores. (FIX-05)
normalize_zip5_raw <- function(zip, pad4 = FALSE) {
  z <- str_remove_all(str_trim(zip), "[^0-9]")
  z <- if_else(nchar(z) >= 5, str_sub(z, 1, 5), z)
  if (isTRUE(pad4)) {
    z <- if_else(nchar(z) == 4, str_pad(z, 5, pad = "0"), z)
  }
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
#' @param addr_full Optional injection seam for tests (140-08-PATCH FIX-10). When
#'   supplied, MUST have columns that are `character` or `Date` — matching what
#'   the CSV load path produces. A `POSIXct` column is not guaranteed to survive
#'   `as.character()` coercion into a `parse_pcornet_date()`-parseable format;
#'   this parameter is a test seam, not a general-purpose data-loader replacement.
#'   Defaults to NULL, preserving the existing load-on-demand behavior exactly.
#' @return A tibble with ONE row per DISTINCT (ID, query_date) pair, sorted by
#'   (ID, query_date): columns ID, query_date, ZIP9, ZIP5, match_type
#'   ("interval" | "most_recent_before" | "none").
#'   IMPORTANT: the result is NOT parallel to the input vectors — duplicate
#'   (ID, date) pairs are returned once. Callers MUST join on c("ID","query_date");
#'   do NOT cbind the result back onto a source frame.
get_zip9_at_date <- function(ids, dates, addr_full = NULL) {
  stopifnot(length(ids) == length(dates))
  queries <- tibble(ID = as.character(ids), query_date = as.Date(dates))

  if (is.null(addr_full)) {
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
  } else {
    # P-07c: test-injection seam — character-coerce to match the file-load path's column
    # types. 140-08-PATCH FIX-10: addr_full's columns MUST be character or Date, matching
    # what the CSV load path above produces — a POSIXct column will coerce to
    # "2020-01-01 00:00:00" via as.character(), which parse_pcornet_date() is not
    # guaranteed to handle. This seam is not a general-purpose data-loader replacement;
    # callers are responsible for passing character/Date columns.
    addr_raw <- as.data.frame(lapply(addr_full, as.character), stringsAsFactors = FALSE)
  }

  # Validate required columns (Pitfall 3: project convention is ID not PATID;
  # Phase 148 added ADDRESS_ZIP5 as a ZIP5 source — an extract without it would
  # silently fall back to deriving ZIP5 from ADDRESS_ZIP9 and lose ~47% of ZIP5 coverage)
  required_cols <- c("ID", "ADDRESS_ZIP5", "ADDRESS_ZIP9",
                     "ADDRESS_PERIOD_START", "ADDRESS_PERIOD_END")
  missing_cols  <- setdiff(required_cols, names(addr_raw))
  if (length(missing_cols) > 0) {
    stop("[utils_address] address file missing required column(s): ",
         paste(missing_cols, collapse = ", "),
         ". ADDRESS_ZIP5 was added as a ZIP5 source in Phase 148; an extract without it ",
         "would silently fall back to deriving ZIP5 from ADDRESS_ZIP9 and lose ~47% of ZIP5 coverage.")
  }

  # FIX-05: report 4-digit ADDRESS_ZIP9 values before pad4 decision is locked
  n_pad4 <- sum(nchar(str_remove_all(str_trim(addr_raw$ADDRESS_ZIP9), "[^0-9]")) == 4, na.rm = TRUE)
  if (n_pad4 > 0) {
    message(glue(
      "[utils_address] {n_pad4} ADDRESS_ZIP9 value(s) reduce to exactly 4 digits; ",
      "not zero-padded (pad4 = FALSE). Set pad4 = TRUE only if these are known New England ZIPs."
    ))
  }

  addr <- addr_raw %>%
    mutate(
      zip9_norm       = normalize_zip9(ADDRESS_ZIP9),
      # Phase 148 D-02: ZIP5 sourced from ADDRESS_ZIP5 first (the field the source
      # system populated deliberately), then from the ZIP9 prefix (fallback for the
      # 291 ZIP9-only records). ADDRESS_ZIP5 wins the 12 prefix-disagreement rows
      # (0.061% of dual-populated records). See 147-DISCOVERY.md §4 for the decision
      # and §3 for the 12 disagreement rows.
      # Phase 139 AMEND-01 Step 0c arm retained: normalize_zip5_raw(ADDRESS_ZIP9)
      # covers records where ADDRESS_ZIP9 holds a bare 5-digit string that
      # normalize_zip9() rejects and ADDRESS_ZIP5 is absent.
      zip5_norm       = dplyr::coalesce(
        normalize_zip5(ADDRESS_ZIP5),
        normalize_zip5(zip9_norm),
        normalize_zip5_raw(ADDRESS_ZIP9)
      ),
      # FIX-06: reject sentinel ZIP5s (00000, 11111, ... 99999) -- placeholder values
      zip5_norm       = if_else(is_sentinel_zip5(zip5_norm), NA_character_, zip5_norm),
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
      by = "ID",
      relationship = "many-to-many"
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
  # FAN-OUT FIX (Phase 145): `queries` is one row per INPUT element, not per
  # distinct key -- callers pass repeated (ID, date) pairs (e.g. several encounters
  # on the same day). interval_hits and fallback_hits are deduped by
  # group_by()+slice(1), but `uncovered` inherits the duplicates and carries them
  # into still_uncovered -> none_rows -> matched. The final left_join then fans out
  # on every match_type == "none" key, breaking the "ONE row per DISTINCT
  # (ID, query_date)" contract in this function's @return.
  # Observed effect (R/116, Phase 144): 1,950,696 encounters -> 2,210,904 rows.
  uncovered <- queries %>%
    distinct(ID, query_date) %>%
    anti_join(covered, by = c("ID", "query_date"))

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
  # Contract assertion (Phase 145): matched must be unique on the join key, or the
  # left_join below fans out and every downstream row count is inflated.
  stopifnot("get_zip9_at_date: matched has duplicate (ID, query_date) keys" =
              !any(duplicated(matched[c("ID", "query_date")])))

  queries %>%
    distinct(ID, query_date) %>%
    left_join(matched, by = c("ID", "query_date")) %>%
    arrange(ID, query_date)
}

# Guard helper: reject centroid crosswalks with synthetic ZIP9s (entries ending
# in '0000' are placeholder delivery-point codes, not real ZIP+4 values).
# Extracted so tests can call it directly without going through the file-load path.
.validate_centroid_lookup <- function(lkp) {
  stopifnot("centroid crosswalk missing centroid_zip9 column" =
              "centroid_zip9" %in% names(lkp))
  bad <- lkp$centroid_zip9[grepl("0000$", lkp$centroid_zip9)]
  if (length(bad) > 0) {
    stop(sprintf(
      "[utils_address] centroid crosswalk contains %d ZIP9 values ending in '0000' — these are ",
      length(bad)),
      "synthetic placeholders, not delivery segments. See ",
      "data/reference/README_zip5_centroid_zip9_crosswalk.txt.")
  }
  invisible(lkp)
}

# ==============================================================================
# approximate_zip9() -- Fill ZIP9 from modal ZIP9 for ZIP5-only address records
# ==============================================================================

# Memoisation cache for the ZIP5->modal-ZIP9 lookup table (AMEND-06).
# Keyed by (addr_path, mtime, size) to force rebuild when file changes.
# FIX-09c: <<- mutation works while sourced into global env; if this ever becomes a
# package with a locked namespace, replace with an rlang environment or R6 cache.
.zip5_lookup_cache <- list(key = NULL, value = NULL)

# Memoisation cache for the ZIP5->centroid-ZIP9 crosswalk (Phase 144 Tier 3).
# Keyed by (path, mtime, size) to force rebuild when file changes.
.centroid_zip9_lookup_cache <- list(key = NULL, value = NULL)

# Shared classifier -- every exit path of approximate_zip9() routes through this so the
# returned column set and row count are identical regardless of which path was taken.
# FIX-01, FIX-02.
.classify_zip9_source <- function(result_tbl, zip5_lookup, unavailable = FALSE,
                                   centroid_lookup = NULL) {

  # FIX-09a: the lookup must be unique on ZIP5 or the join fans out
  stopifnot(!any(duplicated(zip5_lookup$ZIP5)))

  # Apply modal (Tier 2) lookup first
  out <- result_tbl %>%
    left_join(zip5_lookup, by = "ZIP5", na_matches = "never") %>%
    mutate(
      zip9_source = case_when(
        !is.na(ZIP9)         ~ "zip9_observed",
        is.na(match_type)    ~ "invalid_input",
        match_type == "none" ~ "none",
        unavailable          ~ "reference_unavailable",
        !is.na(modal_zip9)   ~ "zip5_modal",
        TRUE                 ~ ".needs_centroid_check"   # placeholder
      ),
      ZIP9 = if_else(zip9_source == "zip5_modal", modal_zip9, ZIP9),
      zip5_modal_freq   = if_else(zip9_source == "zip5_modal", as.integer(zip5_modal_freq),   NA_integer_),
      zip5_n_candidates = if_else(zip9_source == "zip5_modal", as.integer(zip5_n_candidates), NA_integer_),
      zip5_modal_share  = if_else(zip9_source == "zip5_modal", zip5_modal_share,              NA_real_)
    ) %>%
    select(-modal_zip9)

  # Apply centroid (Tier 3) lookup for rows still needing resolution
  if (!is.null(centroid_lookup) && nrow(centroid_lookup) > 0) {
    stopifnot(!any(duplicated(centroid_lookup$ZIP5)))
    out <- out %>%
      left_join(centroid_lookup, by = "ZIP5", na_matches = "never") %>%
      mutate(
        zip9_source = case_when(
          zip9_source != ".needs_centroid_check" ~ zip9_source,
          !is.na(centroid_zip9)                  ~ "zip5_centroid",
          !is.na(ZIP5)                            ~ "zip5_no_zip9",
          TRUE                                    ~ "no_zip5"
        ),
        ZIP9 = if_else(zip9_source == "zip5_centroid", centroid_zip9, ZIP9)
      ) %>%
      select(-centroid_zip9)
  } else {
    # No centroid lookup available — resolve placeholder directly
    out <- out %>%
      mutate(
        zip9_source = case_when(
          zip9_source != ".needs_centroid_check" ~ zip9_source,
          !is.na(ZIP5)                            ~ "zip5_no_zip9",
          TRUE                                    ~ "no_zip5"
        )
      )
  }

  out <- out %>% arrange(ID, query_date)

  # FIX-02: assert row count is preserved on every exit path
  stopifnot(nrow(out) == nrow(result_tbl))
  out
}

# Empty lookup with correct column types, used on exit paths where no lookup is built.
.empty_zip5_lookup <- function() {
  tibble(
    ZIP5              = character(),
    modal_zip9        = character(),
    zip5_modal_freq   = integer(),
    zip5_n_candidates = integer(),
    zip5_modal_share  = double()
  )
}

# Empty centroid lookup with correct column types, used on probe-gate exit paths.
.empty_centroid_lookup <- function() {
  tibble(
    ZIP5          = character(),
    centroid_zip9 = character()
  )
}

#' Approximate ZIP9 for rows returned by get_zip9_at_date() that have ZIP9 = NA.
#'
#' For each row where ZIP9 is NA and match_type is not "none", looks up the
#' most frequent (modal) valid ZIP9 for that ZIP5 across the full
#' LDS_ADDRESS_HISTORY file. Returns the input tibble with ZIP9 filled in where
#' approximation succeeds, plus four provenance/confidence columns.
#'
#' The column set returned is identical on every exit path (file absent, missing
#' columns, zero candidates, normal run). Row count is preserved on all paths.
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
#'       \code{"none"} — match_type was "none" (no address record found at all);
#'       \code{"reference_unavailable"} — gate fired, approximation was never attempted
#'         (LDS file absent or required columns missing);
#'       \code{"invalid_input"} — match_type was NA; malformed row, not approximated.
#'         Should be zero for any tibble produced by get_zip9_at_date().
#'     }
#'     \item{zip5_modal_freq}{(int) Number of distinct patient IDs whose ZIP+4 modal
#'       count determined the winner for this ZIP5. NA for non-zip5_modal rows.}
#'     \item{zip5_n_candidates}{(int) Number of distinct ZIP+4 values seen for this ZIP5.
#'       NA for non-zip5_modal rows.}
#'     \item{zip5_modal_share}{(dbl) Approximate fraction of freq / sum(freq) across all
#'       ZIP+4 candidates for this ZIP5. Approximate because patients appearing at more
#'       than one ZIP+4 within the same ZIP5 are double-counted in sum(freq). NA for
#'       non-zip5_modal rows.}
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
# Requirements: Phase 139 -- D-01 through D-08 (+ 139-01-PATCH, 139-02-PATCH)
approximate_zip9 <- function(result_tbl) {

  ADDR_FILENAME <- "LDS_ADDRESS_HISTORY_Mailhot_V1.csv"
  addr_path     <- file.path(CONFIG$data_dir, ADDR_FILENAME)

  # FIX-03: idempotency guard -- a second application would collide on the join columns
  # and produce .x/.y suffixes with no error
  prov_cols <- c("zip9_source", "zip5_modal_freq", "zip5_n_candidates", "zip5_modal_share")
  if (any(prov_cols %in% names(result_tbl))) {
    message(glue(
      "[utils_address] approximate_zip9: input already carries provenance column(s) ",
      "{paste(intersect(prov_cols, names(result_tbl)), collapse = ', ')} -- returning input unchanged"
    ))
    return(result_tbl)
  }

  # D-08: probe-first gate -- classify with an empty lookup so the schema still holds
  if (!file.exists(addr_path)) {
    message(glue(
      "[utils_address] approximate_zip9: LDS_ADDRESS_HISTORY not found at {addr_path} ",
      "-- no approximation attempted"
    ))
    return(.classify_zip9_source(result_tbl, .empty_zip5_lookup(), unavailable = TRUE))
  }

  # D-01 / D-02: count approximable rows. Used only to skip the file load -- classification
  # still runs, so the schema and row count are unaffected.
  n_to_approx <- result_tbl %>%
    filter(is.na(ZIP9), !is.na(match_type), match_type != "none") %>%
    nrow()

  if (n_to_approx == 0) {
    return(.classify_zip9_source(result_tbl, .empty_zip5_lookup(), unavailable = FALSE))
  }

  # D-05 / AMEND-06: memoised lookup, keyed on path + mtime + size
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
          "[utils_address] approximate_zip9: vroom failed ({conditionMessage(e)}); ",
          "falling back to read.csv"
        ))
        read.csv(addr_path, colClasses = "character", na.strings = c("", "NA"))
      }
    )

    req     <- c("ID", "ADDRESS_ZIP9", "ADDRESS_PERIOD_START")
    missing <- setdiff(req, names(addr_raw))
    if (length(missing) > 0) {
      message(glue(
        "[utils_address] approximate_zip9: missing column(s) ",
        "{paste(missing, collapse = ', ')} -- no approximation attempted"
      ))
      return(.classify_zip9_source(result_tbl, .empty_zip5_lookup(), unavailable = TRUE))
    }

    # D-03 / D-04 (AMEND-04): modal frequency counts distinct patients, not rows.
    # Tie-break is total: freq desc, recency desc, ZIP9 string asc.
    zip5_lookup <- addr_raw %>%
      mutate(
        zip9_norm       = normalize_zip9(ADDRESS_ZIP9),
        zip5_norm       = normalize_zip5(zip9_norm),
        period_start_dt = parse_pcornet_date(ADDRESS_PERIOD_START)
      ) %>%
      filter(
        !is.na(zip9_norm),
        !is.na(zip5_norm),
        !is.na(period_start_dt),
        !is_sentinel_zip5(zip5_norm)          # FIX-06
      ) %>%
      group_by(zip5_norm, zip9_norm) %>%
      summarise(
        freq        = n_distinct(ID),
        latest_date = suppressWarnings(max(period_start_dt, na.rm = TRUE)),
        .groups     = "drop"
      ) %>%
      group_by(zip5_norm) %>%
      mutate(
        n_candidates = n(),
        modal_share  = freq / sum(freq)
      ) %>%
      arrange(desc(freq), desc(latest_date), zip9_norm, .by_group = TRUE) %>%
      slice(1) %>%
      ungroup() %>%
      select(
        ZIP5              = zip5_norm,
        modal_zip9        = zip9_norm,
        zip5_modal_freq   = freq,
        zip5_n_candidates = n_candidates,
        zip5_modal_share  = modal_share
      )

    .zip5_lookup_cache$key   <<- cache_key
    .zip5_lookup_cache$value <<- zip5_lookup
  }

  # After Phase 148: ADDRESS_ZIP5 is now read directly, so approximable rows
  # should have ZIP5 from that column. If all still have ZIP5 = NA, that means
  # the sentinel filter or genuine missingness accounts for it -- not an unread column.
  n_approx_with_zip5 <- result_tbl %>%
    filter(is.na(ZIP9), !is.na(match_type), match_type != "none", !is.na(ZIP5)) %>%
    nrow()
  if (n_approx_with_zip5 == 0) {
    message(glue(
      "[utils_address] approximate_zip9: {n_to_approx} approximable row(s) found ",
      "but all have ZIP5 = NA after coalescing ADDRESS_ZIP5 and ADDRESS_ZIP9 prefix; ",
      "zip5_modal tier will report zero rows for these. ",
      "Note: before Phase 147, ADDRESS_ZIP5 was never read so this was structurally ",
      "guaranteed -- see 147-DISCOVERY.md. Post-147 a zero here is a genuine data ",
      "observation, not an artefact."
    ))
  }

  # D-03 (Phase 144): Tier 3 centroid crosswalk — probe-first gated.
  CENTROID_FILENAME <- "zip5_centroid_zip9_crosswalk.csv"
  # Anchor to the project root, not getwd(). Every other path in this file goes
  # through CONFIG; a bare relative path silently reports "not found" and skips
  # Tier 3 whenever the caller's working directory differs.
  centroid_path     <- if (!is.null(CONFIG$reference_dir)) {
    file.path(CONFIG$reference_dir, CENTROID_FILENAME)
  } else if (requireNamespace("here", quietly = TRUE)) {
    here::here("data", "reference", CENTROID_FILENAME)
  } else {
    file.path("data", "reference", CENTROID_FILENAME)
  }

  centroid_lookup <- if (file.exists(centroid_path)) {
    cache_key_c <- paste0(
      normalizePath(centroid_path, mustWork = FALSE), "|",
      as.numeric(file.mtime(centroid_path)), "|",
      file.size(centroid_path)
    )
    if (!is.null(.centroid_zip9_lookup_cache$key) &&
        identical(.centroid_zip9_lookup_cache$key, cache_key_c)) {
      .centroid_zip9_lookup_cache$value
    } else {
      raw_c <- tryCatch(
        vroom::vroom(centroid_path,
                     col_types = vroom::cols(ZIP5 = "c", centroid_zip9 = "c"),
                     progress = FALSE),
        error = function(e) {
          message(glue("[utils_address] approximate_zip9: centroid crosswalk read failed ",
                       "({conditionMessage(e)}) -- Tier 3 skipped"))
          NULL
        }
      )
      if (!is.null(raw_c) && all(c("ZIP5", "centroid_zip9") %in% names(raw_c))) {
        lkp_c <- raw_c %>%
          filter(!is.na(ZIP5), !is.na(centroid_zip9)) %>%
          distinct(ZIP5, .keep_all = TRUE) %>%
          select(ZIP5, centroid_zip9)
        .centroid_zip9_lookup_cache$key   <<- cache_key_c
        .centroid_zip9_lookup_cache$value <<- lkp_c
        lkp_c
      } else {
        message(glue("[utils_address] approximate_zip9: centroid crosswalk missing required ",
                     "columns ZIP5/centroid_zip9 -- Tier 3 skipped"))
        .empty_centroid_lookup()
      }
    }
  } else {
    message(glue(
      "[utils_address] approximate_zip9: centroid crosswalk not found at {centroid_path} ",
      "-- Tier 3 skipped (stage data/reference/zip5_centroid_zip9_crosswalk.csv to activate)"
    ))
    .empty_centroid_lookup()
  }

  # Guard: reject crosswalks that contain synthetic ZIP9s (P0-01).
  # Delegated to .validate_centroid_lookup() so tests can exercise the guard directly.
  .validate_centroid_lookup(centroid_lookup)

  result_out <- .classify_zip9_source(result_tbl, zip5_lookup, unavailable = FALSE,
                                       centroid_lookup = centroid_lookup)

  # AMEND-08a / FIX-08: one line per level, newline-terminated
  src_counts <- table(result_out$zip9_source)
  get_count  <- function(k) { v <- src_counts[k]; if (is.na(v)) 0L else as.integer(v) }

  modal_rows <- result_out %>% filter(zip9_source == "zip5_modal")
  share_line <- if (nrow(modal_rows) > 0) {
    ms <- modal_rows$zip5_modal_share
    glue("  modal_share -- min {round(min(ms, na.rm = TRUE), 3)} / ",
         "median {round(median(ms, na.rm = TRUE), 3)} / ",
         "max {round(max(ms, na.rm = TRUE), 3)}")
  } else {
    "  modal_share -- (no approximated rows)"
  }

  message(paste(
    "[utils_address] approximate_zip9: zip9_source breakdown",
    glue("  zip9_observed:         {get_count('zip9_observed')}"),
    glue("  zip5_modal:            {get_count('zip5_modal')}"),
    glue("  zip5_centroid:         {get_count('zip5_centroid')}"),
    glue("  zip5_no_zip9:          {get_count('zip5_no_zip9')}"),
    glue("  no_zip5:               {get_count('no_zip5')}"),
    glue("  none:                  {get_count('none')}"),
    glue("  reference_unavailable: {get_count('reference_unavailable')}"),
    glue("  invalid_input:         {get_count('invalid_input')}"),
    share_line,
    sep = "\n"
  ))

  result_out
}
