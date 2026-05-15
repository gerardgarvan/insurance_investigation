# ==============================================================================
# Phase 45: Radiation CPT Audit
# ==============================================================================
#
# Audits the full CPT 70010-79999 radiology range to explain why the pipeline
# uses a narrow set of radiation treatment codes rather than the full range
# specified in TreatmentVariables.docx.
#
# Purpose:
#   - Provide collaborators (Amy Crisp / team) a self-explanatory document
#     justifying the pipeline's narrow radiation code set.
#   - Show which 7-prefix codes actually appear in PROCEDURES data.
#   - Classify each code as Diagnostic Imaging / Radiation Treatment / Mixed.
#   - Auto-add any confirmed treatment codes found in data but not in config.
#
# Inputs:
#   - R/00_config.R (TREATMENT_CODES$radiation_cpt)
#   - PROCEDURES DuckDB table (all patients, all PX_TYPEs)
#
# Outputs:
#   - output/tables/radiation_cpt_audit.xlsx (2-sheet styled workbook)
#     Sheet 1: "CPT Classification" — AMA chapter structure table
#     Sheet 2: "Codes in Data" — all 7xxxx + G60xx codes found in PROCEDURES
#
# Usage:
#   Rscript R/45_radiation_cpt_audit.R
#
# Requirements: RADCPT-01, RADCPT-02, RADCPT-03
# Phase 45 Plan 01 -- radiation-cpt-audit
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP AND CLASSIFICATION TABLE (RADCPT-01)
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

OUTPUT_PATH <- file.path(CONFIG$output_dir, "tables", "radiation_cpt_audit.xlsx")
dir.create(dirname(OUTPUT_PATH), showWarnings = FALSE, recursive = TRUE)

message("=== Phase 45: Radiation CPT Audit ===")
message(glue("Output: {OUTPUT_PATH}"))

# Hardcoded AMA CPT chapter structure — authoritative reference, no API needed.
# Source: AMA CPT Manual chapter organization (publicly documented range boundaries).
# Citation: AMA CPT chapter structure; CMS LCD L34652 RAD014; CMS Article A57669
classification_table <- tibble::tribble(
  ~range_start, ~range_end, ~ama_category,           ~classification,       ~rationale,
  70010L,       76499L,     "Diagnostic Radiology",   "Diagnostic Imaging",  "X-ray, CT, MRI, fluoroscopy, angiography — produces images for diagnosis, not therapeutic radiation",
  76506L,       76999L,     "Diagnostic Ultrasound",  "Diagnostic Imaging",  "Ultrasound for obstetric, abdominal, and vascular diagnosis — no ionizing radiation delivered",
  77001L,       77032L,     "Radiological Guidance",  "Diagnostic Imaging",  "Fluoroscopic/CT guidance during interventional procedures — imaging component billed separately from treatment",
  77046L,       77067L,     "Mammography",            "Diagnostic Imaging",  "Breast screening and diagnostic imaging — not therapeutic radiation",
  77261L,       77299L,     "Treatment Planning",     "Radiation Treatment", "Clinical simulation, target volume definition, beam arrangement — essential precursor to treatment delivery",
  77295L,       77370L,     "Physics & Dosimetry",    "Radiation Treatment", "Medical physicist services, dose calculations, treatment device fabrication — integral to safe treatment delivery",
  77371L,       77499L,     "Treatment Delivery",     "Radiation Treatment", "External beam radiation delivery (EBRT, IMRT, VMAT, SRS, SBRT, proton, neutron) — actual therapeutic radiation",
  77520L,       77525L,     "Proton Beam Delivery",   "Radiation Treatment", "Proton beam treatment delivery (particle therapy subset within 77371-77499) — higher precision than photon",
  77600L,       77620L,     "Hyperthermia",           "Radiation Treatment", "Thermal adjunct applied concurrent with radiation — enhances tumor response",
  77750L,       77799L,     "Brachytherapy",          "Radiation Treatment", "Internal radiation source placement (seeds, catheters, HDR) — high/low dose rate, interstitial/intracavitary",
  78000L,       78999L,     "Nuclear Medicine",       "Mixed",               "Mostly diagnostic (PET, thyroid scan, bone scan); therapeutic codes 78800-78816 exist for radionuclide therapy"
)

