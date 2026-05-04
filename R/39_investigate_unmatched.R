# ==============================================================================
# 39_investigate_unmatched.R -- Investigate Unmatched CPT/HCPCS Codes
# ==============================================================================
#
# Extracts CPT/HCPCS codes from PROCEDURES table using widened heuristic ranges,
# filters out codes already in TREATMENT_CODES, looks up descriptions via the
# NLM HCPCS API, auto-classifies each code, and produces a styled xlsx report.
#
# Purpose: Identify treatment-relevant procedure codes that Phase 38's curated
# lists miss, producing a classification report for config update.
#
# Output:
#   - output/unmatched_codes_report.xlsx (styled workbook with classification)
#   - output/unmatched_codes_classified.rds (RDS for Plan 02 consumption)
#
# Usage:
#   Rscript R/39_investigate_unmatched.R
#
# Dependencies:
#   - R/00_config.R (TREATMENT_CODES list)
#   - R/01_load_pcornet.R (get_pcornet_table)
#   - httr, jsonlite, openxlsx2, dplyr, stringr, glue, tidyr
#
# Phase 39 Plan 01 -- investigate-unmatched-codes
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP AND CONFIGURATION
# ==============================================================================

source("R/00_config.R")
source("R/01_load_pcornet.R")

library(httr)
library(jsonlite)
library(openxlsx2)
library(dplyr)
library(stringr)
library(glue)
library(tidyr)

OUTPUT_PATH <- file.path(CONFIG$output_dir, "unmatched_codes_report.xlsx")

# ==============================================================================
# SECTION 2: WIDENED HEURISTIC RANGES (per D-02)
# ==============================================================================

# Expanded beyond Phase 38's CPT_HCPCS_RANGES to catch more codes
# Per D-01: CPT/HCPCS only -- no ICD-10-PCS, ICD-9, DRG, revenue, RXNORM, NDC
# Per D-03: Skip NDC entirely
CPT_HCPCS_RANGES_WIDENED <- list(
  Chemotherapy = list(
    j9_codes = "^J9[0-9]{3}$",           # J9000-J9999 (same as Phase 38)
    j0_j8_drugs = "^J[0-8][0-9]{3}$"     # J0000-J8999 full range for classification
  ),
  Radiation = list(
    delivery = "^774[0-9]{2}$",           # 77400-77499 (same as Phase 38)
    planning = "^773[0-9]{2}$"            # 77300-77399 treatment planning (NEW per D-02)
  ),
  SCT = list(
    transplant = "^382[3-4][0-9]$"        # 38230-38249 (no change per D-02)
  ),
  Immunotherapy = list(
    car_t_admin = "^XW0[34]3[A-Z][0-9]$" # CAR T-cell ICD-10-PCS (no change per D-02)
  )
)

# Treatment type colors extended with Supportive Care and Unrelated
TREATMENT_TYPE_COLORS <- list(
  Chemotherapy      = list(fill = "FFDCEEFB", font = "FF0B5394"),   # light blue / dark blue
  Radiation         = list(fill = "FFDDF4E1", font = "FF274E13"),   # light green / dark green
  SCT               = list(fill = "FFFFF4D6", font = "FF7F6000"),   # light yellow / dark olive
  Immunotherapy     = list(fill = "FFE8DCF4", font = "FF4C1D7A"),   # light purple / dark purple
  `Supportive Care` = list(fill = "FFD5F5F0", font = "FF0E6655"),   # light teal / dark teal
  Unrelated         = list(fill = "FFF3F4F6", font = "FF6B7280")    # light gray / medium gray
)

# ==============================================================================
# SECTION 3: EXTRACT UNMATCHED CODES
# ==============================================================================

