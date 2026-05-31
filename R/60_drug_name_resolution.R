# =============================================================================
# Phase 60: Drug Name Resolution via RxNorm API
# =============================================================================
# Resolves RXNORM_CUI and NDC codes from chemotherapy patient data to generic
# drug names using the NLM RxNorm REST API. Produces a cached lookup table
# for downstream use in R/44a treatment episode detail.
#
# Decision traceability:
#   D-06: Drug name resolution covers chemotherapy only
#   D-07: Both RXNORM_CUI and NDC codes resolved via R/40 functions
#   D-08: Only codes from patient data (not all config codes) are resolved
#   D-09: Results cached in drug_name_lookup.rds; re-runs only query new codes
#   D-10: Standalone script separate from episode extraction
#
# Outputs:
#   - cache/outputs/drug_name_lookup.rds (cached lookup table)
#   - output/drug_name_lookup.csv (human-readable reference)
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(httr2)
  library(purrr)
})

source("R/00_config.R")
source("R/utils_duckdb.R")

# =============================================================================
# API Lookup Functions (Copied from R/40_investigate_unmatched_ndc.R)
# =============================================================================
# Copied from R/40_investigate_unmatched_ndc.R for script independence (per Claude's discretion)

#' Look up RxCUI drug name via RxNorm API
#'
#' Queries the NLM RxNorm API for drug name by RxCUI.
#' Uses httr2 with retry logic for transient failures.
#'
#' @param rxcui Character. RxCUI to look up.
#' @param sleep_sec Numeric. Seconds to sleep after request (default 0.1 = ~10 req/sec)
#' @return Tibble with columns: code, drug_name, lookup_status
lookup_rxcui_name <- function(rxcui, sleep_sec = 0.1) {
  result <- tryCatch({
    url <- glue("https://rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/properties.json")

    resp <- request(url) %>%
      req_timeout(10) %>%
      req_retry(
        max_tries = 3,
        is_transient = ~ resp_status(.x) %in% c(429, 503, 504)
      ) %>%
      req_perform()

    # Success - extract drug name
    data <- resp_body_json(resp)

    if (!is.null(data$properties) && !is.null(data$properties$name)) {
      tibble(
        code = rxcui,
        drug_name = data$properties$name,
        lookup_status = "success"
      )
    } else {
      tibble(
        code = rxcui,
        drug_name = NA_character_,
        lookup_status = "not_found"
      )
    }
  }, error = function(e) {
    tibble(
      code = rxcui,
      drug_name = NA_character_,
      lookup_status = glue("error: {e$message}")
    )
  })

  Sys.sleep(sleep_sec)
  result
}

#' Look up NDC drug name via RxNorm API (2-step: NDC -> RxCUI -> Name)
#'
#' Step 1: Convert NDC to RxCUI via idtype=NDC endpoint
#' Step 2: Look up drug name via RxCUI properties endpoint
#'
#' @param ndc Character. NDC code to look up.
#' @param sleep_sec Numeric. Seconds to sleep between steps (default 0.1)
#' @return Tibble with columns: code, drug_name, lookup_status
lookup_ndc_to_name <- function(ndc, sleep_sec = 0.1) {
  # Step 1: NDC -> RxCUI
  rxcui_result <- tryCatch({
    url <- glue("https://rxnav.nlm.nih.gov/REST/rxcui.json?idtype=NDC&id={ndc}")

    resp <- request(url) %>%
      req_timeout(10) %>%
      req_retry(
        max_tries = 3,
        is_transient = ~ resp_status(.x) %in% c(429, 503, 504)
      ) %>%
      req_perform()

    data <- resp_body_json(resp)

    if (!is.null(data$idGroup) && !is.null(data$idGroup$rxnormId) &&
        length(data$idGroup$rxnormId) > 0) {
      # Take first RxCUI if multiple returned
      data$idGroup$rxnormId[[1]]
    } else {
      NA_character_
    }
  }, error = function(e) {
    NA_character_
  })

  if (is.na(rxcui_result)) {
    return(tibble(
      code = ndc,
      drug_name = NA_character_,
      lookup_status = "ndc_not_found"
    ))
  }

  Sys.sleep(sleep_sec)

  # Step 2: RxCUI -> Name
  name_result <- lookup_rxcui_name(rxcui_result, sleep_sec = sleep_sec)

  tibble(
    code = ndc,
    drug_name = name_result$drug_name,
    lookup_status = name_result$lookup_status
  )
}

