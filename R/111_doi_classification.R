# ==============================================================================
# 111_doi_classification.R -- Diagnosis-of-Interest (DoI) Classification
# ==============================================================================
# Purpose:     CLASSIFICATION-ONLY investigation script that produces encounter-
#              level DoI classification across the FULL DIAGNOSIS extract (all
#              patients, all diagnosis positions P+S). Pulls DIAGNOSIS via a
#              DuckDB-native 3-char prefix pushdown so only DoI-candidate rows
#              are ever materialized into R. Classifies codes with is_doi_code()
#              + classify_doi_codes() from utils_doi.R (Phase 127), runs a
#              mutual-exclusivity hard-stop guaranteeing no oncology code leaks
#              into the DoI layer, attaches paraneoplastic_flag for L10.81, tags
#              in_hl_cohort membership, and writes doi_encounters.rds.
#
# Inputs:      DuckDB DIAGNOSIS table (ID, ENCOUNTERID, DX, DX_TYPE, DX_DATE)
#              DOI_CODE_MAP / DOI_CODE_TIER / RITDIS_CODE_VERSION (R/00_config.R)
#              get_hl_patient_ids() -> character vector (utils_treatment.R)
#
# Outputs:     doi_encounters.rds (encounter grain):
#                Columns: ID, ENCOUNTERID, DX_DATE, doi_code, doi_category,
#                         paraneoplastic_flag, in_hl_cohort
#              (Console) prefix count, materialized row count, HL cohort size,
#                         mutual-exclusivity result, doi_encounters row count.
#
# Dependencies: R/00_config.R (DOI_CODE_MAP, DOI_CODE_TIER, RITDIS_CODE_VERSION,
#               CONFIG$cache$outputs_dir; auto-sources utils_duckdb + utils_dates +
#               utils_treatment + utils_cancer)
#               R/utils/utils_duckdb.R (open_pcornet_con, get_pcornet_table,
#                                       close_pcornet_con)
#               R/utils/utils_dates.R  (parse_pcornet_date)
#               R/utils/utils_treatment.R (get_hl_patient_ids)
#               R/utils/utils_doi.R    (is_doi_code, classify_doi_codes)
#               R/utils/utils_cancer.R (is_cancer_code -- mutual-exclusivity check)
#               tidyverse ecosystem: dplyr, glue, stringr, lubridate, janitor
#
# Requirements: DOI-CLASS-02 (encounter-level DoI flag + category artifact),
#               DOI-CLASS-04 (mutual-exclusivity hard-stop; DuckDB-native prefix
#                             filter — no full-table load),
#               DOI-CLASS-05 (L10.81 paraneoplastic_flag while remaining Pemphigus)
#
# Usage:       Rscript R/111_doi_classification.R
#              source("R/111_doi_classification.R")
#
# Note:        Structural-only verification on Windows (no Rscript against real
#              DuckDB); full run with real DIAGNOSIS counts is HiPerGator ONLY.
#              READ-ONLY w.r.t. utils_cancer.R, R/28, and treatment_episodes.rds.
#              Registration (R/39, SCRIPT_INDEX, R/88) is Phase 130 — this script
#              is structured to fit those conventions but is NOT yet registered.
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND LIBRARIES ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(lubridate)
  library(janitor)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")

# Defensive sourcing: utils_treatment / utils_doi / utils_cancer may already be
# loaded via R/00_config.R auto-source glob; only re-source if absent.
if (!exists("get_hl_patient_ids")) source("R/utils/utils_treatment.R")
if (!exists("is_doi_code"))        source("R/utils/utils_doi.R")
if (!exists("is_cancer_code"))     source("R/utils/utils_cancer.R")

message(glue("=== R/111 DoI Classification (code version {RITDIS_CODE_VERSION}) ==="))


# ==============================================================================
# SECTION 2: PREFIX LIST FOR DUCKDB PUSHDOWN ----
# ==============================================================================

# Build the 3-char pushdown prefix set from DOI_CODE_MAP keys. DuckDB receives
# LEFT(DX,3) IN (...), which safely over-captures at 3-char granularity. The
# 4-char disambiguation keys (D692, D693, H460, H461, H468, H469, D891) share a
# 3-char prefix (D69, H46, D89) that is already in this list; classify_doi_codes()
# then applies the 4-char-before-3-char cascade to resolve them precisely in R.
doi_prefixes3 <- unique(substr(names(DOI_CODE_MAP), 1, 3))

message(glue(
  "DoI 3-char pushdown prefixes: {length(doi_prefixes3)} -> ",
  "{paste(sort(doi_prefixes3), collapse = ', ')}"
))


# ==============================================================================
# SECTION 3: SELF-BOOTSTRAP DUCKDB ----
# ==============================================================================

# Mirror R/107 Section 3: open_pcornet_con() is idempotent; running standalone
# in a fresh session requires the connection to be established here if not already.
USE_DUCKDB <- TRUE
if (!exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}


# ==============================================================================
# SECTION 4: NATIVE PREFIX PULL FROM DIAGNOSIS ----
# ==============================================================================

