# ==============================================================================
# 40_investigate_unmatched_ndc.R -- Investigate Unmatched NDC/RXNORM Drug Codes
# ==============================================================================
# Purpose: Extract NDC codes and unmatched RXNORM CUIs from HL patient drug
# records (DISPENSING, PRESCRIBING, MED_ADMIN), look up drug names via NLM
# RxNorm API, auto-classify into treatment categories, produce styled xlsx
# report and RDS artifact for config update.
#
# Output:
#   - output/unmatched_ndc_report.xlsx (styled workbook with classification)
#   - output/unmatched_ndc_classified.rds (RDS for Plan 02 consumption)
#
# Usage:
#   Rscript R/40_investigate_unmatched_ndc.R
#
# Dependencies:
#   - R/00_config.R (TREATMENT_CODES list)
#   - R/01_load_pcornet.R (get_pcornet_table)
#   - httr2, jsonlite, openxlsx2, dplyr, stringr, glue, tidyr
#
# Phase 40 Plan 01 -- investigate-unmatched-ndc-codes
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP AND CONFIGURATION
# ==============================================================================

source("R/00_config.R")
source("R/01_load_pcornet.R")

library(httr2)
library(jsonlite)
library(openxlsx2)
library(dplyr)
library(stringr)
library(glue)
library(tidyr)

OUTPUT_PATH <- file.path(CONFIG$output_dir, "unmatched_ndc_report.xlsx")
RDS_PATH <- file.path(CONFIG$output_dir, "unmatched_ndc_classified.rds")

# Treatment type colors for xlsx pills (8-char hex with FF alpha prefix)
# Matching Phase 39 palette with "SCT-related" key instead of "SCT"
TREATMENT_TYPE_COLORS <- list(
  Chemotherapy      = list(fill = "FFDCEEFB", font = "FF0B5394"),   # light blue / dark blue
  Radiation         = list(fill = "FFDDF4E1", font = "FF274E13"),   # light green / dark green
  `SCT-related`     = list(fill = "FFFFF4D6", font = "FF7F6000"),   # light yellow / dark olive
  Immunotherapy     = list(fill = "FFE8DCF4", font = "FF4C1D7A"),   # light purple / dark purple
  `Supportive Care` = list(fill = "FFD5F5F0", font = "FF0E6655"),   # light teal / dark teal
  Unrelated         = list(fill = "FFF3F4F6", font = "FF6B7280")    # light gray / medium gray
)

#' Safely access a PCORnet table with null-guard
#'
#' Wraps get_pcornet_table() in tryCatch to handle missing tables gracefully.
#' Returns NULL (not an error) when a table doesn't exist in the current
#' data extract.
#'
#' @param name Character. PCORnet table name (e.g., "DISPENSING", "PRESCRIBING")
#' @return A dplyr-compatible object (tibble or tbl_dbi), or NULL if not found
safe_table <- function(name) {
  tryCatch(
    get_pcornet_table(name),
    error = function(e) {
      message(glue("  Warning: {name} table not found: {e$message}"))
      NULL
    }
  )
}

#' Get patient IDs with a Hodgkin Lymphoma diagnosis
#'
#' Queries DIAGNOSIS table for any patient with an HL ICD-10 or ICD-9 code.
#' Used to pull ALL drugs for HL patients (not just curated TREATMENT_CODES).
#'
#' @return Character vector of unique patient IDs
get_hl_patient_ids <- function() {
  dx_tbl <- safe_table("DIAGNOSIS")
  if (is.null(dx_tbl)) {
    message("  Warning: DIAGNOSIS table not found, cannot identify HL patients")
    return(character(0))
  }

  tryCatch({
    hl_ids <- dx_tbl %>%
      filter(
        (DX_TYPE == "10" & DX %in% ICD_CODES$hl_icd10) |
        (DX_TYPE == "09" & DX %in% ICD_CODES$hl_icd9)
      ) %>%
      select(ID) %>%
      distinct() %>%
      collect() %>%
      pull(ID)
    message(glue("  Found {format(length(hl_ids), big.mark = ',')} patients with HL diagnosis"))
    hl_ids
  }, error = function(e) {
    message(glue("  Warning: HL patient lookup failed: {e$message}"))
    character(0)
  })
}

# ==============================================================================
# SECTION 2: EXTRACT UNMATCHED DRUG CODES (per D-01, D-02, D-03)
# ==============================================================================

