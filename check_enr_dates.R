# ==============================================================================
# check_enr_dates.R -- Print invalid ENR dates with their original text values
# ==============================================================================
# Loads ENROLLMENT twice:
#   1. Raw (dates as character) to preserve original text
#   2. Parsed (via 01_load_pcornet.R) to get _VALID flags
# Then joins them so you can see: ID, SOURCE, raw text, parsed date, valid flag
# ==============================================================================

source("R/00_config.R")

library(readr)
library(dplyr)
library(glue)

# --- Load raw text (dates stay as character strings) ---
enr_raw <- read_csv(
  PCORNET_PATHS[["ENROLLMENT"]],
  col_types = cols(.default = col_character()),
  show_col_types = FALSE
)

# Add a row number so we can join back after parsing
enr_raw <- enr_raw %>%
  mutate(.row = row_number()) %>%
  select(.row, ID, SOURCE,
         ENR_START_DATE_RAW = ENR_START_DATE,
         ENR_END_DATE_RAW   = ENR_END_DATE)

# --- Load parsed version (gets _VALID flags from 01_load_pcornet.R) ---
source("R/01_load_pcornet.R")

enr_parsed <- pcornet$ENROLLMENT %>%
  mutate(.row = row_number()) %>%
  select(.row,
         ENR_START_DATE, ENR_START_DATE_VALID,
         ENR_END_DATE,   ENR_END_DATE_VALID)

# --- Join raw text with parsed dates ---
enr_combined <- inner_join(enr_raw, enr_parsed, by = ".row")

# --- Filter to rows with at least one invalid date ---
bad_rows <- enr_combined %>%
  filter(ENR_START_DATE_VALID == FALSE | ENR_END_DATE_VALID == FALSE) %>%
  select(-.row)

# ---------- Print results ----------

date_max <- Sys.Date() + 5 * 365

message("\n", strrep("=", 70))
message("ENROLLMENT rows with out-of-range dates")
message("Valid range: 1900-01-01 to ", date_max)
message(strrep("=", 70))

# Split by which date column is bad
bad_start <- bad_rows %>% filter(ENR_START_DATE_VALID == FALSE)
bad_end   <- bad_rows %>% filter(ENR_END_DATE_VALID == FALSE)

message(glue("\n--- ENR_START_DATE invalid: {nrow(bad_start)} rows ---"))
if (nrow(bad_start) > 0) {
  bad_start %>%
    select(ID, SOURCE, ENR_START_DATE_RAW, ENR_START_DATE) %>%
    print(n = Inf)
}

message(glue("\n--- ENR_END_DATE invalid: {nrow(bad_end)} rows ---"))
if (nrow(bad_end) > 0) {
  bad_end %>%
    select(ID, SOURCE, ENR_END_DATE_RAW, ENR_END_DATE) %>%
    print(n = Inf)
}

message(glue("\nTotal ENROLLMENT rows: {format(nrow(enr_combined), big.mark = ',')}"))
message(glue("Rows with any invalid date: {nrow(bad_rows)}"))
