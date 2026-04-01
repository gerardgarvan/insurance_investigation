# ==============================================================================
# 01_load_pcornet.R -- Load PCORnet CDM CSV tables with explicit column types
# ==============================================================================
#
# Loads 13 primary tables into a named list (pcornet$ENROLLMENT, pcornet$DIAGNOSIS, etc.)
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
# Phase 1 loads 9 primary tables; Phase 9 adds DISPENSING and MED_ADMIN;
# Phase 10 adds LAB_RESULT_CM and PROVIDER
# ==============================================================================

source("R/00_config.R")

library(vroom)
library(dplyr)
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
# Missing values (missing_values_audit.csv):
#   RX_DAYS_SUPPLY: 92.89% missing (expected -- optional field, rarely populated)
#   RX_END_DATE: 50 future dates (max 2037-08-08) flagged by date _VALID
# Encoding (encoding_issues.csv):
#   No encoding issues in PRESCRIBING.
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
# Missing values (missing_values_audit.csv):
#   DISCHARGE_DATE: 70.87% missing (expected -- most encounters are outpatient)
#   PAYER_TYPE_SECONDARY: 75.04% missing (expected -- not all encounters have secondary payer)
#   Both are optional PCORnet CDM fields; no parsing fix needed.
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
#
# DIAGNOSTIC VALIDATION (Phase 6, Plan 02 -- tr_type_audit.csv):
#   Many columns flagged as "Consider col_double()" (HISTOLOGICAL_TYPE, GRADE,
#   SITE_CODE, LATERALITY, BEHAVIOR_CODE, etc.) but these are coded categorical
#   values (ICD-O-3 morphology codes, NAACCR staging codes). They MUST stay as
#   character to preserve leading zeros and categorical semantics. Changing to
#   numeric would lose "0200" -> 200, misrepresenting morphology/site codes.
#
# Known data quality (numeric_range_issues.csv):
#   AGE_AT_DIAGNOSIS: 3 values of 200 (sentinel for "unknown age")
#   TUMOR_SIZE_*: within expected ranges
#
# Missing values (missing_values_audit.csv):
#   All 17 date columns are 100% NA in this dataset (empty columns).
#   Many coded columns have high missingness -- expected for optional NAACCR fields.
#
# Encoding (encoding_issues.csv):
#   HISTOLOGICAL_TYPE_DESCRIPTION: 8 non-ASCII characters, no BOM.
#   Accepted as cosmetic -- does not affect analysis (coded values unaffected).
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
# DIAGNOSTIC VALIDATION (Phase 6, Plan 02 -- tr_type_audit.csv):
#   Same rationale as TR1: coded columns (MORPH, SITE, GRADE, etc.) stay character.
#
# Known data quality (numeric_range_issues.csv):
#   DXAGE: 2 negative values (-84, -76) and 2 sentinels (200) -- flagged by _VALID
#
# Missing values: 404 rows total, many columns 100% missing (small dataset).
TUMOR_REGISTRY2_SPEC <- cols(
  .default = col_character(),
  DXAGE = col_integer()
)

# ------------------------------------------------------------------------------
# 9. TUMOR_REGISTRY3 (140 columns - use .default strategy)
# ------------------------------------------------------------------------------
# DIAGNOSTIC VALIDATION (Phase 6, Plan 02 -- tr_type_audit.csv):
#   Same rationale as TR1/TR2: coded columns stay character.
#
# Known data quality (numeric_range_issues.csv):
#   DXAGE: 13 sentinel values of 999 (unknown age) -- flagged by _VALID
#
# Missing values: 15 rows total, many columns 100% missing (very small dataset).
TUMOR_REGISTRY3_SPEC <- cols(
  .default = col_character(),
  DXAGE = col_integer()
)

# ------------------------------------------------------------------------------
# 10. DISPENSING (15 columns)
# ------------------------------------------------------------------------------
# Phase 9: Added for expanded treatment detection (D-08, D-15)
# RXNORM_CUI is the key matching column for chemo drugs (D-12: no NDC matching)
# DISPENSE_DATE used for treatment date anchoring
# Column list from PCORnet CDM v7.0 specification (Jan 2025)
DISPENSING_SPEC <- cols(
  DISPENSINGID = col_character(),
  PRESCRIBINGID = col_character(),
  ID = col_character(),
  DISPENSE_DATE = col_character(),       # Parsed by parse_pcornet_date()
  NDC = col_character(),
  DISPENSE_SUP = col_integer(),          # Days supply
  DISPENSE_AMT = col_double(),           # Quantity dispensed
  DISPENSE_DOSE_DISP = col_double(),
  DISPENSE_DOSE_DISP_UNIT = col_character(),
  DISPENSE_ROUTE = col_character(),
  RAW_NDC = col_character(),
  RXNORM_CUI = col_character(),          # KEY: chemo matching per D-12
  DISPENSE_SOURCE = col_character(),
  RAW_DISPENSE_MED_NAME = col_character(),
  SOURCE = col_character()
)