#' Extract unmatched drug codes from DISPENSING, PRESCRIBING, MED_ADMIN
#'
#' Queries 3 drug tables for HL patients, extracting:
#' - NDC codes from DISPENSING (no existing config vectors)
#' - RXNORM CUIs not in TREATMENT_CODES$chemo_rxnorm (only 4 known)
#' - Counts records and distinct patients per code
#' - Captures raw drug names from each table
#'
#' @return Tibble with columns: code, code_type, source_table, n_records, n_patients, raw_drug_name
extract_unmatched_drug_codes <- function() {
  hl_ids <- get_hl_patient_ids()

  if (length(hl_ids) == 0) {
    message("  No HL patients found, returning empty result")
    return(tibble(code = character(), code_type = character(),
                  source_table = character(), n_records = integer(),
                  n_patients = integer(), raw_drug_name = character()))
  }

  # Get known RXNORM codes to exclude
  # Collect all RXNORM vectors from TREATMENT_CODES
  known_rxnorm <- character(0)
  for (name in names(TREATMENT_CODES)) {
    if (grepl("_rxnorm$", name)) {
      known_rxnorm <- c(known_rxnorm, TREATMENT_CODES[[name]])
    }
  }
  message(glue("  Excluding {length(known_rxnorm)} known RXNORM CUIs from TREATMENT_CODES"))

  # No NDC vectors exist in TREATMENT_CODES yet
  known_ndc <- character(0)

  results <- list()

  # --- 1. DISPENSING RXNORM ---
  dispensing_tbl <- safe_table("DISPENSING")
  if (!is.null(dispensing_tbl)) {
    message("  Extracting DISPENSING RXNORM codes...")
    dispensing_rxnorm <- tryCatch({
      dispensing_tbl %>%
        filter(ID %in% hl_ids) %>%
        filter(!is.na(RXNORM_CUI), RXNORM_CUI != "") %>%
        filter(!RXNORM_CUI %in% known_rxnorm) %>%
        group_by(code = RXNORM_CUI) %>%
        summarise(
          n_records = n(),
          n_patients = n_distinct(ID),
          raw_drug_name = first(RAW_DISPENSE_MED_NAME[!is.na(RAW_DISPENSE_MED_NAME)]),
          .groups = "drop"
        ) %>%
        collect() %>%
        mutate(source_table = "DISPENSING", code_type = "RXNORM")
    }, error = function(e) {
      message(glue("    Warning: DISPENSING RXNORM extraction failed: {e$message}"))
      tibble(code = character(), code_type = character(), source_table = character(),
             n_records = integer(), n_patients = integer(), raw_drug_name = character())
    })

    if (nrow(dispensing_rxnorm) > 0) {
      message(glue("    Found {nrow(dispensing_rxnorm)} unmatched RXNORM codes"))
      results <- c(results, list(dispensing_rxnorm))
    }
  }

  # --- 2. DISPENSING NDC ---
  if (!is.null(dispensing_tbl)) {
    message("  Extracting DISPENSING NDC codes...")
    dispensing_ndc <- tryCatch({
      dispensing_tbl %>%
        filter(ID %in% hl_ids) %>%
        filter(!is.na(NDC), NDC != "") %>%
        group_by(code = NDC) %>%
        summarise(
          n_records = n(),
          n_patients = n_distinct(ID),
          raw_drug_name = first(RAW_DISPENSE_MED_NAME[!is.na(RAW_DISPENSE_MED_NAME)]),
          .groups = "drop"
        ) %>%
        collect() %>%
        mutate(source_table = "DISPENSING", code_type = "NDC")
    }, error = function(e) {
      message(glue("    Warning: DISPENSING NDC extraction failed: {e$message}"))
      tibble(code = character(), code_type = character(), source_table = character(),
             n_records = integer(), n_patients = integer(), raw_drug_name = character())
    })

    if (nrow(dispensing_ndc) > 0) {
      message(glue("    Found {nrow(dispensing_ndc)} NDC codes"))
      results <- c(results, list(dispensing_ndc))
    }
  }

  # --- 3. PRESCRIBING RXNORM ---
  prescribing_tbl <- safe_table("PRESCRIBING")
  if (!is.null(prescribing_tbl)) {
    message("  Extracting PRESCRIBING RXNORM codes...")
    prescribing_rxnorm <- tryCatch({
      prescribing_tbl %>%
        filter(ID %in% hl_ids) %>%
        filter(!is.na(RXNORM_CUI), RXNORM_CUI != "") %>%
        filter(!RXNORM_CUI %in% known_rxnorm) %>%
        group_by(code = RXNORM_CUI) %>%
        summarise(
          n_records = n(),
          n_patients = n_distinct(ID),
          raw_drug_name = first(RAW_RX_MED_NAME[!is.na(RAW_RX_MED_NAME)]),
          .groups = "drop"
        ) %>%
        collect() %>%
        mutate(source_table = "PRESCRIBING", code_type = "RXNORM")
    }, error = function(e) {
      message(glue("    Warning: PRESCRIBING RXNORM extraction failed: {e$message}"))
      tibble(code = character(), code_type = character(), source_table = character(),
             n_records = integer(), n_patients = integer(), raw_drug_name = character())
    })

    if (nrow(prescribing_rxnorm) > 0) {
      message(glue("    Found {nrow(prescribing_rxnorm)} unmatched RXNORM codes"))
      results <- c(results, list(prescribing_rxnorm))
    }
  }

  # --- 4. MED_ADMIN RXNORM ---
  medadmin_tbl <- safe_table("MED_ADMIN")
  if (!is.null(medadmin_tbl)) {
    message("  Extracting MED_ADMIN RXNORM codes...")
    medadmin_rxnorm <- tryCatch({
      medadmin_tbl %>%
        filter(ID %in% hl_ids) %>%
        filter(!is.na(RXNORM_CUI), RXNORM_CUI != "") %>%
        filter(!RXNORM_CUI %in% known_rxnorm) %>%
        group_by(code = RXNORM_CUI) %>%
        summarise(
          n_records = n(),
          n_patients = n_distinct(ID),
          raw_drug_name = first(RAW_MEDADMIN_MED_NAME[!is.na(RAW_MEDADMIN_MED_NAME)]),
          .groups = "drop"
        ) %>%
        collect() %>%
        mutate(source_table = "MED_ADMIN", code_type = "RXNORM")
    }, error = function(e) {
      message(glue("    Warning: MED_ADMIN RXNORM extraction failed: {e$message}"))
      tibble(code = character(), code_type = character(), source_table = character(),
             n_records = integer(), n_patients = integer(), raw_drug_name = character())
    })

    if (nrow(medadmin_rxnorm) > 0) {
      message(glue("    Found {nrow(medadmin_rxnorm)} unmatched RXNORM codes"))
      results <- c(results, list(medadmin_rxnorm))
    }
  }

  # Combine all results
  if (length(results) == 0) {
    message("  No unmatched codes found across all drug tables")
    return(tibble(code = character(), code_type = character(),
                  source_table = character(), n_records = integer(),
                  n_patients = integer(), raw_drug_name = character()))
  }

  all_results <- bind_rows(results)
  message(glue("  Total unmatched codes: {nrow(all_results)} ({sum(all_results$n_records)} records)"))

  all_results
}

