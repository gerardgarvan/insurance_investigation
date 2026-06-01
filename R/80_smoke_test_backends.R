# ==============================================================================
# 80_smoke_test_backends.R -- Backend parity smoke test (Phase 30)
# ==============================================================================
#
# Tests all 6 named predicates from 03_cohort_predicates.R on both RDS and
# DuckDB backends using a 100-patient sample (D-06, D-07).
#
# For each predicate:
#   1. Run on RDS backend (pcornet$ tibbles) -> collect PATID set
#   2. Run on DuckDB backend -> collect PATID set
#   3. Compare via setequal() -> log pass/fail
#
# Produces console output with per-predicate results and overall summary.
# Translation gaps are logged to console for documentation in
# docs/DUCKDB_TRANSLATION_NOTES.md.
#
# Usage:
#   source("R/80_smoke_test_backends.R")
#   # Or run interactively on HiPerGator after sourcing pipeline
#
# Dependencies:
#   - 00_config.R (auto-sources utils), 01_load_pcornet.R (loads pcornet$),
#     02_harmonize_payer.R (creates payer_summary for exclude_missing_payer),
#     10_cohort_predicates.R (defines predicates)
#   - R/utils/utils_duckdb.R (open/close_pcornet_con, get_pcornet_table)
#   - DuckDB file must exist at CONFIG$cache$duckdb_path
#     (created by R/03_duckdb_ingest.R)
#
# Requirement: DBAPI-04
# ==============================================================================

# Load pipeline (RDS mode first -- this is the baseline)
USE_DUCKDB <<- FALSE
source("R/00_config.R")
source("R/01_load_pcornet.R")
source("R/02_harmonize_payer.R")
source("R/10_cohort_predicates.R")

library(dplyr)
library(glue)

message(strrep("=", 70))
message("SMOKE TEST: Backend Parity (RDS vs DuckDB)")
message(strrep("=", 70))

# --------------------------------------------------------------------------
# 1. Sample 100 random patients from DEMOGRAPHIC (D-07)
# --------------------------------------------------------------------------
SAMPLE_SIZE <- 100
SEED <- 20260423

set.seed(SEED)
sample_ids <- pcornet$DEMOGRAPHIC %>%
  distinct(ID) %>%
  slice_sample(n = SAMPLE_SIZE) %>%
  pull(ID)

sample_df <- tibble(ID = sample_ids)
message(glue("\nSample: {SAMPLE_SIZE} patients (seed={SEED})"))
message(glue("Sample IDs (first 5): {paste(head(sample_ids, 5), collapse=', ')}"))

# --------------------------------------------------------------------------
# 2. RDS Baseline: Run all 6 predicates
# --------------------------------------------------------------------------
message(glue("\n{strrep('-', 50)}"))
message("Phase 1: Running predicates on RDS backend...")
message(strrep("-", 50))

# Filter predicates
rds_hl <- has_hodgkin_diagnosis(sample_df) %>% pull(ID)
rds_enrolled <- with_enrollment_period(sample_df) %>% pull(ID)
rds_payer <- exclude_missing_payer(sample_df, payer_summary) %>% pull(ID)

# Treatment detectors (no input arg)
rds_chemo <- has_chemo() %>% pull(ID)
rds_rad <- has_radiation() %>% pull(ID)
rds_sct <- has_sct() %>% pull(ID)

rds_results <- list(
  has_hodgkin_diagnosis = rds_hl,
  with_enrollment_period = rds_enrolled,
  exclude_missing_payer = rds_payer,
  has_chemo = rds_chemo,
  has_radiation = rds_rad,
  has_sct = rds_sct
)

message("\nRDS baseline counts:")
for (nm in names(rds_results)) {
  message(glue("  {nm}: {length(rds_results[[nm]])} patients"))
}

# --------------------------------------------------------------------------
# 3. DuckDB: Open connection, swap pcornet$ entries, run predicates
# --------------------------------------------------------------------------
message(glue("\n{strrep('-', 50)}"))
message("Phase 2: Running predicates on DuckDB backend...")
message(strrep("-", 50))

# Save original pcornet$ entries
pcornet_rds_backup <- pcornet

# Open DuckDB connection
duckdb_path <- CONFIG$cache$duckdb_path
if (!file.exists(duckdb_path)) {
  stop(glue("DuckDB file not found: {duckdb_path}. Run R/03_duckdb_ingest.R first."))
}
open_pcornet_con(db_path = duckdb_path, read_only = TRUE)

# Swap pcornet$ entries with DuckDB tbl_dbi objects
# This simulates what predicates will see when they access pcornet$TABLE_NAME
for (tbl_name in names(pcornet)) {
  # Skip NULL entries and TUMOR_REGISTRY_ALL (handled via DuckDB VIEW)
  if (is.null(pcornet[[tbl_name]])) next

  # Check if table exists in DuckDB
  if (tbl_name %in% DBI::dbListTables(pcornet_con)) {
    pcornet[[tbl_name]] <- dplyr::tbl(pcornet_con, tbl_name)
  } else {
    message(glue("  Note: {tbl_name} not in DuckDB, keeping RDS tibble"))
  }
}