#' Extract unmatched codes from PROCEDURES table
#'
#' For each treatment type in CPT_HCPCS_RANGES_WIDENED:
#' 1. Build combined regex from all patterns
#' 2. Query PROCEDURES table
#' 3. Filter by PX_TYPE ("CH" for CPT/HCPCS, "10" for ICD-10-PCS)
#' 4. Filter codes matching the combined regex
#' 5. Exclude codes already in TREATMENT_CODES
#' 6. Count occurrences per code AND distinct patients per code
#'
#' @return Tibble with columns: code, n_records, n_patients, heuristic_type
extract_unmatched_codes <- function() {
  proc_tbl <- tryCatch(
    get_pcornet_table("PROCEDURES"),
    error = function(e) {
      stop(glue("PROCEDURES table not found: {e$message}"))
    }
  )

  results <- list()

  for (treatment_type in names(CPT_HCPCS_RANGES_WIDENED)) {
    message(glue("  Checking {treatment_type} codes..."))

    range_patterns <- CPT_HCPCS_RANGES_WIDENED[[treatment_type]]
    combined_regex <- paste(unlist(range_patterns), collapse = "|")

    # Determine PX_TYPE filter
    px_type_filter <- if (treatment_type == "Immunotherapy") "10" else "CH"

    # Build list of known codes to exclude
    known_codes <- switch(treatment_type,
      "Chemotherapy" = TREATMENT_CODES$chemo_hcpcs,
      "Radiation" = TREATMENT_CODES$radiation_cpt,
      "SCT" = c(TREATMENT_CODES$sct_cpt, TREATMENT_CODES$sct_hcpcs),
      "Immunotherapy" = TREATMENT_CODES$cart_icd10pcs_prefixes,
      character(0)
    )

    unmatched <- tryCatch({
      proc_tbl %>%
        filter(PX_TYPE == px_type_filter) %>%
        materialize() %>%
        filter(str_detect(PX, combined_regex)) %>%
        filter(!PX %in% known_codes) %>%
        group_by(code = PX) %>%
        summarise(
          n_records = n(),
          n_patients = n_distinct(ID),
          .groups = "drop"
        ) %>%
        collect() %>%
        mutate(heuristic_type = treatment_type)
    }, error = function(e) {
      message(glue("    Warning: Extraction failed for {treatment_type}: {e$message}"))
      tibble(code = character(), n_records = integer(),
             n_patients = integer(), heuristic_type = character())
    })

    if (nrow(unmatched) > 0) {
      message(glue("    Found {nrow(unmatched)} unmatched codes"))
      results <- c(results, list(unmatched))
    }
  }

  bind_rows(results)
}

# ==============================================================================
# SECTION 4: NLM HCPCS API LOOKUP (per D-04)
# ==============================================================================

#' Look up HCPCS code descriptions via NLM API
#'
#' Queries the NLM Clinical Tables HCPCS API for each code.
#' Handles HTTP errors, timeouts, and not-found cases gracefully.
#' Logs progress every 10 codes.
#'
#' @param codes Character vector. Codes to look up.
#' @param sleep_sec Numeric. Seconds to sleep between requests (default 0.15 = ~7 req/sec)
#' @return Tibble with columns: code, description, lookup_status
lookup_hcpcs_batch <- function(codes, sleep_sec = 0.15) {
  results <- list()

  for (i in seq_along(codes)) {
    code <- codes[i]

    # Log progress every 10 codes
    if (i %% 10 == 0) {
      message(glue("  Looked up {i}/{length(codes)} codes"))
    }

    result <- tryCatch({
      url <- glue("https://clinicaltables.nlm.nih.gov/api/hcpcs/v3/search?terms={code}&ef=display")
      resp <- GET(url, timeout(10))

      if (http_error(resp)) {
        list(
          code = code,
          description = NA_character_,
          lookup_status = glue("error: HTTP {status_code(resp)}")
        )
      } else {
        json <- fromJSON(content(resp, as = "text", encoding = "UTF-8"))

        # json structure: [total_count, [matched_codes], ..., [[display_strings]]]
        # json[[1]] = total count
        # json[[2]] = matched codes
        # json[[4]] = display strings

        if (length(json) >= 4 && json[[1]] > 0) {
          matched_code <- json[[2]][1]
          if (toupper(matched_code) == toupper(code)) {
            list(
              code = code,
              description = json[[4]][1],
              lookup_status = "success"
            )
          } else {
            list(
              code = code,
              description = NA_character_,
              lookup_status = "not_found"
            )
          }
        } else {
          list(
            code = code,
            description = NA_character_,
            lookup_status = "not_found"
          )
        }
      }
    }, error = function(e) {
      list(
        code = code,
        description = NA_character_,
        lookup_status = glue("error: {e$message}")
      )
    })

    results <- c(results, list(as_tibble(result)))

    # Sleep between requests
    Sys.sleep(sleep_sec)
  }

  bind_rows(results)
}

