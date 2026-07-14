# ==============================================================================
# 108_build_ndc_rxnorm_crosswalk.R -- NDC -> RxNorm Crosswalk Builder
# ==============================================================================
# Purpose:     ONE-TIME HiPerGator-only build step. Harvests all distinct NDC
#              codes from DISPENSING (NDC column) and MED_ADMIN
#              (MEDADMIN_CODE where MEDADMIN_TYPE == "ND"), normalises each to
#              11-digit no-hyphen format, resolves each via the NLM RxNav
#              rxcui.json?idtype=NDC endpoint, and writes two artefacts:
#
#                data/reference/ndc_rxnorm_crosswalk.rds
#                   Named character vector: NDC (11-digit) -> RxCUI string.
#                   Contains only successfully resolved entries (misses dropped).
#                   Loaded by load_ndc_crosswalk() in utils_treatment.R.
#
#                output/ndc_rxnorm_crosswalk_audit.csv
#                   Columns: NDC, rxcui, lookup_status ("matched" / "miss").
#                   Full record of every NDC attempted, including misses.
#
#              OFFLINE AFTER BUILD: once the .rds is built and committed, all
#              pipeline consumers load it via load_ndc_crosswalk() with no
#              network access at pipeline run time.
#
#              Not every NDC resolves (comorbidity medications, unknown codes).
#              Misses degrade gracefully — the crosswalk simply has no entry for
#              that NDC and the consumer's chemo-match filter excludes it.
#
# Inputs:      DuckDB DISPENSING table  -- NDC column
#              DuckDB MED_ADMIN table   -- MEDADMIN_CODE where MEDADMIN_TYPE=="ND"
#
# Outputs:     data/reference/ndc_rxnorm_crosswalk.rds  (named char: NDC->RxCUI)
#              output/ndc_rxnorm_crosswalk_audit.csv     (NDC, rxcui, lookup_status)
#
# Dependencies:
#   httr2     -- RxNav API HTTP calls with retry / timeout
#   purrr     -- map_chr() batch over NDC vector
#   dplyr     -- filter / mutate / select / distinct / bind_rows
#   stringr   -- normalize_ndc() string operations
#   glue      -- progress and summary messages
#   here      -- project-relative output paths
#   R/00_config.R (TREATMENT_CODES, CONFIG, auto-sources utils_treatment + utils_duckdb)
#   R/utils/utils_duckdb.R (open_pcornet_con, get_pcornet_table, close_pcornet_con)
#
# Requirements: D-02 (NDC-coded DISPENSING + MED_ADMIN ND rows resolve to RxNorm)
#               D-03 (D-12 revised: NDC matching now in scope)
#
# Usage:       Rscript R/108_build_ndc_rxnorm_crosswalk.R
#              source("R/108_build_ndc_rxnorm_crosswalk.R")
#
# REGISTRATION NOTE: This is a ONE-TIME data-preparation utility — NOT wired
#              into R/39 (investigation runner) and NOT covered by R/88 structural
#              sections. Registration is limited to R/SCRIPT_INDEX.md only,
#              mirroring the R/107 precedent. R/88 Section 15t Check 7 confirms
#              this file exists.
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND LIBRARIES ----
# ==============================================================================

