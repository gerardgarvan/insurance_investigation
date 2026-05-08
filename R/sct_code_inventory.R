# ==============================================================================
# sct_code_inventory.R -- SCT Evidence: All Codes from Every Source Table
# ==============================================================================
#
# Extracts every SCT-related record from all PCORnet CDM tables, showing
# the actual NDC codes, PX codes, DX codes, DRG codes, and RXNORM CUIs
# found per patient per date across:
#   PROCEDURES, DISPENSING, PRESCRIBING, MED_ADMIN, ENCOUNTER,
#   DIAGNOSIS, TUMOR_REGISTRY
#
# Output: output/sct_code_inventory.xlsx (one sheet per source table + summary)
#
# Usage:
#   Rscript R/sct_code_inventory.R
#
# ==============================================================================

source("R/00_config.R")
source("R/01_load_pcornet.R")

library(openxlsx2)
library(dplyr)
library(stringr)
library(glue)

OUTPUT_PATH <- file.path(CONFIG$output_dir, "sct_code_inventory.xlsx")

# ==============================================================================
# HELPER
# ==============================================================================

safe_table <- function(name) {
  tryCatch(
    get_pcornet_table(name),
    error = function(e) {
      message(glue("  Table {name} not found; skipping"))
      NULL
    }
  )
}

# ==============================================================================
# SECTION 1: PROCEDURES -- CPT, HCPCS, ICD-9, ICD-10-PCS, Revenue codes
# ==============================================================================

extract_sct_procedures <- function() {
  message("  PROCEDURES...")
  proc_tbl <- safe_table("PROCEDURES")
  if (is.null(proc_tbl)) return(NULL)

  results <- list()

  # CPT codes (PX_TYPE = "CH")
  cpt <- tryCatch({
    proc_tbl %>%
      filter(PX_TYPE == "CH" & PX %in% c(TREATMENT_CODES$sct_cpt, TREATMENT_CODES$sct_hcpcs)) %>%
      select(ID, PX, PX_TYPE, PX_DATE, ENCOUNTERID) %>%
      collect() %>%
      mutate(code_system = case_when(
        PX %in% TREATMENT_CODES$sct_cpt   ~ "CPT",
        PX %in% TREATMENT_CODES$sct_hcpcs ~ "HCPCS",
        TRUE ~ "CH"
      ))
  }, error = function(e) NULL)
  results <- c(results, list(cpt))

  # ICD-9-CM Vol 3 (PX_TYPE = "09")
  icd9 <- tryCatch({
    proc_tbl %>%
      filter(PX_TYPE == "09" & PX %in% TREATMENT_CODES$sct_icd9) %>%
      select(ID, PX, PX_TYPE, PX_DATE, ENCOUNTERID) %>%
      collect() %>%
      mutate(code_system = "ICD-9-CM Vol3")
  }, error = function(e) NULL)
  results <- c(results, list(icd9))

  # ICD-10-PCS (PX_TYPE = "10") -- exact match (full 7-char codes)
  icd10 <- tryCatch({
    proc_tbl %>%
      filter(PX_TYPE == "10" & PX %in% TREATMENT_CODES$sct_icd10pcs) %>%
      select(ID, PX, PX_TYPE, PX_DATE, ENCOUNTERID) %>%
      collect() %>%
      mutate(code_system = "ICD-10-PCS")
  }, error = function(e) NULL)
  results <- c(results, list(icd10))

  # Revenue codes (PX_TYPE = "RE")
  rev <- tryCatch({
    proc_tbl %>%
      filter(PX_TYPE == "RE" & PX %in% TREATMENT_CODES$sct_revenue) %>%
      select(ID, PX, PX_TYPE, PX_DATE, ENCOUNTERID) %>%
      collect() %>%
      mutate(code_system = "Revenue")
  }, error = function(e) NULL)
  results <- c(results, list(rev))

  df <- bind_rows(compact(results))
  if (nrow(df) == 0) return(NULL)

  df %>%
    mutate(source_table = "PROCEDURES", event_date = PX_DATE) %>%
    select(ID, source_table, code = PX, code_system, event_date, ENCOUNTERID)
}

