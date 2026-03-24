# ==============================================================================
# 01_load_pcornet.R -- Load PCORnet CDM CSV tables with explicit column types
# ==============================================================================
#
# Loads 9 primary tables into a named list (pcornet$ENROLLMENT, pcornet$DIAGNOSIS, etc.)
# All date columns are parsed via parse_pcornet_date() (multi-format fallback)
# All ID columns are loaded as character (prevents leading-zero truncation)
# Missing files produce a warning and NULL entry (per D-10)
#
# Usage:
#   source("R/00_config.R")  # Auto-loads utils
#   source("R/01_load_pcornet.R")
#   pcornet$ENROLLMENT  # Access loaded table
#
# Requirement: LOAD-01 (load 22 CDM tables with explicit col_types)
# Phase 1 loads 9 primary tables; remaining 13 added as needed
# ==============================================================================

source("R/00_config.R")

library(readr)
library(stringr)
library(purrr)
library(glue)

# ==============================================================================
# COLUMN TYPE SPECIFICATIONS
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. ENROLLMENT (6 columns)
# ------------------------------------------------------------------------------
ENROLLMENT_SPEC <- cols(
  ID = col_character(),
  ENR_START_DATE = col_character(),
  ENR_END_DATE = col_character(),
  CHART = col_character(),
  ENR_BASIS = col_character(),
  SOURCE = col_character()
)

# ------------------------------------------------------------------------------
# 2. DIAGNOSIS (14 columns)
# ------------------------------------------------------------------------------
DIAGNOSIS_SPEC <- cols(
  DIAGNOSISID = col_character(),
  ID = col_character(),
  ENCOUNTERID = col_character(),
  ENC_TYPE = col_character(),
  ADMIT_DATE = col_character(),
  PROVIDERID = col_character(),
  DX = col_character(),
  DX_TYPE = col_character(),
  DX_DATE = col_character(),
  DX_SOURCE = col_character(),
  DX_ORIGIN = col_character(),
  PDX = col_character(),
  DX_POA = col_character(),
  SOURCE = col_character()
)

# ------------------------------------------------------------------------------
# 3. PROCEDURES (12 columns)
# ------------------------------------------------------------------------------
PROCEDURES_SPEC <- cols(
  PROCEDURESID = col_character(),
  ID = col_character(),
  ENCOUNTERID = col_character(),
  ENC_TYPE = col_character(),
  ADMIT_DATE = col_character(),
  PROVIDERID = col_character(),
  PX_DATE = col_character(),
  PX = col_character(),
  PX_TYPE = col_character(),
  PX_SOURCE = col_character(),
  PPX = col_character(),
  SOURCE = col_character()
)

# ------------------------------------------------------------------------------
# 4. PRESCRIBING (24 columns)
# ------------------------------------------------------------------------------
PRESCRIBING_SPEC <- cols(
  PRESCRIBINGID = col_character(),
  ID = col_character(),
  ENCOUNTERID = col_character(),
  RX_PROVIDERID = col_character(),
  RX_ORDER_DATE = col_character(),
  RX_ORDER_TIME = col_character(),
  RX_START_DATE = col_character(),
  RX_END_DATE = col_character(),
  RX_DOSE_ORDERED = col_double(),
  RX_DOSE_ORDERED_UNIT = col_character(),
  RX_QUANTITY = col_double(),
  RX_DOSE_FORM = col_character(),
  RX_REFILLS = col_integer(),
  RX_DAYS_SUPPLY = col_integer(),
  RX_FREQUENCY = col_character(),
  RX_PRN_FLAG = col_character(),
  RX_ROUTE = col_character(),
  RX_BASIS = col_character(),
  RXNORM_CUI = col_character(),
  RX_SOURCE = col_character(),
  RX_DISPENSE_AS_WRITTEN = col_character(),
  RAW_RX_MED_NAME = col_character(),
  RAW_RXNORM_CUI = col_character(),
  SOURCE = col_character()
)

# ------------------------------------------------------------------------------
# 5. ENCOUNTER (19 columns)
# ------------------------------------------------------------------------------
ENCOUNTER_SPEC <- cols(
  ENCOUNTERID = col_character(),
  ID = col_character(),
  ADMIT_DATE = col_character(),
  ADMIT_TIME = col_character(),
  DISCHARGE_DATE = col_character(),
  DISCHARGE_TIME = col_character(),
  PROVIDERID = col_character(),
  FACILITY_LOCATION = col_character(),
  ENC_TYPE = col_character(),
  FACILITYID = col_character(),
  DISCHARGE_DISPOSITION = col_character(),
  DISCHARGE_STATUS = col_character(),
  DRG = col_character(),
  DRG_TYPE = col_character(),
  ADMITTING_SOURCE = col_character(),
  PAYER_TYPE_PRIMARY = col_character(),
  PAYER_TYPE_SECONDARY = col_character(),
  FACILITY_TYPE = col_character(),
  SOURCE = col_character()
)

# ------------------------------------------------------------------------------
# 6. DEMOGRAPHIC (12 columns)
# ------------------------------------------------------------------------------
DEMOGRAPHIC_SPEC <- cols(
  ID = col_character(),
  BIRTH_DATE = col_character(),
  BIRTH_TIME = col_character(),
  SEX = col_character(),
  SEXUAL_ORIENTATION = col_character(),
  GENDER_IDENTITY = col_character(),
  HISPANIC = col_character(),
  RACE = col_character(),
  BIOBANK_FLAG = col_character(),
  PAT_PREF_LANGUAGE_SPOKEN = col_character(),
  ZIP_CODE = col_character(),
  SOURCE = col_character()
)

