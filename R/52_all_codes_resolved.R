# =============================================================================
# Phase 5: All Codes Resolved XLSX Update
# =============================================================================
# Regenerates all_codes_resolved.xlsx and 5 per-type resolved xlsx files from
# the current TREATMENT_CODES in R/00_config.R, with patient/record counts
# queried from PCORnet data via DuckDB and descriptions from a multi-source
# cascade (Phase 39-41 RDS artifacts, Phase 45 hardcoded descriptions, config
# inline comments).
#
# Also curates R/00_config.R inline comments where better descriptions are
# available from API sources.
#
# Input:  R/00_config.R (TREATMENT_CODES source of truth)
#         PCORnet data via DuckDB (PROCEDURES, PRESCRIBING, MED_ADMIN, ENCOUNTER)
#         output/unmatched_codes_classified.rds (Phase 39, optional)
#         output/unmatched_ndc_classified.rds (Phase 40, optional)
# Output: all_codes_resolved.xlsx (6 sheets: 5 types + Summary)
#         chemotherapy_codes_resolved.xlsx
#         radiation_codes_resolved.xlsx
#         sct_codes_resolved.xlsx
#         immunotherapy_codes_resolved.xlsx
#         supportive_care_codes_resolved.xlsx
#         R/00_config.R (inline comment updates)
# =============================================================================

# =============================================================================
# SECTION 1: SETUP AND CONFIGURATION
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(openxlsx2)
  library(tibble)
})

source("R/00_config.R")

message("=== Phase 5: All Codes Resolved XLSX Update ===")
message(glue("Config source: R/00_config.R"))
message(glue("Backend: ", if (USE_DUCKDB) "DuckDB" else "RDS"))

# Define code_type_map: mapping from TREATMENT_CODES vector names to metadata
code_type_map <- tribble(
  ~vector_name,                  ~category,         ~code_type,    ~source_table,          ~px_type, ~match_type,
  "chemo_hcpcs",                 "Chemotherapy",    "CPT/HCPCS",   "PROCEDURES",           "CH",     "exact",
  "chemo_rxnorm",                "Chemotherapy",    "RXNORM",      "PRESCRIBING|MED_ADMIN", NA_character_, "exact",
  "chemo_icd9",                  "Chemotherapy",    "ICD-9",       "PROCEDURES",           "09",     "exact",
  "chemo_icd10pcs_prefixes",     "Chemotherapy",    "ICD-10-PCS",  "PROCEDURES",           "10",     "prefix",
  "chemo_drg",                   "Chemotherapy",    "DRG",         "ENCOUNTER",            NA_character_, "exact",
  "chemo_revenue",               "Chemotherapy",    "Revenue",     "PROCEDURES",           "RE",     "exact",
  "radiation_cpt",               "Radiation",       "CPT/HCPCS",   "PROCEDURES",           "CH",     "exact",
  "radiation_icd9",              "Radiation",       "ICD-9",       "PROCEDURES",           "09",     "exact",
  "radiation_icd10pcs_prefixes", "Radiation",       "ICD-10-PCS",  "PROCEDURES",           "10",     "prefix",
  "radiation_drg",               "Radiation",       "DRG",         "ENCOUNTER",            NA_character_, "exact",
  "radiation_revenue",           "Radiation",       "Revenue",     "PROCEDURES",           "RE",     "exact",
  "sct_cpt",                     "SCT",            "CPT/HCPCS",   "PROCEDURES",           "CH",     "exact",
  "sct_hcpcs",                   "SCT",            "CPT/HCPCS",   "PROCEDURES",           "CH",     "exact",
  "sct_icd9",                    "SCT",            "ICD-9",       "PROCEDURES",           "09",     "exact",
  "sct_icd10pcs",                "SCT",            "ICD-10-PCS",  "PROCEDURES",           "10",     "exact",
  "sct_drg",                     "SCT",            "DRG",         "ENCOUNTER",            NA_character_, "exact",
  "sct_revenue",                 "SCT",            "Revenue",     "PROCEDURES",           "RE",     "exact",
  "sct_rxnorm",                  "SCT",            "RXNORM",      "PRESCRIBING|MED_ADMIN", NA_character_, "exact",
  "cart_icd10pcs_prefixes",      "Immunotherapy",  "ICD-10-PCS",  "PROCEDURES",           "10",     "prefix",
  "immunotherapy_drg",           "Immunotherapy",  "DRG",         "ENCOUNTER",            NA_character_, "exact",
  "immunotherapy_rxnorm",        "Immunotherapy",  "RXNORM",      "PRESCRIBING|MED_ADMIN", NA_character_, "exact",
  "supportive_care_rxnorm",      "Supportive Care","RXNORM",      "PRESCRIBING|MED_ADMIN", NA_character_, "exact"
)