# ------------------------------------------------------------------------------
# 11. MED_ADMIN (12 columns)
# ------------------------------------------------------------------------------
# Phase 9: Added for expanded treatment detection (D-08, D-15)
# RXNORM_CUI is the key matching column for chemo drugs (D-12: no NDC matching)
# MEDADMIN_START_DATE used for treatment date anchoring
# Column list from PCORnet CDM v7.0 specification (Jan 2025)
MED_ADMIN_SPEC <- cols(
  MEDADMINID = col_character(),
  ID = col_character(),
  ENCOUNTERID = col_character(),
  PRESCRIBINGID = col_character(),
  MEDADMIN_CODE = col_character(),
  MEDADMIN_TYPE = col_character(),
  MEDADMIN_START_DATE = col_character(),  # Parsed by parse_pcornet_date()
  MEDADMIN_STOP_DATE = col_character(),   # Parsed by parse_pcornet_date()
  MEDADMIN_ROUTE = col_character(),
  RXNORM_CUI = col_character(),          # KEY: chemo matching per D-12
  RAW_MEDADMIN_MED_NAME = col_character(),
  SOURCE = col_character()
)

# ------------------------------------------------------------------------------
# 12. LAB_RESULT_CM (23 columns)
# ------------------------------------------------------------------------------
# Phase 10: Added for surveillance lab value detection
# LAB_LOINC is the primary matching column against LAB_CODES list
# RESULT_NUM is the only numeric column; dates are character for parse_pcornet_date()
# LAB_PX / LAB_PX_TYPE allow CPT-based matching when LOINC is missing
# Schema from PCORnet CDM v7.0 specification (Jan 2025)
LAB_RESULT_CM_SPEC <- cols(
  .default = col_character(),
  LAB_RESULTID = col_character(),
  ID = col_character(),
  ENCOUNTERID = col_character(),
  LAB_ORDER_DATE = col_character(),     # Parsed by parse_pcornet_date()
  RESULT_DATE = col_character(),        # Parsed by parse_pcornet_date()
  SPECIMEN_DATE = col_character(),      # Parsed by parse_pcornet_date()
  LAB_LOINC = col_character(),          # KEY: LOINC-based lab matching
  LAB_LOINC_SOURCE = col_character(),
  LAB_PX = col_character(),             # CPT fallback matching
  LAB_PX_TYPE = col_character(),
  RESULT_NUM = col_double(),            # Numeric result value
  RESULT_UNIT = col_character(),
  RESULT_QUAL = col_character(),
  RESULT_MODIFIER = col_character(),
  SPECIMEN_SOURCE = col_character(),
  ABN_IND = col_character(),
  NORM_RANGE_HIGH = col_character(),
  NORM_RANGE_LOW = col_character(),
  RAW_LAB_CODE = col_character(),
  RAW_LAB_NAME = col_character(),
  RAW_RESULT = col_character(),
  SOURCE = col_character()
)