# Add display range column
classification_table <- classification_table %>%
  mutate(
    code_range = glue("{range_start}-{range_end}"),
    citation   = "AMA CPT Manual chapter structure"
  ) %>%
  relocate(code_range, .before = range_start)

message(glue("Built classification table: {nrow(classification_table)} AMA sub-ranges"))

# ==============================================================================
# SECTION 2: CODE DESCRIPTION LOOKUP
# ==============================================================================

# Hardcoded descriptions for retired radiation codes (NLM API returns "not_found"
# for deleted codes — this is the root cause of the Phase 39 "no description" problem).
# Source: AMA CPT pre-2015 descriptors; CMS LCD L34652 RAD014 (archived)
hardcoded_descriptions <- c(
  "77401" = "External beam radiation delivery, surface/orthovoltage (DELETED 2026; historical claims only)",
  "77402" = "Radiation treatment delivery; simple (complexity-based, 2026 new code)",
  "77404" = "Radiation treatment delivery; single area, 6-10 MeV (DELETED 2015)",
  "77407" = "Radiation treatment delivery; intermediate (complexity-based, 2026 new code)",
  "77408" = "Radiation treatment delivery; 2 separate areas, 3+ ports, 6-10 MeV (DELETED 2015)",
  "77412" = "Radiation treatment delivery; complex (complexity-based, 2026 new code)",
  "77413" = "Radiation treatment delivery; 3+ separate areas, custom blocking, 6-10 MeV (DELETED 2015)",
  "77414" = "Radiation treatment delivery; 3+ separate areas, custom blocking, 11-19 MeV (DELETED 2015)",
  "77416" = "Radiation treatment delivery; 3+ separate areas, complex, 20+ MeV (DELETED 2015)",
  "77417" = "Port film(s) per treatment session / portal imaging (DELETED 2026, bundled into delivery)",
  "77418" = "Radiation treatment delivery, IMRT — intensity modulated (DELETED 2015)",
  "77421" = "Stereoscopic x-ray guidance for target localization (DELETED 2015, replaced by 77387)",
  "77427" = "Radiation treatment management, weekly — per 5 fractions",
  "77431" = "Radiation treatment management, 1-4 treatments (end-of-course)",
  "77432" = "Stereotactic radiation treatment management of cranial lesion",
  "77435" = "Stereotactic body radiation therapy (SBRT) management",
  "77470" = "Special treatment procedure (total body irradiation, hemibody irradiation)",
  "77520" = "Proton treatment delivery; simple, without compensation",
  "77522" = "Proton treatment delivery; simple, with compensation",
  "77523" = "Proton treatment delivery; intermediate",
  "77525" = "Proton treatment delivery; complex",
  # G-codes (deleted 2026; Medicare temporary codes for LINAC delivery)
  "G6003" = "Radiation treatment delivery, IMRT — 1 or more sessions (DELETED 2026)",
  "G6004" = "Radiation treatment delivery, IMRT — subsequent sessions (DELETED 2026)",
  "G6005" = "Radiation treatment delivery using electron beam — simple (DELETED 2026)",
  "G6006" = "Radiation treatment delivery using electron beam — intermediate (DELETED 2026)",
  "G6007" = "Radiation treatment delivery using electron beam — complex (DELETED 2026)",
  "G6008" = "Radiation treatment delivery; simple, 2D (DELETED 2026)",
  "G6009" = "Radiation treatment delivery; intermediate, 2D (DELETED 2026)",
  "G6010" = "Radiation treatment delivery; complex, 2D (DELETED 2026)",
  "G6011" = "Radiation treatment delivery; simple, 3D (DELETED 2026)",
  "G6012" = "Radiation treatment delivery; intermediate, 3D (DELETED 2026)",
  "G6013" = "Radiation treatment delivery; complex, 3D (DELETED 2026)",
  "G6014" = "Radiation treatment delivery, IMRT — simple (DELETED 2026)",
  "G6015" = "Radiation treatment delivery, IMRT — complex (DELETED 2026)",
  "G6016" = "Radiation treatment delivery; custom blocks (DELETED 2026)"
)

#' Get description for a CPT/HCPCS code.
#' Returns hardcoded description if available, else "No description available".
get_description <- function(code) {
  if (code %in% names(hardcoded_descriptions)) {
    return(hardcoded_descriptions[[code]])
  }
  "No description available"
}

