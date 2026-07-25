# ==============================================================================
# utils/utils_format.R -- Shared multi-value field formatting helpers
# ==============================================================================
#
# Purpose:
#   Canonical definitions of clean_multi_value() and union_field(). These
#   helpers normalise semicolon- or comma-separated multi-value strings that
#   appear in Gantt and lifespan-collapse outputs: they deduplicate, drop blank
#   and literal "NA" tokens, sort alphabetically, and re-join with a chosen
#   separator. Previously defined inline (verbatim) in R/52, R/101, and R/104;
#   extracted here per CONFIRM-01 so future changes require only one edit.
#
# Inputs:
#   - None (utility function library, not a standalone script)
#
# Outputs:
#   - None (defines functions loaded into calling scripts' environment)
#
# Dependencies:
#   - stringr: str_split(), str_trim()
#
# Requirements: CONFIRM-01
#
# ==============================================================================

#' Clean a multi-value delimited string
#'
#' Splits \code{field_str} on \code{sep_in}, trims whitespace, drops blank and
#' literal "NA" tokens (DOC-03: upstream fields such as drug_group may carry
#' the string "NA" from missing upstream values), deduplicates, sorts, and
#' rejoins with \code{sep_out}. Returns \code{""} for NA, empty, or all-blank
#' input.
#'
#' @param field_str Character. A single delimited string (e.g. "a,b,a,NA,,b").
#' @param sep_in    Character. Input separator pattern passed to str_split(). Default ",".
#' @param sep_out   Character. Output separator used in paste(). Default ";".
#' @return Character. Cleaned, sorted, deduplicated string, or "" if no valid tokens remain.
clean_multi_value <- function(field_str, sep_in = ",", sep_out = ";") {
  if (is.na(field_str) || field_str == "" || field_str == "NA") {
    return("")
  }

  values <- str_split(field_str, sep_in)[[1]]
  values <- str_trim(values)
  # DOC-03: drug_group carries literal "NA" string tokens from upstream (e.g. "Chemotherapy,NA");
  # filter them out alongside blanks and R-NA so they never reach the output CSVs.
  values <- values[values != "" & values != "NA" & !is.na(values)]
  values <- sort(unique(values))

  if (length(values) == 0) {
    return("")
  }
  paste(values, collapse = sep_out)
}

#' Union multi-value fields across a group of rows
#'
#' Intended for use inside dplyr summarise() or sapply() over a group of rows
#' where each element of \code{x} is already a semicolon-separated multi-value
#' string (as produced by Gantt episode exports). Pastes all elements together
#' with ";" and calls clean_multi_value() with sep_in=";" to union, dedup, and
#' sort the combined set.
#'
#' @param x Character vector. Each element may itself be a ";"-joined string.
#' @return Character. Sorted, deduplicated union of all tokens across \code{x}.
union_field <- function(x) {
  clean_multi_value(paste(x, collapse = ";"), sep_in = ";", sep_out = ";")
}