# ------------------------------------------------------------------------------
# 7. TUMOR_REGISTRY1 (314 columns - use .default strategy)
# ------------------------------------------------------------------------------
# Strategy: Most columns are character codes/text
# Only numeric: AGE_AT_DIAGNOSIS (integer), TUMOR_SIZE_* (double)
TUMOR_REGISTRY1_SPEC <- cols(
  .default = col_character(),
  AGE_AT_DIAGNOSIS = col_integer(),
  TUMOR_SIZE_SUMMARY = col_double(),
  TUMOR_SIZE_CLINICAL = col_double(),
  TUMOR_SIZE_PATHOLOGIC = col_double()
)

# ------------------------------------------------------------------------------
# 8. TUMOR_REGISTRY2 (140 columns - use .default strategy)
# ------------------------------------------------------------------------------
TUMOR_REGISTRY2_SPEC <- cols(
  .default = col_character(),
  DXAGE = col_integer()
)

# ------------------------------------------------------------------------------
# 9. TUMOR_REGISTRY3 (140 columns - use .default strategy)
# ------------------------------------------------------------------------------
TUMOR_REGISTRY3_SPEC <- cols(
  .default = col_character(),
  DXAGE = col_integer()
)

# ==============================================================================
# TABLE SPECS LOOKUP
# ==============================================================================

TABLE_SPECS <- list(
  ENROLLMENT = ENROLLMENT_SPEC,
  DIAGNOSIS = DIAGNOSIS_SPEC,
  PROCEDURES = PROCEDURES_SPEC,
  PRESCRIBING = PRESCRIBING_SPEC,
  ENCOUNTER = ENCOUNTER_SPEC,
  DEMOGRAPHIC = DEMOGRAPHIC_SPEC,
  TUMOR_REGISTRY1 = TUMOR_REGISTRY1_SPEC,
  TUMOR_REGISTRY2 = TUMOR_REGISTRY2_SPEC,
  TUMOR_REGISTRY3 = TUMOR_REGISTRY3_SPEC
)

# ==============================================================================
# LOAD FUNCTION
# ==============================================================================

#' Load a single PCORnet CDM table with explicit column types
#'
#' @param table_name Character. Name of the table (e.g., "ENROLLMENT")
#' @param file_path Character. Full path to CSV file
#' @param col_spec readr cols() specification
#'
#' @return Tibble with loaded data, or NULL if file not found
#'
#' @details
#' - Checks file existence before attempting load (warns and returns NULL if missing)
#' - Loads CSV with explicit col_types (prevents type inference errors)
#' - Auto-detects date columns by name pattern and parses via parse_pcornet_date()
#' - Prints load summary: table name, row count, column count
#' - Warns if any parse problems occurred
load_pcornet_table <- function(table_name, file_path, col_spec) {
  # Check file exists (per D-10: warn and skip)
  if (!file.exists(file_path)) {
    message(glue("WARNING: {table_name} not found at {file_path}. Skipping."))
    return(NULL)
  }

  # Load with explicit col_types (per D-08)
  df <- read_csv(file_path, col_types = col_spec, show_col_types = FALSE)

  # Parse all date columns with multi-format parser
  # Detect date columns by name pattern (DATE, TIME, BDATE, DOD, DT_*)
  date_cols <- names(df)[str_detect(names(df), "(?i)(DATE|^DT_|^BDATE$|^DOD$|^DT_FU$|DXDATE)")]
  for (col in date_cols) {
    if (is.character(df[[col]])) {
      df[[col]] <- parse_pcornet_date(df[[col]])
    }
  }

  # Print load summary (per D-12)
  n_parse_problems <- nrow(problems(df))
  message(glue("Loaded {table_name}: {format(nrow(df), big.mark=',')} rows, {ncol(df)} columns"))
  if (n_parse_problems > 0) {
    message(glue("  WARNING: {n_parse_problems} parse failures in {table_name}"))
  }

  return(df)
}

# ==============================================================================
# MAIN LOADING BLOCK
# ==============================================================================

message("=" %>% strrep(60))
message("Loading PCORnet CDM tables...")
message("=" %>% strrep(60))

pcornet <- imap(PCORNET_PATHS, function(path, table_name) {
  spec <- TABLE_SPECS[[table_name]]
  if (is.null(spec)) {
    message(glue("WARNING: No col_types spec defined for {table_name}. Using .default = col_character()."))
    spec <- cols(.default = col_character())
  }
  load_pcornet_table(table_name, path, spec)
})

# Summary
loaded_tables <- names(pcornet)[!sapply(pcornet, is.null)]
skipped_tables <- names(pcornet)[sapply(pcornet, is.null)]

message(glue("\n{'=' %>% strrep(60)}"))
message(glue("Loading complete: {length(loaded_tables)}/{length(PCORNET_PATHS)} tables loaded"))
if (length(skipped_tables) > 0) {
  message(glue("Skipped: {paste(skipped_tables, collapse = ', ')}"))
}
message(glue("{'=' %>% strrep(60)}"))

# ==============================================================================
# End of script
# ==============================================================================
