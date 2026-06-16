# ==============================================================================
# 33_code_verification.R -- Code Verification (CODE-01/02/03)
# ==============================================================================
#
# Purpose:
#   Combined investigation of three code classification concerns raised in team
#   meetings: (1) Ethna/etanercept immunotherapy classification, (2) revenue code
#   0362 organ transplant vs SCT usage, (3) SCT diagnosis codes above line 22.
#   Standalone investigation script producing meeting-ready xlsx with data-driven
#   findings and recommendations.
#
# Inputs:
#   - DuckDB PRESCRIBING table (via get_pcornet_table) -- for etanercept RxNorm queries
#   - DuckDB PROCEDURES table (via get_pcornet_table) -- for revenue code 0362 and SCT procedures
#   - DuckDB DIAGNOSIS table (via get_pcornet_table) -- for SCT status/complication codes
#   - R/00_config.R -- DRUG_GROUPINGS immunotherapy_rxnorm, sct codes, QUESTIONABLE_IMMUNO_CODES
#
# Outputs:
#   - output/code_verification.xlsx (four-sheet meeting-presentable xlsx)
#     Sheet 1 "Summary": Combined recommendations from all 3 investigations
#     Sheet 2 "CODE-01 Detail": Etanercept prescription records
#     Sheet 3 "CODE-02 Detail": Revenue code 0362 records with SCT evidence flags
#     Sheet 4 "CODE-03 Detail": SCT status/complication diagnosis records
#
# Phase 105 Decisions (Code Verification):
#   D-01: Two scripts total (this is the combined CODE-01/02/03 script)
#   D-02: Single xlsx with tabs per investigation plus summary tab with recommendations
#   D-04: CODE-01 queries PRESCRIBING for etanercept RxNorm codes (1653225, 809158, 809159, 214555)
#   D-05: CODE-02 queries PROCEDURES for revenue code 0362, cross-references SCT evidence
#   D-06: CODE-03 queries DIAGNOSIS for Z94.84/T86.5/T86.09, cross-references procedure evidence
#   D-10: Report-only -- no modifications to R/00_config.R or existing scripts
#   D-11: Raw counts without HIPAA suppression (manual suppression before sharing)
#
# Dependencies:
#   - R/00_config.R (CONFIG paths, DRUG_GROUPINGS)
#   - R/utils/utils_duckdb.R (get_pcornet_table)
#   - R/utils/utils_assertions.R (assert functions)
#
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND CONFIGURATION ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(lubridate)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/utils/utils_assertions.R")
source("R/utils/utils_duckdb.R")

# --- Define file paths ---
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "code_verification.xlsx")

message("=== R/33: Code Verification (CODE-01/02/03) ===")
message()
message(glue("  Output: {OUTPUT_XLSX}"))
message()


# ==============================================================================
# SECTION 2: INPUT VALIDATION ----
# ==============================================================================

message("--- Input validation ---")

# Validate DuckDB connection is available (test query)
tryCatch({
  test_query <- get_pcornet_table("DIAGNOSIS") %>% head(1) %>% collect()
  message("  DuckDB connection validated.")
}, error = function(e) {
  stop(glue("DuckDB connection failed: {e$message}"), call. = FALSE)
})

message()


# ==============================================================================
# SECTION 3: CODE-01 -- ETANERCEPT/ETHNA INVESTIGATION ----
# ==============================================================================

message("--- CODE-01: Etanercept/Ethna immunotherapy classification ---")

# Define etanercept RxNorm codes (per D-04)
# Pitfall 1 guard: Always quote RxNorm codes as character strings
etanercept_codes <- c("1653225", "809158", "809159", "214555")

# Query PRESCRIBING for etanercept prescriptions
etanercept_rx <- get_pcornet_table("PRESCRIBING") %>%
  filter(RXNORM_CUI %in% etanercept_codes) %>%
  select(ID, RXNORM_CUI, RX_START_DATE, RAW_RX_MED_NAME) %>%
  collect()

message(glue("  Found {nrow(etanercept_rx)} etanercept prescriptions for {n_distinct(etanercept_rx$ID)} patients"))

