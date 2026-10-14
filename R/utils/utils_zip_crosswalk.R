# ==============================================================================
# utils/utils_zip_crosswalk.R -- HRSA ZIP-to-ZCTA crosswalk helpers (Phase 182.1)
# ==============================================================================
#
# Purpose:
#   Load the HRSA UDS Mapper ZIP Code to ZCTA Crosswalk and provide pure helper
#   functions for mapping facility ZIPs to ZCTAs and flagging placeholder facility
#   ZIPs. Patient-side sentinel logic (is_sentinel_zip5) is NOT modified here.
#
# Functions:
#   load_hrsa_crosswalk(path)
#     Reads the HRSA UDS Mapper crosswalk file (CSV or xlsx). Accepts columns
#     named ZIP_CODE or ZIP (case-insensitive) plus ZCTA. Pads both columns to
#     5 digits. Stops with a clear message if the file is absent or malformed.
#     Returns a data.frame with columns ZIP and ZCTA (character, 5-digit, unique
#     on ZIP). Records the source filename as attr(out, "source_file").
#
#   map_zip_to_zcta(zip5, xwalk)
#     Looks up each element of zip5 in the crosswalk. Returns the corresponding
#     ZCTA or NA if not found. Never alters ZIPs that already resolve via
#     zipcodeR; use this only for fallback mapping.
#
#   is_placeholder_facility_zip5(zip5, xwalk)
#     Returns TRUE for 000xx patterns AND for ZIP3+"00" codes (e.g., 32800,
#     32700) that are absent from the HRSA crosswalk (i.e., not real delivery
#     ZIPs). Uses the crosswalk to avoid hard-coding the list of placeholder
#     values. Returns NA for NA input.
#
# Design decisions (Phase 182.1 CONTEXT.md):
#   D-04: Pure helpers with no library() calls; no data.table syntax.
#   D-05: is_sentinel_zip5() in utils_address.R is NOT modified.
#   D-01a: Loader accepts ZIP_CODE or ZIP and ZCTA, case-insensitive, pads to 5.
#
# Dependencies:
#   normalize_zip5_raw() from R/utils/utils_address.R (auto-sourced by 00_config.R)
#   readxl (only for .xlsx files; loaded at point of use via requireNamespace)
#
# No I/O except in load_hrsa_crosswalk(); no library() calls; no data.table syntax.
# ==============================================================================

# ------------------------------------------------------------------------------
#' Load the HRSA UDS Mapper ZIP Code to ZCTA Crosswalk.
#'
#' Accepts CSV or Excel (.xls/.xlsx) files. Column names are matched
#' case-insensitively: the first column named ZIP_CODE or ZIP is used as the
#' ZIP source column; the first column named ZCTA is used as the ZCTA column.
#' Both are padded to 5 digits (numeric-only characters; leading zeros preserved).
#' Rows with non-parseable ZIP values are dropped with a warning. Duplicate ZIPs
#' are deduplicated, keeping the first occurrence.
#'
#' @param path Character. Path to the HRSA crosswalk file.
#' @return A data.frame with columns ZIP (chr, 5-digit) and ZCTA (chr, 5-digit
#'   or NA where ZCTA is missing/unparseable). attr(out, "source_file") = basename.
#' @examples
#' \dontrun{
#'   xwalk <- load_hrsa_crosswalk(CONFIG$hrsa_zip_zcta_path)
#' }
load_hrsa_crosswalk <- function(path) {
  if (is.null(path) || !nzchar(path) || !file.exists(path))
    stop(
      "[Phase 182.1] HRSA ZIP→ZCTA crosswalk not found at: ", path,
      "\nStage the UDS Mapper 'ZIP Code to ZCTA Crosswalk' in data/reference/ ",
      "and set CONFIG$hrsa_zip_zcta_path.",
      call. = FALSE
    )

  x <- if (grepl("\\.xlsx?$", path, ignore.case = TRUE)) {
    if (!requireNamespace("readxl", quietly = TRUE))
      stop("[Phase 182.1] readxl is required to read .xlsx crosswalk files.",
           call. = FALSE)
    readxl::read_excel(path, col_types = "text")
  } else {
    utils::read.csv(path, colClasses = "character", check.names = FALSE)
  }

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
    v <- gsub("[^0-9]", "", trimws(v))
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

  attr(out, "source_file") <- basename(path)
  out
}

# ------------------------------------------------------------------------------
#' Map ZIP5 codes to ZCTAs using the HRSA crosswalk.
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
#'       the HRSA crosswalk -- i.e., not a real delivery ZIP with a ZCTA mapping.
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
