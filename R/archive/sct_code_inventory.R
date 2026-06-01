# ==============================================================================
# sct_code_inventory.R -- SCT Evidence: All Codes from Every Source Table
# ==============================================================================
#
# Extracts every SCT-related record from all PCORnet CDM tables, showing
# the actual PX codes, DX codes, DRG codes found per patient per date across:
#   PROCEDURES, ENCOUNTER, DIAGNOSIS, TUMOR_REGISTRY
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

# safe_table() now provided by R/utils_treatment.R (auto-sourced via R/00_config.R)

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
# SECTION 4: TUMOR_REGISTRY -- SCT date columns
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
          ENCOUNTERID = NA_character_
        ) %>%
        select(ID, source_table, code, code_system, event_date, ENCOUNTERID)
      results <- c(results, list(out))
    }
  }

  bind_rows(compact(results))
}

# ==============================================================================
# SECTION 5: CODE MEANING LOOKUP
# ==============================================================================
#
# Built-in descriptions for all known SCT codes from TREATMENT_CODES in config.

SCT_CODE_MEANINGS <- c(
  # CPT
  "38230"   = "Bone marrow harvesting for transplantation",
  "38232"   = "Bone marrow harvesting for transplantation, autologous",
  "38240"   = "Allogeneic hematopoietic cell transplantation (HCT)",
  "38241"   = "Autologous hematopoietic cell transplantation (HCT)",
  "38242"   = "Allogeneic donor lymphocyte infusion (DLI)",
  "38243"   = "Allogeneic hematopoietic cell boost",
  # HCPCS
  "S2140"   = "Cord blood harvesting for transplantation, allogeneic",
  "S2142"   = "Cord blood-derived stem-cell transplantation, allogeneic",
  "S2150"   = "Bone marrow or blood-derived stem cells, allogeneic or autologous",
  # ICD-9-CM Vol 3
  "41.00"   = "Bone marrow transplant, NOS",
  "41.01"   = "Autologous bone marrow transplant without purging",
  "41.02"   = "Allogeneic bone marrow transplant with purging",
  "41.03"   = "Allogeneic bone marrow transplant without purging",
  "41.04"   = "Autologous hematopoietic stem cell transplant without purging",
  "41.05"   = "Allogeneic hematopoietic stem cell transplant without purging",
  "41.06"   = "Cord blood stem cell transplant",
  "41.07"   = "Autologous hematopoietic stem cell transplant with purging",
  "41.08"   = "Allogeneic hematopoietic stem cell transplant with purging",
  "41.09"   = "Autologous bone marrow transplant with purging",
  # ICD-10-PCS (selected -- full list is 49 codes)
  "30230G0" = "Autologous bone marrow, peripheral vein, open",
  "30230Y0" = "Autologous HPC, peripheral vein, open",
  "30230C0" = "Autologous HPC (genetically modified), peripheral vein, open",
  "30230X0" = "Autologous cord blood stem cells, peripheral vein, open",
  "30240G0" = "Autologous bone marrow, central vein, open",
  "30240Y0" = "Autologous HPC, central vein, open",
  "30240C0" = "Autologous HPC (genetically modified), central vein, open",
  "30240X0" = "Autologous cord blood stem cells, central vein, open",
  "30233C0" = "Autologous HPC (genetically modified), peripheral vein, percutaneous",
  "30233G0" = "Autologous HPC, peripheral vein, percutaneous",
  "30233X0" = "Autologous cord blood stem cells, peripheral vein, percutaneous",
  "30233Y0" = "Autologous HPC (other), peripheral vein, percutaneous",
  "30243C0" = "Autologous HPC (genetically modified), central vein, percutaneous",
  "30243G0" = "Autologous HPC, central vein, percutaneous",
  "30243X0" = "Autologous cord blood stem cells, central vein, percutaneous",
  "30243Y0" = "Autologous HPC (other), central vein, percutaneous",
  "30233G1" = "Nonautologous HPC, peripheral vein, percutaneous",
  "30233X1" = "Nonautologous cord blood stem cells, peripheral vein, percutaneous",
  "30233Y1" = "Nonautologous HPC (other), peripheral vein, percutaneous",
  "30243G1" = "Nonautologous HPC, central vein, percutaneous",
  "30243X1" = "Nonautologous cord blood stem cells, central vein, percutaneous",
  "30243Y1" = "Nonautologous HPC (other), central vein, percutaneous",
  "30233G2" = "Allogeneic related bone marrow, peripheral vein, percutaneous",
  "30233G3" = "Allogeneic unrelated bone marrow, peripheral vein, percutaneous",
  "30233U2" = "Allogeneic related T-cell depleted BM, peripheral vein, percutaneous",
  "30233U3" = "Allogeneic unrelated T-cell depleted BM, peripheral vein, percutaneous",
  "30233X2" = "Allogeneic related cord blood, peripheral vein, percutaneous",
  "30233X3" = "Allogeneic unrelated cord blood, peripheral vein, percutaneous",
  "30233Y2" = "Allogeneic related HPC, peripheral vein, percutaneous",
  "30233Y3" = "Allogeneic unrelated HPC, peripheral vein, percutaneous",
  "30243G2" = "Allogeneic related bone marrow, central vein, percutaneous",
  "30243G3" = "Allogeneic unrelated bone marrow, central vein, percutaneous",
  "30243U2" = "Allogeneic related T-cell depleted BM, central vein, percutaneous",
  "30243U3" = "Allogeneic unrelated T-cell depleted BM, central vein, percutaneous",
  "30243X2" = "Allogeneic related cord blood, central vein, percutaneous",
  "30243X3" = "Allogeneic unrelated cord blood, central vein, percutaneous",
  "30243Y2" = "Allogeneic related HPC, central vein, percutaneous",
  "30243Y3" = "Allogeneic unrelated HPC, central vein, percutaneous",
  "30230AZ" = "Embryonic stem cells, peripheral vein, open",
  "30233AZ" = "Embryonic stem cells, peripheral vein, percutaneous",
  "30240AZ" = "Embryonic stem cells, central vein, open",
  "30243AZ" = "Embryonic stem cells, central vein, percutaneous",
  "XW133C8" = "Transfusion of Omidubicel, peripheral vein, percutaneous",
  "XW143C8" = "Transfusion of Omidubicel, central vein, percutaneous",
  # DX codes
  "Z94.84"  = "Stem cells transplant status",
  "T86.5"   = "Complications of stem cell transplant",
  "T86.09"  = "Other complications of bone marrow transplant",
  "T86.0"   = "Complications of bone marrow transplant",
  "Z48.290" = "Encounter for aftercare following bone marrow transplant",
  # DRG codes
  "014"     = "Allogeneic bone marrow transplant",
  "016"     = "Autologous BMT w CC/MCC or T-cell immunotherapy",
  "017"     = "Autologous BMT w/o CC/MCC",
  # Revenue codes
  "0362"    = "Organ transplant - other than kidney (includes SCT)",
  "0815"    = "Allogeneic stem cell acquisition/donor services",
  # Tumor registry date columns
  "DT_HTE"  = "Hematologic transplant and endocrine therapy date",
  "HEMATOLOGIC_TRANSPLANT_AND_ENDOC" = "Hematologic transplant and endocrine flag"
)

