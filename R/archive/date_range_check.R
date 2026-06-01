# ==============================================================================
# Date Range Check: Earliest DIAGNOSIS date, Latest TUMOR_REGISTRY dates
# ==============================================================================
# Quick diagnostic script — run after source("R/01_load_pcornet.R")
# ==============================================================================

source("R/00_config.R")
library(dplyr)
library(lubridate)

# Load tables if not already loaded
if (!exists("pcornet")) source("R/01_load_pcornet.R")

cat("\n============================================================\n")
cat("DATE RANGE CHECK\n")
cat("============================================================\n")

# --- DIAGNOSIS table: earliest date ---
cat("\n--- DIAGNOSIS Table ---\n")

dx <- pcornet$DIAGNOSIS

if (!is.null(dx)) {
  # Check DX_DATE
  dx_dates <- dx$DX_DATE[!is.na(dx$DX_DATE)]
  cat(glue::glue("  DX_DATE: {length(dx_dates)} non-NA values out of {nrow(dx)} rows"), "\n")
  if (length(dx_dates) > 0) {
    cat(glue::glue("  Earliest DX_DATE: {min(dx_dates)}"), "\n")
    cat(glue::glue("  Latest DX_DATE:   {max(dx_dates)}"), "\n")
  }

  # Check ADMIT_DATE
  admit_dates <- dx$ADMIT_DATE[!is.na(dx$ADMIT_DATE)]
  cat(glue::glue("  ADMIT_DATE: {length(admit_dates)} non-NA values out of {nrow(dx)} rows"), "\n")
  if (length(admit_dates) > 0) {
    cat(glue::glue("  Earliest ADMIT_DATE: {min(admit_dates)}"), "\n")
    cat(glue::glue("  Latest ADMIT_DATE:   {max(admit_dates)}"), "\n")
  }
} else {
  cat("  DIAGNOSIS table not loaded\n")
}

# --- TUMOR_REGISTRY tables: latest date ---
cat("\n--- TUMOR_REGISTRY Tables ---\n")

for (tr_name in c("TUMOR_REGISTRY1", "TUMOR_REGISTRY2", "TUMOR_REGISTRY3", "TUMOR_REGISTRY_ALL")) {
  tr <- pcornet[[tr_name]]
  if (is.null(tr)) {
    cat(glue::glue("  {tr_name}: not loaded"), "\n")
    next
  }

  cat(glue::glue("\n  {tr_name} ({format(nrow(tr), big.mark=',')} rows, {ncol(tr)} cols)"), "\n")

  # Find all date columns (Date class or columns with DATE/DT in name)
  date_cols <- names(tr)[sapply(tr, inherits, "Date")]
  date_name_cols <- grep("DATE|_DT$|^DT_|DXDATE", names(tr), value = TRUE, ignore.case = TRUE)
  all_date_cols <- unique(c(date_cols, date_name_cols))

  if (length(all_date_cols) == 0) {
    cat("    No date columns found\n")
    next
  }

  cat(glue::glue("    Date columns found: {length(all_date_cols)}"), "\n")

  # Check each date column for non-NA values
  has_data <- FALSE
  for (col in all_date_cols) {
    vals <- tr[[col]][!is.na(tr[[col]])]
    if (length(vals) > 0) {
      has_data <- TRUE
      cat(glue::glue("    {col}: {length(vals)} non-NA | earliest: {min(vals)} | latest: {max(vals)}"), "\n")
    }
  }

  if (!has_data) {
    cat("    All date columns are 100% NA\n")
  }
}

cat("\n============================================================\n")
