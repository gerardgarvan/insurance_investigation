# ==============================================================================
# 82_benchmark_cohort.R -- RDS vs DuckDB diagnostic-script benchmark
# ==============================================================================
#
# Purpose:
#   RDS vs DuckDB benchmark for the 5 diagnostic scripts (R/20-R/24): 3 runs
#   per backend per script, saves per-run timings to CSV for R/83 to evaluate.
#   WHY 3 runs per backend: Reduces variance from system load; median is more
#   robust than mean for timing. WHY these 5 scripts: They are the diagnostic
#   set (DBDIAG-01) identified in the code review as the benchmark target.
#
# Inputs:
#   - Full PCORnet CDM data (via DuckDB or RDS)
#
# Outputs:
#   - output/logs/duckdb_benchmark.csv (columns: script, backend, run,
#     elapsed_seconds, user_seconds, system_seconds, timestamp)
#
# Dependencies:
#   - R/00_config.R, R/01_load_pcornet.R
#   - R/20_treatment_inventory.R
#   - R/21_investigate_unmatched.R
#   - R/22_investigate_unmatched_ndc.R
#   - R/23_combine_reports.R
#   - R/24_treatment_codes_resolved.R
#
# Requirements:
#   - DBDIAG-01, PATTERN-E
#
# Usage:
#   source("R/82_benchmark_cohort.R")
#
# ==============================================================================

library(dplyr)
library(glue)
library(readr)

# ==============================================================================
# SETUP: Load infrastructure (not timed per D-10)
# ==============================================================================

message("\n", strrep("=", 60))
message("BENCHMARK SETUP: Loading infrastructure")
message(strrep("=", 60))

source("R/00_config.R")
# ==============================================================================
# SECTION 1: SETUP ----
# ==============================================================================
source("R/01_load_pcornet.R")

# Ensure DuckDB connection is open for DuckDB runs
if (!exists("pcornet_con", envir = .GlobalEnv)) {
  source("R/utils/utils_duckdb.R")
  open_pcornet_con()
}

message("[Setup] Infrastructure loaded")

# ==============================================================================
# TIMING FUNCTION
# ==============================================================================

time_script <- function(script_path, backend, run_number) {
  message(glue("\n--- {backend} run {run_number}: {basename(script_path)} ---"))

  USE_DUCKDB <<- (backend == "DuckDB")

  start_time <- proc.time()
  source(script_path, local = FALSE)
  elapsed <- proc.time() - start_time

  tibble(
    script          = basename(script_path),
    backend         = backend,
    run             = run_number,
    elapsed_seconds = elapsed["elapsed"],
    user_seconds    = elapsed["user.self"],
    system_seconds  = elapsed["sys.self"],
    timestamp       = Sys.time()
  )
}

# ==============================================================================
# RUN BENCHMARK: 5 scripts x 3 runs x 2 backends (DBDIAG-01, PATTERN-E)
# ==============================================================================

SCRIPTS_TO_BENCHMARK <- c(
  "R/20_treatment_inventory.R",
  "R/21_investigate_unmatched.R",
  "R/22_investigate_unmatched_ndc.R",
  "R/23_combine_reports.R",
  "R/24_treatment_codes_resolved.R"
)

n_runs <- 3L
results <- list()

message(strrep("=", 60))
message(glue("BENCHMARK: {length(SCRIPTS_TO_BENCHMARK)} scripts x {n_runs} runs x 2 backends"))
message(strrep("=", 60))

for (script_path in SCRIPTS_TO_BENCHMARK) {
  for (i in seq_len(n_runs)) {
    results[[length(results) + 1]] <- time_script(script_path, "RDS", i)
  }
  for (i in seq_len(n_runs)) {
    results[[length(results) + 1]] <- time_script(script_path, "DuckDB", i)
  }
}

benchmark_results <- bind_rows(results)

# ==============================================================================
# WRITE CSV OUTPUT
# ==============================================================================

output_path <- build_output_path("logs", "duckdb_benchmark.csv")
write_csv(benchmark_results, output_path)
message(glue("\nBenchmark results saved to: {output_path}"))

# ==============================================================================
# CONSOLE SUMMARY (per-script grouped)
# ==============================================================================

message(strrep("=", 60))
message("BENCHMARK RESULTS (per script)")
message(strrep("=", 60))

benchmark_summary <- benchmark_results %>%
  group_by(script, backend) %>%
  summarise(
    n_runs         = n(),
    median_seconds = median(elapsed_seconds),
    min_seconds    = min(elapsed_seconds),
    max_seconds    = max(elapsed_seconds),
    sd_seconds     = sd(elapsed_seconds),
    .groups        = "drop"
  )

for (scr in SCRIPTS_TO_BENCHMARK) {
  scr_name <- basename(scr)
  rds_row <- benchmark_summary %>% filter(script == scr_name, backend == "RDS")
  ddb_row <- benchmark_summary %>% filter(script == scr_name, backend == "DuckDB")
  if (nrow(rds_row) > 0 && nrow(ddb_row) > 0) {
    speedup <- rds_row$median_seconds / ddb_row$median_seconds
    message(glue(
      "\n{scr_name}",
      "\n  RDS:    median {round(rds_row$median_seconds, 2)}s ",
      "(range: {round(rds_row$min_seconds, 2)}-{round(rds_row$max_seconds, 2)}s)",
      "\n  DuckDB: median {round(ddb_row$median_seconds, 2)}s ",
      "(range: {round(ddb_row$min_seconds, 2)}-{round(ddb_row$max_seconds, 2)}s)",
      "\n  Speedup: {round(speedup, 2)}x"
    ))
  }
}

# ==============================================================================
# CLEANUP
# ==============================================================================

USE_DUCKDB <<- FALSE # Restore default
message(strrep("=", 60))
# ==============================================================================
# SECTION 2: OUTPUT ----
# ==============================================================================

message("Benchmark complete")
message(strrep("=", 60))
