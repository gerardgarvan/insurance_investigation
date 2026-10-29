# ==============================================================================
# utils/utils_doi.R -- Diagnosis-of-Interest (DoI) classification utilities
# ==============================================================================
#
# Purpose:
#   is_doi_code(dx, dx_type)  -- DX_TYPE-gated detector for non-malignant
#     rituximab/methotrexate indication codes (autoimmune/inflammatory/
#     hematologic). Prefix-matches against DOI_CODE_MAP from R/00_config.R.
#   classify_doi_codes(codes) -- maps ICD-10/ICD-9 codes to DoI categories via
#     the 4-char-before-3-char prefix cascade over DOI_CODE_MAP.
#
#   WHY parallel to utils_cancer.R but NOT merged: classify_codes() has 10+
#   consumers that assume cancer-site output; merging would corrupt them.
#   Auto-sourced via the R/utils/*.R glob at the end of R/00_config.R.
#
#   WHY is_doi_code() is DX_TYPE-gated (unlike is_cancer_code()): ICD-9 RA is
#   "714" and there is no ICD-10 code beginning "714", but bare-numeric prefix
#   keys (714, 710, 446, 287, 283, 341, 358, 696, 555, 556) MUST only match
#   ICD-9 records. Gating on dx_type ("09"/"10", NA/SNOMED -> FALSE) mirrors
#   is_hl_diagnosis() and prevents ICD-9/ICD-10 numeric collision (PITFALLS 1).
#
# Dependencies: DOI_CODE_MAP from R/00_config.R; normalize_icd() from
#   utils_icd.R; stringr.
# ==============================================================================

library(stringr)

# Which DOI_CODE_MAP keys are ICD-9 (bare numeric) vs ICD-10 (alpha-leading).
# Computed once at source time from the map so the two systems never cross-match.
.doi_keys_icd9  <- grep("^[0-9]", names(DOI_CODE_MAP), value = TRUE)
.doi_keys_icd10 <- grep("^[0-9]", names(DOI_CODE_MAP), value = TRUE, invert = TRUE)

#' Detect whether diagnosis codes are non-malignant DoI codes (DX_TYPE-gated)
#'
#' Prefix-matches against DOI_CODE_MAP from R/00_config.R, gated on DX_TYPE so
#' that numeric ICD-9 keys (714, 710, 446, ...) only match ICD-9 records and
#' alpha-leading ICD-10 keys (M05, D692, ...) only match ICD-10 records.
#' NA or non-"09"/"10" DX_TYPE values (e.g. "SM" for SNOMED) return FALSE.
#'
#' @param dx      Character vector of diagnosis codes (dotted or undotted)
#' @param dx_type Character vector of DX_TYPE values ("09" ICD-9, "10" ICD-10;
#'   NA / "SM" / anything else -> FALSE)
#' @return Logical vector; TRUE only when the code's prefix is in DOI_CODE_MAP
#'   AND dx_type matches the coding system that key belongs to.
#'
#' @examples
#' is_doi_code(c("M05.9", "714.0", "714.0", "C81.90"), c("10", "09", "10", "10"))
#' # Returns: c(TRUE, TRUE, FALSE, FALSE)
#'
#' is_doi_code(c("M05.9", "M05.9"), c(NA, "SM"))
#' # Returns: c(FALSE, FALSE)
is_doi_code <- function(dx, dx_type) {
  if (length(dx) == 0) return(logical(0))
  result <- rep(FALSE, length(dx))

  # Gate: both values present AND dx_type is a recognized ICD coding system
  valid <- !is.na(dx) & !is.na(dx_type) & dx_type %in% c("09", "10")
  if (!any(valid)) return(result)

  dx_clean <- normalize_icd(dx)          # reuse: uppercase + strip dots
  p4 <- substr(dx_clean, 1, 4)
  p3 <- substr(dx_clean, 1, 3)

  is10 <- valid & dx_type == "10"
  is09 <- valid & dx_type == "09"

  # ICD-10 records: match against alpha-leading DOI_CODE_MAP keys only
  result[is10] <- (p4[is10] %in% .doi_keys_icd10) | (p3[is10] %in% .doi_keys_icd10)

  # ICD-9 records: match against numeric DOI_CODE_MAP keys only
  result[is09] <- (p4[is09] %in% .doi_keys_icd9) | (p3[is09] %in% .doi_keys_icd9)

  result
}

