# ==============================================================================
# Ad-hoc: Hodgkin Lymphoma Diagnosis Date Counts
# ==============================================================================
# Reports:
#   1. Total HL patients (any C81 dx in DIAGNOSIS table)
#   2. HL patients with a valid (non-NA) DX_DATE
#   3. HL patients with >= 2 unique DX_DATEs separated by 7+ days
#
# Usage:
#   source("R/hl_dx_date_check.R")
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

message("=== Hodgkin Lymphoma Diagnosis Date Check ===\n")

# --- Pull C81 diagnoses (ICD-10 only) from DIAGNOSIS table ---
hl_dx <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  select(ID, DX, DX_DATE) %>%
  collect() %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^C81"))

n_total <- n_distinct(hl_dx$ID)
message(glue("1. Total HL patients (any C81 dx):         {format(n_total, big.mark=',')}"))

# --- Patients with at least one valid DX_DATE ---
hl_with_date <- hl_dx %>%
  filter(!is.na(DX_DATE))

n_valid_date <- n_distinct(hl_with_date$ID)
n_no_date    <- n_total - n_valid_date
message(glue("2. HL patients with valid DX_DATE:          {format(n_valid_date, big.mark=',')}"))
message(glue("   HL patients with NO valid DX_DATE:       {format(n_no_date, big.mark=',')}"))

# --- Patients with >= 2 unique dates separated by 7+ days ---
confirmed <- hl_with_date %>%
  distinct(ID, DX_DATE) %>%
  group_by(ID) %>%
  filter(n() >= 2) %>%                                      # must have 2+ unique dates
  filter(as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7) %>%  # span >= 7 days

  ungroup()

n_confirmed <- n_distinct(confirmed$ID)
message(glue("3. HL patients with 2+ dates, 7-day span:  {format(n_confirmed, big.mark=',')}"))

message(glue("\n   Confirmation rate (of those with date): {scales::percent(n_confirmed / n_valid_date, accuracy=0.1)}"))
message(glue("   Confirmation rate (of all HL patients): {scales::percent(n_confirmed / n_total, accuracy=0.1)}"))

close_pcornet_con()

message("\n=== Done ===")