suppressPackageStartupMessages({
  library(httr2)
  library(purrr)
  library(dplyr)
  library(stringr)
  library(glue)
  library(here)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")

# Defensive load of utils_treatment (auto-sourced via R/00_config.R in normal
# flow; sourced explicitly here for standalone Rscript runs).
if (!exists("normalize_ndc")) {
  source("R/utils/utils_treatment.R")
}

message("=== R/108: NDC -> RxNorm Crosswalk Builder ===\n")


# ==============================================================================
# SECTION 2: SELF-BOOTSTRAP DUCKDB ----
# ==============================================================================

# Self-bootstrap the DuckDB connection so R/108 runs standalone in a fresh
# session (consistent with R/107, R/27). open_pcornet_con() is idempotent.
USE_DUCKDB <- TRUE
if (!exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}


# ==============================================================================
# SECTION 3: HARVEST DISTINCT NDCs ----
# ==============================================================================

message("--- SECTION 3: Harvesting distinct NDCs ---\n")

# 3a. DISPENSING — NDC column (non-missing, non-blank)
disp_tbl <- tryCatch(
  get_pcornet_table("DISPENSING"),
  error = function(e) {
    message(glue("  [DISPENSING] table not found: {e$message}"))
    NULL
  }
)

ndc_from_dispensing <- character(0)
if (!is.null(disp_tbl) && "NDC" %in% colnames(disp_tbl)) {
  ndc_from_dispensing <- disp_tbl |>
    dplyr::filter(!is.na(NDC), NDC != "") |>
    dplyr::distinct(NDC) |>
    dplyr::pull(NDC)
  message(glue("  DISPENSING: {length(ndc_from_dispensing)} distinct raw NDC values"))
} else {
  message("  DISPENSING: table absent or NDC column missing — skipping")
}

# 3b. MED_ADMIN — MEDADMIN_CODE where MEDADMIN_TYPE == "ND" (non-missing)
ma_tbl <- tryCatch(
  get_pcornet_table("MED_ADMIN"),
  error = function(e) {
    message(glue("  [MED_ADMIN] table not found: {e$message}"))
    NULL
  }
)

ndc_from_med_admin <- character(0)
if (!is.null(ma_tbl) &&
    all(c("MEDADMIN_TYPE", "MEDADMIN_CODE") %in% colnames(ma_tbl))) {
  ndc_from_med_admin <- ma_tbl |>
    dplyr::filter(MEDADMIN_TYPE == "ND", !is.na(MEDADMIN_CODE), MEDADMIN_CODE != "") |>
    dplyr::distinct(MEDADMIN_CODE) |>
    dplyr::pull(MEDADMIN_CODE)
  message(glue("  MED_ADMIN ND-typed: {length(ndc_from_med_admin)} distinct raw NDC values"))
} else {
  message("  MED_ADMIN: table absent or required columns missing — skipping")
}

# 3c. Union, normalise to 11-digit no-hyphen, deduplicate
raw_ndc_union <- unique(c(ndc_from_dispensing, ndc_from_med_admin))
ndc_vec       <- unique(normalize_ndc(raw_ndc_union))
ndc_vec       <- ndc_vec[!is.na(ndc_vec) & ndc_vec != ""]

message(glue(
  "\n  Total distinct NDCs after union + normalise: {length(ndc_vec)}\n"
))
message("  (API calls will follow — one per NDC at ~0.1 s spacing)\n")

if (length(ndc_vec) == 0) {
  message("  No NDCs to resolve. Exiting without writing outputs.")
  stop("No NDC values harvested from DISPENSING or MED_ADMIN — cannot build crosswalk.")
}


# ==============================================================================
# SECTION 4: RxNAV LOOKUP FUNCTION ----
# ==============================================================================

#' Look up a single NDC code via NLM RxNav rxcui.json?idtype=NDC
#'
#' Uses httr2 with a 10-second timeout and up to 3 retries on transient HTTP
#' errors (429 Too Many Requests, 503 Service Unavailable, 504 Gateway Timeout).
#' Returns NA_character_ on any failure or miss (idGroup$rxnormId absent/empty).
#' Sleeps sleep_sec seconds after every call to respect the RxNav rate limit.
#'
#' @param ndc       Character. 11-digit no-hyphen normalised NDC.
#' @param sleep_sec Numeric. Seconds to sleep after request (default 0.1 = 10 req/s).
#' @return Character scalar: RxCUI string, or NA_character_ if not found / error.
lookup_ndc_to_rxcui <- function(ndc, sleep_sec = 0.1) {
  url <- glue::glue(
    "https://rxnav.nlm.nih.gov/REST/rxcui.json?idtype=NDC&id={ndc}"
  )
  result <- tryCatch({
    resp <- httr2::request(url) |>
      httr2::req_timeout(10) |>
      httr2::req_retry(
        max_tries = 3,
        is_transient = ~ httr2::resp_status(.x) %in% c(429L, 503L, 504L)
      ) |>
      httr2::req_perform()
    data <- httr2::resp_body_json(resp)
    if (!is.null(data$idGroup$rxnormId) && length(data$idGroup$rxnormId) > 0) {
      data$idGroup$rxnormId[[1]]
    } else {
      NA_character_
    }
  }, error = function(e) {
    NA_character_
  })
  Sys.sleep(sleep_sec)
  result
}


# ==============================================================================
# SECTION 5: BATCH LOOKUP WITH PROGRESS ----
# ==============================================================================

message("--- SECTION 5: Batch RxNav lookup ---\n")

n_ndc        <- length(ndc_vec)
rxcui_vec    <- character(n_ndc)
progress_interval <- 100L

for (i in seq_along(ndc_vec)) {
  rxcui_vec[[i]] <- lookup_ndc_to_rxcui(ndc_vec[[i]])
  if (i %% progress_interval == 0L || i == n_ndc) {
    n_matched_so_far <- sum(!is.na(rxcui_vec[seq_len(i)]))
    message(glue(
      "  Progress: {i}/{n_ndc} NDCs resolved — {n_matched_so_far} matched so far"
    ))
  }
}


# ==============================================================================
# SECTION 6: BUILD CROSSWALK AND WRITE OUTPUTS ----
# ==============================================================================

message("\n--- SECTION 6: Building crosswalk and writing outputs ---\n")

# Summary counts
n_matched <- sum(!is.na(rxcui_vec))
n_miss    <- sum(is.na(rxcui_vec))

message(glue(
  "  Lookup complete: {n_ndc} distinct NDCs queried\n",
  "  Matched: {n_matched}  |  Misses (no RxCUI): {n_miss}\n"
))

# 6a. Named vector crosswalk (matched entries only)
crosswalk <- stats::setNames(rxcui_vec, ndc_vec)
crosswalk <- crosswalk[!is.na(crosswalk)]

# 6b. Audit tibble (all entries including misses)
audit_df <- dplyr::tibble(
  NDC          = ndc_vec,
  rxcui        = rxcui_vec,
  lookup_status = dplyr::if_else(!is.na(rxcui_vec), "matched", "miss")
)

# 6c. Write RDS (crosswalk — matched only, named vector)
rds_path <- here::here("data", "reference", "ndc_rxnorm_crosswalk.rds")
saveRDS(crosswalk, rds_path)
message(glue("  RDS written: {rds_path}  ({length(crosswalk)} entries)"))

# 6d. Write audit CSV (all entries)
audit_path <- file.path(CONFIG$output_dir, "ndc_rxnorm_crosswalk_audit.csv")
write.csv(audit_df, audit_path, row.names = FALSE, na = "")
message(glue("  Audit CSV written: {audit_path}  ({nrow(audit_df)} rows)"))


# ==============================================================================
# SECTION 7: FINAL SUMMARY ----
# ==============================================================================

message(glue(
  "\n=== R/108 Complete ===\n",
  "  {n_ndc} distinct NDCs processed (DISPENSING + MED_ADMIN ND)\n",
  "  {n_matched} matched to an RxCUI  |  {n_miss} misses\n",
  "  Crosswalk RDS : {rds_path}\n",
  "  Audit CSV     : {audit_path}\n",
  "\n",
  "  Next steps:\n",
  "    1. git add data/reference/ndc_rxnorm_crosswalk.rds && git commit\n",
  "    2. Rscript R/88_smoke_test_comprehensive.R  (expect Section 15t 14/14 PASS)\n",
  "    3. Rscript R/107_med_admin_dispensing_gap_diagnostic.R\n",
  "       (DISPENSING + MED_ADMIN ND rows should now show non-zero chemo hits)\n"
))