#' Look up drug codes in batch with progress logging
#'
#' Deduplicates by unique code+code_type, then looks up each via appropriate API.
#' RXNORM codes: direct RxCUI lookup
#' NDC codes: 2-step NDC->RxCUI->Name lookup
#'
#' @param codes_df Tibble with code and code_type columns
#' @return Tibble with columns: code, drug_name, lookup_status
lookup_drug_codes_batch <- function(codes_df) {
  # Deduplicate by unique code+code_type
  unique_codes <- codes_df %>%
    distinct(code, code_type)

  message(glue("  Looking up {nrow(unique_codes)} unique drug codes..."))

  results <- list()

  # Lookup RXNORM codes
  rxnorm_codes <- unique_codes %>% filter(code_type == "RXNORM") %>% pull(code)
  if (length(rxnorm_codes) > 0) {
    message(glue("    Processing {length(rxnorm_codes)} RXNORM CUIs..."))
    for (i in seq_along(rxnorm_codes)) {
      if (i %% 10 == 0) {
        message(glue("      Looked up {i}/{length(rxnorm_codes)} RXNORM codes"))
      }
      results <- c(results, list(lookup_rxcui_name(rxnorm_codes[i])))
    }
  }

  # Lookup NDC codes
  ndc_codes <- unique_codes %>% filter(code_type == "NDC") %>% pull(code)
  if (length(ndc_codes) > 0) {
    message(glue("    Processing {length(ndc_codes)} NDC codes..."))
    for (i in seq_along(ndc_codes)) {
      if (i %% 10 == 0) {
        message(glue("      Looked up {i}/{length(ndc_codes)} NDC codes"))
      }
      results <- c(results, list(lookup_ndc_to_name(ndc_codes[i])))
    }
  }

  lookups <- bind_rows(results)

  # Summary
  success_count <- sum(lookups$lookup_status == "success", na.rm = TRUE)
  not_found_count <- sum(grepl("not_found", lookups$lookup_status), na.rm = TRUE)
  error_count <- sum(grepl("error", lookups$lookup_status), na.rm = TRUE)

  message(glue("  Lookup summary: {success_count} success, {not_found_count} not found, {error_count} errors"))

  lookups
}

# =============================================================================
# Extract Unique Chemotherapy Drug Codes from Patient Data (per D-08)
# =============================================================================

message("=== Phase 60: Drug Name Resolution ===\n")
message("--- Extracting unique chemotherapy drug codes from patient data ---")

open_pcornet_con()

# RXNORM_CUI codes from PRESCRIBING
rx_codes_prescribing <- NULL
if (!is.null(get_pcornet_table("PRESCRIBING")) &&
    "RXNORM_CUI" %in% colnames(get_pcornet_table("PRESCRIBING"))) {
  rx_codes_prescribing <- get_pcornet_table("PRESCRIBING") %>%
    filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
    filter(!is.na(RXNORM_CUI)) %>%
    distinct(RXNORM_CUI) %>%
    collect() %>%
    mutate(code = RXNORM_CUI, code_type = "RXNORM", source_table = "PRESCRIBING") %>%
    select(code, code_type, source_table)
}

# RXNORM_CUI codes from DISPENSING
rx_codes_dispensing <- NULL
if (!is.null(get_pcornet_table("DISPENSING")) &&
    "RXNORM_CUI" %in% colnames(get_pcornet_table("DISPENSING"))) {
  rx_codes_dispensing <- get_pcornet_table("DISPENSING") %>%
    filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
    filter(!is.na(RXNORM_CUI)) %>%
    distinct(RXNORM_CUI) %>%
    collect() %>%
    mutate(code = RXNORM_CUI, code_type = "RXNORM", source_table = "DISPENSING") %>%
    select(code, code_type, source_table)
}

# RXNORM_CUI codes from MED_ADMIN
rx_codes_medadmin <- NULL
if (!is.null(get_pcornet_table("MED_ADMIN")) &&
    "RXNORM_CUI" %in% colnames(get_pcornet_table("MED_ADMIN"))) {
  rx_codes_medadmin <- get_pcornet_table("MED_ADMIN") %>%
    filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
    filter(!is.na(RXNORM_CUI)) %>%
    distinct(RXNORM_CUI) %>%
    collect() %>%
    mutate(code = RXNORM_CUI, code_type = "RXNORM", source_table = "MED_ADMIN") %>%
    select(code, code_type, source_table)
}