# ==============================================================================
# SECTION 3: RXNORM API LOOKUP (per D-04, D-05, D-06)
# ==============================================================================

#' Look up RXNORM CUI name via RxNorm API
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

# ==============================================================================
# SECTION 4: AUTO-CLASSIFICATION (per D-07, D-08, D-09)
# ==============================================================================

#' Classify a drug into treatment categories
#'
#' Uses case_when() with keyword matching on drug names.
#' CRITICAL: Supportive Care MUST be checked FIRST to avoid misclassifying
#' G-CSF and antiemetics as chemotherapy (per D-09 and Pitfall 3).
#'
#' @param drug_name Character. Drug name from API lookup (may be NA).
#' @return Character. One of: "Supportive Care", "Chemotherapy", "Immunotherapy",
#'         "SCT-related", "Radiation", "Unrelated"
classify_drug <- function(drug_name) {
  name_lower <- tolower(ifelse(is.na(drug_name), "", drug_name))

  case_when(
    # 1. Supportive Care FIRST (per D-09) - G-CSF, antiemetics, EPO
    str_detect(name_lower,
      "filgrastim|pegfilgrastim|neulasta|neupogen|zarxio|granix|udenyca|nyvepria|ziextenzo|stimufend|fylnetra|releuko|ondansetron|zofran|granisetron|kytril|palonosetron|aloxi|fosaprepitant|emend|aprepitant|dexamethasone|colony.stimulating|growth factor|antiemetic|epoetin|procrit|darbepoetin|aranesp|lenograstim|tbo-filgrastim|lipegfilgrastim"
    ) ~ "Supportive Care",

    # 2. Chemotherapy - ABVD drugs, other chemo agents, and immunoconjugates
    str_detect(name_lower,
      "doxorubicin|adriamycin|bleomycin|vinblastine|dacarbazine|dtic|brentuximab|adcetris|nivolumab|opdivo|pembrolizumab|keytruda|etoposide|cisplatin|carboplatin|vincristine|cyclophosphamide|cytoxan|bendamustine|gemcitabine|ifosfamide|methotrexate|procarbazine|mechlorethamine|lomustine|carmustine|chemotherapy|antineoplastic|cytotoxic"
    ) ~ "Chemotherapy",

    # 3. Immunotherapy - checkpoint inhibitors, CAR-T
    str_detect(name_lower,
      "nivolumab|pembrolizumab|atezolizumab|durvalumab|avelumab|ipilimumab|cemiplimab|dostarlimab|retifanlimab|toripalimab|tislelizumab|checkpoint inhibitor|anti-pd-1|anti-pd-l1|anti-ctla-4|car.t|chimeric antigen|axicabtagene|tisagenlecleucel|brexucabtagene|lisocabtagene"
    ) ~ "Immunotherapy",

    # 4. SCT-related - transplant, conditioning regimens
    str_detect(name_lower,
      "stem cell|bone marrow|hematopoietic|transplant|conditioning|busulfan|melphalan|thiotepa|fludarabine"
    ) ~ "SCT-related",

    # 5. Radiation - radiolabeled drugs
    str_detect(name_lower,
      "radiation|radiotherapy|radiolabeled"
    ) ~ "Radiation",

    # 6. Default - unrelated to HL treatment
    TRUE ~ "Unrelated"
  )
}