#' Classify ICD-10/ICD-9 codes into DoI categories (4-char before 3-char)
#'
#' Mirrors classify_codes() from utils_cancer.R: normalizes codes (dots
#' stripped), tries the 4-character prefix against DOI_CODE_MAP first (so
#' D692 -> "Vasculitis" and D693 -> "Hematologic Autoimmune" resolve before
#' the 3-char "D69" prefix would be attempted), then falls back to the
#' 3-character prefix, and returns NA for codes with no map entry.
#'
#' NOT DX_TYPE-gated -- callers that need gating should filter rows with
#' is_doi_code() first, matching the contract of classify_codes() which
#' classifies only codes already known to be in scope.
#'
#' @param codes Character vector of diagnosis codes (dotted or undotted)
#' @return Character vector of DoI category names (NA if no map entry)
#'
#' @examples
#' classify_doi_codes(c("M05.9", "D69.2", "D69.3", "K50.90"))
#' # Returns: c("Rheumatoid Arthritis", "Vasculitis",
#' #            "Hematologic Autoimmune", "Inflammatory Bowel Disease")
#'
#' classify_doi_codes("C81.90")
#' # Returns: NA  (HL code, no DOI_CODE_MAP entry)
classify_doi_codes <- function(codes) {
  # Normalize: strip ALL dots + toupper — delegates to .normalize_code() from
  # utils_cancer.R (sourced before this file via the R/utils/*.R glob).
  # Replaces str_remove() which stripped only the first dot and skipped toupper.
  codes_clean <- .normalize_code(codes)
  p4 <- substr(codes_clean, 1, 4)
  p3 <- substr(codes_clean, 1, 3)

  # 4-char lookup (most specific -- disambiguates D692/D693, H460/H461/H468/H469)
  m4 <- DOI_CODE_MAP[p4]

  # 3-char fallback (catches M05, M06, K50, K51, L40, M30, M31, etc.)
  m3 <- DOI_CODE_MAP[p3]

  # Apply 4-char-before-3-char priority; return unnamed vector
  unname(ifelse(!is.na(m4), m4, ifelse(!is.na(m3), m3, NA_character_)))
}

# ==============================================================================
# Phase 192.1: Autoimmune diagnosis helpers (AUTOIMMUNE-FLAG-02)
# ==============================================================================
# Three functions mirroring the HL flag/date pattern in R/52 and R/142 but
# sourcing data from DuckDB DIAGNOSIS rather than a pre-built cohort RDS.
#
# is_autoimmune_code()      — vectorised, DX_TYPE-gated prefix match
# summarise_autoimmune_dx() — pure (in-memory) per-patient aggregation
# build_autoimmune_dx_flags() — DuckDB wrapper (calls the two above)
#
# Dependencies: AUTOIMMUNE_DX_CODES, AUTOIMMUNE_DX_TYPE_ACCEPT, SENTINEL_CUTOFF
#   from R/00_config.R; normalize_icd() from utils_icd.R (auto-sourced before
#   this file via the R/utils/*.R glob).
# ==============================================================================

#' Detect autoimmune diagnosis codes (DX_TYPE-gated prefix match)
#'
#' Prefix-matches dx against AUTOIMMUNE_DX_CODES, gated on DX_TYPE so that
#' numeric ICD-9 keys only match ICD-9 records and alpha-leading ICD-10 keys
#' only match ICD-10 records. NA or unrecognised DX_TYPE values return FALSE.
#' Tolerates dotted codes (normalize_icd strips dots before matching).
#'
#' @param dx      Character vector of diagnosis codes (dotted or undotted)
#' @param dx_type Character vector of DX_TYPE values
#' @param codes   Named list with \code{$icd10} and \code{$icd9} named character
#'   vectors (default: \code{AUTOIMMUNE_DX_CODES} from config)
#' @param accept  Named list with \code{$icd10} and \code{$icd9} character
#'   vectors of accepted DX_TYPE values (default: \code{AUTOIMMUNE_DX_TYPE_ACCEPT})
#' @return Logical vector; TRUE only when the code's prefix is in the
#'   appropriate sub-list and dx_type is in the matching accepted set.
#'
#' @examples
#' is_autoimmune_code(c("M05.79", "714.0", "C81.90"), c("10", "09", "10"))
#' # Returns: c(TRUE, TRUE, FALSE)
is_autoimmune_code <- function(dx, dx_type,
                               codes  = AUTOIMMUNE_DX_CODES,
                               accept = AUTOIMMUNE_DX_TYPE_ACCEPT) {
  n <- length(dx)
  if (n == 0) return(logical(0))

  dx_clean <- normalize_icd(trimws(dx))          # strip dots, uppercase
  dt       <- trimws(as.character(dx_type))

  # Helper: TRUE where x starts with any key in `keys`
  match_any <- function(x, keys) {
    if (!length(keys)) return(rep(FALSE, length(x)))
    Reduce(`|`, lapply(keys, function(k) startsWith(x, k)))
  }

  out <- rep(FALSE, n)

  i10 <- !is.na(dx_clean) & !is.na(dt) & dt %in% accept$icd10
  i09 <- !is.na(dx_clean) & !is.na(dt) & dt %in% accept$icd9

  if (any(i10)) out[i10] <- match_any(dx_clean[i10], names(codes$icd10))
  if (any(i09)) out[i09] <- match_any(dx_clean[i09], names(codes$icd9))

  out
}