# ==============================================================================
# SECTION 5: AUTO-CLASSIFICATION (per D-05, D-06)
# ==============================================================================

#' Classify an unmatched code into a treatment category
#'
#' Uses case_when() with specific keyword matching.
#' Order matters: Supportive Care MUST come before Chemotherapy to avoid
#' misclassifying supportive drugs as chemo (Pitfall 2).
#'
#' @param code Character. The code to classify.
#' @param description Character. The description from NLM API (may be NA).
#' @param heuristic_type Character. The heuristic that matched this code.
#' @return Character. One of: "Supportive Care", "Chemotherapy", "Radiation",
#'         "SCT", "Immunotherapy", "Unrelated"
classify_unmatched_code <- function(code, description, heuristic_type) {
  desc_lower <- tolower(ifelse(is.na(description), "", description))

  case_when(
    # 1. Supportive care: J0-J8 codes with specific supportive care keywords
    #    MUST come before Chemotherapy to avoid misclassification (Pitfall 2)
    str_detect(code, "^J[0-8]") & str_detect(desc_lower,
      "filgrastim|pegfilgrastim|neulasta|neupogen|zarxio|granix|udenyca|nyvepria|ziextenzo|stimufend|fylnetra|releuko|ondansetron|zofran|granisetron|kytril|palonosetron|aloxi|fosaprepitant|emend|aprepitant|dexamethasone|colony.stimulating|growth factor|antiemetic|epoetin|procrit|darbepoetin|aranesp"
    ) ~ "Supportive Care",

    # 2. Chemotherapy: J9xxx always chemo; J0-J8 with antineoplastic keywords
    str_detect(code, "^J9") ~ "Chemotherapy",
    str_detect(code, "^J[0-8]") & str_detect(desc_lower,
      "chemotherapy|antineoplastic|doxorubicin|cisplatin|carboplatin|etoposide|vincristine|bleomycin|dacarbazine|cyclophosphamide|methotrexate|cytarabine|fludarabine|bendamustine|gemcitabine|ifosfamide|brentuximab|nivolumab|pembrolizumab|rituximab|obinutuzumab"
    ) ~ "Chemotherapy",

    # 3. Radiation: 773xx-774xx or radiation keywords
    str_detect(code, "^77[34]") & str_detect(desc_lower,
      "radiation|radiotherapy|irradiation|beam|brachytherapy|dosimetry|treatment.planning|isodose|teletherapy|treatment.delivery|treatment.management"
    ) ~ "Radiation",
    str_detect(code, "^774") ~ "Radiation",  # 774xx delivery codes always radiation

    # 4. SCT: 382xx or transplant keywords
    str_detect(code, "^382[34]") ~ "SCT",
    str_detect(desc_lower, "transplant|bone marrow|stem cell|hematopoietic|allogeneic|autologous") ~ "SCT",

    # 5. Immunotherapy: XW0xx or immunotherapy keywords
    str_detect(code, "^XW0[34]3") ~ "Immunotherapy",
    str_detect(desc_lower, "car.t|chimeric antigen|immunotherapy|checkpoint inhibitor") ~ "Immunotherapy",

    # 6. Default: Unrelated
    TRUE ~ "Unrelated"
  )
}

# ==============================================================================
# SECTION 6: XLSX REPORT GENERATION (per D-07)
# ==============================================================================

