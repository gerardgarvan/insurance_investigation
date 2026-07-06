# ==============================================================================
# filter_strange_death_csvs.R -- Filter DEATH CSVs to strange-death patients
# ==============================================================================
#
# Purpose:
#   Filter DEATH_Mailhot_V1.csv and DEATH_CAUSE_Mailhot_V1.csv to only the ~258
#   patients flagged as "strange deaths" (post_death_activity == TRUE from
#   validated_death_dates.rds). Ad-hoc utility, not part of the numbered pipeline.
#
# Inputs:
#   - {CONFIG$cache$outputs_dir}/validated_death_dates.rds  (from R/53)
#   - {CONFIG$data_dir}/DEATH_Mailhot_V1.csv
#   - {CONFIG$data_dir}/DEATH_CAUSE_Mailhot_V1.csv
#
# Outputs:
#   - output/strange_deaths/DEATH_Mailhot_V1_strange_only.csv
#   - output/strange_deaths/DEATH_CAUSE_Mailhot_V1_strange_only.csv
#
# All columns are read as character to preserve the source values verbatim.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(readr)
})

source("R/00_config.R")

DEATH_RDS <- file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")
DEATH_CSV <- file.path(CONFIG$data_dir, "DEATH_Mailhot_V1.csv")
DEATH_CAUSE_CSV <- file.path(CONFIG$data_dir, "DEATH_CAUSE_Mailhot_V1.csv")

OUT_DIR <- file.path(CONFIG$output_dir, "strange_deaths")
OUT_DEATH <- file.path(OUT_DIR, "DEATH_Mailhot_V1_strange_only.csv")
OUT_DEATH_CAUSE <- file.path(OUT_DIR, "DEATH_CAUSE_Mailhot_V1_strange_only.csv")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

message("=== Filter DEATH CSVs to strange-death patients ===")
message()

# ------------------------------------------------------------------------------
# 1. Load strange-death patient IDs
# ------------------------------------------------------------------------------
stopifnot(file.exists(DEATH_RDS))

validated <- readRDS(DEATH_RDS)
strange_ids <- validated %>%
  filter(death_valid == TRUE, post_death_activity == TRUE) %>%
  pull(ID) %>%
  unique()

message(glue("Strange-death patients: {length(strange_ids)}"))
if (length(strange_ids) != 258) {
  message(glue("  NOTE: expected 258, got {length(strange_ids)} -- verify upstream if this drifts"))
}
message()

# ------------------------------------------------------------------------------
# 2. Filter DEATH_Mailhot_V1.csv
# ------------------------------------------------------------------------------
stopifnot(file.exists(DEATH_CSV))

death <- read_csv(DEATH_CSV, col_types = cols(.default = col_character()), progress = FALSE)
message(glue("DEATH input rows:  {nrow(death)}"))

# Identify the patient-ID column (raw PCORnet uses PATID; local extract uses ID)
id_col_death <- intersect(c("ID", "PATID"), names(death))[1]
stopifnot(!is.na(id_col_death))

death_filtered <- death %>% filter(.data[[id_col_death]] %in% strange_ids)
message(glue("DEATH filtered rows: {nrow(death_filtered)} ({n_distinct(death_filtered[[id_col_death]])} unique patients)"))

write_csv(death_filtered, OUT_DEATH)
message(glue("  Wrote: {OUT_DEATH}"))
message()

# ------------------------------------------------------------------------------
# 3. Filter DEATH_CAUSE_Mailhot_V1.csv
# ------------------------------------------------------------------------------
stopifnot(file.exists(DEATH_CAUSE_CSV))

death_cause <- read_csv(DEATH_CAUSE_CSV, col_types = cols(.default = col_character()), progress = FALSE)
message(glue("DEATH_CAUSE input rows:  {nrow(death_cause)}"))

id_col_cause <- intersect(c("ID", "PATID"), names(death_cause))[1]
stopifnot(!is.na(id_col_cause))

cause_filtered <- death_cause %>% filter(.data[[id_col_cause]] %in% strange_ids)
message(glue("DEATH_CAUSE filtered rows: {nrow(cause_filtered)} ({n_distinct(cause_filtered[[id_col_cause]])} unique patients)"))

write_csv(cause_filtered, OUT_DEATH_CAUSE)
message(glue("  Wrote: {OUT_DEATH_CAUSE}"))
message()

message("Done.")
