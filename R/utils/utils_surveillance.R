# ==============================================================================
# utils_surveillance.R -- Phase 158 surveillance modality frequency helpers
# ==============================================================================
# Pure functions (no DuckDB, no CONFIG) so every rule is unit-testable locally.
# The DuckDB wrapper get_hl_any_dx_ids() lives in utils_treatment.R (D-04).
#
# Contents:
#   Codeset:    load_surveillance_codeset(), normalize_surv_code(),
#               surv_components()
#   SQL:        surv_sql_in(), surv_code_where()
#   Denominator: hl_any_dx_from_tibble()
#   Matching:   match_coded_events(), build_component_events()
#   Outputs:    build_code_presence(), compute_followup(),
#               classify_event_window(), compute_modality_stats(),
#               build_patient_modality(), suppress_small(), suppress_table()
# ==============================================================================

SURV_REQUIRED_COLS <- c("codeset_row_id", "modality", "submodality",
                        "code_system", "code", "code_norm", "cdm_table",
                        "cdm_column", "type_filter", "match", "tier",
                        "plausibility")
SURV_MATCH_VALUES  <- c("exact", "prefix", "component_all_same_day")
SURV_TIERS         <- c("primary", "sensitivity")
SURV_TABLE_TYPES   <- list(PROCEDURES    = c("CH", "10", "09"),
                           DIAGNOSIS     = c("10", "09"),
                           LAB_RESULT_CM = "")

# ------------------------------------------------------------------------------
# Codeset
# ------------------------------------------------------------------------------

#' Normalize a code: trim, uppercase, strip dots and a trailing "*" (D-15)
normalize_surv_code <- function(x) {
  x <- toupper(trimws(as.character(x)))
  x <- gsub(".", "", x, fixed = TRUE)
  sub("\\*$", "", x)
}

#' Split a component_all_same_day code_norm ("a;b;c") into normalized parts
surv_components <- function(code_norm) {
  parts <- normalize_surv_code(strsplit(code_norm, ";", fixed = TRUE)[[1]])
  parts[nzchar(parts)]
}

#' Load and validate data/reference/surveillance_codeset.xlsx (SURV-01)
#'
#' Reads every column as text, turns NA (blank cells) into "", normalizes
#' code_norm, and stops on any structural violation.
load_surveillance_codeset <- function(
    path = file.path("data", "reference", "surveillance_codeset.xlsx")) {

  if (!file.exists(path))
    stop("surveillance codeset not found: ", path)

  cs <- readxl::read_excel(path, sheet = "Analysis_Codeset",
                           col_types = "text")

  missing_cols <- setdiff(SURV_REQUIRED_COLS, names(cs))
  if (length(missing_cols) > 0)
    stop("surveillance codeset missing required columns: ",
         paste(missing_cols, collapse = ", "))

  cs <- cs |>
    dplyr::mutate(dplyr::across(dplyr::everything(),
                                ~ trimws(dplyr::coalesce(.x, ""))))

  # Drop fully blank rows (e.g. trailing formatting rows)
  cs <- cs[rowSums(cs != "") > 0, , drop = FALSE]

  if (any(cs$codeset_row_id == ""))
    stop("codeset_row_id must be non-blank on every row")
  if (anyDuplicated(cs$codeset_row_id))
    stop("Duplicate codeset_row_id values: not allowed")
  if (any(cs$modality == "" | cs$code_norm == ""))
    stop("modality and code_norm must be non-blank on every row")

  bad_tier <- setdiff(unique(cs$tier), SURV_TIERS)
  if (length(bad_tier) > 0)
    stop("Invalid tier values: ", paste(bad_tier, collapse = ", "))

  bad_match <- setdiff(unique(cs$match), SURV_MATCH_VALUES)
  if (length(bad_match) > 0)
    stop("Invalid match values: ", paste(bad_match, collapse = ", "))

  bad_table <- setdiff(unique(cs$cdm_table), names(SURV_TABLE_TYPES))
  if (length(bad_table) > 0)
    stop("Invalid cdm_table values: ", paste(bad_table, collapse = ", "))

  # type_filter must be the bare value for its table (e.g. "CH", not
  # "PX_TYPE='CH'"); LAB_RESULT_CM rows must be blank
  bad_type <- purrr::pmap_lgl(list(cs$cdm_table, cs$type_filter),
                              function(t, f) !(f %in% SURV_TABLE_TYPES[[t]]))
  if (any(bad_type))
    stop("Invalid type_filter for its cdm_table on rows: ",
         paste(cs$codeset_row_id[bad_type], collapse = ", "))

  # Normalize code_norm (component rows part by part)
  cs$code_norm <- ifelse(
    cs$match == "component_all_same_day",
    vapply(cs$code_norm, function(z) paste(surv_components(z), collapse = ";"),
           character(1)),
    normalize_surv_code(cs$code_norm)
  )

  comp <- cs$match == "component_all_same_day"
  if (any(comp)) {
    n_parts <- vapply(cs$code_norm[comp],
                      function(z) length(surv_components(z)), integer(1))
    if (any(n_parts < 2) || any(cs$cdm_table[comp] != "LAB_RESULT_CM"))
      stop("component_all_same_day rows need >= 2 ';'-separated component ",
           "codes and cdm_table = LAB_RESULT_CM")
  }

  dup <- duplicated(cs[, c("modality", "code_norm")])
  if (any(dup))
    stop("Duplicate modality x code_norm (not unique): ",
         paste(cs$modality[dup], cs$code_norm[dup], sep = "/", collapse = "; "))

  tibble::as_tibble(cs)
}

