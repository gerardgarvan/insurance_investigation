# ==============================================================================
# 83_generate_speedup_report.R -- DuckDB vs RDS speedup report generator
# ==============================================================================
#
# Purpose:
#   Generate human-readable DuckDB vs RDS speedup report from benchmark CSV.
#   WHY separate report generator from benchmark: Benchmark produces raw data,
#   report is human-readable interpretation.
#
# Inputs:
#   - output/benchmark_results.csv from R/82
#
# Outputs:
#   - output/speedup_report.txt
#
# Dependencies:
#   - R/00_config.R
#
# Requirements:
#   - DBDIAG-03
#
# Usage:
#   source("R/83_generate_speedup_report.R")
#
# ==============================================================================

source("R/00_config.R")
n # ==============================================================================
# SECTION 1: SETUP ----
# ==============================================================================

library(dplyr)
library(readr)
library(glue)
library(tidyr)

message("\n", strrep("=", 60))
message("DuckDB SPEEDUP REPORT GENERATOR")
message(strrep("=", 60))

# ==============================================================================
# 1. READ BENCHMARK DATA
# ==============================================================================

benchmark_path <- file.path(CONFIG$output_dir, "logs", "duckdb_benchmark.csv")

if (!file.exists(benchmark_path)) {
  stop(glue(
    "Benchmark CSV not found: {benchmark_path}\n",
    "Run R/28_benchmark_cohort.R and diagnostic benchmarks on HiPerGator first."
  ))
}

benchmarks <- read_csv(benchmark_path, show_col_types = FALSE)
message(glue("[Report] Read {nrow(benchmarks)} benchmark rows from {benchmark_path}"))

# Handle legacy format: if no "script" column, assume all rows are cohort build
if (!"script" %in% colnames(benchmarks)) {
  message("[Report] No 'script' column found -- treating all rows as '14_build_cohort'")
  benchmarks <- benchmarks %>% mutate(script = "14_build_cohort")
}

# Validate required columns
required_cols <- c("script", "backend", "run", "elapsed_seconds")
missing_cols <- setdiff(required_cols, colnames(benchmarks))
if (length(missing_cols) > 0) {
  stop(glue("Missing required columns: {paste(missing_cols, collapse = ', ')}"))
}

# Detect optional columns
has_memory <- "peak_memory_mb" %in% colnames(benchmarks)
has_user_time <- "user_seconds" %in% colnames(benchmarks)

# ==============================================================================
# 2. COMPUTE SUMMARY STATISTICS
# ==============================================================================

# Per-script, per-backend median
script_summary <- benchmarks %>%
  group_by(script, backend) %>%
  summarise(
    n_runs       = n(),
    median_sec   = median(elapsed_seconds, na.rm = TRUE),
    min_sec      = min(elapsed_seconds, na.rm = TRUE),
    max_sec      = max(elapsed_seconds, na.rm = TRUE),
    mean_sec     = mean(elapsed_seconds, na.rm = TRUE),
    sd_sec       = sd(elapsed_seconds, na.rm = TRUE),
    .groups      = "drop"
  )

# Add memory stats if available
if (has_memory) {
  memory_summary <- benchmarks %>%
    group_by(script, backend) %>%
    summarise(
      median_memory_mb = median(peak_memory_mb, na.rm = TRUE),
      .groups = "drop"
    )
  script_summary <- script_summary %>% left_join(memory_summary, by = c("script", "backend"))
}

# Compute speedup ratios (RDS median / DuckDB median)
rds_stats <- script_summary %>%
  filter(backend == "RDS") %>%
  select(script, rds_median = median_sec, rds_min = min_sec, rds_max = max_sec)

ddb_stats <- script_summary %>%
  filter(backend == "DuckDB") %>%
  select(script, ddb_median = median_sec, ddb_min = min_sec, ddb_max = max_sec)

speedup_table <- rds_stats %>%
  inner_join(ddb_stats, by = "script") %>%
  mutate(
    speedup_ratio = round(rds_median / ddb_median, 2),
    time_saved_sec = round(rds_median - ddb_median, 2),
    faster_backend = if_else(speedup_ratio > 1, "DuckDB", "RDS")
  )