# ==============================================================================
# SECTION 3: CLASSIFY CODE FUNCTION
# ==============================================================================

#' Classify a numeric CPT code against the AMA classification table.
#' Uses findInterval to identify which sub-range the code falls in.
#' @param code_numeric Integer. Numeric code value.
#' @return Named list: classification, ama_category
classify_code <- function(code_numeric, table) {
  # Check if code falls within 70010-79999 range
  if (code_numeric < 70010L || code_numeric > 79999L) {
    return(list(classification = "Outside 70010-79999", ama_category = NA_character_))
  }

  # Find the sub-range: use findInterval on range_start sorted ascending
  idx <- findInterval(code_numeric, table$range_start)

  if (idx == 0L) {
    return(list(classification = "Outside 70010-79999", ama_category = NA_character_))
  }

  # Check the code is not ABOVE the range_end for that sub-range
  if (code_numeric > table$range_end[idx]) {
    # In a gap between sub-ranges (e.g., 76500-76505)
    return(list(classification = "Between AMA Sub-Ranges", ama_category = NA_character_))
  }

  list(
    classification = table$classification[idx],
    ama_category   = table$ama_category[idx]
  )
}

# ==============================================================================
# SECTION 4: QUERY PROCEDURES FOR 70010-79999 CODES (RADCPT-02)
# ==============================================================================

message("Querying PROCEDURES table for 7xxxxx CPT codes (all patients, all PX_TYPEs)...")

proc_tbl <- tryCatch(
  get_pcornet_table("PROCEDURES"),
  error = function(e) {
    stop(glue("PROCEDURES table not found: {e$message}"))
  }
)

# D-12: ALL patients (no HL filter)
# D-13: ALL PX_TYPEs (no PX_TYPE filter)
# Materialize first (Phase 39 pattern), then apply str_detect regex in R memory

message("  Materializing PROCEDURES table...")
proc_materialized <- proc_tbl %>%
  materialize()

message(glue("  Materialized {format(nrow(proc_materialized), big.mark = ',')} procedure records"))

# Filter for 5-digit codes starting with 7 (CPT 70000-79999 range)
message("  Filtering for 7xxxxx CPT codes...")
codes_7x <- proc_materialized %>%
  filter(str_detect(PX, "^7[0-9]{4}$"))

# Filter for G-codes G6003-G6016 (Medicare radiation codes, deleted 2026)
# Per D-13: include all PX_TYPEs; these use PX_TYPE='CH'
message("  Filtering for G6003-G6016 radiation G-codes...")
codes_gx <- proc_materialized %>%
  filter(str_detect(PX, "^G60(0[3-9]|1[0-6])$"))

# Union and group by code + px_type
codes_in_data <- bind_rows(codes_7x, codes_gx) %>%
  group_by(code = PX, px_type = PX_TYPE) %>%
  summarise(
    encounter_count = n(),
    patient_count   = n_distinct(ID),
    .groups = "drop"
  ) %>%
  arrange(code, px_type)

message(glue("  Found {format(nrow(codes_in_data), big.mark = ',')} code-PX_TYPE combinations across all patients"))

# ==============================================================================
# SECTION 5: CLASSIFY CODES FOUND IN DATA
# ==============================================================================

message("Classifying codes by AMA sub-range...")

# Build a helper to classify a single code string (handles both 7xxxx and G60xx)
classify_code_str <- function(code_str, table) {
  if (str_detect(code_str, "^G60(0[3-9]|1[0-6])$")) {
    # G-codes are Medicare radiation delivery codes (deleted 2026)
    return(list(classification = "Radiation Treatment",
                ama_category   = "G-Code Radiation Delivery (CMS)"))
  }
  cn <- suppressWarnings(as.integer(code_str))
  if (is.na(cn)) {
    return(list(classification = "Outside 70010-79999", ama_category = NA_character_))
  }
  classify_code(cn, table)
}