# Cross-reference against TREATMENT_CODES immunotherapy_rxnorm
immuno_rxnorm <- TREATMENT_CODES$immunotherapy_rxnorm

# Check overlap
overlap_immuno <- intersect(etanercept_codes, immuno_rxnorm)
message(glue("  Etanercept codes in DRUG_GROUPINGS immunotherapy_rxnorm: {length(overlap_immuno)} of {length(etanercept_codes)}"))

# Check QUESTIONABLE_IMMUNO_CODES
overlap_questionable <- intersect(etanercept_codes, names(QUESTIONABLE_IMMUNO_CODES))
message(glue("  Etanercept codes in QUESTIONABLE_IMMUNO_CODES: {length(overlap_questionable)} of {length(etanercept_codes)}"))

# Build CODE-01 findings table
code01_finding <- data.frame(
  Finding = "Etanercept classification",
  Status = if (length(overlap_immuno) == 0) "CORRECT" else "NEEDS CORRECTION",
  Detail = if (length(overlap_immuno) == 0) {
    "Etanercept correctly excluded from DRUG_GROUPINGS immunotherapy -- it is a TNF-alpha inhibitor (immunosuppressant), not anticancer immunotherapy"
  } else {
    glue("{length(overlap_immuno)} etanercept codes found in immunotherapy_rxnorm -- should be excluded")
  },
  Recommendation = if (length(overlap_immuno) == 0) {
    "No action needed -- etanercept is correctly excluded from immunotherapy grouping"
  } else {
    "Remove etanercept codes from DRUG_GROUPINGS immunotherapy_rxnorm"
  },
  stringsAsFactors = FALSE
)

# Build CODE-01 detail table
code01_detail <- etanercept_rx %>%
  select(ID, RXNORM_CUI, RX_START_DATE, RAW_RX_MED_NAME)

message(glue("  CODE-01 finding: {code01_finding$Status}"))
message()


# ==============================================================================
# SECTION 4: CODE-02 -- ORGAN TRANSPLANT CODE 0362 INVESTIGATION ----
# ==============================================================================

message("--- CODE-02: Revenue code 0362 investigation ---")

# Query PROCEDURES for revenue code 0362 (per D-05)
rev_0362 <- get_pcornet_table("PROCEDURES") %>%
  filter(REVENUE_CODE == "0362") %>%
  select(ID, ENCOUNTERID, REVENUE_CODE, PX, PX_TYPE, PX_DATE) %>%
  collect()

message(glue("  Found {nrow(rev_0362)} records with revenue code 0362 for {n_distinct(rev_0362$ID)} patients"))

# Cross-reference with SCT diagnosis codes (Z94.84)
# Pitfall 2 guard: Normalize ICD codes with toupper(str_remove_all(DX, "\\."))
sct_dx <- get_pcornet_table("DIAGNOSIS") %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(DX_norm == "Z9484") %>%
  select(ID) %>%
  distinct() %>%
  collect()

message(glue("  Patients with Z94.84 SCT status code: {nrow(sct_dx)}"))

# Cross-reference with SCT procedure codes (38240-38243, 30233/30243 series)
# Extract from TREATMENT_CODES or DRUG_GROUPINGS
sct_proc_codes <- c("38240", "38241", "38242", "38243",
                    "30233Y0", "30233Y1", "30233Y2", "30233Y3", "30233C0", "30233G0", "30233X0",
                    "30243Y0", "30243Y1", "30243Y2", "30243Y3", "30243C0", "30243G0", "30243G1",
                    "30243G2", "30243G3", "30243U3", "30243X0")

sct_proc <- get_pcornet_table("PROCEDURES") %>%
  filter(PX %in% sct_proc_codes) %>%
  select(ID) %>%
  distinct() %>%
  collect()

message(glue("  Patients with SCT procedure codes: {nrow(sct_proc)}"))

# Classify 0362 patients by SCT evidence
patients_0362 <- unique(rev_0362$ID)
has_sct_dx <- intersect(patients_0362, sct_dx$ID)
has_sct_proc <- intersect(patients_0362, sct_proc$ID)
has_either_sct <- unique(c(has_sct_dx, has_sct_proc))