# ------------------------------------------------------------------------------
# 13. PROVIDER (7 columns)
# ------------------------------------------------------------------------------
# Phase 10: Added for oncology provider specialty identification
# PROVIDER_SPECIALTY_PRIMARY is the primary matching column against PROVIDER_SPECIALTIES
# PROVIDERID links to PROVIDERID in ENCOUNTER, DIAGNOSIS, PROCEDURES tables
# Schema from PCORnet CDM v7.0 specification (Jan 2025)
PROVIDER_SPEC <- cols(
  PROVIDERID = col_character(),
  PROVIDER_SEX = col_character(),
  PROVIDER_SPECIALTY_PRIMARY = col_character(),  # KEY: NUCC taxonomy code matching
  SOURCE = col_character()
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
  TUMOR_REGISTRY3 = TUMOR_REGISTRY3_SPEC,
  DISPENSING = DISPENSING_SPEC,          # Phase 9
  MED_ADMIN = MED_ADMIN_SPEC,            # Phase 9
  LAB_RESULT_CM = LAB_RESULT_CM_SPEC,   # Phase 10: surveillance lab values
  PROVIDER = PROVIDER_SPEC              # Phase 10: oncology provider specialty
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
  df <- vroom(file_path, col_types = col_spec, show_col_types = FALSE,
              .name_repair = "check_unique",
              num_threads = CONFIG$performance$num_threads)
  n_parse_problems <- nrow(problems(df))

  # Parse all date columns with multi-format parser
  # Detect date columns by name pattern for automatic date parsing
  # Catches: *DATE*, ^DT_*, BDATE, DOD, DT_FU, DXDATE, *_DT (end), RECUR_DT,
  #          COMBINED_LAST_CONTACT, ADDRESS_PERIOD_START/END
  # Verified against csv_columns.txt (2026-03-25)
  #
  # DIAGNOSTIC VALIDATION (Phase 6, Plan 02 -- date_column_regex_audit.csv):
  #   ALL date columns have regex_match = TRUE. No missed columns detected.
  #   No regex expansion needed for this cohort extract.
  # Columns that match the date regex but are NOT dates (Y/N flags, etc.)
  NOT_DATE_COLS <- c("DXDATE_IMPUTED")
  date_cols <- names(df)[str_detect(names(df), "(?i)(DATE|^DT_|^BDATE$|^DOD$|^DT_FU$|DXDATE|_DT$|RECUR_DT|COMBINED_LAST_CONTACT|ADDRESS_PERIOD_START|ADDRESS_PERIOD_END)")]
  date_cols <- date_cols[!date_cols %in% NOT_DATE_COLS]
  for (col in date_cols) {
    if (is.character(df[[col]])) {
      df[[col]] <- parse_pcornet_date(df[[col]])
    }
  }

  # ============================================================================
  # Numeric range validation (Phase 6, Plan 02 -- D-08)
  # ============================================================================
  # Preserve raw values; add _VALID flag columns for downstream filtering.
  # Ranges based on clinical plausibility; sentinels (200, 999, negative) flagged.
  # Findings from numeric_range_issues.csv drove these specific validations.

  # --- Age validation: range 0-120 (flags sentinels like 200, 999, negatives) ---
  if (table_name == "TUMOR_REGISTRY1" && "AGE_AT_DIAGNOSIS" %in% names(df)) {
    df <- df %>%
      mutate(
        AGE_AT_DIAGNOSIS_VALID = case_when(
          is.na(AGE_AT_DIAGNOSIS) ~ NA,
          AGE_AT_DIAGNOSIS < 0 ~ FALSE,
          AGE_AT_DIAGNOSIS > 120 ~ FALSE,
          TRUE ~ TRUE
        )
      )
    n_invalid <- sum(!df$AGE_AT_DIAGNOSIS_VALID, na.rm = TRUE)
    if (n_invalid > 0) {
      message(glue("  Validation: {n_invalid} invalid AGE_AT_DIAGNOSIS values flagged (sentinel/out-of-range)"))
    }
  }

  if (table_name %in% c("TUMOR_REGISTRY2", "TUMOR_REGISTRY3") && "DXAGE" %in% names(df)) {
    df <- df %>%
      mutate(
        DXAGE_VALID = case_when(
          is.na(DXAGE) ~ NA,
          DXAGE < 0 ~ FALSE,
          DXAGE > 120 ~ FALSE,
          TRUE ~ TRUE
        )
      )
    n_invalid <- sum(!df$DXAGE_VALID, na.rm = TRUE)
    if (n_invalid > 0) {
      message(glue("  Validation: {n_invalid} invalid DXAGE values flagged in {table_name} (sentinel/out-of-range)"))
    }
  }

  # --- Tumor size validation: range 0-989 (990+ are NAACCR sentinel codes) ---
  tumor_size_cols <- c("TUMOR_SIZE_SUMMARY", "TUMOR_SIZE_CLINICAL", "TUMOR_SIZE_PATHOLOGIC")
  if (table_name == "TUMOR_REGISTRY1") {
    for (ts_col in tumor_size_cols) {
      if (ts_col %in% names(df)) {
        valid_col_name <- paste0(ts_col, "_VALID")
        df[[valid_col_name]] <- case_when(
          is.na(df[[ts_col]]) ~ NA,
          df[[ts_col]] < 0 ~ FALSE,
          df[[ts_col]] >= 990 ~ FALSE,   # 990-999 are NAACCR sentinel codes
          TRUE ~ TRUE
        )
        n_invalid <- sum(!df[[valid_col_name]], na.rm = TRUE)
        if (n_invalid > 0) {
          message(glue("  Validation: {n_invalid} invalid {ts_col} values flagged"))
        }
      }
    }
  }

  # --- Date range validation: data collection period 2012-01-01 to 2025-03-31 ---
  # Flags dates outside the study period and SAS epoch sentinels (1899-12-30)
  date_range_min <- as.Date("1900-01-01")
  date_range_max <- as.Date("2025-03-31")  # End of data collection period
  for (dcol in date_cols) {
    if (dcol %in% names(df) && inherits(df[[dcol]], "Date")) {
      valid_col_name <- paste0(dcol, "_VALID")
      df[[valid_col_name]] <- case_when(
        is.na(df[[dcol]]) ~ NA,
        df[[dcol]] < date_range_min ~ FALSE,   # Pre-1900 (SAS epoch sentinel)
        df[[dcol]] > date_range_max ~ FALSE,    # Extreme future dates
        TRUE ~ TRUE
      )
      n_invalid <- sum(!df[[valid_col_name]], na.rm = TRUE)
      if (n_invalid > 0) {
        message(glue("  Validation: {n_invalid} invalid {dcol} values flagged (out of {date_range_min} to {date_range_max} range)"))
      }
    }
  }

  # Print load summary (per D-12)
  message(glue("Loaded {table_name}: {format(nrow(df), big.mark=',')} rows, {ncol(df)} columns"))
  if (n_parse_problems > 0) {
    message(glue("  WARNING: {n_parse_problems} parse failures in {table_name}"))
  }

  return(df)
}