# NDC codes from DISPENSING (if NDC column exists)
ndc_codes <- NULL
if (!is.null(get_pcornet_table("DISPENSING")) &&
    "NDC" %in% colnames(get_pcornet_table("DISPENSING")) &&
    "RXNORM_CUI" %in% colnames(get_pcornet_table("DISPENSING"))) {
  # Get NDC codes that appear alongside chemo RXNORM_CUI codes
  # These are NDC codes for prescriptions that matched chemo_rxnorm
  ndc_codes <- get_pcornet_table("DISPENSING") %>%
    filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
    filter(!is.na(NDC)) %>%
    distinct(NDC) %>%
    collect() %>%
    mutate(code = NDC, code_type = "NDC", source_table = "DISPENSING") %>%
    select(code, code_type, source_table)
}

close_pcornet_con()

# Combine and deduplicate
all_codes <- bind_rows(
  rx_codes_prescribing, rx_codes_dispensing, rx_codes_medadmin, ndc_codes
) %>%
  filter(!is.na(code) & code != "")

# Deduplicate by code (keep first source_table for reference)
unique_codes <- all_codes %>%
  group_by(code, code_type) %>%
  summarise(source_tables = paste(unique(source_table), collapse = ","), .groups = "drop")

message(glue("  Found {nrow(unique_codes)} unique drug codes in patient data"))
message(glue("    RXNORM: {sum(unique_codes$code_type == 'RXNORM')}"))
message(glue("    NDC: {sum(unique_codes$code_type == 'NDC')}"))

# =============================================================================
# Load Cache and Determine Codes to Query (per D-09)
# =============================================================================

CACHE_FILE <- file.path(CONFIG$cache$outputs_dir, "drug_name_lookup.rds")
OUTPUT_CSV <- file.path(CONFIG$output_dir, "drug_name_lookup.csv")

if (file.exists(CACHE_FILE)) {
  cached_lookups <- readRDS(CACHE_FILE)
  message(glue("  Loaded {nrow(cached_lookups)} cached drug name lookups"))
} else {
  cached_lookups <- tibble(
    code = character(0),
    code_type = character(0),
    drug_name = character(0),
    lookup_status = character(0),
    source_tables = character(0)
  )
  message("  No cache found -- all codes will be queried")
}

# Only query codes not already in cache
codes_to_query <- unique_codes %>%
  anti_join(cached_lookups, by = "code")

message(glue("  {nrow(codes_to_query)} new codes to resolve via RxNorm API"))

# =============================================================================
# Query RxNorm API for Uncached Codes
# =============================================================================

if (nrow(codes_to_query) > 0) {
  message("\n--- Querying RxNorm API ---")

  new_lookups <- lookup_drug_codes_batch(codes_to_query)

  # Add code_type and source_tables from codes_to_query
  new_lookups <- new_lookups %>%
    left_join(codes_to_query %>% select(code, code_type, source_tables), by = "code")

  # Combine with cache
  all_lookups <- bind_rows(cached_lookups, new_lookups)
} else {
  message("\n--- All codes already cached, skipping API calls ---")
  all_lookups <- cached_lookups
}

# =============================================================================
# Save Outputs
# =============================================================================

# Save RDS cache (per D-09)
saveRDS(all_lookups, CACHE_FILE)
message(glue("\nRDS cache saved: {CACHE_FILE} ({nrow(all_lookups)} entries)"))

# Save CSV reference (per D-10, TREAT-03)
write.csv(all_lookups, OUTPUT_CSV, row.names = FALSE)
message(glue("CSV reference saved: {OUTPUT_CSV}"))

# =============================================================================
# Summary Statistics
# =============================================================================

message("\n=== Drug Name Resolution Complete ===")
message(glue("  Total codes resolved: {nrow(all_lookups)}"))
message(glue("  Successful lookups: {sum(all_lookups$lookup_status == 'success', na.rm = TRUE)}"))
message(glue("  Not found: {sum(grepl('not_found', all_lookups$lookup_status), na.rm = TRUE)}"))
message(glue("  Errors: {sum(grepl('error', all_lookups$lookup_status), na.rm = TRUE)}"))

# Show unique drug names found
drug_names_found <- all_lookups %>%
  filter(lookup_status == "success") %>%
  distinct(drug_name) %>%
  arrange(drug_name)

message(glue("  Unique drug names: {nrow(drug_names_found)}"))
if (nrow(drug_names_found) > 0) {
  message("  Drug names:")
  for (name in drug_names_found$drug_name) {
    message(glue("    - {name}"))
  }
}

message(glue("\nOutputs:"))
message(glue("  RDS: {CACHE_FILE}"))
message(glue("  CSV: {OUTPUT_CSV}"))