# Add memory reduction if available
if (has_memory) {
  rds_mem <- script_summary %>%
    filter(backend == "RDS") %>%
    select(script, rds_memory_mb = median_memory_mb)
  ddb_mem <- script_summary %>%
    filter(backend == "DuckDB") %>%
    select(script, ddb_memory_mb = median_memory_mb)
  speedup_table <- speedup_table %>%
    left_join(rds_mem, by = "script") %>%
    left_join(ddb_mem, by = "script") %>%
    mutate(
      memory_reduction_pct = round((1 - ddb_memory_mb / rds_memory_mb) * 100, 1)
    )
}

# Compute milestone check: >= 3x on at least 3 of 5 scripts
n_scripts <- nrow(speedup_table)
n_meeting_target <- sum(speedup_table$speedup_ratio >= 3, na.rm = TRUE)
target_met <- n_meeting_target >= 3

message(glue("[Report] {n_scripts} scripts benchmarked"))
message(glue("[Report] {n_meeting_target}/{n_scripts} scripts meet >= 3x speedup target"))
message(glue("[Report] Milestone target (>= 3x on 3+ scripts): {if (target_met) 'MET' else 'NOT MET'}"))

# ==============================================================================
# 3. FORMAT MARKDOWN REPORT
# ==============================================================================

report_lines <- c(
  "# DuckDB vs RDS Speedup Report",
  "",
  glue("**Generated:** {Sys.time()}"),
  glue("**Benchmark data:** `{benchmark_path}`"),
  glue("**Scripts benchmarked:** {n_scripts}"),
  "",
  "## Milestone Summary",
  "",
  glue("**Phase 32 target:** >= 3x speedup on at least 3 of 5 diagnostic scripts."),
  ""
)

if (target_met) {
  report_lines <- c(
    report_lines,
    glue("**Result: TARGET MET** -- {n_meeting_target}/{n_scripts} scripts achieved >= 3x speedup."),
    ""
  )
} else {
  report_lines <- c(
    report_lines,
    glue("**Result: TARGET NOT MET** -- {n_meeting_target}/{n_scripts} scripts achieved >= 3x speedup (need 3+)."),
    ""
  )
}

# Overall speedup summary
overall_rds <- sum(speedup_table$rds_median, na.rm = TRUE)
overall_ddb <- sum(speedup_table$ddb_median, na.rm = TRUE)
overall_speedup <- round(overall_rds / overall_ddb, 2)
overall_saved <- round(overall_rds - overall_ddb, 1)

report_lines <- c(
  report_lines,
  glue("**Aggregate speedup:** {overall_speedup}x across all scripts ({overall_saved}s saved per full run)."),
  ""
)

# ==============================================================================
# Speedup table
# ==============================================================================

report_lines <- c(
  report_lines,
  "## Per-Script Speedup",
  "",
  "| Script | RDS Median (s) | DuckDB Median (s) | Speedup | Time Saved (s) | Target |",
  "|--------|---------------:|-------------------:|--------:|---------------:|--------|"
)

for (i in seq_len(nrow(speedup_table))) {
  row <- speedup_table[i, ]
  target_flag <- if (row$speedup_ratio >= 3) ">=3x" else "<3x"
  report_lines <- c(
    report_lines,
    glue(
      "| {row$script} | {round(row$rds_median, 2)} | {round(row$ddb_median, 2)} | ",
      "{row$speedup_ratio}x | {row$time_saved_sec} | {target_flag} |"
    )
  )
}

report_lines <- c(report_lines, "")

# Memory table (if available)
if (has_memory) {
  report_lines <- c(
    report_lines,
    "## Memory Usage",
    "",
    "| Script | RDS Peak (MB) | DuckDB Peak (MB) | Reduction |",
    "|--------|-------------:|------------------:|----------:|"
  )
  for (i in seq_len(nrow(speedup_table))) {
    row <- speedup_table[i, ]
    report_lines <- c(
      report_lines,
      glue(
        "| {row$script} | {round(row$rds_memory_mb, 1)} | {round(row$ddb_memory_mb, 1)} | ",
        "{row$memory_reduction_pct}% |"
      )
    )
  }
  report_lines <- c(report_lines, "")
}