# Fetch the HL cohort ID set once before the DuckDB pull so it is available for
# the in_hl_cohort tag in Section 5.
hl_ids <- get_hl_patient_ids()
message(glue("HL cohort size for in_hl_cohort tag: {format(length(hl_ids), big.mark = ',')}"))

dx_tbl <- get_pcornet_table("DIAGNOSIS")
if (is.null(dx_tbl)) stop("DIAGNOSIS table not found in DuckDB — cannot classify DoI.")

# The DuckDB-native LEFT(DX,3) IN (...) pushdown executes entirely in DuckDB
# BEFORE the result is collected into R — the full multi-million-row DIAGNOSIS
# table is never loaded into R memory (DOI-CLASS-04 design constraint #4, D-01).
# Classifies ALL diagnosis positions (P+S), NOT principal-only (D-03).
doi_raw <- dx_tbl %>%
  filter(!is.na(DX), DX_TYPE %in% c("09", "10")) %>%
  filter(substr(DX, 1, 3) %in% doi_prefixes3) %>%   # DuckDB pushdown: runs in SQL before R collects
  select(ID, ENCOUNTERID, DX, DX_TYPE, DX_DATE) %>%
  collect()

message(glue("Prefix-filtered DIAGNOSIS rows materialized: {format(nrow(doi_raw), big.mark = ',')}"))


# ==============================================================================
# SECTION 5: CLASSIFY + FLAGS ----
# ==============================================================================

doi_enc <- doi_raw %>%
  mutate(
    is_doi       = is_doi_code(DX, DX_TYPE),
    doi_category = classify_doi_codes(DX)
  ) %>%
  filter(is_doi, !is.na(doi_category)) %>%        # drop over-captured non-DoI rows (e.g. D69 non-vasculitis/ITP)
  mutate(
    doi_code           = DX,
    DX_DATE            = parse_pcornet_date(DX_DATE),
    # paraneoplastic_flag marks L10.81 (paraneoplastic pemphigus) — it STILL
    # counts as DoI and stays in doi_category 'Pemphigus' (D-04); the flag is a
    # per-encounter caveat, NOT a separate category (DOI-CLASS-05).
    paraneoplastic_flag = str_remove(toupper(DX), "\\.") %in% c("L1081"),  # L10.81 (D-04, DOI-CLASS-05)
    in_hl_cohort        = ID %in% hl_ids
  ) %>%
  # 1900 sentinel filtering per prior pipeline practice — Claude's-discretion
  # item in 128-CONTEXT. Rows with a valid parsed date that is the 1900 sentinel
  # (erroneous default date from some PCORnet sites) are dropped; NA dates kept.
  filter(is.na(DX_DATE) | year(DX_DATE) != 1900L)

message(glue("DoI-classified encounter rows after refinement: {format(nrow(doi_enc), big.mark = ',')}"))

# Clinical plausibility review: count by DoI category
message("--- DoI category distribution ---")
print(tabyl(doi_enc, doi_category))


# ==============================================================================
# SECTION 6: MUTUAL-EXCLUSIVITY HARD-STOP (DOI-CLASS-04) ----
# ==============================================================================

# HARD-STOP: zero tolerance for a code that maps to BOTH the DoI and cancer layers.
# Runs on the classified DoI rows BEFORE any artifact is written. Halts the script
# if non-zero.
overlap_n <- sum(is_doi_code(doi_enc$DX, doi_enc$DX_TYPE) & is_cancer_code(doi_enc$DX))
message(glue("Mutual-exclusivity check: {overlap_n} codes classify as BOTH DoI and cancer (must be 0)."))
stopifnot(
  "DOI-CLASS-04 mutual-exclusivity violated: a code maps to both DoI and cancer layers" = overlap_n == 0
)


# ==============================================================================
# SECTION 6b: WRITE doi_encounters.rds ----
# ==============================================================================

# INTERNAL-ONLY investigation output: raw counts, NO automated small-cell suppression
# (Phase 127 D-07). Suppress manually before external sharing.
doi_encounters <- doi_enc %>%
  select(ID, ENCOUNTERID, DX_DATE, doi_code, doi_category, paraneoplastic_flag, in_hl_cohort)

doi_encounters_path <- file.path(CONFIG$cache$outputs_dir, "doi_encounters.rds")
saveRDS(doi_encounters, doi_encounters_path, compress = TRUE)
message(glue(
  "Wrote doi_encounters.rds: {format(nrow(doi_encounters), big.mark = ',')} rows -> ",
  "{doi_encounters_path}"
))

# close_pcornet_con() is called at the end of Section 7 (patient-grain rollup,
# Plan 128-02). Plan 02 reads doi_encounters in-memory (DuckDB-free), so the
# connection can remain open through that section.

# ==============================================================================
# End of R/111 Sections 1-6 (Plan 128-01).
# Plan 128-02 appends Section 7: patient-grain rollup (doi_patients.rds)
# + close_pcornet_con() teardown.
# ==============================================================================
