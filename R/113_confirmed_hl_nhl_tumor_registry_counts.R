# ==============================================================================
# 113_confirmed_hl_nhl_tumor_registry_counts.R -- Confirmed HL/NHL TUMOR_REGISTRY Counts (quick-260716)
# ==============================================================================
# Purpose:     Read-only diagnostic that answers "how many patients are
#              'confirmed' Hodgkin Lymphoma (HL) / Non-Hodgkin Lymphoma (NHL)
#              in the tumor registry data" using ONLY TUMOR_REGISTRY histology
#              codes (TR1.HISTOLOGICAL_TYPE, TR2/TR3.MORPH), matched against
#              ICD_CODES$hl_histology / ICD_CODES$nhl_histology via
#              substr(x, 1, 4).
#
#              THIS IS DELIBERATELY NARROWER than the project's production HL
#              cohort definition. has_hodgkin_diagnosis() in
#              R/10_cohort_predicates.R combines BOTH the DIAGNOSIS table
#              (ICD-9/ICD-10 dx codes) AND TUMOR_REGISTRY_ALL histology codes.
#              This script does NOT query the DIAGNOSIS table at all -- it
#              only counts patients "confirmed" via a tumor-registry
#              histology entry. Do not treat these counts as equivalent to
#              the pipeline's HL cohort size.
#
#              *** NHL CODE LIST VALIDATION CAVEAT ***
#              ICD_CODES$nhl_histology (R/00_config.R) is UNVERIFIED: it was
#              assembled from general SEER/WHO ICD-O-3 hematopoietic/lymphoid
#              neoplasm knowledge, but has NOT been cross-checked against this
#              project's actual TUMOR_REGISTRY extract, nor reviewed by a
#              clinical or tumor-registry SME. Do NOT use the NHL (or overlap)
#              counts below in any authoritative report until a registry
#              reviewer has validated that code list. (ICD_CODES$hl_histology
#              has no such caveat -- it is the project's existing, already-used
#              HL code list.)
#
# Inputs:      PCORnet TUMOR_REGISTRY_ALL (TR1+TR2+TR3 union) via
#              get_pcornet_table("TUMOR_REGISTRY_ALL")
#              ICD_CODES$hl_histology / ICD_CODES$nhl_histology (R/00_config.R)
#
# Outputs:     (Console only) three headline distinct-patient counts:
#              Confirmed HL, Confirmed NHL, Confirmed BOTH (overlap), plus the
#              NHL validation caveat printed at both the top and bottom of the
#              console output. No file is written.
#
# Dependencies: R/00_config.R (ICD_CODES$hl_histology / ICD_CODES$nhl_histology)
#               R/01_load_pcornet.R (backend-transparent loader; builds
#               get_pcornet_table("TUMOR_REGISTRY_ALL") in both RDS/in-memory
#               and DuckDB-cache modes)
#               dplyr, glue
#
# Requirements: quick-260716
#
# Usage:       Rscript R/113_confirmed_hl_nhl_tumor_registry_counts.R
#              source("R/113_confirmed_hl_nhl_tumor_registry_counts.R")
#
# Note:        Read-only, console-only diagnostic -- writes no output file and
#              does not touch DIAGNOSIS-table-based cohort logic. Verified via
#              a local end-to-end run against tests/fixtures/ during planning
#              (R_TESTING_ENV=local); TUMOR_REGISTRY1/2/3 fixtures are
#              header-only, so local runs correctly report 0/0/0 counts -- the
#              point of the local run is proving the access pattern works, not
#              exercising non-empty match data.
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND LIBRARIES ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

message("=== quick-260716: Confirmed HL/NHL TUMOR_REGISTRY Counts ===\n")

message("*** NHL CODE LIST VALIDATION CAVEAT ***")
message("ICD_CODES$nhl_histology is UNVERIFIED -- assembled from general SEER/WHO")
message("ICD-O-3 knowledge, NOT cross-checked against this project's TUMOR_REGISTRY")
message("extract, NOT reviewed by a clinical/tumor-registry SME. Do not use the")
message("NHL / overlap counts below authoritatively until reviewed.\n")