message(glue("Code type map: {nrow(code_type_map)} treatment vector names"))

# =============================================================================
# SECTION 2: DESCRIPTION CASCADE
# =============================================================================

message("\nBuilding description lookup from multi-source cascade...")

# Source 1: Phase 39-41 RDS artifacts
rds_39_path <- file.path(CONFIG$output_dir, "unmatched_codes_classified.rds")
rds_40_path <- file.path(CONFIG$output_dir, "unmatched_ndc_classified.rds")

api_descriptions <- tibble(code = character(), description = character())

if (file.exists(rds_39_path)) {
  rds_39 <- readRDS(rds_39_path)
  message(glue("  Loaded Phase 39 RDS: {nrow(rds_39)} codes"))
  # Extract code + description columns (column names may vary)
  if ("code" %in% names(rds_39) && "description" %in% names(rds_39)) {
    api_descriptions <- bind_rows(api_descriptions, rds_39 %>% select(code, description))
  } else {
    message("  Warning: Phase 39 RDS does not have code/description columns")
  }
} else {
  message("  Phase 39 RDS not found (optional)")
}

if (file.exists(rds_40_path)) {
  rds_40 <- readRDS(rds_40_path)
  message(glue("  Loaded Phase 40 RDS: {nrow(rds_40)} codes"))
  if ("code" %in% names(rds_40) && "description" %in% names(rds_40)) {
    api_descriptions <- bind_rows(api_descriptions, rds_40 %>% select(code, description))
  } else {
    message("  Warning: Phase 40 RDS does not have code/description columns")
  }
} else {
  message("  Phase 40 RDS not found (optional)")
}

# Deduplicate API descriptions (prioritize first occurrence)
api_descriptions <- api_descriptions %>% distinct(code, .keep_all = TRUE)
message(glue("  API descriptions: {nrow(api_descriptions)} unique codes"))

# Source 2: Phase 45 hardcoded radiation descriptions (from R/45b_radiation_cpt_audit.R)
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

hardcoded_desc_tbl <- tibble(
  code = names(hardcoded_descriptions),
  description = unname(hardcoded_descriptions)
)
message(glue("  Hardcoded descriptions: {nrow(hardcoded_desc_tbl)} codes"))

# Source 3: R/00_config.R inline comments
extract_config_comments <- function(config_path = "R/00_config.R") {
  config_lines <- readLines(config_path)
  results <- list()

  for (i in seq_along(config_lines)) {
    line <- config_lines[i]
    # Match: quoted code followed by optional comma and comment
    match <- str_match(line, "\"([A-Za-z0-9]+)\".*#\\s*(.+)$")
    if (!is.na(match[1, 2])) {
      code <- match[1, 2]
      desc <- match[1, 3]
      # Strip Phase 39/40 attribution prefixes
      desc <- str_replace(desc, "^Phase \\d+:\\s*", "")
      results <- c(results, list(tibble(code = code, description = desc)))
    }
  }

  if (length(results) > 0) {
    bind_rows(results) %>% distinct(code, .keep_all = TRUE)
  } else {
    tibble(code = character(), description = character())
  }
}

config_comments <- extract_config_comments()
message(glue("  Config inline comments: {nrow(config_comments)} codes"))

# =============================================================================
# SECTION 3: DUCKDB COUNT QUERIES
# =============================================================================

message("\nQuerying PCORnet tables for patient/record counts...")

# Collect all unique codes from all treatment vectors
all_codes_for_counts <- character()
for (i in seq_len(nrow(code_type_map))) {
  vec_name <- code_type_map$vector_name[i]
  codes <- TREATMENT_CODES[[vec_name]]
  if (!is.null(codes) && length(codes) > 0) {
    all_codes_for_counts <- c(all_codes_for_counts, codes)
  }
}
all_codes_for_counts <- unique(all_codes_for_counts)
message(glue("  Total unique codes across all vectors: {length(all_codes_for_counts)}"))

# Initialize count results
count_results <- tibble(
  code = character(),
  records = integer(),
  patients = integer(),
  vector_name = character()
)