#' Aggregate per-patient autoimmune flags from in-memory diagnosis rows (pure)
#'
#' Returns one row per unique cohort ID with:
#'   \itemize{
#'     \item \code{has_autoimmune_dx} - logical, TRUE iff first_autoimmune_dx_date is non-NA
#'     \item \code{first_autoimmune_dx_date} - Date, earliest valid date across
#'       qualifying records (NA if none)
#'     \item \code{qc_qualifying_no_valid_date} - logical, TRUE only for patients
#'       who have a qualifying code but no valid date at all
#'   }
#'
#' Date priority per record: DX_DATE if non-NA and after sentinel, else ADMIT_DATE
#' if non-NA and after sentinel, else no valid date. Mirrors the sentinel usage in
#' R/47, R/48, R/49 (SENTINEL_CUTOFF = 1910-01-01).
#'
#' @param dx          data.frame with columns ID, DX, DX_TYPE, DX_DATE, ADMIT_DATE
#' @param cohort_ids  character vector of patient IDs (defines output row set)
#' @param sentinel    Date; records with all dates on or before this are invalid
#' @return tibble; nrow == n_distinct(cohort_ids); asserted on exit
summarise_autoimmune_dx <- function(dx, cohort_ids, sentinel) {
  # Filter to qualifying codes only
  q <- dx[is_autoimmune_code(dx$DX, dx$DX_TYPE), , drop = FALSE]

  if (nrow(q) > 0) {
    d1  <- as.Date(q$DX_DATE)
    d2  <- as.Date(q$ADMIT_DATE)
    ok1 <- !is.na(d1) & d1 > sentinel
    ok2 <- !is.na(d2) & d2 > sentinel
    # Valid date: DX_DATE if usable, else ADMIT_DATE if usable, else NA
    q$valid_date <- as.Date(
      ifelse(ok1, as.character(d1),
             ifelse(ok2, as.character(d2), NA_character_))
    )

    per_id <- q |>
      dplyr::group_by(ID) |>
      dplyr::summarise(
        first_autoimmune_dx_date = if (all(is.na(valid_date))) as.Date(NA) else min(valid_date, na.rm = TRUE),
        any_qualifying            = TRUE,
        any_valid_date            = any(!is.na(valid_date)),
        .groups = "drop"
      )
  } else {
    per_id <- tibble::tibble(
      ID                       = character(0),
      first_autoimmune_dx_date = as.Date(character(0)),
      any_qualifying           = logical(0),
      any_valid_date           = logical(0)
    )
  }

  out <- tibble::tibble(ID = unique(cohort_ids)) |>
    dplyr::left_join(per_id, by = "ID") |>
    dplyr::mutate(
      has_autoimmune_dx = !is.na(first_autoimmune_dx_date),
      qc_qualifying_no_valid_date =
        dplyr::coalesce(any_qualifying, FALSE) &
        !dplyr::coalesce(any_valid_date, FALSE)
    )

  # Invariant assertions (fail-fast)
  stopifnot(
    "output has one row per distinct cohort ID" =
      nrow(out) == dplyr::n_distinct(cohort_ids),
    "no TRUE flag with NA date" =
      !any(out$has_autoimmune_dx & is.na(out$first_autoimmune_dx_date)),
    "no FALSE flag with non-NA date" =
      !any(!out$has_autoimmune_dx & !is.na(out$first_autoimmune_dx_date))
  )

  out
}


#' Build patient-level autoimmune flags by querying DuckDB DIAGNOSIS
#'
#' Joins DIAGNOSIS to the cohort via a registered table (no IN-list), collects
#' into memory, then delegates to \code{summarise_autoimmune_dx()} for all
#' aggregation logic.
#'
#' Connection protocol: opens a connection only if one is not already open;
#' always unregisters the temporary table; closes only if it opened.
#' Uses \code{open_pcornet_con()} / \code{close_pcornet_con()} from
#' utils_duckdb.R (single shared connection pattern).
#'
#' @param cohort_ids character vector of patient IDs
#' @param sentinel   Date passed to \code{summarise_autoimmune_dx()}
#' @return tibble from \code{summarise_autoimmune_dx()}
build_autoimmune_dx_flags <- function(cohort_ids, sentinel = SENTINEL_CUTOFF) {
  opened_here <- FALSE
  if (!exists("pcornet_con", envir = .GlobalEnv) || !DBI::dbIsValid(pcornet_con)) {
    open_pcornet_con()
    opened_here <- TRUE
  }

  duckdb::duckdb_register(
    pcornet_con, "aim_cohort",
    tibble::tibble(ID = unique(as.character(cohort_ids)))
  )

  on.exit({
    try(duckdb::duckdb_unregister(pcornet_con, "aim_cohort"), silent = TRUE)
    if (opened_here) try(close_pcornet_con(), silent = TRUE)
  }, add = TRUE)

  dx <- DBI::dbGetQuery(pcornet_con,
    "SELECT d.ID, d.DX, d.DX_TYPE, d.DX_DATE, d.ADMIT_DATE
     FROM DIAGNOSIS d JOIN aim_cohort c ON c.ID = d.ID"
  )

  summarise_autoimmune_dx(dx, cohort_ids, sentinel)
}

# ==============================================================================
# End of utils_doi.R
# ==============================================================================