message(glue("  0362 patients with SCT dx: {length(has_sct_dx)} ({sprintf('%.1f%%', 100*length(has_sct_dx)/length(patients_0362))})"))
message(glue("  0362 patients with SCT proc: {length(has_sct_proc)} ({sprintf('%.1f%%', 100*length(has_sct_proc)/length(patients_0362))})"))
message(glue("  0362 patients with either SCT evidence: {length(has_either_sct)} ({sprintf('%.1f%%', 100*length(has_either_sct)/length(patients_0362))})"))

# Build CODE-02 summary table
code02_summary <- data.frame(
  Revenue_Code = "0362",
  Total_Records = nrow(rev_0362),
  Unique_Patients = length(patients_0362),
  With_SCT_Dx = length(has_sct_dx),
  With_SCT_Proc = length(has_sct_proc),
  With_Either_SCT_Evidence = length(has_either_sct),
  Pct_SCT_Evidence = sprintf("%.1f%%", 100 * length(has_either_sct) / length(patients_0362)),
  Recommendation = "Revenue code 0362 covers both solid organ and SCT -- assess fraction with corroborating SCT evidence",
  stringsAsFactors = FALSE
)

# Build CODE-02 detail table with SCT evidence flags
code02_detail <- rev_0362 %>%
  mutate(
    has_sct_dx_flag = ID %in% has_sct_dx,
    has_sct_proc_flag = ID %in% has_sct_proc
  ) %>%
  select(ID, ENCOUNTERID, PX_DATE, has_sct_dx_flag, has_sct_proc_flag)

message()


# ==============================================================================
# SECTION 5: CODE-03 -- SCT DIAGNOSIS CODES ABOVE LINE 22 ----
# ==============================================================================

message("--- CODE-03: SCT status/complication diagnosis codes above line 22 ---")

# Define SCT status/complication codes (both dotted and undotted per D-06)
# Pitfall 2 guard: Include both formats for normalization
sct_status_codes_norm <- c("Z9484", "T865", "T8609")

# Query DIAGNOSIS for these codes
sct_status_dx <- get_pcornet_table("DIAGNOSIS") %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(DX_norm %in% sct_status_codes_norm) %>%
  select(ID, DX, DX_TYPE, DX_DATE) %>%
  collect()

message(glue("  Found {nrow(sct_status_dx)} SCT status/complication diagnosis records for {n_distinct(sct_status_dx$ID)} patients"))

# Add normalized DX column for grouping
sct_status_dx <- sct_status_dx %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\.")))

# Break down by code
code_breakdown <- sct_status_dx %>%
  group_by(DX_norm) %>%
  summarise(n_patients = n_distinct(ID), n_records = n(), .groups = "drop")

message("  Breakdown by code:")
for (i in seq_len(nrow(code_breakdown))) {
  message(glue("    {code_breakdown$DX_norm[i]}: {code_breakdown$n_patients[i]} patients, {code_breakdown$n_records[i]} records"))
}

# Cross-reference with procedure-based SCT evidence (reuse from Section 4)
patients_sct_dx <- unique(sct_status_dx$ID)
patients_diagnosis_only <- setdiff(patients_sct_dx, sct_proc$ID)
patients_diagnosis_and_proc <- intersect(patients_sct_dx, sct_proc$ID)

message(glue("  Diagnosis-only (no procedure evidence): {length(patients_diagnosis_only)} patients"))
message(glue("  Diagnosis + procedure evidence: {length(patients_diagnosis_and_proc)} patients"))

# Verify these codes are NOT in DRUG_GROUPINGS
# DRUG_GROUPINGS is a named character vector where names are codes, values are categories
drug_grouping_codes <- names(DRUG_GROUPINGS)
z9484_in_dg <- "Z9484" %in% drug_grouping_codes | "Z94.84" %in% drug_grouping_codes
t865_in_dg <- "T865" %in% drug_grouping_codes | "T86.5" %in% drug_grouping_codes
t8609_in_dg <- "T8609" %in% drug_grouping_codes | "T86.09" %in% drug_grouping_codes