# ------------------------------------------------------------------------------
# SQL builders (string-only; used with dplyr::filter(dplyr::sql(...)))
# ------------------------------------------------------------------------------

surv_sql_in <- function(x) {
  x <- unique(x)
  paste0("(", paste0("'", gsub("'", "''", x, fixed = TRUE), "'",
                     collapse = ", "), ")")
}

#' WHERE clause matching a CDM code column against exact codes and prefixes,
#' with the column normalized in SQL the same way as normalize_surv_code()
surv_code_where <- function(col, exact = character(), prefix = character()) {
  norm  <- sprintf("REPLACE(UPPER(TRIM(%s)), '.', '')", col)
  parts <- character()
  if (length(exact))  parts <- c(parts, sprintf("%s IN %s", norm, surv_sql_in(exact)))
  if (length(prefix)) parts <- c(parts, sprintf("%s LIKE '%s%%'", norm,
                                                gsub("'", "''", unique(prefix))))
  if (!length(parts)) return("FALSE")
  paste0("(", paste(parts, collapse = " OR "), ")")
}

# ------------------------------------------------------------------------------
# Denominator (SURV-02)
# ------------------------------------------------------------------------------

#' HL any-dx logic on an in-memory DIAGNOSIS extract.
#' dx_tbl: ID, DX, DX_TYPE, DX_DATE (Date), ADMIT_DATE (Date).
#' Returns ID, hl_anchor_date (min of DX_DATE, falling back to ADMIT_DATE);
#' patients with no usable date keep hl_anchor_date = NA.
hl_any_dx_from_tibble <- function(dx_tbl) {
  dx_tbl |>
    dplyr::mutate(dx_norm = normalize_surv_code(DX),
                  dx_type = trimws(as.character(DX_TYPE))) |>
    dplyr::filter((dx_type == "10" & startsWith(dx_norm, "C81")) |
                  (dx_type == "09" & startsWith(dx_norm, "201"))) |>
    dplyr::mutate(use_date = dplyr::coalesce(DX_DATE, ADMIT_DATE)) |>
    dplyr::group_by(ID) |>
    dplyr::summarise(
      hl_anchor_date = if (all(is.na(use_date))) as.Date(NA)
                       else min(use_date, na.rm = TRUE),
      .groups = "drop")
}