codes_classified <- codes_in_data %>%
  mutate(
    classification = purrr::map_chr(code, function(c) {
      classify_code_str(c, classification_table)$classification
    }),
    ama_category = purrr::map_chr(code, function(c) {
      res <- classify_code_str(c, classification_table)$ama_category
      if (is.null(res) || is.na(res)) NA_character_ else res
    }),
    in_config   = code %in% TREATMENT_CODES$radiation_cpt,
    description = purrr::map_chr(code, get_description)
  ) %>%
  select(code, px_type, description, ama_category, classification,
         in_config, patient_count, encounter_count) %>%
  arrange(code, px_type)

message(glue("  Classified {format(nrow(codes_classified), big.mark = ',')} code-PX_TYPE combinations"))

# ==============================================================================
# SECTION 6: AUTO-ADD CONFIRMED TREATMENT CODES (D-10)
# ==============================================================================

# Identify codes classified as Radiation Treatment that appear in data but NOT in config.
# Only consider numeric 7xxxxx codes (not G-codes, which are deleted/retired).
new_treatment_codes <- codes_classified %>%
  filter(
    classification == "Radiation Treatment",
    !in_config,
    str_detect(code, "^7[0-9]{4}$")
  ) %>%
  distinct(code) %>%
  pull(code)

if (length(new_treatment_codes) > 0) {
  message(glue("AUTO-ADD: Found {length(new_treatment_codes)} new radiation treatment codes in data: {paste(new_treatment_codes, collapse=', ')}"))
  message("Applying parse/source validated config update (Phase 39 pattern)...")

  config_path <- "R/00_config.R"
  config_text <- readLines(config_path)

  # Find the closing paren of radiation_cpt vector
  # Look for the last entry before the closing paren
  rad_close_idx <- which(str_detect(config_text, '"77525"\\s+# Proton treatment delivery; complex'))

  if (length(rad_close_idx) == 1) {
    # Build new lines to insert before closing paren
    new_lines <- purrr::map_chr(new_treatment_codes, function(code) {
      desc <- get_description(code)
      glue('    "{code}",   # {desc}  (auto-added Phase 45: found in PROCEDURES data)')
    })

    # Change the last existing entry to have a comma (if it doesn't already)
    config_text[rad_close_idx] <- str_replace(
      config_text[rad_close_idx],
      '("77525"\\s+# Proton treatment delivery; complex)',
      '"77525",   # Proton treatment delivery; complex'
    )

    # Update the final new code to not have a trailing comma
    new_lines[length(new_lines)] <- str_replace(new_lines[length(new_lines)], ",$", "")

    # Insert new lines after the 77525 line
    config_text <- c(
      config_text[1:rad_close_idx],
      new_lines,
      config_text[(rad_close_idx + 1):length(config_text)]
    )

    # Validate: write to temp, parse, source
    tmp <- tempfile(fileext = ".R")
    writeLines(config_text, tmp)
    tryCatch({
      parse(tmp)
      tmp_env <- new.env(parent = emptyenv())
      source(tmp, local = tmp_env)
      # If valid, overwrite original
      writeLines(config_text, config_path)
      message(glue("  Auto-added to radiation_cpt: {paste(new_treatment_codes, collapse=', ')}"))
    }, error = function(e) {
      message(glue("  WARNING: Config auto-update failed validation: {e$message}"))
      message("  New codes NOT added to config. Manual review required.")
    }, finally = {
      if (file.exists(tmp)) file.remove(tmp)
    })
  } else {
    message("  WARNING: Could not locate 77525 anchor line in config. Manual review required.")
  }
} else {
  message("No new radiation treatment codes to auto-add (all treatment codes in data are already in config)")
}

# ==============================================================================
# SECTION 7: BUILD SUMMARY STATS
# ==============================================================================

# Unique codes (aggregate across PX_TYPEs for classification)
codes_unique <- codes_classified %>%
  group_by(code, description, ama_category, classification, in_config) %>%
  summarise(
    patient_count   = max(patient_count),
    encounter_count = sum(encounter_count),
    px_types        = paste(sort(unique(px_type)), collapse = ", "),
    .groups = "drop"
  ) %>%
  arrange(code)

n_total       <- nrow(codes_unique)
n_diag        <- sum(codes_unique$classification == "Diagnostic Imaging")
n_treatment   <- sum(codes_unique$classification == "Radiation Treatment")
n_mixed       <- sum(codes_unique$classification == "Mixed")
n_other       <- n_total - n_diag - n_treatment - n_mixed
n_in_config   <- sum(codes_unique$in_config)
n_not_config  <- n_total - n_in_config

