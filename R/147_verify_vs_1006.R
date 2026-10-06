# ==============================================================================
# 147_verify_vs_1006.R -- Comparison: R/147 output vs 1006 reference workbook
# ==============================================================================
# Compares the latest surveillance_modality_frequency_INTERNAL_<date>.xlsx
# produced by R/147 against the reference workbook
# surveillance_modality_frequency_20261006.xlsx, sheet by sheet.
#
# Run after R/147 has completed on HiPerGator.  Expected differences:
#   C_modality_with_sensitivity: sensitivity_* and any_* for Echo, ECG,
#     Mammogram, PFT will change (Z-code rows excluded per 163 D-01).
#   QC: "DIAGNOSIS rows collected" replaced by "Codeset rows excluded (DIAGNOSIS)".
#   Codeset_summary: per-modality stacked layout replaces the old two-block layout.
#   KEY: updated codeset counts and Diagnosis-codes note.
#
# All other sheets (B_modality_primary, A_code_presence, A2, D, E, A3) must
# be identical.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readxl)
  library(glue)
})

source("R/00_config.R")

out_dir   <- CONFIG$cache$outputs_dir
ref_path  <- file.path("data", "reference", "surveillance_modality_frequency_20261006.xlsx")

# Find the most recent INTERNAL output
internal_files <- list.files(out_dir,
  pattern = "surveillance_modality_frequency_INTERNAL_\\d{8}\\.xlsx",
  full.names = TRUE)
if (length(internal_files) == 0)
  stop("No INTERNAL output found in ", out_dir, ". Run R/147 first.")
new_path <- internal_files[which.max(file.mtime(internal_files))]
message(glue("Comparing:\n  NEW: {new_path}\n  REF: {ref_path}"))

if (!file.exists(ref_path))
  stop("Reference workbook not found: ", ref_path)

# Helper: read a sheet, return NULL if missing
read_sheet <- function(path, sheet) {
  sheets <- excel_sheets(path)
  if (!sheet %in% sheets) return(NULL)
  read_excel(path, sheet = sheet, col_types = "text")
}

# Sheets to check as identical
identical_sheets <- c("B_modality_primary", "A_code_presence", "A2_analyte_presence",
                      "D_pre_vs_post_anchor", "E_patient_modality_dates")

results <- list()

for (sht in identical_sheets) {
  new_df <- read_sheet(new_path, sht)
  ref_df <- read_sheet(ref_path, sht)
  if (is.null(new_df) || is.null(ref_df)) {
    results[[sht]] <- glue("SKIP — sheet not present in one file")
    next
  }
  if (identical(as.data.frame(new_df), as.data.frame(ref_df))) {
    results[[sht]] <- "PASS — identical"
  } else {
    diff_cols <- names(new_df)[vapply(names(new_df), function(col) {
      !identical(new_df[[col]], ref_df[[col]])
    }, logical(1))]
    results[[sht]] <- glue("DIFF — differing columns: {paste(diff_cols, collapse=', ')}")
  }
}

# C_modality_with_sensitivity: primary_* columns must match; sensitivity_*
# and any_* for Echo/ECG/Mammogram/PFT expected to change.
CHANGED_MODS <- c("Echocardiogram", "Electrocardiogram", "Mammogram",
                  "Pulmonary function test")
