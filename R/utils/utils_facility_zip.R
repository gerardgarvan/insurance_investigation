# ==============================================================================
# utils_facility_zip.R -- Facility ZIP fill helpers (Phase 182)
# ==============================================================================
# Purpose:
#   Build a lookup keyed on (SOURCE, FACILITYID) mapping each key to its fill
#   ZIP5 under the Tier 1 rule (exactly one distinct normalized ZIP5, ≥ 3
#   supporting encounters), plus sensitivity-tier fields.  Apply the lookup to
#   fill NA zip5_facility values in the encounter frame used by R/122.
#
# Inputs (to build_facility_zip_lookup):
#   enc_raw: data frame with columns SOURCE, FACILITYID, enc_zip_raw.
#
# Inputs (to apply_facility_zip_fill):
#   enc_for_dist: data frame with columns SOURCE, FACILITYID, zip5_facility.
#   lookup:       output of build_facility_zip_lookup().
#   apply:        logical (default TRUE); FALSE reproduces pre-182 behaviour.
#
# Outputs:
#   build_facility_zip_lookup() → tibble with one row per valid (SOURCE, FACILITYID)
#   apply_facility_zip_fill()   → enc_for_dist with zip5_facility filled and
#                                  facility_zip_source column added
#
# Design decisions (Phase 182 CONTEXT.md):
#   D-01: Key = SOURCE + FACILITYID; na_matches = "never".
#   D-02: Tier 1 = exactly one distinct ZIP5 with ≥ 3 supporting encounters.
#   D-03: Sensitivity tier = modal ZIP ≥ 95% share, ≥ 10 supporting (reported only).
#   D-04: No fuzzy FACILITY_LOCATION text matching.
#   D-05: facility_zip_source ∈ {observed / filled_tier1 / not_filled / not_filled_no_key}.
#   D-08: guarded by CONFIG$facility_zip_fill toggle in R/122 (not here).
#
# Dependencies:
#   dplyr (no library() calls here -- caller sources R/00_config.R first)
#   normalize_zip5_raw() from R/utils/utils_address.R (auto-sourced by R/00_config.R)
#
# No I/O, no library() calls, no data.table syntax.
# ==============================================================================

# ------------------------------------------------------------------------------
# FACILITYID placeholder codes (confirmed initial set; extend after HiPerGator
# pre-flight reveals additional codes in the 20261013 extract).
# ------------------------------------------------------------------------------
FACILITYID_PLACEHOLDERS <- c("", "0", "NI", "UN", "UNK", "UNKNOWN", "OT", "NA")

# ------------------------------------------------------------------------------
#' Check whether a FACILITYID value is usable as a fill key.
#'
#' Returns FALSE for NA, blank/whitespace-only, and values that match
#' FACILITYID_PLACEHOLDERS (case-insensitive). Returns TRUE otherwise.
#'
#' @param x Character (or coercible). FACILITYID values.
#' @return Logical vector, same length as x.
facility_key_ok <- function(x) {
  x <- trimws(as.character(x))
  !is.na(x) & !(toupper(x) %in% FACILITYID_PLACEHOLDERS)
}