message("")
message("=== AUDIT SUMMARY ===")
message(glue("Total unique codes found in PROCEDURES (all patients, all PX_TYPEs): {n_total}"))
message(glue("  Diagnostic Imaging codes: {n_diag}"))
message(glue("  Radiation Treatment codes: {n_treatment}"))
message(glue("  Mixed (Nuclear Medicine): {n_mixed}"))
message(glue("  Other/Gap/Outside range:  {n_other}"))
message(glue("  Already in pipeline config (radiation_cpt): {n_in_config}"))
message(glue("  NOT in pipeline config: {n_not_config}"))
if (length(new_treatment_codes) > 0) {
  message(glue("  Auto-added to config: {paste(new_treatment_codes, collapse=', ')}"))
} else {
  message("  Auto-added to config: none")
}

# ==============================================================================
# SECTION 8: WRITE STYLED XLSX (D-05, Phase 42 openxlsx2 pattern)
# ==============================================================================

message("")
message(glue("Writing xlsx to {OUTPUT_PATH}..."))

# Color scheme consistent with project (dark header, classification-based row colors)
DARK_HEADER_FILL  <- "FF374151"
WHITE_FONT        <- "FFFFFFFF"
TITLE_FONT_COLOR  <- "FF1F2937"
GREEN_FILL        <- "FFDDF4E1"   # Radiation Treatment
YELLOW_FILL       <- "FFFFF4D6"   # Mixed
# No fill for Diagnostic Imaging (default white)

wb <- wb_workbook()

# ---------------------------------------------------------------------------
# SHEET 1: CPT Classification (RADCPT-01)
# ---------------------------------------------------------------------------

SHEET1 <- "CPT Classification"
wb$add_worksheet(SHEET1)

# Row 1: Title
title1 <- "AMA CPT 70010-79999 Range Classification"
n_cols1 <- 7L  # code_range, ama_category, classification, rationale, citation, range_start, range_end
wb$add_data(sheet = SHEET1, x = title1, start_row = 1, start_col = 1)
wb$add_font(sheet = SHEET1, dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color(TITLE_FONT_COLOR))
wb$merge_cells(sheet = SHEET1, dims = glue("A1:{int2col(n_cols1)}1"))

# Row 2: Headers
headers1 <- c("CPT Range", "Range Start", "Range End", "AMA Category",
               "Classification", "Rationale", "Citation")