# ==============================================================================
# SECTION 2: ENCOUNTER -- DRG codes
# ==============================================================================

extract_sct_encounters <- function() {
  message("  ENCOUNTER...")
  enc_tbl <- safe_table("ENCOUNTER")
  if (is.null(enc_tbl)) return(NULL)

  df <- tryCatch({
    enc_tbl %>%
      filter(DRG %in% TREATMENT_CODES$sct_drg) %>%
      select(ID, DRG, ADMIT_DATE, ENCOUNTERID) %>%
      collect()
  }, error = function(e) NULL)

  if (is.null(df) || nrow(df) == 0) return(NULL)

  df %>%
    mutate(source_table = "ENCOUNTER", code_system = "DRG") %>%
    select(ID, source_table, code = DRG, code_system, event_date = ADMIT_DATE, ENCOUNTERID)
}

# ==============================================================================
# SECTION 3: DIAGNOSIS -- ICD-10-CM Z/T codes for SCT
# ==============================================================================

extract_sct_diagnosis <- function() {
  message("  DIAGNOSIS...")
  dx_tbl <- safe_table("DIAGNOSIS")
  if (is.null(dx_tbl)) return(NULL)

  df <- tryCatch({
    dx_tbl %>%
      filter(DX_TYPE == "10" & DX %in% TREATMENT_CODES$sct_dx_icd10) %>%
      select(ID, DX, DX_TYPE, DX_DATE, ENCOUNTERID) %>%
      collect()
  }, error = function(e) NULL)

  if (is.null(df) || nrow(df) == 0) return(NULL)

  df %>%
    mutate(source_table = "DIAGNOSIS", code_system = "ICD-10-CM") %>%
    select(ID, source_table, code = DX, code_system, event_date = DX_DATE, ENCOUNTERID)
}

# ==============================================================================
# SECTION 4: DISPENSING -- NDC codes and RXNORM for SCT-related drugs
# ==============================================================================

extract_sct_dispensing <- function() {
  message("  DISPENSING...")
  disp_tbl <- safe_table("DISPENSING")
  if (is.null(disp_tbl)) return(NULL)

  # Get patient IDs with known SCT evidence from PROCEDURES/ENCOUNTER/DIAGNOSIS
  # Then pull ALL dispensing records for those patients to find SCT-related NDCs
  sct_ids <- get_sct_patient_ids()
  if (length(sct_ids) == 0) {
    message("    No SCT patients found; skipping DISPENSING")
    return(NULL)
  }

  results <- list()

  # NDC codes for SCT patients
  ndc <- tryCatch({
    disp_tbl %>%
      filter(ID %in% sct_ids & !is.na(NDC) & NDC != "") %>%
      select(ID, NDC, RXNORM_CUI, RAW_DISPENSE_MED_NAME, DISPENSE_DATE) %>%
      collect()
  }, error = function(e) NULL)

  if (!is.null(ndc) && nrow(ndc) > 0) {
    ndc_out <- ndc %>%
      mutate(
        source_table = "DISPENSING",
        code_system = "NDC",
        drug_name = RAW_DISPENSE_MED_NAME,
        rxnorm = RXNORM_CUI,
        ENCOUNTERID = NA_character_
      ) %>%
      select(ID, source_table, code = NDC, code_system, event_date = DISPENSE_DATE,
             ENCOUNTERID, drug_name, rxnorm)
    results <- c(results, list(ndc_out))
  }

  bind_rows(compact(results))
}

# ==============================================================================
# SECTION 5: PRESCRIBING -- RXNORM for SCT patients
# ==============================================================================

