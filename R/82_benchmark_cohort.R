# ==============================================================================
# 82_benchmark_cohort.R -- RDS vs DuckDB cohort build benchmark
# ==============================================================================
# Phase 31: DBCOH-03
# Times the cohort build pipeline (14_build_cohort.R) under both backends.
# 3 runs per backend with median comparison (D-12).
#
# Per D-10: Times cohort build ONLY, not config/data loading.
# Per D-11: Standalone script, separate from production code.
# Per D-12: 3 runs per backend, median comparison.
#
# Output: output/logs/duckdb_benchmark.csv
#
# Usage:
#   source("R/82_benchmark_cohort.R")  # Run interactively on HiPerGator
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

time_cohort_build <- function(backend, run_number) {
  message(glue("\n--- {backend} run {run_number} ---"))

  # Set backend
  USE_DUCKDB <<- (backend == "DuckDB")

  # Clear prior results
  if (exists("hl_cohort", envir = .GlobalEnv)) rm(hl_cohort, envir = .GlobalEnv)
  if (exists("attrition_log", envir = .GlobalEnv)) rm(attrition_log, envir = .GlobalEnv)

  # Time the cohort build only (D-10)
  start_time <- proc.time()
  source("R/14_build_cohort.R", local = FALSE)
  elapsed <- proc.time() - start_time

  # Capture result dimensions for verification
  cohort_rows <- nrow(get("hl_cohort", envir = .GlobalEnv))
  cohort_cols <- ncol(get("hl_cohort", envir = .GlobalEnv))

  tibble(
    backend = backend,
    run = run_number,
    elapsed_seconds = elapsed["elapsed"],
    user_seconds = elapsed["user.self"],
    system_seconds = elapsed["sys.self"],
    cohort_rows = cohort_rows,
    cohort_cols = cohort_cols,
    timestamp = Sys.time()
  )
}

# ==============================================================================
# RUN BENCHMARK: 3 runs per backend (D-12)
# ==============================================================================

n_runs <- 3L
results <- list()

message(strrep("=", 60))
message("BENCHMARK: RDS vs DuckDB Cohort Build")
message(strrep("=", 60))

# RDS runs first
for (i in seq_len(n_runs)) {
  results[[length(results) + 1]] <- time_cohort_build("RDS", i)
}

# DuckDB runs
for (i in seq_len(n_runs)) {
  results[[length(results) + 1]] <- time_cohort_build("DuckDB", i)
}

benchmark_results <- bind_rows(results)

# ==============================================================================
# SUMMARY STATISTICS
# ==============================================================================

benchmark_summary <- benchmark_results %>%
  group_by(backend) %>%
  summarise(
    n_runs = n(),
    median_seconds = median(elapsed_seconds),
    min_seconds = min(elapsed_seconds),
    max_seconds = max(elapsed_seconds),
    mean_seconds = mean(elapsed_seconds),
    sd_seconds = sd(elapsed_seconds),
    .groups = "drop"
  )

# Compute speedup ratio
rds_median <- benchmark_summary %>% filter(backend == "RDS") %>% pull(median_seconds)
ddb_median <- benchmark_summary %>% filter(backend == "DuckDB") %>% pull(median_seconds)
speedup <- rds_median / ddb_median

# Extract min/max/sd for console summary
rds_summary <- benchmark_summary %>% filter(backend == "RDS")
ddb_summary <- benchmark_summary %>% filter(backend == "DuckDB")
min_rds <- rds_summary$min_seconds
max_rds <- rds_summary$max_seconds
sd_rds <- rds_summary$sd_seconds
min_ddb <- ddb_summary$min_seconds
max_ddb <- ddb_summary$max_seconds
sd_ddb <- ddb_summary$sd_seconds

# ==============================================================================
# WRITE CSV OUTPUT
# ==============================================================================

dir.create(file.path(CONFIG$output_dir, "logs"), showWarnings = FALSE, recursive = TRUE)
output_path <- file.path(CONFIG$output_dir, "logs", "duckdb_benchmark.csv")
write_csv(benchmark_results, output_path)
message(glue("\nBenchmark results saved to: {output_path}"))

# ==============================================================================
# CONSOLE SUMMARY
# ==============================================================================

message(strrep("=", 60))
message("BENCHMARK RESULTS")
message(strrep("=", 60))
message(glue("\nRDS:    median {round(rds_median, 2)}s (range: {round(min_rds, 2)}-{round(max_rds, 2)}s)"))
message(glue("DuckDB: median {round(ddb_median, 2)}s (range: {round(min_ddb, 2)}-{round(max_ddb, 2)}s)"))
message(glue("\nSpeedup ratio: {round(speedup, 2)}x"))
if (speedup > 1) {
  message(glue("DuckDB is {round(speedup, 2)}x faster than RDS"))
} else {
  message(glue("RDS is {round(1/speedup, 2)}x faster than DuckDB"))
}
message(glue("\nVariance: RDS sd={round(sd_rds, 3)}s, DuckDB sd={round(sd_ddb, 3)}s"))

# ==============================================================================
# CLEANUP
# ==============================================================================

USE_DUCKDB <<- FALSE  # Restore default
message(strrep("=", 60))
message("Benchmark complete")
message(strrep("=", 60))
