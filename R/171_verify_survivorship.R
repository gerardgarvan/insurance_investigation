# ==============================================================================
# 171_verify_survivorship.R -- Verify survivorship workbook vs 2026-10-08 ref
# ==============================================================================
# Compares today's survivorship_modality_rates_<SURV_RUN_DATE>.xlsx against
# the 2026-10-08 reference workbook and confirms provenance (R/147 input date
# recorded in the KEY sheet).
#
# Usage:
#   export SURV_RUN_DATE=20261012   # optional; defaults to today
#   Rscript R/171_verify_survivorship.R
#
# Chained after 166_survivorship.sbatch via afterok dependency.
# SURV_RUN_DATE must be passed via --export so both R/168 and this script
# use the same date to locate the new workbook.
#
# Always writes OVERALL: PASS or OVERALL: FAIL to the log and exits with
# code 0 (PASS) or 1 (FAIL).  No stop() outside check functions.
#
# See .planning/phases/171-survivorship-workbook-refresh/171-CONTEXT.md
# for phase context and decisions.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readxl)
  library(glue)
})

source("R/00_config.R")

# ==============================================================================
# A. SETUP AND LOG FIRST
# ==============================================================================

surv_date <- Sys.getenv("SURV_RUN_DATE", unset = format(Sys.Date(), "%Y%m%d"))
out_dir   <- CONFIG$cache$outputs_dir
log_dir   <- file.path(CONFIG$output_dir, "logs")
dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)

log_path <- file.path(log_dir, glue("171_verify_survivorship_{surv_date}.txt"))
con      <- file(log_path, open = "wt")
sink(con, split = TRUE)

cat("SURV_RUN_DATE:", surv_date, "\n")

results <- list()

# EXPECTED_DIFFS: survivorship workbook changes are all affirmative assertions —
# no checks need to be skipped.  Primary-tier rates are expected to be identical
# to the 2026-10-08 reference.  Any-tier values do not flow into this workbook
# (confirmed Task 0: R/166 uses n_dates_post_primary, no _any columns reach xlsx).
# See 170-BASELINE-DRIFT.md §7 and 171-CONTEXT.md D-03.
EXPECTED_DIFFS <- character(0)

run_check <- function(name, fn) {
  if (name %in% EXPECTED_DIFFS) {
    results[[name]] <<- glue("SKIP — expected difference (170-BASELINE-DRIFT.md)")
    return(invisible())
  }
  results[[name]] <<- tryCatch(
    fn(),
    error = function(e) paste0("FAIL — error: ", conditionMessage(e))
  )
}

# ==============================================================================
# B. POINTER AND PATHS (failures are results, not stop())
# ==============================================================================

ptr           <- file.path(log_dir, "147_verify_last_pass.txt")
r147_run_date <- NA_character_

run_check("input:pointer", function() {
  if (!file.exists(ptr)) return(paste0("FAIL — pointer missing: ", ptr))
  kv <- read.delim(ptr, sep = "=", header = FALSE,
                   col.names = c("k", "v"), quote = "")
  d  <- kv$v[kv$k == "run_date"][1]
  if (is.na(d) || !grepl("^[0-9]{8}$", d))
    return("FAIL — pointer has no valid run_date")
  r147_run_date <<- d
  paste0("PASS — R/147 verified run ", d)
})

ref_path <- file.path(out_dir, "survivorship_modality_rates_20261008.xlsx")
new_path <- file.path(out_dir, glue("survivorship_modality_rates_{surv_date}.xlsx"))

cat("REF:", ref_path, "\n")
cat("NEW:", new_path, "\n\n")

run_check("input:ref_workbook", function() {
  if (file.exists(ref_path)) "PASS — present" else paste0("FAIL — missing ", ref_path)
})

run_check("input:new_workbook", function() {
  if (file.exists(new_path)) "PASS — present" else
    paste0("FAIL — missing ", new_path,
           " (did R/168 run today with SURV_RUN_DATE=", surv_date, "?)")
})

both <- file.exists(ref_path) && file.exists(new_path)

# ==============================================================================
# C. HELPERS
# ==============================================================================

read_txt <- function(path, sheet) {
  read_excel(path, sheet = sheet, col_types = "text", .name_repair = "minimal")
}