# ------------------------------------------------------------------------------
#' Build the facility ZIP lookup table.
#'
#' For each valid (SOURCE, FACILITYID) key, summarises supporting encounters
#' (those with a parseable facility ZIP) and computes:
#' - Tier 1 fill_zip (primary fill; one distinct ZIP, ≥ 3 supporting).
#' - fill_status: filled_tier1 / ambiguous / no_donor.
#' - Sensitivity-tier fields: sens_modal_zip, sens_modal_n, sens_modal_share,
#'   sens_fill_ok (reported only; not applied to the primary RDS).
#'
#' FACILITYID values that are NA, blank, or in FACILITYID_PLACEHOLDERS are
#' excluded from the lookup (never donors, never recipients).
#'
#' @param enc_raw Data frame with columns SOURCE, FACILITYID, enc_zip_raw.
#' @return A grouped-free tibble with one row per valid (SOURCE, FACILITYID) key.
build_facility_zip_lookup <- function(enc_raw) {
  stopifnot(all(c("SOURCE", "FACILITYID", "enc_zip_raw") %in% names(enc_raw)))
  enc_raw |>
    dplyr::mutate(
      FACILITYID     = trimws(as.character(FACILITYID)),
      candidate_zip5 = normalize_zip5_raw(enc_zip_raw)
    ) |>
    dplyr::filter(facility_key_ok(FACILITYID), !is.na(SOURCE)) |>
    dplyr::group_by(SOURCE, FACILITYID) |>
    dplyr::summarise(
      n_total         = dplyr::n(),
      n_missing_zip   = sum(is.na(candidate_zip5)),
      n_supporting    = sum(!is.na(candidate_zip5)),
      n_distinct_zips = dplyr::n_distinct(candidate_zip5[!is.na(candidate_zip5)]),
      fill_zip        = if (n_distinct_zips == 1L && n_supporting >= 3L)
                          candidate_zip5[!is.na(candidate_zip5)][1] else NA_character_,
      fill_status     = dplyr::case_when(
                          n_distinct_zips == 1L & n_supporting >= 3L ~ "filled_tier1",
                          n_distinct_zips > 1L                       ~ "ambiguous",
                          TRUE                                       ~ "no_donor"),
      sens_modal_zip   = { v <- candidate_zip5[!is.na(candidate_zip5)]
                           if (length(v)) names(which.max(table(v))) else NA_character_ },
      sens_modal_n     = { v <- candidate_zip5[!is.na(candidate_zip5)]
                           if (length(v)) as.integer(max(table(v))) else 0L },
      sens_modal_share = ifelse(n_supporting > 0, sens_modal_n / n_supporting, NA_real_),
      sens_fill_ok     = n_distinct_zips > 1L & sens_modal_share >= 0.95 & n_supporting >= 10L,
      .groups = "drop")
}

# ------------------------------------------------------------------------------
#' Apply the facility ZIP fill lookup to an encounter frame.
#'
#' Joins the lookup to enc_for_dist by (SOURCE, FACILITYID) using
#' na_matches = "never" so that NA FACILITYID never matches any lookup row.
#' Only NA zip5_facility values whose key has fill_status == "filled_tier1"
#' and whose FACILITYID passes facility_key_ok() are filled.
#'
#' Adds column facility_zip_source:
#'   "observed"           – zip5_facility was already non-NA before fill.
#'   "filled_tier1"       – was NA; filled from Tier 1 lookup.
#'   "not_filled_no_key"  – was NA; FACILITYID is NA/blank/placeholder (no key).
#'   "not_filled"         – was NA; key exists but fill_status is not filled_tier1.
#'
#' Row count is asserted unchanged (stopifnot).
#'
#' @param enc_for_dist Data frame with columns SOURCE, FACILITYID, zip5_facility.
#' @param lookup       Output of build_facility_zip_lookup().
#' @param apply        Logical. When FALSE, no fills are applied (only sources
#'                     "observed" / "not_filled" are emitted). Default TRUE.
#' @return enc_for_dist with zip5_facility (possibly filled) and
#'         facility_zip_source added.
apply_facility_zip_fill <- function(enc_for_dist, lookup, apply = TRUE) {
  stopifnot(all(c("SOURCE", "FACILITYID", "zip5_facility") %in% names(enc_for_dist)))
  n0 <- nrow(enc_for_dist)
  lk <- dplyr::select(lookup, SOURCE, FACILITYID, fill_zip, fill_status)
  out <- enc_for_dist |>
    dplyr::mutate(
      FACILITYID = trimws(as.character(FACILITYID)),
      .key_ok    = facility_key_ok(FACILITYID)
    ) |>
    dplyr::left_join(lk, by = c("SOURCE", "FACILITYID"), na_matches = "never") |>
    dplyr::mutate(
      .was_observed = !is.na(zip5_facility),
      .fillable     = apply & !.was_observed & .key_ok &
                      fill_status %in% "filled_tier1" & !is.na(fill_zip),
      zip5_facility      = dplyr::if_else(.fillable, fill_zip, zip5_facility),
      facility_zip_source = dplyr::case_when(
        .was_observed ~ "observed",
        .fillable     ~ "filled_tier1",
        !.key_ok      ~ "not_filled_no_key",
        TRUE          ~ "not_filled")
    ) |>
    dplyr::select(-.was_observed, -.fillable, -.key_ok, -fill_zip, -fill_status)
  stopifnot("apply_facility_zip_fill changed row count" = nrow(out) == n0)
  out
}
