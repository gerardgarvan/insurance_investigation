# ==============================================================================
# Ad-hoc: Hodgkin Lymphoma Diagnosis Date Counts
# ==============================================================================
# Based on the confirmed 7-day HL cohort (6,347 patients from Phase 55).
#
# Reports:
#   1. Total confirmed HL cohort size
#   2. Patients with a valid (non-NA) DX_DATE on C81 diagnosis rows
#   3. Patients with >= 2 unique C81 DX_DATEs separated by 7+ days
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

INPUT_RDS <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")

message("=== Hodgkin Lymphoma Diagnosis Date Check ===\n")

# --- Load confirmed 7-day HL cohort (Phase 55) ---
message(glue("Loading confirmed HL cohort from {INPUT_RDS}..."))
confirmed_hl_cohort <- readRDS(INPUT_RDS)
cohort_ids <- confirmed_hl_cohort$ID
n_cohort <- length(cohort_ids)
message(glue("  Confirmed HL cohort: {format(n_cohort, big.mark=',')} patients\n"))

# --- Pull C81 diagnoses (ICD-10 only) restricted to cohort ---
hl_dx <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  select(ID, DX, DX_DATE) %>%
  collect() %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^C81")) %>%
  filter(ID %in% cohort_ids)

n_with_dx <- n_distinct(hl_dx$ID)
n_no_dx   <- n_cohort - n_with_dx
message(glue("1. Cohort patients with any C81 dx row:    {format(n_with_dx, big.mark=',')}"))
message(glue("   Cohort patients with NO C81 dx row:     {format(n_no_dx, big.mark=',')}"))

# --- Patients with at least one valid DX_DATE ---
hl_with_date <- hl_dx %>%
  filter(!is.na(DX_DATE))

n_valid_date <- n_distinct(hl_with_date$ID)
n_no_date    <- n_with_dx - n_valid_date
message(glue("2. With valid C81 DX_DATE:                 {format(n_valid_date, big.mark=',')}"))
message(glue("   With NO valid C81 DX_DATE:              {format(n_no_date, big.mark=',')}"))

# --- Patients with >= 2 unique dates separated by 7+ days ---
confirmed <- hl_with_date %>%
  distinct(ID, DX_DATE) %>%
  group_by(ID) %>%
  filter(n() >= 2) %>%
  filter(as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7) %>%
  ungroup()

n_confirmed <- n_distinct(confirmed$ID)
message(glue("3. With 2+ unique dates, 7-day span:       {format(n_confirmed, big.mark=',')}"))

message(glue("\n   Rate (of cohort):           {scales::percent(n_confirmed / n_cohort, accuracy=0.1)}"))
message(glue("   Rate (of those with date):  {scales::percent(n_confirmed / n_valid_date, accuracy=0.1)}"))

close_pcornet_con()

message("\n=== Done ===")