# TUMOR_REGISTRY_ALL is a VIEW in DuckDB (D-03)
if ("TUMOR_REGISTRY_ALL" %in% DBI::dbListTables(pcornet_con)) {
  pcornet$TUMOR_REGISTRY_ALL <- dplyr::tbl(pcornet_con, "TUMOR_REGISTRY_ALL")
}

# Track translation gaps
translation_gaps <- list()

# Run filter predicates with tryCatch for translation errors
run_predicate_safe <- function(pred_name, expr) {
  tryCatch(
    {
      result <- eval(expr)
      if (inherits(result, "tbl_lazy")) {
        result <- dplyr::collect(result)
      }
      result %>% pull(ID)
    },
    error = function(e) {
      msg <- conditionMessage(e)
      message(glue("  ERROR in {pred_name}: {msg}"))
      translation_gaps[[pred_name]] <<- msg
      character(0)
    }
  )
}

ddb_hl <- run_predicate_safe(
  "has_hodgkin_diagnosis",
  quote(has_hodgkin_diagnosis(sample_df) %>% collect())
)
ddb_enrolled <- run_predicate_safe(
  "with_enrollment_period",
  quote(with_enrollment_period(sample_df) %>% collect())
)
ddb_payer <- run_predicate_safe(
  "exclude_missing_payer",
  quote(exclude_missing_payer(sample_df, payer_summary) %>% collect())
)
ddb_chemo <- run_predicate_safe(
  "has_chemo",
  quote(has_chemo() %>% collect())
)
ddb_rad <- run_predicate_safe(
  "has_radiation",
  quote(has_radiation() %>% collect())
)
ddb_sct <- run_predicate_safe(
  "has_sct",
  quote(has_sct() %>% collect())
)

ddb_results <- list(
  has_hodgkin_diagnosis = ddb_hl,
  with_enrollment_period = ddb_enrolled,
  exclude_missing_payer = ddb_payer,
  has_chemo = ddb_chemo,
  has_radiation = ddb_rad,
  has_sct = ddb_sct
)

# --------------------------------------------------------------------------
# 4. Restore RDS pcornet$ and close DuckDB
# --------------------------------------------------------------------------
pcornet <<- pcornet_rds_backup
close_pcornet_con()
USE_DUCKDB <<- FALSE

# --------------------------------------------------------------------------
# 5. Compare results
# --------------------------------------------------------------------------
message(glue("\n{strrep('=', 70)}"))
message("RESULTS: PATID Set Equality")
message(strrep("=", 70))

results_summary <- list()

for (pred_name in names(rds_results)) {
  rds_ids <- sort(rds_results[[pred_name]])
  ddb_ids <- sort(ddb_results[[pred_name]])

  match <- setequal(rds_ids, ddb_ids)
  results_summary[[pred_name]] <- match

  status <- if (match) "PASS" else "FAIL"
  rds_n <- length(rds_ids)
  ddb_n <- length(ddb_ids)

  message(glue("\n  [{status}] {pred_name}"))
  message(glue("    RDS: {rds_n} patients, DuckDB: {ddb_n} patients"))

  if (!match) {
    in_rds_not_ddb <- setdiff(rds_ids, ddb_ids)
    in_ddb_not_rds <- setdiff(ddb_ids, rds_ids)
    if (length(in_rds_not_ddb) > 0) {
      message(glue("    In RDS only ({length(in_rds_not_ddb)}): {paste(head(in_rds_not_ddb, 10), collapse=', ')}"))
    }
    if (length(in_ddb_not_rds) > 0) {
      message(glue("    In DuckDB only ({length(in_ddb_not_rds)}): {paste(head(in_ddb_not_rds, 10), collapse=', ')}"))
    }
  }
}

# --------------------------------------------------------------------------
# 6. Summary
# --------------------------------------------------------------------------
n_pass <- sum(unlist(results_summary))
n_total <- length(results_summary)
n_errors <- length(translation_gaps)

message(glue("\n{strrep('=', 70)}"))
message(glue("SUMMARY: {n_pass}/{n_total} predicates passed PATID set equality"))
if (n_errors > 0) {
  message(glue("         {n_errors} translation errors encountered"))
  message("\nTranslation gaps found:")
  for (gap_name in names(translation_gaps)) {
    message(glue("  - {gap_name}: {translation_gaps[[gap_name]]}"))
  }
}
message(strrep("=", 70))

if (n_pass < n_total || n_errors > 0) {
  message("\nAction: Document gaps in docs/DUCKDB_TRANSLATION_NOTES.md")
  message("Phase 31 may need to refactor predicates for full SQL translation.")
} else {
  message("\nAll predicates produce identical results on both backends.")
  message("Phase 31 can proceed with cohort migration.")
}

message("\n[Smoke test complete]")