extract_sct_prescribing <- function() {
  message("  PRESCRIBING...")
  rx_tbl <- safe_table("PRESCRIBING")
  if (is.null(rx_tbl)) return(NULL)

  sct_ids <- get_sct_patient_ids()
  if (length(sct_ids) == 0) {
    message("    No SCT patients found; skipping PRESCRIBING")
    return(NULL)
  }

  df <- tryCatch({
    rx_tbl %>%
      filter(ID %in% sct_ids & !is.na(RXNORM_CUI) & RXNORM_CUI != "") %>%
      select(ID, RXNORM_CUI, RAW_RX_MED_NAME, RX_ORDER_DATE, ENCOUNTERID) %>%
      collect()
  }, error = function(e) NULL)

  if (is.null(df) || nrow(df) == 0) return(NULL)

  df %>%
    mutate(
      source_table = "PRESCRIBING",
      code_system = "RXNORM",
      drug_name = RAW_RX_MED_NAME,
      rxnorm = RXNORM_CUI
    ) %>%
    select(ID, source_table, code = RXNORM_CUI, code_system,
           event_date = RX_ORDER_DATE, ENCOUNTERID, drug_name, rxnorm)
}

# ==============================================================================
# SECTION 6: MED_ADMIN -- RXNORM for SCT patients
# ==============================================================================

extract_sct_med_admin <- function() {
  message("  MED_ADMIN...")
  ma_tbl <- safe_table("MED_ADMIN")
  if (is.null(ma_tbl)) return(NULL)

  sct_ids <- get_sct_patient_ids()
  if (length(sct_ids) == 0) {
    message("    No SCT patients found; skipping MED_ADMIN")
    return(NULL)
  }

  df <- tryCatch({
    ma_tbl %>%
      filter(ID %in% sct_ids & !is.na(RXNORM_CUI) & RXNORM_CUI != "") %>%
      select(ID, RXNORM_CUI, RAW_MEDADMIN_MED_NAME, MEDADMIN_START_DATE, ENCOUNTERID) %>%
      collect()
  }, error = function(e) NULL)

  if (is.null(df) || nrow(df) == 0) return(NULL)

  df %>%
    mutate(
      source_table = "MED_ADMIN",
      code_system = "RXNORM",
      drug_name = RAW_MEDADMIN_MED_NAME,
      rxnorm = RXNORM_CUI
    ) %>%
    select(ID, source_table, code = RXNORM_CUI, code_system,
           event_date = MEDADMIN_START_DATE, ENCOUNTERID, drug_name, rxnorm)
}

# ==============================================================================
# SECTION 7: TUMOR_REGISTRY -- SCT date columns
# ==============================================================================

extract_sct_tumor_registry <- function() {
  message("  TUMOR_REGISTRY...")
  tr_tbl <- safe_table("TUMOR_REGISTRY_ALL")
  if (is.null(tr_tbl)) return(NULL)

  tr_cols <- colnames(tr_tbl)

  # SCT-related date columns in TUMOR_REGISTRY
  sct_date_cols <- intersect(
    c("DT_HTE", "HEMATOLOGIC_TRANSPLANT_AND_ENDOC"),
    tr_cols
  )

  if (length(sct_date_cols) == 0) {
    message("    No SCT date columns found in TUMOR_REGISTRY")
    return(NULL)
  }

  results <- list()

  for (col in sct_date_cols) {
    df <- tryCatch({
      tr_tbl %>%
        filter(!is.na(!!sym(col))) %>%
        select(ID, !!sym(col)) %>%
        collect()
    }, error = function(e) NULL)

    if (!is.null(df) && nrow(df) > 0) {
      out <- df %>%
        mutate(
          source_table = "TUMOR_REGISTRY",
          code = col,
          code_system = "DATE_COLUMN",
          event_date = as.character(!!sym(col)),
          ENCOUNTERID = NA_character_,
          drug_name = NA_character_,
          rxnorm = NA_character_
        ) %>%
        select(ID, source_table, code, code_system, event_date, ENCOUNTERID, drug_name, rxnorm)
      results <- c(results, list(out))
    }
  }

  bind_rows(compact(results))
}

# ==============================================================================
# SECTION 8: SCT PATIENT ID LOOKUP (used by DISPENSING/PRESCRIBING/MED_ADMIN)
# ==============================================================================