message(glue("  Z94.84 in DRUG_GROUPINGS: {z9484_in_dg}"))
message(glue("  T86.5 in DRUG_GROUPINGS: {t865_in_dg}"))
message(glue("  T86.09 in DRUG_GROUPINGS: {t8609_in_dg}"))

# Build CODE-03 summary table
code03_summary <- data.frame(
  Code = c("Z94.84", "T86.5", "T86.09"),
  Code_Description = c("Bone marrow transplant status", "SCT complications", "BMT complications"),
  Patient_Count = c(
    sum(sct_status_dx$DX_norm == "Z9484"),
    sum(sct_status_dx$DX_norm == "T865"),
    sum(sct_status_dx$DX_norm == "T8609")
  ),
  In_DRUG_GROUPINGS = c(
    if (z9484_in_dg) "Yes" else "No",
    if (t865_in_dg) "Yes" else "No",
    if (t8609_in_dg) "Yes" else "No"
  ),
  With_Procedure_Evidence = sprintf("%d (%.1f%%)",
    c(
      sum(sct_status_dx$DX_norm == "Z9484" & sct_status_dx$ID %in% sct_proc$ID),
      sum(sct_status_dx$DX_norm == "T865" & sct_status_dx$ID %in% sct_proc$ID),
      sum(sct_status_dx$DX_norm == "T8609" & sct_status_dx$ID %in% sct_proc$ID)
    ),
    100 * c(
      sum(sct_status_dx$DX_norm == "Z9484" & sct_status_dx$ID %in% sct_proc$ID) / max(sum(sct_status_dx$DX_norm == "Z9484"), 1),
      sum(sct_status_dx$DX_norm == "T865" & sct_status_dx$ID %in% sct_proc$ID) / max(sum(sct_status_dx$DX_norm == "T865"), 1),
      sum(sct_status_dx$DX_norm == "T8609" & sct_status_dx$ID %in% sct_proc$ID) / max(sum(sct_status_dx$DX_norm == "T8609"), 1)
    )
  ),
  Without_Procedure_Evidence = sprintf("%d (%.1f%%)",
    c(
      sum(sct_status_dx$DX_norm == "Z9484" & !(sct_status_dx$ID %in% sct_proc$ID)),
      sum(sct_status_dx$DX_norm == "T865" & !(sct_status_dx$ID %in% sct_proc$ID)),
      sum(sct_status_dx$DX_norm == "T8609" & !(sct_status_dx$ID %in% sct_proc$ID))
    ),
    100 * c(
      sum(sct_status_dx$DX_norm == "Z9484" & !(sct_status_dx$ID %in% sct_proc$ID)) / max(sum(sct_status_dx$DX_norm == "Z9484"), 1),
      sum(sct_status_dx$DX_norm == "T865" & !(sct_status_dx$ID %in% sct_proc$ID)) / max(sum(sct_status_dx$DX_norm == "T865"), 1),
      sum(sct_status_dx$DX_norm == "T8609" & !(sct_status_dx$ID %in% sct_proc$ID)) / max(sum(sct_status_dx$DX_norm == "T8609"), 1)
    )
  ),
  Recommendation = "Correctly excluded from DRUG_GROUPINGS -- status/complication codes, not treatment events",
  stringsAsFactors = FALSE
)

# Build CODE-03 detail table
code03_detail <- sct_status_dx %>%
  mutate(has_sct_proc_flag = ID %in% sct_proc$ID) %>%
  select(ID, DX, DX_norm, DX_DATE, has_sct_proc_flag)

message()


# ==============================================================================
# SECTION 6: CREATE STYLED XLSX ----
# ==============================================================================

message("--- Creating styled xlsx output ---")

wb <- wb_workbook()

# ==============================================================================
# Sheet 1: Summary ----
# ==============================================================================

wb$add_worksheet("Summary")

# Title row (Calibri 16pt bold, dark gray)
wb$add_data(sheet = "Summary", x = "Code Verification -- Combined Investigation Report", start_row = 1, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A1", name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Summary", dims = "A1:D1")

