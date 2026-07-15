# ==============================================================================
# run_88_smoke_to_log.R -- Run the comprehensive smoke test, capture all output
# ==============================================================================
#
# Purpose:
#   Runs R/88_smoke_test_comprehensive.R in a clean subprocess and tees ALL
#   console output (both stdout AND stderr -- check() results are emitted via
#   message(), which goes to stderr) into a single timestamped log file for
#   sharing. R/88 calls rm(list=ls()) at the top and quit(status=1) at the end,
#   so it MUST run as a subprocess, not source()'d into this session.
#
# Usage (run from the project root so the R/ and output/ paths resolve):
#   Rscript R/run_88_smoke_to_log.R
#
#   On HiPerGator, load R first:
#     module load R/4.4.2
#     Rscript R/run_88_smoke_to_log.R
#
# Output:
#   output/logs/phase125_smoke_<YYYYMMDD_HHMMSS>.log   (stdout + stderr interleaved)
#   Prints the log path and the R/88 exit code to this console.
# ==============================================================================

log_dir <- file.path("output", "logs")
dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)

stamp    <- format(Sys.time(), "%Y%m%d_%H%M%S")
log_file <- file.path(log_dir, paste0("phase125_smoke_", stamp, ".log"))

rscript  <- file.path(R.home("bin"), "Rscript")
smoke    <- file.path("R", "88_smoke_test_comprehensive.R")

if (!file.exists(smoke)) {
  stop(sprintf("Cannot find %s -- run this from the project root.", smoke))
}

cat(sprintf("Running %s ...\n", smoke))
cat(sprintf("Logging stdout + stderr to: %s\n\n", log_file))

# system2() interleaves both streams into the one file when stdout == stderr.
# The return value is R/88's exit status (0 = all checks passed, 1 = failures).
exit_code <- system2(
  command = rscript,
  args    = shQuote(smoke),
  stdout  = log_file,
  stderr  = log_file
)

# Append the exit code to the log so it's captured in what you share.
cat(sprintf("\n[exit code R/88: %s]\n", exit_code), file = log_file, append = TRUE)

cat(sprintf("R/88 exit code: %s  (%s)\n",
            exit_code,
            if (identical(exit_code, 0L)) "PASS - all checks passed"
            else "FAIL - see FAIL: lines in the log"))
cat(sprintf("Log written to: %s\n", log_file))