# ==============================================================================
# Detailed per-run data
# ==============================================================================

report_lines <- c(
  report_lines,
  "## Detailed Run Data",
  "",
  "| Script | Backend | Run | Elapsed (s) |",
  "|--------|---------|----:|------------:|"
)

detail_rows <- benchmarks %>% arrange(script, backend, run)
for (i in seq_len(nrow(detail_rows))) {
  row <- detail_rows[i, ]
  report_lines <- c(
    report_lines,
    glue("| {row$script} | {row$backend} | {row$run} | {round(row$elapsed_seconds, 2)} |")
  )
}

report_lines <- c(report_lines, "")

# ==============================================================================
# Variance analysis
# ==============================================================================

report_lines <- c(
  report_lines,
  "## Variance Analysis",
  "",
  "| Script | Backend | Median (s) | Min (s) | Max (s) | SD (s) | Runs |",
  "|--------|---------|----------:|---------:|--------:|-------:|-----:|"
)

variance_rows <- script_summary %>% arrange(script, backend)
for (i in seq_len(nrow(variance_rows))) {
  row <- variance_rows[i, ]
  sd_val <- if (is.na(row$sd_sec)) "N/A" else as.character(round(row$sd_sec, 3))
  report_lines <- c(
    report_lines,
    glue(
      "| {row$script} | {row$backend} | {round(row$median_sec, 2)} | ",
      "{round(row$min_sec, 2)} | {round(row$max_sec, 2)} | {sd_val} | {row$n_runs} |"
    )
  )
}

report_lines <- c(report_lines, "")

# ==============================================================================
# Interpretation notes
# ==============================================================================

report_lines <- c(
  report_lines,
  "## Interpretation Notes",
  "",
  "- **Speedup ratio** = RDS median / DuckDB median. Values > 1 mean DuckDB is faster.",
  "- **Time saved** = RDS median - DuckDB median (positive = DuckDB faster).",
  "- Scripts dominated by CSV writing overhead may show lower speedup,",
  "  since those operations are backend-independent.",
  "- Diagnostic scripts (R/20-R/24) materialize early and do most work in-memory, so their",
  "  speedup reflects only the initial data loading advantage of DuckDB over RDS.",
  "- The cohort pipeline (R/04) chains lazy queries before materializing, which may show",
  "  different speedup characteristics than diagnostic scripts.",
  "",
  "---",
  glue("*Report generated by R/29_generate_speedup_report.R on {Sys.Date()}*")
)

# ==============================================================================
# 4. WRITE REPORT
# ==============================================================================

report_dir <- file.path(CONFIG$output_dir, "reports")
dir.create(report_dir, showWarnings = FALSE, recursive = TRUE)

report_path <- file.path(report_dir, "duckdb_speedup_report.md")
writeLines(report_lines, report_path)
message(glue("\n[Report] Written to: {report_path}"))
message(glue("[Report] {length(report_lines)} lines"))

# ==============================================================================
# 5. CONSOLE SUMMARY
# ==============================================================================

# ==============================================================================
# SECTION 2: OUTPUT ----
# ==============================================================================

message(strrep("=", 60))
message("SPEEDUP SUMMARY")
message(strrep("=", 60))
for (i in seq_len(nrow(speedup_table))) {
  row <- speedup_table[i, ]
  marker <- if (row$speedup_ratio >= 3) "[>=3x]" else "[<3x] "
  message(glue("  {marker} {row$script}: {row$speedup_ratio}x ({row$time_saved_sec}s saved)"))
}
message(glue("\nAggregate: {overall_speedup}x ({overall_saved}s saved)"))
message(glue("Target: {if (target_met) 'MET' else 'NOT MET'} ({n_meeting_target}/{n_scripts} scripts >= 3x)"))
message(strrep("=", 60))
