# ==============================================================================
# 193_tr_lymphoma_flags_all_patients.R
# ==============================================================================
#
# Purpose:
#   Patient-level tumor-registry HL / NHL flags for EVERY patient in the extract
#   (DEMOGRAPHIC), independent of the Gantt population. Uses the same helper as
#   R/142 Section 4C5 (build_tr_lymphoma_flags), so values match gantt_episodes_180.
#
# Inputs:
#   - DEMOGRAPHIC (all IDs)
#   - TUMOR_REGISTRY_ALL (via build_tr_lymphoma_flags)
#   - ICD_CODES$hl_histology / ICD_CODES$nhl_histology (R/00_config.R)
#
# Outputs:
#   - output/tr_lymphoma_flags_all_patients_YYYYMMDD.csv
#       ID, tr_hl_dx, tr_nhl_dx
#       TRUE  = in tumor registry with matching histology
#       FALSE = in tumor registry, no matching histology
#       blank = not in any tumor registry table
#
# Caveat: ICD_CODES$nhl_histology is UNVERIFIED (Phase 201 D-201-03).
#
# Standalone. Not registered in R/39. Run interactively on HiPerGator:
#   module load R/4.5; R --no-save
#   source("R/193_tr_lymphoma_flags_all_patients.R", local = new.env(parent = globalenv()))
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_cancer.R")

message("=== R/193: Tumor-registry HL/NHL flags, all patients ===\n")

fmt_sup <- function(n) if (n >= 1L && n <= 10L) "<11" else format(n, big.mark = ",")

# --- SECTION 1: ALL PATIENT IDS (DEMOGRAPHIC) ---
# get_pcornet_table() needs an open connection; close it before the helper,
# which opens and closes its own.
open_pcornet_con()
all_ids <- get_pcornet_table("DEMOGRAPHIC") |>
  distinct(ID) |>
  collect() |>
  pull(ID)
close_pcornet_con()
all_ids <- unique(all_ids[!is.na(all_ids) & all_ids != ""])
message(glue("  DEMOGRAPHIC patients: {format(length(all_ids), big.mark = ',')}"))

# --- SECTION 2: TUMOR-REGISTRY FLAGS ---
trf <- build_tr_lymphoma_flags(all_ids)

out <- trf |>
  select(ID = patient_id, tr_hl_dx, tr_nhl_dx) |>
  arrange(ID)

stopifnot(
  "one row per patient"               = !anyDuplicated(out$ID),
  "covers every DEMOGRAPHIC patient"  = setequal(out$ID, all_ids),
  "tr_hl_dx / tr_nhl_dx share NA set" = all(is.na(out$tr_hl_dx) == is.na(out$tr_nhl_dx))
)

# --- SECTION 3: WRITE ---
out_path <- file.path(
  CONFIG$output_dir,
  paste0("tr_lymphoma_flags_all_patients_", format(Sys.Date(), "%Y%m%d"), ".csv")
)
write.csv(out, out_path, row.names = FALSE, na = "")
message(glue("  Wrote {out_path} ({format(nrow(out), big.mark = ',')} patients, 3 columns)"))

# --- SECTION 4: QC (suppressed) ---
n_in_tr <- sum(!is.na(out$tr_hl_dx))
message("\n  === QC ===")
message(glue("  In tumor registry:      {fmt_sup(n_in_tr)}"))
message(glue("  Not in tumor registry:  {fmt_sup(sum(is.na(out$tr_hl_dx)))}"))
message(glue("  tr_hl_dx  TRUE {fmt_sup(sum(out$tr_hl_dx,  na.rm = TRUE))} / FALSE {fmt_sup(sum(!out$tr_hl_dx,  na.rm = TRUE))}"))
message(glue("  tr_nhl_dx TRUE {fmt_sup(sum(out$tr_nhl_dx, na.rm = TRUE))} / FALSE {fmt_sup(sum(!out$tr_nhl_dx, na.rm = TRUE))}"))
message(glue("  Both TRUE:              {fmt_sup(sum(out$tr_hl_dx & out$tr_nhl_dx, na.rm = TRUE))}"))

# Cross-check vs Phase 201 TR-HL-not-in-Gantt list (if present)
miss_path <- file.path(CONFIG$output_dir, "internal", "tr_hl_not_in_gantt_180.csv")
if (file.exists(miss_path)) {
  miss <- read.csv(miss_path, colClasses = "character")
  n_found <- sum(miss$ID %in% out$ID[out$tr_hl_dx %in% TRUE])
  message(glue("  Phase 201 TR-HL-not-in-Gantt patients present here with tr_hl_dx TRUE: {fmt_sup(n_found)} of {fmt_sup(nrow(miss))}"))
}

message("  CAVEAT: nhl_histology list is UNVERIFIED (D-201-03).")
message("\n=== R/193 complete ===")