# Cache for SCT patient IDs (computed once, reused)
.sct_ids_cache <- NULL

get_sct_patient_ids <- function() {
  if (!is.null(.sct_ids_cache)) return(.sct_ids_cache)

  message("    Identifying SCT patients from PROCEDURES + ENCOUNTER + DIAGNOSIS...")
  ids <- character(0)

  # From PROCEDURES
  proc_tbl <- safe_table("PROCEDURES")
  if (!is.null(proc_tbl)) {
    proc_ids <- tryCatch({
      all_sct_px <- c(
        TREATMENT_CODES$sct_cpt, TREATMENT_CODES$sct_hcpcs,
        TREATMENT_CODES$sct_icd9, TREATMENT_CODES$sct_icd10pcs,
        TREATMENT_CODES$sct_revenue
      )
      proc_tbl %>%
        filter(PX %in% all_sct_px) %>%
        select(ID) %>%
        distinct() %>%
        collect() %>%
        pull(ID)
    }, error = function(e) character(0))
    ids <- union(ids, proc_ids)
  }

  # From ENCOUNTER (DRG)
  enc_tbl <- safe_table("ENCOUNTER")
  if (!is.null(enc_tbl)) {
    enc_ids <- tryCatch({
      enc_tbl %>%
        filter(DRG %in% TREATMENT_CODES$sct_drg) %>%
        select(ID) %>%
        distinct() %>%
        collect() %>%
        pull(ID)
    }, error = function(e) character(0))
    ids <- union(ids, enc_ids)
  }

  # From DIAGNOSIS
  dx_tbl <- safe_table("DIAGNOSIS")
  if (!is.null(dx_tbl)) {
    dx_ids <- tryCatch({
      dx_tbl %>%
        filter(DX_TYPE == "10" & DX %in% TREATMENT_CODES$sct_dx_icd10) %>%
        select(ID) %>%
        distinct() %>%
        collect() %>%
        pull(ID)
    }, error = function(e) character(0))
    ids <- union(ids, dx_ids)
  }

  # From TUMOR_REGISTRY
  tr_tbl <- safe_table("TUMOR_REGISTRY_ALL")
  if (!is.null(tr_tbl)) {
    tr_cols <- colnames(tr_tbl)
    if ("DT_HTE" %in% tr_cols) {
      tr_ids <- tryCatch({
        tr_tbl %>%
          filter(!is.na(DT_HTE)) %>%
          select(ID) %>%
          distinct() %>%
          collect() %>%
          pull(ID)
      }, error = function(e) character(0))
      ids <- union(ids, tr_ids)
    }
  }

  message(glue("    Found {length(ids)} unique SCT patients"))
  .sct_ids_cache <<- ids
  ids
}

# ==============================================================================
# SECTION 9: XLSX OUTPUT
# ==============================================================================