# Query PROCEDURES (for CPT/HCPCS, ICD-9, ICD-10-PCS, Revenue)
proc_tbl <- tryCatch(get_pcornet_table("PROCEDURES"), error = function(e) NULL)
if (!is.null(proc_tbl)) {
  message("  Querying PROCEDURES table...")

  # Filter code_type_map to PROCEDURES rows
  proc_vectors <- code_type_map %>% filter(source_table == "PROCEDURES")

  for (i in seq_len(nrow(proc_vectors))) {
    vec_name <- proc_vectors$vector_name[i]
    px_type <- proc_vectors$px_type[i]
    match_type <- proc_vectors$match_type[i]
    codes <- TREATMENT_CODES[[vec_name]]

    if (is.null(codes) || length(codes) == 0) next

    message(glue("    {vec_name} ({length(codes)} codes, PX_TYPE={px_type}, {match_type})..."))

    if (match_type == "exact") {
      # Exact match
      counts <- tryCatch({
        proc_tbl %>%
          filter(PX_TYPE == px_type, PX %in% codes) %>%
          group_by(code = PX) %>%
          summarise(records = n(), patients = n_distinct(ID), .groups = "drop") %>%
          collect() %>%
          mutate(vector_name = vec_name)
      }, error = function(e) {
        message(glue("      Error: {e$message}"))
        tibble(code = character(), records = integer(), patients = integer(), vector_name = character())
      })
      count_results <- bind_rows(count_results, counts)
    } else if (match_type == "prefix") {
      # Prefix match: check if codes are full 7-char codes or actual prefixes
      # For ICD-10-PCS, config codes are full 7-char codes, use exact match
      if (all(str_length(codes) == 7)) {
        counts <- tryCatch({
          proc_tbl %>%
            filter(PX_TYPE == px_type, PX %in% codes) %>%
            group_by(code = PX) %>%
            summarise(records = n(), patients = n_distinct(ID), .groups = "drop") %>%
            collect() %>%
            mutate(vector_name = vec_name)
        }, error = function(e) {
          message(glue("      Error: {e$message}"))
          tibble(code = character(), records = integer(), patients = integer(), vector_name = character())
        })
        count_results <- bind_rows(count_results, counts)
      } else {
        # True prefix match: materialize and use str_starts_with
        # (This path is unlikely for current config, but handled for completeness)
        all_proc <- tryCatch({
          proc_tbl %>%
            filter(PX_TYPE == px_type) %>%
            select(ID, PX) %>%
            collect()
        }, error = function(e) {
          message(glue("      Error: {e$message}"))
          tibble(ID = character(), PX = character())
        })

        if (nrow(all_proc) > 0) {
          for (prefix in codes) {
            matches <- all_proc %>% filter(str_starts(PX, prefix))
            if (nrow(matches) > 0) {
              counts <- matches %>%
                group_by(code = PX) %>%
                summarise(records = n(), patients = n_distinct(ID), .groups = "drop") %>%
                mutate(vector_name = vec_name)
              count_results <- bind_rows(count_results, counts)
            }
          }
        }
      }
    }
  }
} else {
  message("  PROCEDURES table not found (skipping)")
}

# Query PRESCRIBING + MED_ADMIN (for RXNORM codes)
# Use combined approach to avoid double-counting patients
rxnorm_vectors <- code_type_map %>% filter(str_detect(source_table, "PRESCRIBING\\|MED_ADMIN"))

for (i in seq_len(nrow(rxnorm_vectors))) {
  vec_name <- rxnorm_vectors$vector_name[i]
  codes <- TREATMENT_CODES[[vec_name]]

  if (is.null(codes) || length(codes) == 0) next

  message(glue("  {vec_name} ({length(codes)} codes, RXNORM)..."))

  # Query PRESCRIBING
  presc_tbl <- safe_table("PRESCRIBING")
  presc_matches <- tibble(ID = character(), code = character())
  if (!is.null(presc_tbl)) {
    presc_matches <- tryCatch({
      presc_tbl %>%
        filter(RXNORM_CUI %in% codes) %>%
        select(ID, code = RXNORM_CUI) %>%
        collect()
    }, error = function(e) {
      message(glue("    PRESCRIBING error: {e$message}"))
      tibble(ID = character(), code = character())
    })
  }

  # Query MED_ADMIN
  medadmin_tbl <- safe_table("MED_ADMIN")
  medadmin_matches <- tibble(ID = character(), code = character())
  if (!is.null(medadmin_tbl)) {
    medadmin_matches <- tryCatch({
      medadmin_tbl %>%
        filter(MEDADMIN_CODE %in% codes, MEDADMIN_TYPE == "RX") %>%
        select(ID, code = MEDADMIN_CODE) %>%
        collect()
    }, error = function(e) {
      message(glue("    MED_ADMIN error: {e$message}"))
      tibble(ID = character(), code = character())
    })
  }

  # Combine and group
  combined <- bind_rows(presc_matches, medadmin_matches)
  if (nrow(combined) > 0) {
    counts <- combined %>%
      group_by(code) %>%
      summarise(records = n(), patients = n_distinct(ID), .groups = "drop") %>%
      mutate(vector_name = vec_name)
    count_results <- bind_rows(count_results, counts)
  }
}

