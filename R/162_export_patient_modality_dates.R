# ==============================================================================
# 162_export_patient_modality_dates.R
# Exports E_patient_modality_dates without *_any columns as a CSV.
#
# Usage (HiPerGator):
#   module load R/4.4.2
#   Rscript R/162_export_patient_modality_dates.R
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
# ------------------------------------------------------------------
rds_files <- list.files(
  file.path(CONFIG$output_dir %||% "output"),
  pattern = "^surveillance_patient_modality_dates_.*\\.rds$",
  full.names = TRUE
)

if (length(rds_files) > 0) {
  latest <- rds_files[order(file.info(rds_files)$mtime, decreasing = TRUE)[1]]
  message("Loading: ", latest)
  patient_wide <- readRDS(latest)
} else {
  stop("No surveillance_patient_modality_dates_*.rds found in output/. ",
       "Run R/147_surveillance_modality_frequency.R first.")
}

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