same_sheet <- function(sheet) {
  if (!both) return("FAIL — input workbook missing")
  r <- as.data.frame(read_txt(ref_path, sheet))
  n <- as.data.frame(read_txt(new_path, sheet))
  if (!identical(dim(r), dim(n)))
    return(sprintf("FAIL — dims ref %dx%d vs new %dx%d", nrow(r), ncol(r), nrow(n), ncol(n)))
  if (!identical(names(r), names(n)))
    return("FAIL — column names differ")
  rm <- as.matrix(r); nm <- as.matrix(n)
  same      <- (is.na(rm) & is.na(nm)) | (!is.na(rm) & !is.na(nm) & rm == nm)
  diff_cells <- sum(!same)
  if (diff_cells == 0) "PASS — identical cell text" else
    sprintf("FAIL — %d cell(s) differ", diff_cells)
}

key_value <- function(path, label) {
  k <- as.data.frame(read_txt(path, "KEY"))
  k[[2]][k[[1]] == label][1]
}

# ==============================================================================
# D. CHECKS
# ==============================================================================

# D1: Provenance — new workbook KEY records the same R/147 run date as the pointer
run_check("provenance:r147_input_date", function() {
  if (!file.exists(new_path)) return(paste0("FAIL — new workbook missing: ", new_path))
  kv_val <- key_value(new_path, "R/147 input run date")
  if (is.na(kv_val))
    return("FAIL — 'R/147 input run date' label not found in KEY sheet")
  if (is.na(r147_run_date))
    return("FAIL — pointer run_date not available (see input:pointer check)")
  ok <- trimws(kv_val) == trimws(r147_run_date)
  if (ok) {
    paste0("PASS — KEY 'R/147 input run date' = ", kv_val, " matches pointer run_date")
  } else {
    paste0("FAIL — KEY value '", kv_val, "' != pointer run_date '", r147_run_date, "'")
  }
})

# D2: A_rates_summary sheet identical
run_check("A_rates_summary", function() same_sheet("A_rates_summary"))

# D3: B_rates_by_fu_year sheet identical
run_check("B_rates_by_fu_year", function() same_sheet("B_rates_by_fu_year"))

# D4: C_anthracycline_echo sheet identical
# Echo timing comes from primary code set; Phase 163 changed only any-tier/sensitivity
# designation, not primary codes.  Explicit assertion per D-02 / 171-CONTEXT.md.
run_check("C_anthracycline_echo", function() same_sheet("C_anthracycline_echo"))

# D5: QC sheet unchanged vs reference
# The reference workbook (2026-10-08) has n_dates_fail=855 and recon_dates_pass=FALSE
# — a pre-existing condition unrelated to Phase 171 (confirmed Task 0 / D-03: no
# any-tier values flow into this workbook).  Asserting zero would be wrong.
# Instead compare the full QC sheet cell-for-cell, same as A/B/C.
run_check("QC:interval_reconciliation", function() same_sheet("QC"))

# ==============================================================================
# E. FINAL BLOCK (always runs)
# ==============================================================================

n_pass <- 0L; n_fail <- 0L; n_skip <- 0L

cat("\n========== 171 SURVIVORSHIP VERIFICATION RESULTS ==========\n")
for (nm in names(results)) {
  v   <- results[[nm]]
  tag <- if (startsWith(v, "PASS")) {
           n_pass <- n_pass + 1L; "[PASS]"
         } else if (startsWith(v, "SKIP")) {
           n_skip <- n_skip + 1L; "[SKIP]"
         } else {
           n_fail <- n_fail + 1L; "[FAIL]"
         }
  cat(sprintf("%s %s: %s\n", tag, nm, sub("^(PASS|FAIL|SKIP)\\s*—\\s*", "", v)))
}

cat(sprintf("\n%d PASS, %d FAIL, %d SKIP out of %d checks\n",
            n_pass, n_fail, n_skip, length(results)))

if (n_fail == 0) {
  cat("OVERALL: PASS\n")
} else {
  cat(sprintf("OVERALL: FAIL (%d checks)\n", n_fail))
}

sink()
close(con)

# quit() kills the R session when sourced interactively; use a condition instead
if (interactive()) {
  if (n_fail == 0) message("171 verify: OVERALL PASS") else stop("171 verify: OVERALL FAIL")
} else {
  quit(status = if (n_fail == 0) 0 else 1, save = "no")
}