# Query ENCOUNTER (for DRG codes)
enc_tbl <- tryCatch(get_pcornet_table("ENCOUNTER"), error = function(e) NULL)
if (!is.null(enc_tbl)) {
  message("  Querying ENCOUNTER table...")

  drg_vectors <- code_type_map %>% filter(source_table == "ENCOUNTER")

  for (i in seq_len(nrow(drg_vectors))) {
    vec_name <- drg_vectors$vector_name[i]
    codes <- TREATMENT_CODES[[vec_name]]

    if (is.null(codes) || length(codes) == 0) next

    message(glue("    {vec_name} ({length(codes)} codes, DRG)..."))

    counts <- tryCatch({
      enc_tbl %>%
        filter(DRG %in% codes) %>%
        group_by(code = DRG) %>%
        summarise(records = n(), patients = n_distinct(ID), .groups = "drop") %>%
        collect() %>%
        mutate(vector_name = vec_name)
    }, error = function(e) {
      message(glue("      Error: {e$message}"))
      tibble(code = character(), records = integer(), patients = integer(), vector_name = character())
    })
    count_results <- bind_rows(count_results, counts)
  }
} else {
  message("  ENCOUNTER table not found (skipping)")
}

message(glue("  Count results: {nrow(count_results)} code-vector combinations"))

# =============================================================================
# SECTION 4: ASSEMBLE MASTER DATA FRAME
# =============================================================================

message("\nAssembling master data frame with descriptions...")

all_codes_df <- tibble(
  code = character(),
  description = character(),
  code_type = character(),
  source_table = character(),
  category = character(),
  records = integer(),
  patients = integer()
)

for (i in seq_len(nrow(code_type_map))) {
  vec_name <- code_type_map$vector_name[i]
  category <- code_type_map$category[i]
  code_type <- code_type_map$code_type[i]
  source_table <- code_type_map$source_table[i]

  codes <- TREATMENT_CODES[[vec_name]]
  if (is.null(codes) || length(codes) == 0) next

  # Create per-code rows
  vec_df <- tibble(code = codes) %>%
    # Look up counts
    left_join(
      count_results %>% filter(vector_name == vec_name) %>% select(code, records, patients),
      by = "code"
    ) %>%
    # Fill NA counts with 0
    mutate(
      records = if_else(is.na(records), 0L, records),
      patients = if_else(is.na(patients), 0L, patients)
    ) %>%
    # Look up descriptions (cascade: api > hardcoded > config)
    left_join(api_descriptions %>% rename(api_desc = description), by = "code") %>%
    left_join(hardcoded_desc_tbl %>% rename(hardcoded_desc = description), by = "code") %>%
    left_join(config_comments %>% rename(config_desc = description), by = "code") %>%
    mutate(
      description = coalesce(api_desc, hardcoded_desc, config_desc, "No description available")
    ) %>%
    select(code, description, records, patients) %>%
    mutate(
      code_type = code_type,
      source_table = source_table,
      category = category
    )

  all_codes_df <- bind_rows(all_codes_df, vec_df)
}