# ==============================================================================
# MAIN LOADING BLOCK
# ==============================================================================

if (exists("pcornet", envir = .GlobalEnv) && is.list(pcornet) && length(pcornet) > 0) {
  message("PCORnet tables already loaded — skipping reload. (rm(pcornet) to force reload)")
} else {
  message(strrep("=", 60))
  message("Loading PCORnet CDM tables...")
  message(strrep("=", 60))

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

  message("\n", strrep("=", 60))
  message(glue("Loading complete: {length(loaded_tables)}/{length(PCORNET_PATHS)} tables loaded"))
  if (length(skipped_tables) > 0) {
    message(glue("Skipped: {paste(skipped_tables, collapse = ', ')}"))
  }
  message(strrep("=", 60))

  # --------------------------------------------------------------------------
  # COMBINED TUMOR REGISTRY (Phase 14: consolidate repeated bind_rows)
  # --------------------------------------------------------------------------
  # Previously, 03_cohort_predicates.R, 10_treatment_payer.R, and other scripts
  # each separately bind_rows(TR1, TR2, TR3). Binding once here avoids
  # redundant operations and simplifies downstream code.
  tr_tables <- compact(list(
    pcornet$TUMOR_REGISTRY1,
    pcornet$TUMOR_REGISTRY2,
    pcornet$TUMOR_REGISTRY3
  ))
  if (length(tr_tables) > 0) {
    pcornet$TUMOR_REGISTRY_ALL <- bind_rows(tr_tables)
    message(glue(
      "Combined TUMOR_REGISTRY_ALL: {format(nrow(pcornet$TUMOR_REGISTRY_ALL), big.mark=',')} rows ",
      "from {length(tr_tables)} TR tables"
    ))
  } else {
    pcornet$TUMOR_REGISTRY_ALL <- NULL
    message("No TUMOR_REGISTRY tables loaded -- TUMOR_REGISTRY_ALL is NULL")
  }

  # --------------------------------------------------------------------------
  # Phase 10 diagnostic logging: PROVIDER specialty values and LAB_LOINC null rate
  # --------------------------------------------------------------------------

  # PROVIDER: log distinct PROVIDER_SPECIALTY_PRIMARY values (sample of 20)
  # Used to validate NUCC taxonomy codes align with actual data before downstream matching
  if (!is.null(pcornet$PROVIDER)) {
    message("\n[PROVIDER] Distinct PROVIDER_SPECIALTY_PRIMARY values (sample up to 20):")
    pcornet$PROVIDER %>%
      dplyr::distinct(PROVIDER_SPECIALTY_PRIMARY) %>%
      dplyr::slice_head(n = 20) %>%
      print()
  }

  # LAB_RESULT_CM: log row count and LAB_LOINC null rate
  # High null rate indicates CPT fallback (LAB_PX) will be needed for lab matching
  if (!is.null(pcornet$LAB_RESULT_CM)) {
    n_total <- nrow(pcornet$LAB_RESULT_CM)
    n_na_loinc <- sum(is.na(pcornet$LAB_RESULT_CM$LAB_LOINC))
    message(glue(
      "\n[LAB_RESULT_CM] {format(n_total, big.mark=',')} rows loaded, ",
      "{n_na_loinc} ({round(100 * n_na_loinc / n_total, 1)}%) with NA LAB_LOINC"
    ))
  }
}

# ==============================================================================
# End of script
# ==============================================================================