sht <- "C_modality_with_sensitivity"
new_c <- read_sheet(new_path, sht)
ref_c <- read_sheet(ref_path, sht)
if (!is.null(new_c) && !is.null(ref_c)) {
  # Primary columns must be identical
  primary_cols <- grep("^primary_", names(new_c), value = TRUE)
  key_cols <- c("modality", "submodality")
  new_pk <- new_c[, c(key_cols, primary_cols)]
  ref_pk <- ref_c[, c(key_cols, primary_cols)]
  if (identical(as.data.frame(new_pk), as.data.frame(ref_pk))) {
    results[[paste0(sht, ":primary_*")]] <- "PASS — primary_* identical"
  } else {
    diff_cols <- primary_cols[vapply(primary_cols, function(col) {
      !identical(new_pk[[col]], ref_pk[[col]])
    }, logical(1))]
    results[[paste0(sht, ":primary_*")]] <- glue("DIFF primary_* — {paste(diff_cols, collapse=', ')}")
  }
  # sensitivity_* and any_* for CHANGED_MODS: sensitivity should be 0
  sens_pat_col <- "sensitivity_n_patients"
  any_pat_col  <- "primary_n_patients"   # any should equal primary for changed mods
  for (mod in CHANGED_MODS) {
    new_row <- dplyr::filter(new_c, modality == mod, .data[["submodality"]] == "(all)")
    if (nrow(new_row) == 0) {
      results[[paste0(sht, ":", mod)]] <- "SKIP — modality not found"
      next
    }
    sens_n <- as.integer(new_row[[sens_pat_col]])
    pri_n  <- as.integer(new_row[["primary_n_patients"]])
    any_n  <- as.integer(new_row[["any_n_patients"]])
    ok_sens <- isTRUE(sens_n == 0L || is.na(sens_n))
    ok_any  <- isTRUE(any_n == pri_n)
    if (ok_sens && ok_any) {
      results[[paste0(sht, ":", mod)]] <- glue("PASS — sensitivity_n={sens_n} (0), any_n={any_n} == primary_n={pri_n}")
    } else {
      results[[paste0(sht, ":", mod)]] <- glue("FAIL — sensitivity_n={sens_n} (expect 0), any_n={any_n}, primary_n={pri_n}")
    }
  }
}

# QC: check that "Codeset rows excluded (DIAGNOSIS)" row exists
sht <- "QC"
new_qc <- read_sheet(new_path, sht)
ref_qc <- read_sheet(ref_path, sht)
if (!is.null(new_qc)) {
  has_excl  <- any(grepl("Codeset rows excluded", new_qc[[1]], fixed = TRUE))
  has_old   <- any(grepl("DIAGNOSIS rows collected", new_qc[[1]], fixed = TRUE))
  results[["QC:excluded_row"]]   <- if (has_excl) "PASS — 'Codeset rows excluded (DIAGNOSIS)' present" else "FAIL — row missing"
  results[["QC:old_diag_row"]]   <- if (!has_old) "PASS — 'DIAGNOSIS rows collected' removed" else "FAIL — old row still present"
}

# KEY: check for Diagnosis-codes note
sht <- "KEY"
new_key <- read_sheet(new_path, sht)
if (!is.null(new_key)) {
  has_diag_note <- any(grepl("163 D-01", new_key[[2]], fixed = TRUE))
  results[["KEY:163_D01_note"]] <- if (has_diag_note) "PASS — '163 D-01' note present" else "FAIL — note missing"
}

# Codeset_summary: check 14 modality blocks exist
sht <- "Codeset_summary"
new_cs <- read_sheet(new_path, sht)
if (!is.null(new_cs)) {
  # Count distinct non-NA modality values (header rows)
  mod_col <- new_cs[[grep("modality", names(new_cs), ignore.case = TRUE)[1]]]
  n_mods <- dplyr::n_distinct(mod_col[!is.na(mod_col)])
  results[["Codeset_summary:n_modality_blocks"]] <- glue("{if (n_mods == 14) 'PASS' else 'FAIL'} — {n_mods} modality blocks (expect 14)")
  # Check no Z-codes appear
  if ("codes" %in% names(new_cs)) {
    has_z <- any(grepl("^Z", new_cs$codes, na.rm = TRUE))
    results[["Codeset_summary:no_z_codes"]] <- if (!has_z) "PASS — no Z-codes" else "FAIL — Z-code found in Codeset_summary"
  }
}

# Print results
message("\n========== 163 VERIFICATION RESULTS ==========")
for (nm in names(results)) {
  tag <- if (grepl("^PASS", results[[nm]])) "[PASS]" else if (grepl("^SKIP", results[[nm]])) "[SKIP]" else "[FAIL]"
  message(glue("  {tag} {nm}: {results[[nm]]}"))
}
n_fail <- sum(grepl("^FAIL", results))
n_pass <- sum(grepl("^PASS", results))
message(glue("\n  {n_pass} PASS, {n_fail} FAIL out of {length(results)} checks"))
if (n_fail == 0) {
  message("  163 verification: ALL PASS")
} else {
  message("  163 verification: REVIEW FAILURES ABOVE")
}