#' Look up meaning for a code from the built-in dictionary
resolve_meaning <- function(code) {
  meaning <- SCT_CODE_MEANINGS[code]
  ifelse(!is.na(meaning), meaning, "")
}

# ==============================================================================
# SECTION 6: XLSX OUTPUT -- resolved-style format
# ==============================================================================

# SCT color scheme (matches 42_treatment_codes_resolved.R)
SCT_FILL  <- "FFFFF4D6"   # light yellow
SCT_FONT  <- "FF7F6000"   # dark olive

write_resolved_sheet <- function(wb, sheet_name, df, title) {
  wb$add_worksheet(sheet_name)

  n_codes <- nrow(df)

  # Row 1: Title
  wb$add_data(sheet = sheet_name, x = glue("{title} ({n_codes} codes)"),
              start_row = 1, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A1",
              name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
  wb$merge_cells(sheet = sheet_name, dims = "A1:F1")

  # Row 2: Column headers
  headers <- c("Code", "Meaning", "Code Type", "Source Table", "Records", "Patients")
  for (i in seq_along(headers)) {
    wb$add_data(sheet = sheet_name, x = headers[i],
                start_row = 2, start_col = i)
  }
  wb$add_fill(sheet = sheet_name, dims = "A2:F2", color = wb_color("FF374151"))
  wb$add_font(sheet = sheet_name, dims = "A2:F2",
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  # Row 3+: Data
  if (n_codes > 0) {
    write_df <- data.frame(
      Code         = df$code,
      Meaning      = df$meaning,
      Code_Type    = df$code_type,
      Source_Table = df$source_table,
      Records      = df$records,
      Patients     = df$patients,
      stringsAsFactors = FALSE
    )
    wb$add_data(sheet = sheet_name, x = write_df, start_row = 3, col_names = FALSE)

    last_row <- 2 + n_codes

    # Code column: SCT yellow pill
    code_dims <- glue("A3:A{last_row}")
    wb$add_fill(sheet = sheet_name, dims = code_dims, color = wb_color(SCT_FILL))
    wb$add_font(sheet = sheet_name, dims = code_dims,
                name = "Calibri", size = 10, bold = TRUE, color = wb_color(SCT_FONT))

    # Number formatting
    wb$add_numfmt(sheet = sheet_name, dims = glue("E3:F{last_row}"), numfmt = "#,##0")
  }

  # Freeze below headers
  wb$freeze_pane(sheet = sheet_name, first_active_row = 3)

  # Column widths
  wb$set_col_widths(sheet = sheet_name, cols = 1:6, widths = c(15, 55, 14, 16, 10, 10))

  invisible(wb)
}

write_detail_sheet <- function(wb, sheet_name, df) {
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
  n_cols <- length(headers)
  col_letter <- if (n_cols <= 26) LETTERS[n_cols] else paste0(LETTERS[(n_cols - 1) %/% 26], LETTERS[((n_cols - 1) %% 26) + 1])
  header_dims <- glue("A{header_row}:{col_letter}{header_row}")
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
# SECTION 7: MAIN EXECUTION
# ==============================================================================

message("=== SCT Code Inventory: All Codes from Every Source Table ===")
message("")
message("Extracting SCT evidence from all PCORnet tables...")

# Extract from each source
proc_df  <- extract_sct_procedures()
enc_df   <- extract_sct_encounters()
dx_df    <- extract_sct_diagnosis()
tr_df    <- extract_sct_tumor_registry()

# Standardize columns
standardize <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(NULL)
  if (!"ENCOUNTERID" %in% names(df)) df$ENCOUNTERID <- NA_character_
  df %>%
    mutate(event_date = as.character(event_date)) %>%
    select(ID, source_table, code, code_system, event_date, ENCOUNTERID)
}

all_evidence <- bind_rows(compact(lapply(
  list(proc_df, enc_df, dx_df, tr_df),
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

# --- Build resolved summary: Code | Meaning | Code Type | Source Table | Records | Patients ---
message("")
message("Building resolved code summary...")

resolved <- all_evidence %>%
  group_by(code, code_system, source_table) %>%
  summarise(
    records  = n(),
    patients = n_distinct(ID),
    .groups = "drop"
  ) %>%
  mutate(
    meaning   = resolve_meaning(code),
    code_type = code_system
  ) %>%
  select(code, meaning, code_type, source_table, records, patients) %>%
  arrange(desc(patients), desc(records))

message(glue("  {nrow(resolved)} unique code/source combinations"))

# --- Write xlsx ---
message("")
message("Writing xlsx workbook...")
wb <- wb_workbook()

# Sheet 1: Resolved summary (matches all_codes_resolved format)
if (nrow(resolved) > 0) {
  write_resolved_sheet(wb, "SCT Codes", resolved, "SCT Codes")
}

# Per-source detail sheets
source_tables <- c("PROCEDURES", "ENCOUNTER", "DIAGNOSIS", "TUMOR_REGISTRY")

for (src in source_tables) {
  src_data <- filter(all_evidence, source_table == src)
  if (nrow(src_data) > 0) {
    sheet_df <- src_data %>%
      arrange(ID, event_date, code) %>%
      select(-source_table)
    write_detail_sheet(wb, src, sheet_df)
  }
}

# Notes sheet
wb$add_worksheet("Notes")
notes <- c(
  glue("Data Source: PCORnet CDM tables via DuckDB ({CONFIG$cache$duckdb_path})"),
  "Code descriptions: Built-in from TREATMENT_CODES (00_config.R)",
  glue("Generated: {Sys.Date()}"),
  "Classification: Stem Cell Transplant (SCT) codes across all source tables",
  "Columns: Code | Meaning | Code Type | Source Table | Records | Patients",
  "Sorted by patient count (descending) for clinical relevance"
)
for (i in seq_along(notes)) {
  wb$add_data(sheet = "Notes", x = as.character(notes[i]),
              start_row = i, start_col = 1)
}

# Save
dir.create(CONFIG$output_dir, showWarnings = FALSE, recursive = TRUE)
wb$save(OUTPUT_PATH)
message("")
message(glue("Output: {OUTPUT_PATH}"))
message("=== SCT Code Inventory Complete ===")
