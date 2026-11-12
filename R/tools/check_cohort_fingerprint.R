# check_cohort_fingerprint.R
# Compares cohort/cohort_final.rds against the saved fingerprint.
# Prints one line per field (OK / MISMATCH) and an overall PASS/FAIL.
# STOP rerun sequence on FAIL or unrecognised baseline format.
# Usage: source("R/tools/check_cohort_fingerprint.R", local = new.env(parent = globalenv()))

suppressPackageStartupMessages({
  library(here)
})

if (!exists("CONFIG")) source("R/00_config.R")
# cohort_fingerprint() is defined in R/utils/utils_io.R, auto-sourced by config.

FINGERPRINT_RDS <- here("output", "baselines", "pre_phaseA_20261111_0852",
                         "cohort_final_fingerprint.rds")
cohort_path     <- file.path(dirname(CONFIG$cache$outputs_dir), "cohort", "cohort_final.rds")

if (!file.exists(FINGERPRINT_RDS)) stop("Fingerprint not found: ", FINGERPRINT_RDS)
if (!file.exists(cohort_path))     stop("cohort_final.rds not found: ", cohort_path)

message("[fingerprint] Comparing against pre-phaseA baseline: ", FINGERPRINT_RDS)

fp  <- readRDS(FINGERPRINT_RDS)
coh <- readRDS(cohort_path)

# Detect unrecognised baseline format before comparing fields
EXPECTED_FIELDS <- c("rows", "ids", "cols", "id_md5")
if (!any(EXPECTED_FIELDS %in% names(fp))) {
  message("BASELINE FORMAT UNRECOGNISED -- fields found: ",
          paste(names(fp), collapse = ", "))
  quit(status = 1L)
}

# Compute fingerprint with the canonical method (utils_io::cohort_fingerprint)
got <- cohort_fingerprint(coh)

# Field-by-field comparison
fields <- c(rows = "rows", ids = "ids", cols = "cols", id_md5 = "id_md5")
all_ok <- TRUE
for (nm in names(fields)) {
  stored  <- fp[[nm]]
  computed <- got[[nm]]
  if (is.null(stored)) {
    message("  ", nm, ": MISSING (field not in fingerprint)")
    all_ok <- FALSE
  } else if (identical(computed, stored)) {
    message("  ", nm, ": OK")
  } else {
    message("  ", nm, ": MISMATCH  expected=", stored, "  got=", computed)
    all_ok <- FALSE
  }
}

status <- if (all_ok) "PASS" else "FAIL"
message("cohort_final fingerprint check: ", status)

if (!all_ok) stop("Fingerprint mismatch -- STOP rerun sequence.")

invisible(TRUE)