# Summary by category
summary_by_category <- all_codes_df %>%
  group_by(category) %>%
  summarise(
    n_codes = n(),
    total_records = sum(records),
    total_patients = sum(patients, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(n_codes))

message("\nSummary by category:")
print(summary_by_category, n = Inf)

# =============================================================================
# SECTION 5: CONFIG COMMENT CURATION
# =============================================================================

message("\nCurating R/00_config.R inline comments...")

# Identify codes where:
# - API or hardcoded description exists (better than config comment)
# - Current config comment is a Phase attribution tag or short/missing

codes_to_update <- all_codes_df %>%
  # Get codes with API or hardcoded descriptions
  left_join(api_descriptions %>% rename(api_desc = description), by = "code") %>%
  left_join(hardcoded_desc_tbl %>% rename(hardcoded_desc = description), by = "code") %>%
  left_join(config_comments %>% rename(config_desc = description), by = "code") %>%
  # Filter to codes with a better description available
  filter(!is.na(api_desc) | !is.na(hardcoded_desc)) %>%
  # Filter to codes where config comment is weak (starts with "Phase" or is short)
  filter(is.na(config_desc) | str_detect(config_desc, "^Phase \\d+:") | str_length(config_desc) < 20) %>%
  mutate(
    new_desc = coalesce(api_desc, hardcoded_desc),
    # Truncate to 60 chars for config readability
    new_desc_trunc = str_trunc(new_desc, 60, "right")
  ) %>%
  select(code, new_desc_trunc)

if (nrow(codes_to_update) > 0) {
  message(glue("  Found {nrow(codes_to_update)} codes with better descriptions available"))

  config_path <- "R/00_config.R"
  config_backup <- "R/00_config.R.bak"

  # Backup
  file.copy(config_path, config_backup, overwrite = TRUE)
  message(glue("  Created backup: {config_backup}"))

  # Read config
  config_lines <- readLines(config_path)

  # Update comments
  n_updated <- 0
  for (i in seq_len(nrow(codes_to_update))) {
    code <- codes_to_update$code[i]
    new_desc <- codes_to_update$new_desc_trunc[i]

    # Find line with this code (quoted)
    pattern <- glue('"{code}"')
    matches <- grep(pattern, config_lines, fixed = TRUE)

    if (length(matches) > 0) {
      # Update first match only
      line_idx <- matches[1]
      old_line <- config_lines[line_idx]
      # Replace comment portion (everything after #)
      new_line <- sub("#.*$", glue("# {new_desc}"), old_line)
      # If no # existed, add one
      if (!str_detect(old_line, "#")) {
        new_line <- glue("{old_line}   # {new_desc}")
      }
      config_lines[line_idx] <- new_line
      n_updated <- n_updated + 1
    }
  }

  # Write updated config
  writeLines(config_lines, config_path)

  # Validate
  validation_ok <- tryCatch({
    parse(config_path)
    env <- new.env()
    source(config_path, local = env)
    if (is.null(env$TREATMENT_CODES)) {
      stop("TREATMENT_CODES is NULL after sourcing")
    }
    TRUE
  }, error = function(e) {
    message(glue("  Validation failed: {e$message}"))
    FALSE
  })

  if (validation_ok) {
    message(glue("  Updated {n_updated} config comments successfully"))
    file.remove(config_backup)
  } else {
    message("  Validation failed, rolling back...")
    file.copy(config_backup, config_path, overwrite = TRUE)
    file.remove(config_backup)
  }
} else {
  message("  No config comments to update")
}

# =============================================================================
# SECTION 6: XLSX GENERATION
# =============================================================================

# 6a. write_resolved_xlsx function (adapted from R/42)
write_resolved_xlsx <- function(df, category, output_path) {
  n_codes <- nrow(df)
  sheet_name <- paste(category, "Codes")

  fill_color <- TREATMENT_TYPE_COLORS[[category]]$fill
  font_color <- TREATMENT_TYPE_COLORS[[category]]$font

  wb <- wb_workbook()
  wb$add_worksheet(sheet_name)

  # Row 1: Title
  wb$add_data(sheet = sheet_name,
              x = glue("{category} Codes ({n_codes} codes)"),
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
  write_df <- data.frame(
    Code         = df$code,
    Meaning      = ifelse(is.na(df$description), "", df$description),
    Code_Type    = df$code_type,
    Source_Table = df$source_table,
    Records      = df$records,
    Patients     = df$patients,
    stringsAsFactors = FALSE
  )
  wb$add_data(sheet = sheet_name, x = write_df, start_row = 3, col_names = FALSE)

  # Styling: Code column
  last_row <- 2 + n_codes
  code_dims <- glue("A3:A{last_row}")
  wb$add_fill(sheet = sheet_name, dims = code_dims, color = wb_color(fill_color))
  wb$add_font(sheet = sheet_name, dims = code_dims,
              name = "Calibri", size = 10, bold = TRUE, color = wb_color(font_color))

  # Number formatting
  if (n_codes > 0) {
    num_dims <- glue("E3:F{last_row}")
    wb$add_numfmt(sheet = sheet_name, dims = num_dims, numfmt = "#,##0")
  }

  # Column widths
  wb$set_col_widths(sheet = sheet_name, cols = 1:6, widths = c(15, 45, 12, 15, 10, 10))

  # Notes sheet
  wb$add_worksheet("Notes")
  notes_lines <- c(
    glue("Data Source: R/00_config.R TREATMENT_CODES"),
    glue("Descriptions: Multi-source cascade (Phase 39-41 RDS, Phase 45 hardcoded, config comments)"),
    glue("Patient/Record Counts: DuckDB queries"),
    glue("Generated: {Sys.Date()}"),
    glue("Classification: {category} codes")
  )
  for (i in seq_along(notes_lines)) {
    wb$add_data(sheet = "Notes", x = as.character(notes_lines[i]),
                start_row = i, start_col = 1)
  }

  # Save
  wb$save(output_path)
  message(glue("  Wrote {output_path} ({n_codes} codes)"))
}

# 6a. Generate per-type resolved xlsx files
message("\nGenerating per-type resolved xlsx files...")

categories <- c("Chemotherapy", "Radiation", "SCT", "Immunotherapy", "Supportive Care")
output_files <- c(
  "chemotherapy_codes_resolved.xlsx",
  "radiation_codes_resolved.xlsx",
  "sct_codes_resolved.xlsx",
  "immunotherapy_codes_resolved.xlsx",
  "supportive_care_codes_resolved.xlsx"
)

for (i in seq_along(categories)) {
  category <- categories[i]
  output_path <- output_files[i]

  df_cat <- all_codes_df %>%
    filter(category == !!category) %>%
    arrange(desc(patients))

  if (nrow(df_cat) > 0) {
    write_resolved_xlsx(df_cat, category, output_path)
  } else {
    message(glue("  Skipping {category} (no codes)"))
  }
}

# 6b. Generate all_codes_resolved.xlsx
message("\nGenerating all_codes_resolved.xlsx...")

wb_all <- wb_workbook()

# Summary sheet (first)
wb_all$add_worksheet("Summary")

# Row 1: Title
wb_all$add_data(sheet = "Summary", x = "All Treatment Codes Summary",
                start_row = 1, start_col = 1)
wb_all$add_font(sheet = "Summary", dims = "A1",
                name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb_all$merge_cells(sheet = "Summary", dims = "A1:D1")

# Row 3: Headers
headers_summary <- c("Treatment Type", "Codes", "Records", "Patients")
for (i in seq_along(headers_summary)) {
  wb_all$add_data(sheet = "Summary", x = headers_summary[i],
                  start_row = 3, start_col = i)
}
wb_all$add_fill(sheet = "Summary", dims = "A3:D3", color = wb_color("FF374151"))
wb_all$add_font(sheet = "Summary", dims = "A3:D3",
                name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Data rows
for (i in seq_len(nrow(summary_by_category))) {
  row_num <- 3 + i
  wb_all$add_data(sheet = "Summary", x = summary_by_category$category[i],
                  start_row = row_num, start_col = 1)
  wb_all$add_data(sheet = "Summary", x = summary_by_category$n_codes[i],
                  start_row = row_num, start_col = 2)
  wb_all$add_data(sheet = "Summary", x = summary_by_category$total_records[i],
                  start_row = row_num, start_col = 3)
  wb_all$add_data(sheet = "Summary", x = summary_by_category$total_patients[i],
                  start_row = row_num, start_col = 4)
  wb_all$add_numfmt(sheet = "Summary", dims = glue("B{row_num}:D{row_num}"), numfmt = "#,##0")
}

# Totals row
totals_row <- 3 + nrow(summary_by_category) + 1
wb_all$add_data(sheet = "Summary", x = "Total", start_row = totals_row, start_col = 1)
wb_all$add_data(sheet = "Summary", x = sum(summary_by_category$n_codes), start_row = totals_row, start_col = 2)
wb_all$add_data(sheet = "Summary", x = sum(summary_by_category$total_records), start_row = totals_row, start_col = 3)
wb_all$add_data(sheet = "Summary", x = sum(summary_by_category$total_patients), start_row = totals_row, start_col = 4)
wb_all$add_fill(sheet = "Summary", dims = glue("A{totals_row}:D{totals_row}"), color = wb_color("FF374151"))
wb_all$add_font(sheet = "Summary", dims = glue("A{totals_row}:D{totals_row}"),
                name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
wb_all$add_numfmt(sheet = "Summary", dims = glue("B{totals_row}:D{totals_row}"), numfmt = "#,##0")

# Column widths
wb_all$set_col_widths(sheet = "Summary", cols = 1:4, widths = c(20, 12, 12, 12))

# Per-category sheets
for (category in categories) {
  df_cat <- all_codes_df %>%
    filter(category == !!category) %>%
    arrange(desc(patients))

  if (nrow(df_cat) == 0) next

  sheet_name <- category  # Use category name directly (not "{Category} Codes")
  wb_all$add_worksheet(sheet_name)

  fill_color <- TREATMENT_TYPE_COLORS[[category]]$fill
  font_color <- TREATMENT_TYPE_COLORS[[category]]$font

  # Row 1: Title
  wb_all$add_data(sheet = sheet_name,
                  x = glue("{category} Codes ({nrow(df_cat)} codes)"),
                  start_row = 1, start_col = 1)
  wb_all$add_font(sheet = sheet_name, dims = "A1",
                  name = "Calibri", size = 14, bold = TRUE, color = wb_color("FF1F2937"))
  wb_all$merge_cells(sheet = sheet_name, dims = "A1:F1")

  # Row 2: Headers
  headers_cat <- c("Code", "Meaning", "Code Type", "Source Table", "Records", "Patients")
  for (i in seq_along(headers_cat)) {
    wb_all$add_data(sheet = sheet_name, x = headers_cat[i],
                    start_row = 2, start_col = i)
  }
  wb_all$add_fill(sheet = sheet_name, dims = "A2:F2", color = wb_color("FF374151"))
  wb_all$add_font(sheet = sheet_name, dims = "A2:F2",
                  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  # Row 3+: Data
  write_df_cat <- data.frame(
    Code         = df_cat$code,
    Meaning      = ifelse(is.na(df_cat$description), "", df_cat$description),
    Code_Type    = df_cat$code_type,
    Source_Table = df_cat$source_table,
    Records      = df_cat$records,
    Patients     = df_cat$patients,
    stringsAsFactors = FALSE
  )
  wb_all$add_data(sheet = sheet_name, x = write_df_cat, start_row = 3, col_names = FALSE)

  # Styling: Code column
  last_row_cat <- 2 + nrow(df_cat)
  code_dims_cat <- glue("A3:A{last_row_cat}")
  wb_all$add_fill(sheet = sheet_name, dims = code_dims_cat, color = wb_color(fill_color))
  wb_all$add_font(sheet = sheet_name, dims = code_dims_cat,
                  name = "Calibri", size = 10, bold = TRUE, color = wb_color(font_color))

  # Number formatting
  if (nrow(df_cat) > 0) {
    num_dims_cat <- glue("E3:F{last_row_cat}")
    wb_all$add_numfmt(sheet = sheet_name, dims = num_dims_cat, numfmt = "#,##0")
  }

  # Column widths
  wb_all$set_col_widths(sheet = sheet_name, cols = 1:6, widths = c(15, 45, 12, 15, 10, 10))

  # Freeze panes at row 3
  wb_all$freeze_pane(sheet = sheet_name, first_active_row = 3)
}

# Save all_codes_resolved.xlsx
wb_all$save("all_codes_resolved.xlsx")
message("  Wrote all_codes_resolved.xlsx")

# =============================================================================
# SECTION 7: FINAL SUMMARY
# =============================================================================

message("\n=== Phase 5 Complete ===")
message(glue("Total codes: {nrow(all_codes_df)}"))
message(glue("Categories: {paste(categories, collapse=', ')}"))
message("\nFiles written:")
message("  all_codes_resolved.xlsx (6 sheets)")
for (output_file in output_files) {
  if (file.exists(output_file)) {
    message(glue("  {output_file}"))
  }
}

# Codes with 0 records (informational)
zero_record_codes <- all_codes_df %>% filter(records == 0)
if (nrow(zero_record_codes) > 0) {
  message(glue("\nCodes with 0 records: {nrow(zero_record_codes)} (in config but not found in data)"))
  message(glue("  Sample: {paste(head(zero_record_codes$code, 10), collapse=', ')}"))
}

message("\nScript complete.")