message("This script counts patients confirmed via TUMOR_REGISTRY histology codes")
message("ONLY (TR1 HISTOLOGICAL_TYPE, TR2/TR3 MORPH). It does NOT query the")
message("DIAGNOSIS table, and is deliberately narrower than has_hodgkin_diagnosis()'s")
message("combined DIAGNOSIS + TUMOR_REGISTRY definition in R/10_cohort_predicates.R.\n")


# ==============================================================================
# SECTION 2: FETCH TUMOR_REGISTRY_ALL ----
# ==============================================================================

# NULL-guard: use tryCatch since get_pcornet_table() returns tbl_dbi (never NULL)
# in DuckDB mode but may error/return NULL depending on backend state.
tr_all_tbl <- tryCatch(get_pcornet_table("TUMOR_REGISTRY_ALL"), error = function(e) NULL)

if (is.null(tr_all_tbl)) {
  message("WARNING: TUMOR_REGISTRY_ALL table not available -- all counts will be 0.")
}


# ==============================================================================
# SECTION 3: HELPER -- CONFIRMED-ID MATCHING ----
# ==============================================================================

# Reusable helper mirroring has_hodgkin_diagnosis()'s TUMOR_REGISTRY matching
# block (R/10_cohort_predicates.R): checks HISTOLOGICAL_TYPE (TR1) and MORPH
# (TR2/TR3) via substr(x, 1, 4) %in% code_list, materializes, and returns
# distinct patient IDs. Called once per code list (hl_histology, nhl_histology)
# to avoid duplicating this logic.
get_confirmed_ids <- function(code_list) {
  if (is.null(tr_all_tbl)) return(character(0))
  tr_cols <- colnames(tr_all_tbl)

  hist_match <- if ("HISTOLOGICAL_TYPE" %in% tr_cols) {
    tr_all_tbl %>%
      filter(substr(as.character(HISTOLOGICAL_TYPE), 1, 4) %in% code_list) %>%
      distinct(ID)
  } else {
    tibble(ID = character())
  }

  morph_match <- if ("MORPH" %in% tr_cols) {
    tr_all_tbl %>%
      filter(substr(as.character(MORPH), 1, 4) %in% code_list) %>%
      distinct(ID)
  } else {
    tibble(ID = character())
  }

  bind_rows(materialize(hist_match), materialize(morph_match)) %>%
    distinct(ID) %>%
    pull(ID)
}

message("--- Matching TUMOR_REGISTRY histology codes ---")

hl_ids  <- get_confirmed_ids(ICD_CODES$hl_histology)
nhl_ids <- get_confirmed_ids(ICD_CODES$nhl_histology)


# ==============================================================================
# SECTION 4: COMPUTE AND PRINT COUNTS ----
# ==============================================================================

n_hl      <- length(unique(hl_ids))
n_nhl     <- length(unique(nhl_ids))
n_overlap <- length(intersect(unique(hl_ids), unique(nhl_ids)))

message(glue("\n=== Confirmed HL/NHL TUMOR_REGISTRY Counts (headline) ==="))
message(glue("  Confirmed HL patients:          {format(n_hl,      big.mark = ',')}"))
message(glue("  Confirmed NHL patients:         {format(n_nhl,     big.mark = ',')}"))
message(glue("  Confirmed BOTH (overlap):       {format(n_overlap, big.mark = ',')}"))
message(glue("\n  Source: TUMOR_REGISTRY_ALL histology codes only (TR1 HISTOLOGICAL_TYPE,"))
message(glue("  TR2/TR3 MORPH) -- DIAGNOSIS table NOT queried. Narrower than the"))
message(glue("  pipeline's has_hodgkin_diagnosis() cohort definition."))
message(glue("\n  REMINDER: ICD_CODES$nhl_histology is UNVERIFIED (not clinically/registry"))
message(glue("  reviewed) -- do not use the NHL / overlap counts above authoritatively."))

message("\nDone. (quick-260716)")
