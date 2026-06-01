# ==============================================================================
# Phase 41: Extract All Unique Codes from Data
# ==============================================================================
# Bottom-up approach: pull every unique code that actually appears in the
# patient data, with patient counts and record counts, so we can categorize
# each code manually.
#
# Outputs:
#   - output/tables/all_codes_inventory.xlsx
#     Sheet 1 "ICD-10 Diagnosis": every unique DX code (ICD-10) with counts
#     Sheet 2 "ICD-O-3 Topography": every unique topography code with counts
#
# Usage:
#   Rscript R/41_extract_all_codes.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

OUTPUT_PATH <- file.path(CONFIG$output_dir, "tables", "all_codes_inventory.xlsx")
dir.create(dirname(OUTPUT_PATH), showWarnings = FALSE, recursive = TRUE)

message("=== Phase 48: Extract All Unique Codes ===")

# ==============================================================================
# 1. ICD-10 codes from DIAGNOSIS
# ==============================================================================

message("Loading DIAGNOSIS table (ICD-10 only)...")

dx_icd10 <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  select(ID, DX) %>%
  collect()

message(glue("  Total ICD-10 DIAGNOSIS rows: {format(nrow(dx_icd10), big.mark=',')}"))

# Normalize: uppercase, remove dots
dx_icd10 <- dx_icd10 %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\.")))

# Summarize: unique code, patient count, record count
icd10_summary <- dx_icd10 %>%
  group_by(DX_norm) %>%
  summarise(
    patients = n_distinct(ID),
    records  = n(),
    .groups  = "drop"
  ) %>%
  arrange(DX_norm) %>%
  rename(code = DX_norm)

message(glue("  Unique ICD-10 codes: {format(nrow(icd10_summary), big.mark=',')}"))
message(glue("  Top 10 by patients:"))
top10_dx <- icd10_summary %>% arrange(desc(patients)) %>% head(10)
for (r in seq_len(nrow(top10_dx))) {
  message(glue("    {top10_dx$code[r]}: {top10_dx$patients[r]} patients, {top10_dx$records[r]} records"))
}

# ==============================================================================
# 2. ICD-O-3 topography codes from TUMOR_REGISTRY_ALL
# ==============================================================================

message("\nLoading TUMOR_REGISTRY_ALL table (topography codes)...")

tr_all_lazy <- get_pcornet_table("TUMOR_REGISTRY_ALL")
tr_cols <- colnames(tr_all_lazy)

# Find topography column(s)
site_candidates <- intersect(c("SITE_CODE", "SITE", "PRIMARY_SITE",
                                "TOPOGRAPHY_CODE", "ICDOSITE"), tr_cols)
message(glue("  Topography column candidates: {paste(site_candidates, collapse=', ')}"))

if (length(site_candidates) == 0) {
  message("  WARNING: No topography column found. Skipping ICD-O-3.")
  icdo3_summary <- tibble(code = character(), patients = integer(), records = integer())
} else {
  coalesce_expr <- rlang::parse_expr(paste0("coalesce(", paste(site_candidates, collapse = ", "), ")"))
  tr_topo <- tr_all_lazy %>%
    mutate(topo_raw = !!coalesce_expr) %>%
    select(ID, topo_raw) %>%
    filter(!is.na(topo_raw)) %>%
    collect()

  message(glue("  Total TUMOR_REGISTRY rows with topography: {format(nrow(tr_topo), big.mark=',')}"))

  tr_topo <- tr_topo %>%
    mutate(topo_norm = toupper(str_remove_all(topo_raw, "\\.")))

  icdo3_summary <- tr_topo %>%
    group_by(topo_norm) %>%
    summarise(
      patients = n_distinct(ID),
      records  = n(),
      .groups  = "drop"
    ) %>%
    arrange(topo_norm) %>%
    rename(code = topo_norm)

  message(glue("  Unique ICD-O-3 topography codes: {format(nrow(icdo3_summary), big.mark=',')}"))
  message(glue("  Top 10 by patients:"))
  top10_tr <- icdo3_summary %>% arrange(desc(patients)) %>% head(10)
  for (r in seq_len(nrow(top10_tr))) {
    message(glue("    {top10_tr$code[r]}: {top10_tr$patients[r]} patients, {top10_tr$records[r]} records"))
  }
}

# ==============================================================================
# 3. Write xlsx with two sheets
# ==============================================================================

message(glue("\nWriting {OUTPUT_PATH}..."))

DARK_HEADER_FILL <- "FF374151"
WHITE_FONT       <- "FFFFFFFF"

wb <- wb_workbook()

# --- Sheet 1: ICD-10 ---
wb$add_worksheet("ICD-10 Diagnosis")
headers_dx <- c("Code", "Patients", "Records")
for (i in seq_along(headers_dx)) {
  wb$add_data(sheet = "ICD-10 Diagnosis", x = headers_dx[i], start_row = 1, start_col = i)
}
wb$add_fill(sheet = "ICD-10 Diagnosis", dims = "A1:C1", color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = "ICD-10 Diagnosis", dims = "A1:C1",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color(WHITE_FONT))

if (nrow(icd10_summary) > 0) {
  wb$add_data(sheet = "ICD-10 Diagnosis", x = as.data.frame(icd10_summary),
              start_row = 2, col_names = FALSE)
  end_row <- 1 + nrow(icd10_summary)
  wb$add_numfmt(sheet = "ICD-10 Diagnosis", dims = glue("B2:C{end_row}"), numfmt = "#,##0")
}

wb$freeze_pane(sheet = "ICD-10 Diagnosis", first_active_row = 2, first_active_col = 1)
wb$set_col_widths(sheet = "ICD-10 Diagnosis", cols = 1:3, widths = c(16, 12, 12))

# --- Sheet 2: ICD-O-3 ---
wb$add_worksheet("ICD-O-3 Topography")
headers_tr <- c("Code", "Patients", "Records")
for (i in seq_along(headers_tr)) {
  wb$add_data(sheet = "ICD-O-3 Topography", x = headers_tr[i], start_row = 1, start_col = i)
}
wb$add_fill(sheet = "ICD-O-3 Topography", dims = "A1:C1", color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = "ICD-O-3 Topography", dims = "A1:C1",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color(WHITE_FONT))

if (nrow(icdo3_summary) > 0) {
  wb$add_data(sheet = "ICD-O-3 Topography", x = as.data.frame(icdo3_summary),
              start_row = 2, col_names = FALSE)
  end_row <- 1 + nrow(icdo3_summary)
  wb$add_numfmt(sheet = "ICD-O-3 Topography", dims = glue("B2:C{end_row}"), numfmt = "#,##0")
}

wb$freeze_pane(sheet = "ICD-O-3 Topography", first_active_row = 2, first_active_col = 1)
wb$set_col_widths(sheet = "ICD-O-3 Topography", cols = 1:3, widths = c(16, 12, 12))

# Save
wb$save(OUTPUT_PATH)

message(glue("\nWrote {OUTPUT_PATH}"))
message(glue("  Sheet 'ICD-10 Diagnosis': {nrow(icd10_summary)} unique codes"))
message(glue("  Sheet 'ICD-O-3 Topography': {nrow(icdo3_summary)} unique codes"))
message("\n=== Done. Open the xlsx and share the code list for categorization. ===")