write_sheet <- function(wb, sheet_name, df) {
  wb$add_worksheet(sheet_name)

  # Title
  wb$add_data(sheet = sheet_name, x = glue("SCT Evidence: {sheet_name}"),
              start_row = 1, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A1",
              name = "Calibri", size = 14, bold = TRUE, color = wb_color("FF1F2937"))

  n_patients <- n_distinct(df$ID)
  n_records <- nrow(df)
  wb$add_data(sheet = sheet_name,
              x = glue("{format(n_records, big.mark = ',')} records from {n_patients} patients"),
              start_row = 2, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A2",
              name = "Calibri", size = 10, color = wb_color("FF6B7280"))

  # Header row
  header_row <- 4
  headers <- names(df)
  for (i in seq_along(headers)) {
    wb$add_data(sheet = sheet_name, x = headers[i],
                start_row = header_row, start_col = i)
  }
  header_dims <- glue("A{header_row}:{LETTERS[length(headers)]}{header_row}")
  wb$add_fill(sheet = sheet_name, dims = header_dims, color = wb_color("FF374151"))
  wb$add_font(sheet = sheet_name, dims = header_dims,
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  # Data
  data_row <- header_row + 1
  if (nrow(df) > 0) {
    wb$add_data(sheet = sheet_name, x = as.data.frame(df),
                start_row = data_row, col_names = FALSE)
  }

  # Freeze
  wb$freeze_pane(sheet = sheet_name, first_active_row = data_row)

  # Column widths
  widths <- pmin(pmax(nchar(headers) + 4, 14), 40)
  wb$set_col_widths(sheet = sheet_name, cols = seq_along(headers), widths = widths)

  invisible(wb)
}

# ==============================================================================
# SECTION 10: MAIN EXECUTION
# ==============================================================================

message("=== SCT Code Inventory: All Codes from Every Source Table ===")
message("")
message("Extracting SCT evidence from all PCORnet tables...")

# Extract from each source
proc_df  <- extract_sct_procedures()
enc_df   <- extract_sct_encounters()
dx_df    <- extract_sct_diagnosis()
disp_df  <- extract_sct_dispensing()
rx_df    <- extract_sct_prescribing()
ma_df    <- extract_sct_med_admin()
tr_df    <- extract_sct_tumor_registry()

# Standardize columns (some sources have drug_name/rxnorm, others don't)
standardize <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(NULL)
  if (!"drug_name" %in% names(df)) df$drug_name <- NA_character_
  if (!"rxnorm" %in% names(df)) df$rxnorm <- NA_character_
  if (!"ENCOUNTERID" %in% names(df)) df$ENCOUNTERID <- NA_character_
  df %>% select(ID, source_table, code, code_system, event_date,
                ENCOUNTERID, drug_name, rxnorm)
}

all_evidence <- bind_rows(compact(lapply(
  list(proc_df, enc_df, dx_df, disp_df, rx_df, ma_df, tr_df),
  standardize
)))

# --- Console summary ---
message("")
message("--- Summary by Source Table ---")
if (nrow(all_evidence) > 0) {
  summary_tbl <- all_evidence %>%
    group_by(source_table, code_system) %>%
    summarise(
      n_records = n(),
      n_patients = n_distinct(ID),
      n_unique_codes = n_distinct(code),
      .groups = "drop"
    ) %>%
    arrange(source_table, desc(n_records))

  for (r in seq_len(nrow(summary_tbl))) {
    row <- summary_tbl[r, ]
    message(glue("  {row$source_table} ({row$code_system}): {format(row$n_records, big.mark = ',')} records, {row$n_patients} patients, {row$n_unique_codes} unique codes"))
  }

  message("")
  message(glue("Total SCT patients: {n_distinct(all_evidence$ID)}"))
  message(glue("Total SCT records:  {format(nrow(all_evidence), big.mark = ',')}"))
} else {
  message("  No SCT evidence found in any table.")
}

# --- Write xlsx ---
message("")
message("Writing xlsx workbook...")
wb <- wb_workbook()

# Summary sheet
if (nrow(all_evidence) > 0) {
  code_summary <- all_evidence %>%
    group_by(source_table, code_system, code) %>%
    summarise(
      n_records = n(),
      n_patients = n_distinct(ID),
      example_drug_name = first(na.omit(drug_name)),
      .groups = "drop"
    ) %>%
    arrange(source_table, code_system, desc(n_records))

  write_sheet(wb, "Summary", code_summary)
}

# Per-source sheets with all detail rows
source_tables <- c("PROCEDURES", "ENCOUNTER", "DIAGNOSIS",
                   "DISPENSING", "PRESCRIBING", "MED_ADMIN", "TUMOR_REGISTRY")

for (src in source_tables) {
  src_data <- filter(all_evidence, source_table == src)
  if (nrow(src_data) > 0) {
    sheet_df <- src_data %>%
      arrange(ID, event_date, code) %>%
      select(-source_table)
    write_sheet(wb, src, sheet_df)
  }
}

# Save
dir.create(CONFIG$output_dir, showWarnings = FALSE, recursive = TRUE)
wb$save(OUTPUT_PATH)
message("")
message(glue("Output: {OUTPUT_PATH}"))
message("=== SCT Code Inventory Complete ===")
