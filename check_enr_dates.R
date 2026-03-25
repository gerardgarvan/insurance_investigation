# ==============================================================================
# check_enr_dates.R -- Print all out-of-range and unparseable dates across
#                      every PCORnet table, with original text values
# ==============================================================================
# For each table:
#   1. Loads raw CSV (dates as character) to preserve original text
#   2. Uses the parsed version from 01_load_pcornet.R to get _VALID flags
#   3. Reports out-of-range dates and parse failures side-by-side
# ==============================================================================

source("R/01_load_pcornet.R")

library(readr)
library(dplyr)
library(stringr)
library(glue)

date_col_regex <- "(?i)(DATE|^DT_|^BDATE$|^DOD$|^DT_FU$|DXDATE|_DT$|RECUR_DT|COMBINED_LAST_CONTACT|ADDRESS_PERIOD_START|ADDRESS_PERIOD_END)"
date_max <- Sys.Date() + 5 * 365

message("\n", strrep("=", 70))
message("DATE AUDIT ACROSS ALL PCORNET TABLES")
message("Valid range: 1900-01-01 to ", date_max)
message(strrep("=", 70))

total_out_of_range <- 0
total_parse_fail   <- 0

for (tbl_name in names(pcornet)) {
  parsed_df <- pcornet[[tbl_name]]
  if (is.null(parsed_df)) next

  # Find date columns in the parsed table
  date_cols <- names(parsed_df)[str_detect(names(parsed_df), date_col_regex)]
  # Exclude the _VALID flag columns

  date_cols <- date_cols[!str_detect(date_cols, "_VALID$")]

  if (length(date_cols) == 0) next

  # Load raw version of the same table (all character)
  raw_df <- read_csv(
    PCORNET_PATHS[[tbl_name]],
    col_types = cols(.default = col_character()),
    show_col_types = FALSE
  )

  # Add row index for joining
  raw_df    <- raw_df %>% mutate(.row = row_number())
  parsed_df <- parsed_df %>% mutate(.row = row_number())

  # ID column for display (ID in most tables, ENCOUNTERID in ENCOUNTER, etc.)
  id_col <- if ("ID" %in% names(raw_df)) "ID" else names(raw_df)[1]

  for (dcol in date_cols) {
    valid_col <- paste0(dcol, "_VALID")

    # --- Out-of-range dates ---
    if (valid_col %in% names(parsed_df)) {
      bad_idx <- which(parsed_df[[valid_col]] == FALSE)
      if (length(bad_idx) > 0) {
        total_out_of_range <- total_out_of_range + length(bad_idx)
        message(glue("\n--- {tbl_name}.{dcol} out of range: {length(bad_idx)} rows ---"))
        out <- tibble(
          ID         = raw_df[[id_col]][bad_idx],
          SOURCE     = if ("SOURCE" %in% names(raw_df)) raw_df$SOURCE[bad_idx] else NA_character_,
          raw_text   = raw_df[[dcol]][bad_idx],
          parsed     = parsed_df[[dcol]][bad_idx]
        )
        print(out, n = Inf)
      }
    }

    # --- Parse failures (non-empty text -> NA after parsing) ---
    raw_vals    <- raw_df[[dcol]]
    parsed_vals <- parsed_df[[dcol]]
    fail_idx <- which(!is.na(raw_vals) & raw_vals != "" & is.na(parsed_vals))
    if (length(fail_idx) > 0) {
      total_parse_fail <- total_parse_fail + length(fail_idx)
      message(glue("\n--- {tbl_name}.{dcol} parse failures: {length(fail_idx)} rows ---"))
      out <- tibble(
        ID       = raw_df[[id_col]][fail_idx],
        SOURCE   = if ("SOURCE" %in% names(raw_df)) raw_df$SOURCE[fail_idx] else NA_character_,
        raw_text = raw_vals[fail_idx]
      )
      print(out, n = Inf)
    }
  }
}

message("\n", strrep("=", 70))
message(glue("TOTAL out-of-range dates: {total_out_of_range}"))
message(glue("TOTAL parse failures:     {total_parse_fail}"))
message(strrep("=", 70))