#' Write styled xlsx report with per-category sheets
#'
#' Creates one sheet per classification category in order:
#' Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care, Unrelated.
#' Skips categories with 0 codes.
#' Adds a Summary sheet as the first sheet.
#'
#' @param df Tibble. All unmatched codes with classification.
#' @param output_path Character. Path to save xlsx file.
write_unmatched_report <- function(df, output_path) {
  wb <- wb_workbook()

  # Category order
  category_order <- c("Chemotherapy", "Radiation", "SCT", "Immunotherapy",
                      "Supportive Care", "Unrelated")

  # --- SUMMARY SHEET ---
  message("  Writing Summary sheet...")
  wb$add_worksheet("Summary")

  # Row 1: Title
  wb$add_data(sheet = "Summary", x = "Unmatched Codes Investigation Summary",
              start_row = 1, start_col = 1)
  wb$add_font(sheet = "Summary", dims = "A1",
              name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
  wb$merge_cells(sheet = "Summary", dims = "A1:C1")

  # Row 3: Column headers
  wb$add_data(sheet = "Summary", x = "Classification",
              start_row = 3, start_col = 1)
  wb$add_data(sheet = "Summary", x = "Count",
              start_row = 3, start_col = 2)
  wb$add_data(sheet = "Summary", x = "% of Total",
              start_row = 3, start_col = 3)
  wb$add_fill(sheet = "Summary", dims = "A3:C3", color = wb_color("FF374151"))
  wb$add_font(sheet = "Summary", dims = "A3:C3",
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  # Data rows
  summary_df <- df %>%
    count(classification) %>%
    mutate(pct = n / sum(n)) %>%
    arrange(match(classification, category_order))

  for (i in seq_len(nrow(summary_df))) {
    row_num <- 3 + i
    wb$add_data(sheet = "Summary", x = summary_df$classification[i],
                start_row = row_num, start_col = 1)
    wb$add_data(sheet = "Summary", x = summary_df$n[i],
                start_row = row_num, start_col = 2)
    wb$add_data(sheet = "Summary", x = summary_df$pct[i],
                start_row = row_num, start_col = 3)
    wb$add_numfmt(sheet = "Summary", dims = glue("B{row_num}"), numfmt = "#,##0")
    wb$add_numfmt(sheet = "Summary", dims = glue("C{row_num}"), numfmt = "0.00%")
  }

  # Total row
  total_row <- 3 + nrow(summary_df) + 1
  wb$add_data(sheet = "Summary", x = "Total",
              start_row = total_row, start_col = 1)
  wb$add_data(sheet = "Summary", x = sum(summary_df$n),
              start_row = total_row, start_col = 2)
  wb$add_data(sheet = "Summary", x = 1.0,
              start_row = total_row, start_col = 3)
  wb$add_fill(sheet = "Summary", dims = glue("A{total_row}:C{total_row}"),
              color = wb_color("FF374151"))
  wb$add_font(sheet = "Summary", dims = glue("A{total_row}:C{total_row}"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
  wb$add_numfmt(sheet = "Summary", dims = glue("B{total_row}"), numfmt = "#,##0")
  wb$add_numfmt(sheet = "Summary", dims = glue("C{total_row}"), numfmt = "0.00%")

  # Column widths
  wb$set_col_widths(sheet = "Summary", cols = 1:3, widths = c(20, 12, 12))

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
    wb$add_data(sheet = sheet_name, x = "Unmatched CPT/HCPCS Codes Investigation",
                start_row = 1, start_col = 1)
    wb$add_font(sheet = sheet_name, dims = "A1",
                name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
    wb$merge_cells(sheet = sheet_name, dims = "A1:F1")

    # Row 2: Subtitle
    subtitle <- glue("{category}: {nrow(df_cat)} unmatched codes")
    wb$add_data(sheet = sheet_name, x = as.character(subtitle),
                start_row = 2, start_col = 1)
    wb$add_font(sheet = sheet_name, dims = "A2",
                name = "Calibri", size = 10, color = wb_color("FF6B7280"))
    wb$merge_cells(sheet = sheet_name, dims = "A2:F2")

    # Row 3: blank

    # Row 4: Column headers
    headers <- c("Code", "Description", "Heuristic Match", "Records", "Patients", "Lookup Status")
    for (i in seq_along(headers)) {
      wb$add_data(sheet = sheet_name, x = headers[i],
                  start_row = 4, start_col = i)
    }
    wb$add_fill(sheet = sheet_name, dims = "A4:F4", color = wb_color("FF374151"))
    wb$add_font(sheet = sheet_name, dims = "A4:F4",
                name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

    # Data rows (starting at row 5)
    for (r in seq_len(nrow(df_cat))) {
      row_num <- 4 + r

      # Code (with colored pill fill)
      wb$add_data(sheet = sheet_name, x = df_cat$code[r],
                  start_row = row_num, start_col = 1)
      wb$add_fill(sheet = sheet_name, dims = glue("A{row_num}"),
                  color = wb_color(fill_color))
      wb$add_font(sheet = sheet_name, dims = glue("A{row_num}"),
                  name = "Calibri", size = 10, bold = TRUE, color = wb_color(font_color))

      # Description
      desc_text <- ifelse(is.na(df_cat$description[r]), "", df_cat$description[r])
      wb$add_data(sheet = sheet_name, x = desc_text,
                  start_row = row_num, start_col = 2)
      wb$add_font(sheet = sheet_name, dims = glue("B{row_num}"),
                  name = "Calibri", size = 10, color = wb_color("FF111827"))

      # Heuristic Match
      wb$add_data(sheet = sheet_name, x = df_cat$heuristic_type[r],
                  start_row = row_num, start_col = 3)
      wb$add_font(sheet = sheet_name, dims = glue("C{row_num}"),
                  name = "Calibri", size = 10, color = wb_color("FF111827"))

      # Records
      wb$add_data(sheet = sheet_name, x = df_cat$n_records[r],
                  start_row = row_num, start_col = 4)
      wb$add_numfmt(sheet = sheet_name, dims = glue("D{row_num}"), numfmt = "#,##0")
      wb$add_font(sheet = sheet_name, dims = glue("D{row_num}"),
                  name = "Calibri", size = 10, color = wb_color("FF111827"))

      # Patients
      wb$add_data(sheet = sheet_name, x = df_cat$n_patients[r],
                  start_row = row_num, start_col = 5)
      wb$add_numfmt(sheet = sheet_name, dims = glue("E{row_num}"), numfmt = "#,##0")
      wb$add_font(sheet = sheet_name, dims = glue("E{row_num}"),
                  name = "Calibri", size = 10, color = wb_color("FF111827"))

      # Lookup Status
      wb$add_data(sheet = sheet_name, x = df_cat$lookup_status[r],
                  start_row = row_num, start_col = 6)
      wb$add_font(sheet = sheet_name, dims = glue("F{row_num}"),
                  name = "Calibri", size = 10, color = wb_color("FF111827"))
    }

    # Freeze panes at row 5 (first data row)
    wb$freeze_pane(sheet = sheet_name, first_active_row = 5)

    # Column widths
    wb$set_col_widths(sheet = sheet_name, cols = 1:6,
                      widths = c(12, 55, 18, 12, 12, 15))
  }

  # Save workbook
  wb$save(output_path)
}

# ==============================================================================
# SECTION 8: UPDATE TREATMENT_CODES IN R/00_config.R (per D-08)
# ==============================================================================

#' Update TREATMENT_CODES in R/00_config.R with classified codes
#'
#' Programmatically inserts auto-classified treatment codes into the appropriate
#' vectors in R/00_config.R. Creates a backup before modification and validates
#' the updated config with parse() and source(). Rolls back on validation failure.
#'
#' For existing vectors (chemo_hcpcs, radiation_cpt, sct_cpt, cart_icd10pcs_prefixes),
#' new codes are inserted before the closing paren with inline comments.
#'
#' For Supportive Care, creates a new supportive_care_hcpcs vector if it doesn't
#' exist, or merges into existing vector if it does.
#'
#' @param classified_codes_path Character. Path to unmatched_codes_classified.rds
update_config_treatment_codes <- function(classified_codes_path) {
  # 1. Load classified codes
  if (!file.exists(classified_codes_path)) {
    stop(glue("Classified codes file not found: {classified_codes_path}"))
  }

  classified <- readRDS(classified_codes_path)

  # 2. Filter to treatment-relevant codes only (exclude "Unrelated")
  treatment_codes_new <- classified %>%
    filter(classification != "Unrelated") %>%
    select(code, classification, description)

  if (nrow(treatment_codes_new) == 0) {
    message("  No treatment codes to add (all classified as Unrelated)")
    return(invisible(NULL))
  }

  # 3. Map classifications to TREATMENT_CODES vector names
  category_map <- c(
    "Chemotherapy" = "chemo_hcpcs",
    "Radiation" = "radiation_cpt",
    "SCT" = "sct_cpt",
    "Immunotherapy" = "cart_icd10pcs_prefixes",
    "Supportive Care" = "supportive_care_hcpcs"
  )

  # 4. Read R/00_config.R
  config_path <- "R/00_config.R"
  backup_path <- paste0(config_path, ".bak")

  if (!file.exists(config_path)) {
    stop(glue("Config file not found: {config_path}"))
  }

  file.copy(config_path, backup_path, overwrite = TRUE)
  message(glue("  Created backup: {backup_path}"))

  config_lines <- readLines(config_path)

  # 5. For each category with new codes, insert into the appropriate vector
  for (cat_name in names(category_map)) {
    vec_name <- category_map[cat_name]

    # Get new codes for this category
    new_codes_for_cat <- treatment_codes_new %>%
      filter(classification == cat_name)

    if (nrow(new_codes_for_cat) == 0) {
      next  # Skip categories with no new codes
    }

    message(glue("  Processing {cat_name}: {nrow(new_codes_for_cat)} codes"))

    # Find the vector in config_lines
    vec_pattern <- glue("^\\s*{vec_name}\\s*=\\s*c\\(")
    vec_start_idx <- grep(vec_pattern, config_lines, perl = TRUE)

    if (length(vec_start_idx) == 0) {
      # Vector doesn't exist yet - need to create it (for supportive_care_hcpcs)
      if (vec_name == "supportive_care_hcpcs") {
        message(glue("    Creating new {vec_name} vector"))

        # Find where to insert: before chemo_revenue
        chemo_revenue_idx <- grep("^\\s*chemo_revenue\\s*=\\s*c\\(", config_lines, perl = TRUE)
        if (length(chemo_revenue_idx) == 0) {
          stop("Cannot find chemo_revenue vector to insert supportive_care_hcpcs before it")
        }

        insert_pos <- chemo_revenue_idx[1] - 1

        # Build new vector block
        new_lines <- c(
          "",
          "  # Supportive care HCPCS J-codes (Phase 39: growth factors, antiemetics, etc.)",
          "  supportive_care_hcpcs = c("
        )

        for (i in seq_len(nrow(new_codes_for_cat))) {
          code <- new_codes_for_cat$code[i]
          desc <- new_codes_for_cat$description[i]
          desc_trunc <- ifelse(is.na(desc) || nchar(desc) == 0, "no description",
                               substr(desc, 1, 40))

          # Last code has no trailing comma
          if (i == nrow(new_codes_for_cat)) {
            new_lines <- c(new_lines, glue("    \"{code}\"    # Phase 39: {desc_trunc}"))
          } else {
            new_lines <- c(new_lines, glue("    \"{code}\",   # Phase 39: {desc_trunc}"))
          }
        }

        new_lines <- c(new_lines, "  ),", "")

        # Insert into config_lines
        config_lines <- c(
          config_lines[1:insert_pos],
          new_lines,
          config_lines[(insert_pos + 1):length(config_lines)]
        )

      } else {
        warning(glue("Vector {vec_name} not found in config - skipping"))
      }
      next
    }

    # Vector exists - find its closing paren
    vec_start_idx <- vec_start_idx[1]

    # Find the closing paren - look for line ending with ")," or just ")"
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

    # Extract existing codes from the block
    existing_codes <- character()
    for (i in vec_start_idx:close_paren_idx) {
      line <- config_lines[i]
      # Match quoted strings
      matches <- str_extract_all(line, "\"([^\"]+)\"")[[1]]
      if (length(matches) > 0) {
        codes <- str_replace_all(matches, "\"", "")
        existing_codes <- c(existing_codes, codes)
      }
    }

    # Compute new codes = codes not already in existing
    new_codes_to_add <- new_codes_for_cat %>%
      filter(!code %in% existing_codes)

    if (nrow(new_codes_to_add) == 0) {
      message(glue("    All codes already exist in {vec_name} - skipping"))
      next
    }

    message(glue("    Adding {nrow(new_codes_to_add)} new codes to {vec_name}"))

    # Ensure last existing code line has trailing comma before we append.
    # Must check for comma AFTER the closing quote (not in comments).
    last_data_idx <- close_paren_idx - 1
    if (!grepl('"[^"]*"\\s*,', config_lines[last_data_idx])) {
      config_lines[last_data_idx] <- sub('(.*")', '\\1,', config_lines[last_data_idx])
    }

    # Build lines to insert
    insert_lines <- character()
    for (i in seq_len(nrow(new_codes_to_add))) {
      code <- new_codes_to_add$code[i]
      desc <- new_codes_to_add$description[i]
      desc_trunc <- ifelse(is.na(desc) || nchar(desc) == 0, "no description",
                           substr(desc, 1, 40))

      # Last inserted code has no trailing comma (matches existing R style)
      if (i == nrow(new_codes_to_add)) {
        insert_lines <- c(insert_lines,
                         glue("    \"{code}\"    # Phase 39: {desc_trunc}"))
      } else {
        insert_lines <- c(insert_lines,
                         glue("    \"{code}\",   # Phase 39: {desc_trunc}"))
      }
    }

    # Insert before closing paren
    config_lines <- c(
      config_lines[1:(close_paren_idx - 1)],
      insert_lines,
      config_lines[close_paren_idx:length(config_lines)]
    )
  }

  # 6. Validate the updated config
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

    # Verify each updated category
    for (cat_name in names(category_map)) {
      vec_name <- category_map[cat_name]
      new_codes_for_cat <- treatment_codes_new %>%
        filter(classification == cat_name) %>%
        pull(code)

      if (length(new_codes_for_cat) > 0) {
        existing <- env$TREATMENT_CODES[[vec_name]]
        if (is.null(existing)) {
          warning(glue("Vector {vec_name} is NULL after update"))
        } else {
          missing <- setdiff(new_codes_for_cat, existing)
          if (length(missing) > 0) {
            warning(glue("Category {cat_name}: {length(missing)} codes not found after update: {paste(missing, collapse=', ')}"))
          }
        }
      }
    }

    NULL  # No error
  }, error = function(e) {
    e$message
  })

  if (!is.null(validation_error)) {
    message(glue("  Config update failed: {validation_error}"))
    message("  Restoring backup...")
    file.copy(backup_path, config_path, overwrite = TRUE)
    stop(glue("Config validation failed: {validation_error}"))
  }

  message("  Config update validated successfully")
  file.remove(backup_path)

  # 7. Log summary of changes
  message("  Config update summary:")
  for (cat_name in names(category_map)) {
    vec_name <- category_map[cat_name]
    n_new <- treatment_codes_new %>%
      filter(classification == cat_name) %>%
      nrow()
    if (n_new > 0) {
      message(glue("    {vec_name}: +{n_new} codes"))
    }
  }

  invisible(NULL)
}

# ==============================================================================
# SECTION 7: MAIN EXECUTION
# ==============================================================================

message("=== Phase 39: Investigate Unmatched CPT/HCPCS Codes ===")
message("")

# Step 1: Extract unmatched codes
message("Step 1: Extracting unmatched codes with widened heuristic ranges...")
all_unmatched <- extract_unmatched_codes()
message(glue("  Found {nrow(all_unmatched)} unmatched codes across all treatment types"))

if (nrow(all_unmatched) == 0) {
  message("")
  message("No unmatched codes found. Exiting.")
  quit(save = "no", status = 0)
}

# Step 2: Look up descriptions
message("")
message("Step 2: Looking up code descriptions via NLM HCPCS API...")
descriptions <- lookup_hcpcs_batch(unique(all_unmatched$code))
all_unmatched <- all_unmatched %>% left_join(descriptions, by = "code")
n_found <- sum(descriptions$lookup_status == "success")
message(glue("  Descriptions found: {n_found}/{nrow(descriptions)} codes"))

# Step 3: Auto-classify
message("")
message("Step 3: Auto-classifying unmatched codes...")
all_unmatched <- all_unmatched %>%
  rowwise() %>%
  mutate(classification = classify_unmatched_code(code, description, heuristic_type)) %>%
  ungroup()

class_summary <- all_unmatched %>%
  count(classification) %>%
  arrange(desc(n))

message("  Classification summary:")
for (i in seq_len(nrow(class_summary))) {
  message(glue("    {class_summary$classification[i]}: {class_summary$n[i]}"))
}

# Step 4: Write xlsx report
message("")
message("Step 4: Writing xlsx report...")
write_unmatched_report(all_unmatched, OUTPUT_PATH)
message(glue("  Report saved to {OUTPUT_PATH}"))

# Step 5: Save RDS for Plan 02 config update
message("")
message("Step 5: Saving classified codes for config update...")
saveRDS(all_unmatched, file.path(CONFIG$output_dir, "unmatched_codes_classified.rds"))
message("  Saved output/unmatched_codes_classified.rds")

# Step 6: Update R/00_config.R with classified treatment codes
message("")
message("Step 6: Updating TREATMENT_CODES in R/00_config.R...")
update_config_treatment_codes(file.path(CONFIG$output_dir, "unmatched_codes_classified.rds"))

message("")
message("=== Phase 39 Investigation Complete ===")