# ==============================================================================
# SECTION 5: XLSX REPORT GENERATION (per D-12)
# ==============================================================================

#' Write styled xlsx report with summary and per-category sheets
#'
#' Creates one sheet per classification category in order:
#' Chemotherapy, Immunotherapy, SCT-related, Supportive Care, Radiation, Unrelated.
#' Skips categories with 0 codes.
#' Adds a Summary sheet as the first sheet with classification counts.
#'
#' @param df Tibble. All unmatched codes with classification, drug_name, etc.
#' @param output_path Character. Path to save xlsx file.
write_unmatched_ndc_report <- function(df, output_path) {
  wb <- wb_workbook()

  # Category order
  category_order <- c("Chemotherapy", "Immunotherapy", "SCT-related",
                      "Supportive Care", "Radiation", "Unrelated")

  # --- SUMMARY SHEET ---
  message("  Writing Summary sheet...")
  wb$add_worksheet("Summary")

  # Row 1: Title
  wb$add_data(sheet = "Summary", x = "Unmatched NDC/RXNORM Investigation Summary",
              start_row = 1, start_col = 1)
  wb$add_font(sheet = "Summary", dims = "A1",
              name = "Calibri", size = 14, bold = TRUE, color = wb_color("FF1F2937"))
  wb$merge_cells(sheet = "Summary", dims = "A1:D1")

  # Row 2: Subtitle
  wb$add_data(sheet = "Summary", x = "Phase 40 — Drug codes in HL patient data not in TREATMENT_CODES",
              start_row = 2, start_col = 1)
  wb$add_font(sheet = "Summary", dims = "A2",
              name = "Calibri", size = 10, color = wb_color("FF6B7280"))
  wb$merge_cells(sheet = "Summary", dims = "A2:D2")

  # Row 3: Date
  wb$add_data(sheet = "Summary", x = as.character(Sys.Date()),
              start_row = 3, start_col = 1)
  wb$add_font(sheet = "Summary", dims = "A3",
              name = "Calibri", size = 10, color = wb_color("FF6B7280"))

  # Row 5: Classification counts header
  headers <- c("Classification", "Codes", "Records", "Patients")
  for (i in seq_along(headers)) {
    wb$add_data(sheet = "Summary", x = headers[i],
                start_row = 5, start_col = i)
  }
  wb$add_fill(sheet = "Summary", dims = "A5:D5", color = wb_color("FF374151"))
  wb$add_font(sheet = "Summary", dims = "A5:D5",
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  # Classification counts data
  summary_df <- df %>%
    group_by(classification) %>%
    summarise(
      n_codes = n_distinct(code),
      n_records = sum(n_records),
      n_patients = sum(n_patients),
      .groups = "drop"
    ) %>%
    arrange(match(classification, category_order))

  for (i in seq_len(nrow(summary_df))) {
    row_num <- 5 + i
    wb$add_data(sheet = "Summary", x = summary_df$classification[i],
                start_row = row_num, start_col = 1)
    wb$add_data(sheet = "Summary", x = summary_df$n_codes[i],
                start_row = row_num, start_col = 2)
    wb$add_data(sheet = "Summary", x = summary_df$n_records[i],
                start_row = row_num, start_col = 3)
    wb$add_data(sheet = "Summary", x = summary_df$n_patients[i],
                start_row = row_num, start_col = 4)
    wb$add_numfmt(sheet = "Summary", dims = glue("B{row_num}:D{row_num}"), numfmt = "#,##0")
  }

  # Total row
  total_row <- 5 + nrow(summary_df) + 1
  wb$add_data(sheet = "Summary", x = "Total",
              start_row = total_row, start_col = 1)
  wb$add_data(sheet = "Summary", x = sum(summary_df$n_codes),
              start_row = total_row, start_col = 2)
  wb$add_data(sheet = "Summary", x = sum(summary_df$n_records),
              start_row = total_row, start_col = 3)
  wb$add_data(sheet = "Summary", x = sum(summary_df$n_patients),
              start_row = total_row, start_col = 4)
  wb$add_fill(sheet = "Summary", dims = glue("A{total_row}:D{total_row}"),
              color = wb_color("FF374151"))
  wb$add_font(sheet = "Summary", dims = glue("A{total_row}:D{total_row}"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
  wb$add_numfmt(sheet = "Summary", dims = glue("B{total_row}:D{total_row}"), numfmt = "#,##0")

  # Code type breakdown section
  code_type_row <- total_row + 2
  wb$add_data(sheet = "Summary", x = "By Code Type:",
              start_row = code_type_row, start_col = 1)
  wb$add_font(sheet = "Summary", dims = glue("A{code_type_row}"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FF1F2937"))

  code_type_summary <- df %>%
    group_by(code_type) %>%
    summarise(n_codes = n_distinct(code), .groups = "drop")

  for (i in seq_len(nrow(code_type_summary))) {
    row_num <- code_type_row + i
    wb$add_data(sheet = "Summary", x = code_type_summary$code_type[i],
                start_row = row_num, start_col = 1)
    wb$add_data(sheet = "Summary", x = code_type_summary$n_codes[i],
                start_row = row_num, start_col = 2)
    wb$add_numfmt(sheet = "Summary", dims = glue("B{row_num}"), numfmt = "#,##0")
  }

  # Source table breakdown section
  source_row <- code_type_row + nrow(code_type_summary) + 2
  wb$add_data(sheet = "Summary", x = "By Source Table:",
              start_row = source_row, start_col = 1)
  wb$add_font(sheet = "Summary", dims = glue("A{source_row}"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FF1F2937"))

  source_summary <- df %>%
    group_by(source_table) %>%
    summarise(n_codes = n_distinct(code), .groups = "drop")

  for (i in seq_len(nrow(source_summary))) {
    row_num <- source_row + i
    wb$add_data(sheet = "Summary", x = source_summary$source_table[i],
                start_row = row_num, start_col = 1)
    wb$add_data(sheet = "Summary", x = source_summary$n_codes[i],
                start_row = row_num, start_col = 2)
    wb$add_numfmt(sheet = "Summary", dims = glue("B{row_num}"), numfmt = "#,##0")
  }

  # Column widths
  wb$set_col_widths(sheet = "Summary", cols = 1:4, widths = c(22, 12, 12, 12))

  # --- PER-CATEGORY SHEETS ---
  for (category in category_order) {
    df_cat <- df %>%
      filter(classification == category) %>%
      arrange(desc(n_patients))

    if (nrow(df_cat) == 0) {
      next  # Skip empty categories
    }

    message(glue("  Writing {category} sheet ({nrow(df_cat)} codes)..."))

    sheet_name <- category
    wb$add_worksheet(sheet_name)

    fill_color <- TREATMENT_TYPE_COLORS[[category]]$fill
    font_color <- TREATMENT_TYPE_COLORS[[category]]$font

    # Row 1: Title
    wb$add_data(sheet = sheet_name, x = "Unmatched NDC/RXNORM Drug Codes Investigation",
                start_row = 1, start_col = 1)
    wb$add_font(sheet = sheet_name, dims = "A1",
                name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
    wb$merge_cells(sheet = sheet_name, dims = "A1:G1")

    # Row 2: Subtitle
    subtitle <- glue("{category}: {nrow(df_cat)} unmatched codes")
    wb$add_data(sheet = sheet_name, x = as.character(subtitle),
                start_row = 2, start_col = 1)
    wb$add_font(sheet = sheet_name, dims = "A2",
                name = "Calibri", size = 10, color = wb_color("FF6B7280"))
    wb$merge_cells(sheet = sheet_name, dims = "A2:G2")

    # Row 3: blank

    # Row 4: Column headers
    headers <- c("Code", "Drug Name", "Code Type", "Source Table", "Records", "Patients", "Lookup Status")
    for (i in seq_along(headers)) {
      wb$add_data(sheet = sheet_name, x = headers[i],
                  start_row = 4, start_col = i)
    }
    wb$add_fill(sheet = sheet_name, dims = "A4:G4", color = wb_color("FF374151"))
    wb$add_font(sheet = sheet_name, dims = "A4:G4",
                name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

    # Write all data rows at once (bulk write instead of cell-by-cell)
    write_df <- data.frame(
      Code = df_cat$code,
      Drug_Name = ifelse(is.na(df_cat$drug_name), "", df_cat$drug_name),
      Code_Type = df_cat$code_type,
      Source_Table = df_cat$source_table,
      Records = df_cat$n_records,
      Patients = df_cat$n_patients,
      Lookup_Status = df_cat$lookup_status,
      stringsAsFactors = FALSE
    )
    wb$add_data(sheet = sheet_name, x = write_df, start_row = 5, col_names = FALSE)

    # Apply styles to entire ranges at once
    last_row <- 4 + nrow(df_cat)
    data_dims <- glue("A5:G{last_row}")
    code_dims <- glue("A5:A{last_row}")
    text_dims <- glue("B5:G{last_row}")
    num_dims <- glue("E5:F{last_row}")

    # Code column: colored pill
    wb$add_fill(sheet = sheet_name, dims = code_dims, color = wb_color(fill_color))
    wb$add_font(sheet = sheet_name, dims = code_dims,
                name = "Calibri", size = 10, bold = TRUE, color = wb_color(font_color))

    # Text columns: standard font
    wb$add_font(sheet = sheet_name, dims = text_dims,
                name = "Calibri", size = 10, color = wb_color("FF111827"))

    # Numeric columns: comma formatting
    wb$add_numfmt(sheet = sheet_name, dims = num_dims, numfmt = "#,##0")

    # Freeze panes at row 5 (first data row)
    wb$freeze_pane(sheet = sheet_name, first_active_row = 5)

    # Column widths
    wb$set_col_widths(sheet = sheet_name, cols = 1:7,
                      widths = c(15, 45, 10, 15, 10, 10, 15))
  }

  # Save workbook
  wb$save(output_path)
  message(glue("  Saved report: {output_path}"))
}

# ==============================================================================
# SECTION 6: SAVE RDS ARTIFACT (per D-13)
# ==============================================================================

#' Save classified codes as RDS for Plan 02 consumption
#'
#' @param classified_df Tibble. All classified codes with full metadata.
#' @param rds_path Character. Path to save RDS file.
save_classified_rds <- function(classified_df, rds_path) {
  saveRDS(classified_df, rds_path)
  message(glue("  Saved RDS artifact: {rds_path} ({nrow(classified_df)} rows)"))
}

# ==============================================================================
# SECTION 8: UPDATE TREATMENT_CODES IN R/00_config.R (per D-10, D-11)
# ==============================================================================

#' Update TREATMENT_CODES in R/00_config.R with NDC and RXNORM codes
#'
#' Programmatically inserts classified NDC and RXNORM codes into R/00_config.R.
#' Creates new NDC vectors (chemo_ndc, supportive_care_ndc, immunotherapy_ndc, sct_ndc)
#' and expands/creates RXNORM vectors (chemo_rxnorm expanded, others created).
#' Creates a backup before modification and validates with parse/source. Rolls back on failure.
#'
#' @param classified_codes_path Character. Path to unmatched_ndc_classified.rds
update_config_ndc_codes <- function(classified_codes_path) {
  # 1. Load classified codes
  if (!file.exists(classified_codes_path)) {
    stop(glue("Classified codes file not found: {classified_codes_path}"))
  }

  classified <- readRDS(classified_codes_path)

  # 2. Filter to treatment-relevant codes (exclude Unrelated and Radiation)
  treatment_codes_new <- classified %>%
    filter(classification %in% c("Chemotherapy", "Supportive Care", "Immunotherapy", "SCT-related")) %>%
    select(code, code_type, classification, drug_name)

  if (nrow(treatment_codes_new) == 0) {
    message("  No treatment codes to add (all classified as Unrelated or Radiation)")
    return(invisible(NULL))
  }

  # 3. Category-to-vector mapping (separate by code type AND classification)
  # NDC vectors (D-10: new vectors)
  ndc_category_map <- c(
    "Chemotherapy" = "chemo_ndc",
    "Supportive Care" = "supportive_care_ndc",
    "Immunotherapy" = "immunotherapy_ndc",
    "SCT-related" = "sct_ndc"
  )
  # RXNORM vectors (D-11: expand existing chemo_rxnorm, create new for others)
  rxnorm_category_map <- c(
    "Chemotherapy" = "chemo_rxnorm",
    "Supportive Care" = "supportive_care_rxnorm",
    "Immunotherapy" = "immunotherapy_rxnorm",
    "SCT-related" = "sct_rxnorm"
  )

  # 4. Read R/00_config.R and create backup
  config_path <- "R/00_config.R"
  backup_path <- paste0(config_path, ".bak")

  if (!file.exists(config_path)) {
    stop(glue("Config file not found: {config_path}"))
  }

  file.copy(config_path, backup_path, overwrite = TRUE)
  message(glue("  Created backup: {backup_path}"))

  config_lines <- readLines(config_path)

  # Track which vectors we've added
  ndc_vectors_added <- character()
  rxnorm_vectors_added <- character()

  # 5. Process each category for each code type (NDC then RXNORM)
  for (code_type in c("NDC", "RXNORM")) {
    category_map <- if (code_type == "NDC") ndc_category_map else rxnorm_category_map

    for (cat_name in names(category_map)) {
      vec_name <- category_map[cat_name]

      # Get new codes for this combination
      new_codes_for_cat <- treatment_codes_new %>%
        filter(classification == cat_name, code_type == !!code_type)

      if (nrow(new_codes_for_cat) == 0) {
        next  # Skip if no codes for this combination
      }

      message(glue("  Processing {cat_name} {code_type}: {nrow(new_codes_for_cat)} codes"))

      # Look for existing vector
      vec_pattern <- glue("^\\s*{vec_name}\\s*=\\s*c\\(")
      vec_start_idx <- grep(vec_pattern, config_lines, perl = TRUE)

      if (length(vec_start_idx) == 0) {
        # Vector doesn't exist - create new (all NDC vectors, new RXNORM vectors)
        message(glue("    Creating new {vec_name} vector"))

        # Find insertion anchor: supportive_care_hcpcs or chemo_revenue
        anchor_idx <- grep("^\\s*supportive_care_hcpcs\\s*=\\s*c\\(", config_lines, perl = TRUE)
        if (length(anchor_idx) == 0) {
          anchor_idx <- grep("^\\s*chemo_revenue\\s*=\\s*c\\(", config_lines, perl = TRUE)
        }
        if (length(anchor_idx) == 0) {
          stop("Cannot find insertion anchor (supportive_care_hcpcs or chemo_revenue)")
        }

        insert_pos <- anchor_idx[1] - 1

        # Build new vector block
        new_lines <- c(
          "",
          glue("  # {cat_name} {code_type} codes (Phase 40: drug investigation)"),
          glue("  {vec_name} = c(")
        )

        for (i in seq_len(nrow(new_codes_for_cat))) {
          code <- new_codes_for_cat$code[i]
          drug_name <- new_codes_for_cat$drug_name[i]
          drug_trunc <- ifelse(is.na(drug_name) || nchar(drug_name) == 0, "no name",
                               substr(drug_name, 1, 40))

          # Last code has no trailing comma
          if (i == nrow(new_codes_for_cat)) {
            new_lines <- c(new_lines, glue("    \"{code}\"    # Phase 40: {drug_trunc}"))
          } else {
            new_lines <- c(new_lines, glue("    \"{code}\",   # Phase 40: {drug_trunc}"))
          }
        }

        new_lines <- c(new_lines, "  ),", "")

        # Insert into config_lines
        config_lines <- c(
          config_lines[1:insert_pos],
          new_lines,
          config_lines[(insert_pos + 1):length(config_lines)]
        )

        if (code_type == "NDC") {
          ndc_vectors_added <- c(ndc_vectors_added, vec_name)
        } else {
          rxnorm_vectors_added <- c(rxnorm_vectors_added, vec_name)
        }

      } else {
        # Vector exists (chemo_rxnorm case) - expand it
        message(glue("    Expanding existing {vec_name} vector"))

        vec_start_idx <- vec_start_idx[1]

        # Find closing paren
        close_paren_idx <- NULL
        for (i in vec_start_idx:length(config_lines)) {
          if (grepl("^\\s*\\)", config_lines[i])) {
            close_paren_idx <- i
            break
          }
        }

        if (is.null(close_paren_idx)) {
          warning(glue("Cannot find closing paren for {vec_name} - skipping"))
          next
        }

        # Extract existing codes
        existing_codes <- character()
        for (i in vec_start_idx:close_paren_idx) {
          line <- config_lines[i]
          matches <- str_extract_all(line, "\"([^\"]+)\"")[[1]]
          if (length(matches) > 0) {
            codes <- str_replace_all(matches, "\"", "")
            existing_codes <- c(existing_codes, codes)
          }
        }

        # Filter new codes to exclude already-existing
        new_codes_to_add <- new_codes_for_cat %>%
          filter(!code %in% existing_codes)

        if (nrow(new_codes_to_add) == 0) {
          message(glue("    All codes already exist in {vec_name} - skipping"))
          next
        }

        message(glue("    Adding {nrow(new_codes_to_add)} new codes to {vec_name}"))

        # Ensure last data line has trailing comma
        last_data_idx <- close_paren_idx - 1
        if (!grepl('"[^"]*"\\s*,', config_lines[last_data_idx])) {
          config_lines[last_data_idx] <- sub('(.*")', '\\1,', config_lines[last_data_idx])
        }

        # Build insert lines
        insert_lines <- character()
        for (i in seq_len(nrow(new_codes_to_add))) {
          code <- new_codes_to_add$code[i]
          drug_name <- new_codes_to_add$drug_name[i]
          drug_trunc <- ifelse(is.na(drug_name) || nchar(drug_name) == 0, "no name",
                               substr(drug_name, 1, 40))

          # Last line omits trailing comma
          if (i == nrow(new_codes_to_add)) {
            insert_lines <- c(insert_lines,
                             glue("    \"{code}\"    # Phase 40: {drug_trunc}"))
          } else {
            insert_lines <- c(insert_lines,
                             glue("    \"{code}\",   # Phase 40: {drug_trunc}"))
          }
        }

        # Insert before closing paren
        config_lines <- c(
          config_lines[1:(close_paren_idx - 1)],
          insert_lines,
          config_lines[close_paren_idx:length(config_lines)]
        )

        if (code_type == "RXNORM") {
          rxnorm_vectors_added <- c(rxnorm_vectors_added, vec_name)
        }
      }
    }
  }

  # 6. Validate updated config
  writeLines(config_lines, config_path)
  message("  Validating updated config...")

  validation_error <- tryCatch({
    # Parse check
    parse(config_path)

    # Source check
    env <- new.env()
    source(config_path, local = env)

    # Verify TREATMENT_CODES exists
    if (is.null(env$TREATMENT_CODES)) {
      stop("TREATMENT_CODES is NULL after sourcing")
    }

    # Verify each new vector exists
    for (vec_name in c(ndc_vectors_added, rxnorm_vectors_added)) {
      if (is.null(env$TREATMENT_CODES[[vec_name]])) {
        warning(glue("Vector {vec_name} is NULL after update"))
      }
    }

    NULL  # No error
  }, error = function(e) {
    e$message
  })

  # 7. Rollback on failure
  if (!is.null(validation_error)) {
    message(glue("  Config update failed: {validation_error}"))
    message("  Restoring backup...")
    file.copy(backup_path, config_path, overwrite = TRUE)
    stop(glue("Config validation failed: {validation_error}"))
  }

  # 8. Cleanup and log
  message("  Config update validated successfully")
  file.remove(backup_path)

  # Log summary of changes per vector
  message("  Config update summary:")
  for (code_type in c("NDC", "RXNORM")) {
    category_map <- if (code_type == "NDC") ndc_category_map else rxnorm_category_map
    for (cat_name in names(category_map)) {
      vec_name <- category_map[cat_name]
      n_new <- treatment_codes_new %>%
        filter(classification == cat_name, code_type == !!code_type) %>%
        nrow()
      if (n_new > 0) {
        message(glue("    {vec_name}: +{n_new} codes"))
      }
    }
  }

  invisible(NULL)
}

# ==============================================================================
# SECTION 7: MAIN EXECUTION
# ==============================================================================

message("=== Phase 40: Investigate Unmatched NDC/RXNORM Drug Codes ===")
message("")

# Step 1: Extract unmatched drug codes
message("Step 1: Extracting unmatched drug codes from DISPENSING, PRESCRIBING, MED_ADMIN...")
all_unmatched <- extract_unmatched_drug_codes()

if (nrow(all_unmatched) == 0) {
  message("")
  message("No unmatched codes found. Exiting.")
  quit(save = "no", status = 0)
}

message("")
message(glue("Extracted {nrow(all_unmatched)} unmatched codes ({sum(all_unmatched$n_records)} records, {sum(all_unmatched$n_patients)} patients)"))
message("")

# Step 2: Look up drug names via RxNorm API
message("Step 2: Looking up drug names via RxNorm API...")

# Deduplicate by unique code before API lookup
unique_codes <- all_unmatched %>% distinct(code, code_type)
lookups <- lookup_drug_codes_batch(unique_codes)

# Join back to all_unmatched
all_unmatched <- all_unmatched %>%
  left_join(lookups, by = "code") %>%
  mutate(drug_name = coalesce(drug_name, raw_drug_name))  # Fallback to raw name

message("")

# Step 3: Auto-classify
message("Step 3: Auto-classifying drug codes...")
all_unmatched <- all_unmatched %>%
  mutate(classification = classify_drug(drug_name))

# Log classification summary
classification_summary <- all_unmatched %>%
  count(classification) %>%
  arrange(desc(n))

message("  Classification summary:")
for (i in seq_len(nrow(classification_summary))) {
  message(glue("    {classification_summary$classification[i]}: {classification_summary$n[i]} codes"))
}

message("")

# Step 4: Write xlsx report
message("Step 4: Writing xlsx report...")
write_unmatched_ndc_report(all_unmatched, OUTPUT_PATH)

message("")

# Step 5: Save RDS
message("Step 5: Saving classified codes for config update...")
save_classified_rds(all_unmatched, RDS_PATH)

message("")

# Step 6: Update R/00_config.R with new codes
message("Step 6: Updating R/00_config.R with new treatment codes...")
update_config_ndc_codes(RDS_PATH)

message("")
message("=== Phase 40 Investigation Complete ===")
message(glue("  Report: {OUTPUT_PATH}"))
message(glue("  RDS: {RDS_PATH}"))
