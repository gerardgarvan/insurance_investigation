# ==============================================================================
# utils/utils_zip_crosswalk.R -- ZIP-to-ZCTA crosswalk helpers (Phase 182.1)
# ==============================================================================
#
# Purpose:
#   Load the UDS Mapper ZIP Code to ZCTA Crosswalk via zippeR and provide pure
#   helper functions for mapping facility ZIPs to ZCTAs and flagging placeholder
#   facility ZIPs. Patient-side sentinel logic (is_sentinel_zip5) is NOT modified.
#
# Functions:
#   load_hrsa_crosswalk()
#     Loads the UDS Mapper 2023 crosswalk via zippeR::zi_load_crosswalk().
#     Normalises columns (ZIP_CODE or ZIP + ZCTA, case-insensitive), pads to
#     5 digits, deduplicates on ZIP. Stops clearly if zippeR is absent or the
#     data is malformed. Returns a data.frame with columns ZIP and ZCTA
#     (character, 5-digit). attr(out, "source_file") = "zippeR::zi_load_crosswalk(UDS,2023)".
#
#   zi_normalise_xwalk(x, label)
#     Internal helper: normalises a raw data.frame to ZIP/ZCTA. Exported for
#     direct use in unit tests without requiring network access.
#
#   map_zip_to_zcta(zip5, xwalk)
#     Looks up each element of zip5 in the crosswalk. Returns the corresponding
#     ZCTA or NA if not found. Never alters ZIPs that already resolve via
#     zipcodeR; use this only for fallback mapping.
#
#   is_placeholder_facility_zip5(zip5, xwalk)
#     Returns TRUE for 000xx patterns AND for ZIP3+"00" codes (e.g., 32800,
#     32700) that are absent from the crosswalk (i.e., not real delivery ZIPs).
#     Returns NA for NA input.
#
# Design decisions (Phase 182.1 CONTEXT.md):
#   D-04: Pure helpers with no library() calls; no data.table syntax.
#   D-05: is_sentinel_zip5() in utils_address.R is NOT modified.
#   D-01a: Loader accepts ZIP_CODE or ZIP and ZCTA, case-insensitive, pads to 5.
#
# Dependencies:
#   zippeR (zi_load_crosswalk); checked at point of use via requireNamespace.
#   normalize_zip5_raw() from R/utils/utils_address.R (auto-sourced by 00_config.R).
#
# No I/O except in load_hrsa_crosswalk(); no library() calls; no data.table syntax.
# ==============================================================================

# ------------------------------------------------------------------------------
#' Normalise a raw ZIP->ZCTA data.frame to the standard two-column format.
#'
#' Detects ZIP_CODE or ZIP column (case-insensitive), pads both to 5 digits,
#' drops unparseable ZIP rows, deduplicates on ZIP. Exported so unit tests can
#' exercise normalisation without a network call.
#'
#' @param x   data.frame returned by zippeR::zi_load_crosswalk or any compatible source.
#' @param label Character scalar. Stored as attr(out, "source_file").
#' @return data.frame with columns ZIP and ZCTA (chr, 5-digit).
zi_normalise_xwalk <- function(x, label = "unknown") {
  nm <- toupper(trimws(names(x)))
  zip_col  <- which(nm %in% c("ZIP_CODE", "ZIP"))[1]
  zcta_col <- which(nm == "ZCTA")[1]

  if (is.na(zip_col) || is.na(zcta_col))
    stop(
      "[Phase 182.1] crosswalk needs ZIP_CODE (or ZIP) and ZCTA columns; found: ",
      paste(names(x), collapse = ", "),
      call. = FALSE
    )

  pad5 <- function(v) {
    v <- gsub("[^0-9]", "", trimws(as.character(v)))
    ifelse(nchar(v) %in% 1:5,
           formatC(as.integer(v), width = 5, flag = "0"),
           NA_character_)
  }

  out <- data.frame(
    ZIP  = pad5(x[[zip_col]]),
    ZCTA = pad5(x[[zcta_col]]),
    stringsAsFactors = FALSE
  )
  out <- out[!is.na(out$ZIP), ]
  out <- out[!duplicated(out$ZIP), ]
  attr(out, "source_file") <- label
  out
}

# ------------------------------------------------------------------------------
#' Load the UDS Mapper ZIP Code to ZCTA Crosswalk via zippeR.
#'
#' Calls zippeR::zi_load_crosswalk(zip_source = "UDS", year = 2023) and
#' normalises the result to a two-column data.frame (ZIP, ZCTA). Stops with a
#' clear message if zippeR is not installed or returns malformed data.
#'
#' @return A data.frame with columns ZIP (chr, 5-digit) and ZCTA (chr, 5-digit
#'   or NA where ZCTA is missing). attr(out, "source_file") records the source.
#' @examples
#' \dontrun{
#'   xwalk <- load_hrsa_crosswalk()
#' }
load_hrsa_crosswalk <- function() {
  if (!requireNamespace("zippeR", quietly = TRUE))
    stop(
      "[Phase 182.1] zippeR package required for ZIP->ZCTA crosswalk. ",
      "Install with: install.packages('zippeR')",
      call. = FALSE
    )
  raw <- zippeR::zi_load_crosswalk(zip_source = "UDS", year = 2023)
  zi_normalise_xwalk(raw, label = "zippeR::zi_load_crosswalk(UDS,2023)")
}

# ------------------------------------------------------------------------------
#' Map ZIP5 codes to ZCTAs using the crosswalk.
#'
#' For each element of zip5, returns the corresponding ZCTA from the crosswalk
#' or NA if the ZIP is not present. Normalises input via normalize_zip5_raw()
#' before matching.
#'
#' @param zip5  Character vector of ZIP5 codes (raw; normalization is applied).
#' @param xwalk data.frame with columns ZIP and ZCTA (output of load_hrsa_crosswalk).
#' @return Character vector, same length as zip5, with ZCTAs or NA.
map_zip_to_zcta <- function(zip5, xwalk) {
  stopifnot(is.data.frame(xwalk), all(c("ZIP", "ZCTA") %in% names(xwalk)))
  z5 <- normalize_zip5_raw(zip5)
  xwalk$ZCTA[match(z5, xwalk$ZIP)]
}

# ------------------------------------------------------------------------------
#' Flag placeholder facility ZIP5 codes.
#'
#' Returns TRUE for:
#'   (1) Any ZIP matching ^000 (000xx codes -- never a real delivery ZIP).
#'   (2) ZIP3+"00" patterns (e.g., 32800, 32700, 34700) that are absent from
#'       the crosswalk -- i.e., not a real delivery ZIP with a ZCTA mapping.
#'
#' Real ZIPs that appear in the crosswalk are never flagged TRUE, even if they
#' happen to end in "00". NA input returns NA.
#'
#' NOTE: This function is for FACILITY ZIPs only. Do not use on patient ZIPs;
#' patient-side logic uses is_sentinel_zip5() in utils_address.R (Phase 182.1 D-05).
#'
#' @param zip5  Character vector of ZIP5 codes.
#' @param xwalk data.frame with at least column ZIP (output of load_hrsa_crosswalk).
#' @return Logical vector, same length as zip5.
is_placeholder_facility_zip5 <- function(zip5, xwalk) {
  stopifnot(is.data.frame(xwalk), "ZIP" %in% names(xwalk))
  z5 <- normalize_zip5_raw(zip5)
  out <- !is.na(z5) & (
    grepl("^000", z5) |
    (grepl("00$", z5) & !(z5 %in% xwalk$ZIP))
  )
  out[is.na(z5)] <- NA
  out
}
