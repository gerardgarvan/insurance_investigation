# check_cohort_fingerprint.R
# Compares cohort/cohort_final.rds against the saved fingerprint.
# Prints PASS or FAIL with details. STOP rerun sequence on FAIL.
# Usage: source("R/tools/check_cohort_fingerprint.R", local = new.env(parent = globalenv()))

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(digest)
})

if (!exists("CONFIG")) source("R/00_config.R")

FINGERPRINT_RDS <- here("output", "baselines", "pre_phaseA_20261111_0852",
                         "cohort_final_fingerprint.rds")
# cohort/ sits adjacent to cache/outputs/; not under output/ root
cohort_path     <- file.path(dirname(CONFIG$cache$outputs_dir), "cohort", "cohort_final.rds")
COHORT_RDS      <- cohort_path

baseline_path   <- FINGERPRINT_RDS

if (!file.exists(FINGERPRINT_RDS)) stop("Fingerprint not found: ", FINGERPRINT_RDS)
if (!file.exists(COHORT_RDS))      stop("cohort_final.rds not found: ", COHORT_RDS)

message("[fingerprint] Comparing against pre-phaseA baseline: ", baseline_path)

fp  <- readRDS(FINGERPRINT_RDS)   # list: n_rows, n_id, sorted_id_md5, col_names
coh <- readRDS(COHORT_RDS)

safe_eq <- function(computed, stored) {
  if (is.null(stored)) return(NA)   # field absent from fingerprint -> MISSING
  v <- (computed == stored)
  if (length(v) != 1L || is.na(v)) return(FALSE)
  v
}

checks <- list(
  n_rows        = safe_eq(nrow(coh),                                      fp$n_rows),
  n_unique_id   = safe_eq(dplyr::n_distinct(coh$ID),                      fp$n_id),
  sorted_id_md5 = safe_eq(digest::digest(sort(coh$ID), algo = "md5"),     fp$sorted_id_md5),
  columns       = if (is.null(fp$col_names)) NA
                  else isTRUE(identical(sort(names(coh)), sort(fp$col_names)))
)

pass   <- all(vapply(checks, isTRUE, logical(1)))
status <- if (pass) "PASS" else "FAIL"

label_check <- function(v) {
  if (is.na(v))    "MISSING (field not in fingerprint)"
  else if (isTRUE(v)) "OK"
  else "MISMATCH"
}

message("cohort_final fingerprint check: ", status)
for (nm in names(checks)) {
  message("  ", nm, ": ", label_check(checks[[nm]]))
}

if (!pass) {
  message("Expected: n_rows=", fp$n_rows, " n_id=", fp$n_id,
          " md5=", fp$sorted_id_md5)
  message("Got:      n_rows=", nrow(coh),
          " n_id=", dplyr::n_distinct(coh$ID),
          " md5=", digest::digest(sort(coh$ID), algo = "md5"))
  stop("Fingerprint mismatch -- STOP rerun sequence.")
}

invisible(pass)
