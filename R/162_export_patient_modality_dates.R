# ==============================================================================
# 162_export_patient_modality_dates.R -- Export patient modality dates CSV
# ==============================================================================
# INTERNAL — output contains patient IDs; write only to output/internal/.
#
# Purpose:
#   Export the patient-modality-dates wide table (excluding *_any columns) as a
#   dated CSV for downstream delivery or manual QC.
#
# Inputs:
#   DuckDB E_patient_modality_dates table (or cached RDS from R/147)
#
# Outputs:
#   output/internal/patient_modality_dates_<YYYYMMDD>.csv   (patient IDs: internal)
#
# Dependencies:
#   R/00_config.R (defines CONFIG, open_pcornet_con)
#
# ==============================================================================

source(here::here("R/00_config.R"))
library(DBI)
library(dplyr)
library(readr)
library(glue)

con <- open_pcornet_con(read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

CUTOFF_DATE <- as.Date(Sys.getenv("HL_CUTOFF_DATE", "2025-12-31"))
run_date    <- format(Sys.Date(), "%Y%m%d")

# ------------------------------------------------------------------
# Load the most recent patient_modality_dates RDS if it exists,
# otherwise source R/147 outputs (patient_wide must be in environment)
# Pin via env var R162_PATIENT_MODALITY_RDS.
# ------------------------------------------------------------------
patient_modality_rds_path <- resolve_input(
  dir     = CONFIG$cache$outputs_dir %||% file.path(CONFIG$output_dir %||% "output"),
  pattern = "^surveillance_patient_modality_dates_.*\\.rds$",
  env_var = "R162_PATIENT_MODALITY_RDS",
  label   = "patient_modality_dates"
)
patient_wide <- readRDS(patient_modality_rds_path)

# ------------------------------------------------------------------
# Drop *_any columns
# ------------------------------------------------------------------
keep_cols <- names(patient_wide)[!grepl("_any$", names(patient_wide))]
out <- patient_wide |> dplyr::select(dplyr::all_of(keep_cols))

message(sprintf("Columns kept: %d  (dropped %d _any columns)",
                ncol(out), ncol(patient_wide) - ncol(out)))

# ------------------------------------------------------------------
# Write CSV
# ------------------------------------------------------------------
out_path <- here::here("output", glue("patient_modality_dates_no_any_{run_date}.csv"))
readr::write_csv(out, out_path)
message("Written: ", out_path)
message(sprintf("  %d patients x %d columns", nrow(out), ncol(out)))

# ==============================================================================
# KEY
# ==============================================================================
# Input env vars (resolve_input):
#   R162_PATIENT_MODALITY_RDS -- surveillance_patient_modality_dates_<date>.rds
#                                (from R/147; default: most recent in cache dir)
# Output:
#   output/patient_modality_dates_no_any_<YYYYMMDD>.csv  (INTERNAL)