for (i in seq_along(headers1)) {
  wb$add_data(sheet = SHEET1, x = headers1[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET1, dims = glue("A2:{int2col(n_cols1)}2"),
            color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = SHEET1, dims = glue("A2:{int2col(n_cols1)}2"),
            name = "Calibri", size = 11, bold = TRUE, color = wb_color(WHITE_FONT))

# Rows 3+: Classification data
write_df1 <- classification_table %>%
  select(code_range, range_start, range_end, ama_category, classification, rationale, citation) %>%
  as.data.frame()

wb$add_data(sheet = SHEET1, x = write_df1, start_row = 3, col_names = FALSE)

# Conditional row coloring
last_row1 <- 2L + nrow(write_df1)
for (i in seq_len(nrow(write_df1))) {
  row_i <- 2L + i
  row_dims <- glue("A{row_i}:{int2col(n_cols1)}{row_i}")
  cls <- write_df1$classification[i]
  if (cls == "Radiation Treatment") {
    wb$add_fill(sheet = SHEET1, dims = row_dims, color = wb_color(GREEN_FILL))
  } else if (cls == "Mixed") {
    wb$add_fill(sheet = SHEET1, dims = row_dims, color = wb_color(YELLOW_FILL))
  }
}

# Recommendation row (D-07)
rec_row <- last_row1 + 2L
rec_text <- paste0(
  "RECOMMENDATION: TreatmentVariables.docx specifies CPT 70010-79999 as the radiology range. ",
  "Per AMA CPT chapter structure, only codes 77261-77799 are radiation oncology treatment codes. ",
  "The remaining codes (70010-77260, 77800-79999) are diagnostic imaging, ultrasound, guidance, ",
  "or nuclear medicine. The pipeline uses the narrow treatment-only range (77261-77799) by design."
)
wb$add_data(sheet = SHEET1, x = rec_text, start_row = rec_row, start_col = 1)
wb$merge_cells(sheet = SHEET1, dims = glue("A{rec_row}:{int2col(n_cols1)}{rec_row}"))
wb$add_font(sheet = SHEET1, dims = glue("A{rec_row}"),
            name = "Calibri", size = 10, bold = TRUE, color = wb_color("FF1B5E20"))
wb$add_fill(sheet = SHEET1, dims = glue("A{rec_row}:{int2col(n_cols1)}{rec_row}"),
            color = wb_color("FFE8F5E9"))

# Column widths
wb$set_col_widths(sheet = SHEET1, cols = 1:n_cols1,
                  widths = c(15, 13, 11, 25, 22, 70, 30))

# ---------------------------------------------------------------------------
# SHEET 2: Codes in Data (RADCPT-02)
# ---------------------------------------------------------------------------

SHEET2 <- "Codes in Data"
wb$add_worksheet(SHEET2)

# Row 1: Title
title2 <- glue("CPT 70010-79999 Codes Found in Patient PROCEDURES Data ({n_total} unique codes, all patients, all PX_TYPEs)")
n_cols2 <- 8L
wb$add_data(sheet = SHEET2, x = as.character(title2), start_row = 1, start_col = 1)
wb$add_font(sheet = SHEET2, dims = "A1",
            name = "Calibri", size = 14, bold = TRUE, color = wb_color(TITLE_FONT_COLOR))
wb$merge_cells(sheet = SHEET2, dims = glue("A1:{int2col(n_cols2)}1"))

# Row 2: Headers
headers2 <- c("Code", "PX Type(s)", "Description", "AMA Category",
               "Classification", "In Pipeline Config?", "Patient Count", "Encounter Count")
for (i in seq_along(headers2)) {
  wb$add_data(sheet = SHEET2, x = headers2[i], start_row = 2, start_col = i)
}
wb$add_fill(sheet = SHEET2, dims = glue("A2:{int2col(n_cols2)}2"),
            color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = SHEET2, dims = glue("A2:{int2col(n_cols2)}2"),
            name = "Calibri", size = 11, bold = TRUE, color = wb_color(WHITE_FONT))

# Rows 3+: Codes data
write_df2 <- codes_unique %>%
  mutate(in_config_label = if_else(in_config, "YES", "NO")) %>%
  select(code, px_types, description, ama_category, classification,
         in_config_label, patient_count, encounter_count) %>%
  as.data.frame()

wb$add_data(sheet = SHEET2, x = write_df2, start_row = 3, col_names = FALSE)

# Conditional row coloring based on classification
last_row2 <- 2L + nrow(write_df2)
for (i in seq_len(nrow(write_df2))) {
  row_i <- 2L + i
  row_dims <- glue("A{row_i}:{int2col(n_cols2)}{row_i}")
  cls <- write_df2$classification[i]
  if (cls == "Radiation Treatment") {
    wb$add_fill(sheet = SHEET2, dims = row_dims, color = wb_color(GREEN_FILL))
  } else if (cls == "Mixed") {
    wb$add_fill(sheet = SHEET2, dims = row_dims, color = wb_color(YELLOW_FILL))
  }
}

# Number formatting for count columns
if (nrow(write_df2) > 0) {
  num_dims <- glue("G3:{int2col(n_cols2)}{last_row2}")
  wb$add_numfmt(sheet = SHEET2, dims = num_dims, numfmt = "#,##0")
}

# Column widths
wb$set_col_widths(sheet = SHEET2, cols = 1:n_cols2,
                  widths = c(10, 12, 65, 30, 22, 20, 14, 17))

# ---------------------------------------------------------------------------
# Save workbook
# ---------------------------------------------------------------------------

wb$save(OUTPUT_PATH)
message(glue("Wrote {OUTPUT_PATH}"))
message(glue("  Sheet 1 '{SHEET1}': {nrow(write_df1)} AMA sub-range rows + recommendation"))
message(glue("  Sheet 2 '{SHEET2}': {nrow(write_df2)} unique codes found in PROCEDURES"))

message("")
message("=== Phase 45 Radiation CPT Audit Complete ===")