# Subtitle row 2
wb$add_data(sheet = "Summary", x = glue("Generated: {Sys.Date()}"), start_row = 2, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A2", name = "Calibri", size = 10, color = wb_color("FF6B7280"))

# Blank row 3

# Sub-header row 4: CODE-01
wb$add_data(sheet = "Summary", x = "CODE-01: Etanercept/Ethna Classification", start_row = 4, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A4", name = "Calibri", size = 14, bold = TRUE)

# Header row 5
code01_headers <- c("Investigation", "Status", "Detail", "Recommendation")
for (i in seq_along(code01_headers)) {
  wb$add_data(sheet = "Summary", x = code01_headers[i], start_row = 5, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A5:D5", color = wb_color("FF374151"))
wb$add_font(sheet = "Summary", dims = "A5:D5", name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Data row 6
wb$add_data(sheet = "Summary", x = code01_finding, start_row = 6, col_names = FALSE)

# Skip row 7, CODE-02 sub-header row 8
wb$add_data(sheet = "Summary", x = "CODE-02: Organ Transplant Revenue Code 0362", start_row = 8, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A8", name = "Calibri", size = 14, bold = TRUE)

# Header row 9
code02_headers <- c("Revenue Code", "Total Records", "Unique Patients", "With SCT Dx", "With SCT Proc", "With Either SCT", "Pct SCT", "Recommendation")
for (i in seq_along(code02_headers)) {
  wb$add_data(sheet = "Summary", x = code02_headers[i], start_row = 9, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A9:H9", color = wb_color("FF374151"))
wb$add_font(sheet = "Summary", dims = "A9:H9", name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Data row 10
wb$add_data(sheet = "Summary", x = code02_summary, start_row = 10, col_names = FALSE)

# Skip row 11, CODE-03 sub-header row 12
wb$add_data(sheet = "Summary", x = "CODE-03: SCT Status/Complication Codes Above Line 22", start_row = 12, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A12", name = "Calibri", size = 14, bold = TRUE)

# Header row 13
code03_headers <- c("Code", "Description", "Patient Count", "In DRUG_GROUPINGS", "With Proc Evidence", "Without Proc Evidence", "Recommendation")
for (i in seq_along(code03_headers)) {
  wb$add_data(sheet = "Summary", x = code03_headers[i], start_row = 13, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A13:G13", color = wb_color("FF374151"))
wb$add_font(sheet = "Summary", dims = "A13:G13", name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Data rows 14-16
wb$add_data(sheet = "Summary", x = code03_summary, start_row = 14, col_names = FALSE)

# Freeze pane below first header row
wb$freeze_pane(sheet = "Summary", firstActiveRow = 6)

# Column widths
wb$set_col_widths(sheet = "Summary", cols = 1:8, widths = c(20, 15, 50, 50, 15, 15, 15, 50))


# ==============================================================================
# Sheet 2: CODE-01 Detail ----
# ==============================================================================

wb$add_worksheet("CODE-01 Detail")

# Title row
wb$add_data(sheet = "CODE-01 Detail", x = "CODE-01: Etanercept Prescriptions in Cohort", start_row = 1, start_col = 1)
wb$add_font(sheet = "CODE-01 Detail", dims = "A1", name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "CODE-01 Detail", dims = "A1:D1")

# Blank row 2, header row 3
code01_detail_headers <- c("ID", "RXNORM_CUI", "RX_START_DATE", "RAW_RX_MED_NAME")
for (i in seq_along(code01_detail_headers)) {
  wb$add_data(sheet = "CODE-01 Detail", x = code01_detail_headers[i], start_row = 3, start_col = i)
}
wb$add_fill(sheet = "CODE-01 Detail", dims = "A3:D3", color = wb_color("FF374151"))
wb$add_font(sheet = "CODE-01 Detail", dims = "A3:D3", name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Data rows
if (nrow(code01_detail) > 0) {
  wb$add_data(sheet = "CODE-01 Detail", x = code01_detail, start_row = 4, col_names = FALSE)
}

# Freeze pane
wb$freeze_pane(sheet = "CODE-01 Detail", firstActiveRow = 4)

# Column widths
wb$set_col_widths(sheet = "CODE-01 Detail", cols = 1:4, widths = c(15, 15, 15, 40))


# ==============================================================================
# Sheet 3: CODE-02 Detail ----
# ==============================================================================

wb$add_worksheet("CODE-02 Detail")

# Title row
wb$add_data(sheet = "CODE-02 Detail", x = "CODE-02: Revenue Code 0362 Records with SCT Evidence", start_row = 1, start_col = 1)
wb$add_font(sheet = "CODE-02 Detail", dims = "A1", name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "CODE-02 Detail", dims = "A1:E1")

# Blank row 2, header row 3
code02_detail_headers <- c("ID", "ENCOUNTERID", "PX_DATE", "Has_SCT_Dx", "Has_SCT_Proc")
for (i in seq_along(code02_detail_headers)) {
  wb$add_data(sheet = "CODE-02 Detail", x = code02_detail_headers[i], start_row = 3, start_col = i)
}
wb$add_fill(sheet = "CODE-02 Detail", dims = "A3:E3", color = wb_color("FF374151"))
wb$add_font(sheet = "CODE-02 Detail", dims = "A3:E3", name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Data rows
if (nrow(code02_detail) > 0) {
  wb$add_data(sheet = "CODE-02 Detail", x = code02_detail, start_row = 4, col_names = FALSE)
}

# Freeze pane
wb$freeze_pane(sheet = "CODE-02 Detail", firstActiveRow = 4)

# Column widths
wb$set_col_widths(sheet = "CODE-02 Detail", cols = 1:5, widths = c(15, 20, 15, 15, 15))


# ==============================================================================
# Sheet 4: CODE-03 Detail ----
# ==============================================================================

wb$add_worksheet("CODE-03 Detail")

# Title row
wb$add_data(sheet = "CODE-03 Detail", x = "CODE-03: SCT Status/Complication Diagnosis Codes", start_row = 1, start_col = 1)
wb$add_font(sheet = "CODE-03 Detail", dims = "A1", name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "CODE-03 Detail", dims = "A1:E1")

# Blank row 2, header row 3
code03_detail_headers <- c("ID", "DX", "DX_norm", "DX_DATE", "Has_SCT_Proc")
for (i in seq_along(code03_detail_headers)) {
  wb$add_data(sheet = "CODE-03 Detail", x = code03_detail_headers[i], start_row = 3, start_col = i)
}
wb$add_fill(sheet = "CODE-03 Detail", dims = "A3:E3", color = wb_color("FF374151"))
wb$add_font(sheet = "CODE-03 Detail", dims = "A3:E3", name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Data rows
if (nrow(code03_detail) > 0) {
  wb$add_data(sheet = "CODE-03 Detail", x = code03_detail, start_row = 4, col_names = FALSE)
}

# Freeze pane
wb$freeze_pane(sheet = "CODE-03 Detail", firstActiveRow = 4)

# Column widths
wb$set_col_widths(sheet = "CODE-03 Detail", cols = 1:5, widths = c(15, 15, 15, 15, 15))


# ==============================================================================
# Save workbook ----
# ==============================================================================

wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
message(glue("  Saved: {OUTPUT_XLSX}"))
message()


# ==============================================================================
# SECTION 7: FINAL SUMMARY ----
# ==============================================================================

message("=== R/33 Code Verification Complete ===")
message()
message("Total findings:")
message(glue("  CODE-01 (Etanercept): {code01_finding$Status}"))
message(glue("    - Etanercept prescriptions in cohort: {nrow(etanercept_rx)}"))
message(glue("    - Overlap with immunotherapy_rxnorm: {length(overlap_immuno)}"))
message()
message(glue("  CODE-02 (Revenue code 0362): {nrow(rev_0362)} records, {length(patients_0362)} patients"))
message(glue("    - With SCT evidence: {length(has_either_sct)} ({sprintf('%.1f%%', 100*length(has_either_sct)/length(patients_0362))})"))
message()
message(glue("  CODE-03 (SCT diagnosis codes): {nrow(sct_status_dx)} records, {length(patients_sct_dx)} patients"))
message(glue("    - Diagnosis-only: {length(patients_diagnosis_only)}"))
message(glue("    - Diagnosis + procedure: {length(patients_diagnosis_and_proc)}"))
message()
message(glue("Output file: {OUTPUT_XLSX}"))
message("Done.")
