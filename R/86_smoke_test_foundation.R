# ==============================================================================
# 86_smoke_test_foundation.R -- Validate Phase 65 Foundation Reorganization
# ==============================================================================
#
# Purpose:
#   Validates Phase 65 foundation reorganization: utils subfolder structure,
#   script renumbering, source() reference resolution. WHY filesystem structure
#   validation: After reorganization, source() calls must resolve to actual files.
#   WHY utils subfolder check: Phase 65 moved utils to R/utils/, verifying they
#   were all moved.
#
# Inputs:
#   - R/ directory filesystem structure
#
# Outputs:
#   - Console output (PASS/FAIL per validation)
#
# Dependencies:
#   - (standalone verification script)
#
# Requirements:
#   - REORG-01, REORG-03, REORG-05
#
# Usage:
#   Rscript R/86_smoke_test_foundation.R
#
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP ----
# ==============================================================================

# Clear workspace to avoid stale references
rm(list = ls())

library(glue)

passed <- 0L
failed <- 0L

check <- function(description, condition) {
  if (condition) {
    message(glue("  PASS: {description}"))
    passed <<- passed + 1L
  } else {
    message(glue("  FAIL: {description}"))
    failed <<- failed + 1L
  }
}

message(strrep("=", 70))
message("SMOKE TEST: Foundation Reorganization (Phase 65)")
message(strrep("=", 70))

# --------------------------------------------------------------------------
# Test 1: R/utils/ subfolder structure
# --------------------------------------------------------------------------
message("\n[1/6] Utils subfolder structure...")

check("R/utils/ directory exists", dir.exists("R/utils"))

utils_files <- list.files("R/utils", pattern = "\\.R$")
check(glue("R/utils/ contains 8 files (found {length(utils_files)})"),
      length(utils_files) == 8)

expected_utils <- c("utils_attrition.R", "utils_dates.R", "utils_duckdb.R",
                    "utils_icd.R", "utils_payer.R", "utils_pptx.R",
                    "utils_snapshot.R", "utils_treatment.R")
missing_utils <- setdiff(expected_utils, utils_files)
check(glue("All expected utils present (missing: {paste(missing_utils, collapse=', ') %||% 'none'})"),
      length(missing_utils) == 0)

# --------------------------------------------------------------------------
# Test 2: No utils files remain in R/ root
# --------------------------------------------------------------------------
message("\n[2/6] No utils files in R/ root...")

stale_utils <- list.files("R", pattern = "^utils_.*\\.R$")
check(glue("No utils_*.R in R/ root (found: {paste(stale_utils, collapse=', ') %||% 'none'})"),
      length(stale_utils) == 0)

# --------------------------------------------------------------------------
# Test 3: 00_config.R loads and auto-sources utils
# --------------------------------------------------------------------------
# ==============================================================================
# SECTION 2: VALIDATION ----
# ==============================================================================

message("\n[3/6] Config loading and auto-sourcing...")

tryCatch({
  source("R/00_config.R")
  check("00_config.R loads without error", TRUE)
}, error = function(e) {
  check(glue("00_config.R loads without error -- {e$message}"), FALSE)
})

# Verify key function from each utils module is available
key_functions <- list(
  utils_dates      = "parse_pcornet_date",
  utils_attrition  = "log_attrition",
  utils_icd        = "normalize_icd",
  utils_snapshot   = "save_output_data",
  utils_duckdb     = "open_pcornet_con",
  utils_treatment  = "safe_table",
  utils_payer      = "is_missing_payer",
  utils_pptx       = "style_table"
)

for (module in names(key_functions)) {
  func_name <- key_functions[[module]]
  check(glue("{module}: {func_name}() exists"), exists(func_name))
}

# --------------------------------------------------------------------------
# Test 4: Foundation script chain (00 -> 01 -> 02)
# --------------------------------------------------------------------------
message("\n[4/6] Foundation script chain...")

check("R/00_config.R exists", file.exists("R/00_config.R"))
check("R/01_load_pcornet.R exists", file.exists("R/01_load_pcornet.R"))
check("R/02_harmonize_payer.R exists", file.exists("R/02_harmonize_payer.R"))

# --------------------------------------------------------------------------
# Test 5: Renumbered DuckDB script
# --------------------------------------------------------------------------
message("\n[5/6] DuckDB script renumbering...")

check("R/03_duckdb_ingest.R exists (renumbered from 25)",
      file.exists("R/03_duckdb_ingest.R"))
check("R/25_duckdb_ingest.R removed (old location)",
      !file.exists("R/25_duckdb_ingest.R"))

# --------------------------------------------------------------------------
# Test 6: No old-style utils source paths remain
# --------------------------------------------------------------------------
message("\n[6/6] No stale source() references...")

r_files <- list.files("R", pattern = "\\.R$", full.names = TRUE)
stale_refs <- character(0)
for (f in r_files) {
  lines <- readLines(f, warn = FALSE)
  # Match source("R/utils_ but NOT source("R/utils/utils_
  hits <- grep('source\\("R/utils_', lines)
  if (length(hits) > 0) {
    stale_refs <- c(stale_refs, glue("{basename(f)}:{hits}"))
  }
}
check(glue("No old-style source() paths (found: {paste(stale_refs, collapse=', ') %||% 'none'})"),
      length(stale_refs) == 0)

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
message(glue("\n{strrep('=', 70)}"))
total <- passed + failed
if (failed == 0) {
  message(glue("ALL {total} CHECKS PASSED"))
} else {
  message(glue("FAILED: {failed}/{total} checks failed"))
}
message(strrep("=", 70))
message("\nValidated:")
message("  * Utils auto-sourcing from R/utils/ (REORG-03)")
message("  * Foundation script numbering 00-03 (REORG-01)")
message("  * No deprecated foundation scripts (REORG-04 N/A -- archival in Phase 68)")

if (failed > 0) {
  quit(status = 1)
}
