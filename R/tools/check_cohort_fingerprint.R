# check_cohort_fingerprint.R
# Compares output/cohort_final.rds against the saved fingerprint.
# Prints PASS or FAIL with details. STOP rerun sequence on FAIL.
# Usage: source("R/tools/check_cohort_fingerprint.R", local = new.env(parent = globalenv()))

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(digest)
})

FINGERPRINT_RDS <- here("output", "baselines", "pre_phaseA_20261111_0852",
                         "cohort_final_fingerprint.rds")
COHORT_RDS      <- here("output", "cohort_final.rds")

if (!file.exists(FINGERPRINT_RDS)) stop("Fingerprint not found: ", FINGERPRINT_RDS)
if (!file.exists(COHORT_RDS))      stop("cohort_final.rds not found: ", COHORT_RDS)

fp  <- readRDS(FINGERPRINT_RDS)   # list: n_rows, n_id, sorted_id_md5, col_names
coh <- readRDS(COHORT_RDS)

checks <- list(
  n_rows        = nrow(coh) == fp$n_rows,
  n_unique_id   = dplyr::n_distinct(coh$ID) == fp$n_id,
  sorted_id_md5 = digest::digest(sort(coh$ID), algo = "md5") == fp$sorted_id_md5,
  columns       = identical(sort(names(coh)), sort(fp$col_names))
)

pass   <- all(unlist(checks))
status <- if (pass) "PASS" else "FAIL"

message("cohort_final fingerprint check: ", status)
for (nm in names(checks)) {
  message("  ", nm, ": ", if (checks[[nm]]) "OK" else "MISMATCH")
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
