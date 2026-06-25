# ==============================================================================
# 99_compare_drug_resolution.R -- Before/After Comparison of Drug Name Resolution
# ==============================================================================
# Purpose:   Compare the 19 RXNORM codes that were previously unresolved
#            (returned "not_found" from /properties endpoint) against the
#            new historystatus fallback + normalization logic.
#
# Shows:     Old result (properties only) vs New result (properties + historystatus
#            fallback + normalize_rxnorm_drug_name) vs Reference Excel name.
#
# Usage:     source("R/99_compare_drug_resolution.R")
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(httr2)
  library(tibble)
})

source("R/00_config.R")

# ==============================================================================
# SECTION 1: The 19 previously unresolved RXNORM codes
# ==============================================================================

target_codes <- c(
 "309638", "637543", "894900", "311627", "1799307",
 "105587", "308770", "310973", "1791598", "308771",
 "1790098", "1719013", "205821", "1541215", "105604",
 "1790129", "1799305", "1863349", "2001102"
)

message("=== Drug Name Resolution: Before vs After Comparison ===\n")
message(glue("Testing {length(target_codes)} RXNORM codes that previously returned 'not_found'\n"))

# ==============================================================================
# SECTION 2: Normalization function (copied from updated R/27)
# ==============================================================================

normalize_rxnorm_drug_name <- function(name) {
  if (is.na(name) || name == "") return(NA_character_)

  n <- name

  # Strip pack wrapper: "{12 (methotrexate 2.5 MG Oral Tablet) } Pack"
  if (str_detect(n, "^\\{")) {
    n <- str_extract(n, "\\((.+?)\\s+\\d", group = 1)
    if (is.na(n)) n <- name
  }

  # Strip leading quantity: "2 ML vincristine...", "25 ML doxorubicin..."
  n <- str_remove(n, "^\\d+(\\.\\d+)?\\s+(ML|MG)\\s+")

  # Extract ingredient: everything before first dosage number
  ingredient <- str_extract(n, "^([A-Za-z][A-Za-z\\s\\-]+?)\\s+\\d", group = 1)
  if (is.na(ingredient)) {
    # No dosage found -- strip brand bracket and trailing whitespace
    ingredient <- str_remove(n, "\\s*\\[.*\\]$")
  }

  ingredient <- str_trim(ingredient)

  # Title case for consistency with MEDICATION_LOOKUP normalization
  ingredient <- str_to_title(ingredient)

  # Preserve common abbreviations (same as MEDICATION_LOOKUP normalize_med)
  ingredient <- str_replace_all(ingredient, "\\bHcl\\b", "HCl")

  ingredient
}

# ==============================================================================
# SECTION 3: Query each code with BOTH approaches
# ==============================================================================

results <- list()

for (i in seq_along(target_codes)) {
  rxcui <- target_codes[i]
  message(glue("  [{i}/{length(target_codes)}] Querying RXNORM {rxcui}..."))

  # --- OLD approach: /properties.json only ---
  old_name <- NA_character_
  old_status <- "not_found"

  tryCatch({
    url <- glue("https://rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/properties.json")
    resp <- request(url) %>% req_timeout(10) %>% req_perform()
    data <- resp_body_json(resp)

    if (!is.null(data$properties) && !is.null(data$properties$name)) {
      old_name <- data$properties$name
      old_status <- "success"
    }
  }, error = function(e) {
    old_status <<- glue("error: {e$message}")
  })

  Sys.sleep(0.1)

  # --- NEW approach: /historystatus.json fallback + normalization ---
  new_name <- NA_character_
  new_raw_name <- NA_character_
  new_status <- "not_found"

  if (old_status == "success") {
    # Properties worked -- normalize the name
    new_raw_name <- old_name
    new_name <- normalize_rxnorm_drug_name(old_name)
    new_status <- "success"
  } else {
    # Fallback to historystatus
    tryCatch({
      url <- glue("https://rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/historystatus.json")
      resp <- request(url) %>% req_timeout(10) %>% req_perform()
      data <- resp_body_json(resp)
      attrs <- data$rxcuiStatusHistory$attributes

      if (!is.null(attrs) && !is.null(attrs$name) && attrs$name != "") {
        new_raw_name <- attrs$name
        new_name <- normalize_rxnorm_drug_name(attrs$name)
        new_status <- "success_historystatus"
      }
    }, error = function(e) {
      new_status <<- glue("error_historystatus: {e$message}")
    })
  }

  Sys.sleep(0.1)

  # --- Reference Excel name ---
  excel_name <- if (rxcui %in% names(MEDICATION_LOOKUP)) {
    MEDICATION_LOOKUP[[rxcui]]
  } else {
    NA_character_
  }

  results[[i]] <- tibble(
    rxnorm_code    = rxcui,
    old_status     = old_status,
    old_name       = old_name,
    new_status     = new_status,
    new_raw_name   = new_raw_name,
    new_normalized = new_name,
    excel_name     = excel_name,
    matches_excel  = !is.na(new_name) & !is.na(excel_name) &
                     tolower(new_name) == tolower(excel_name)
  )
}

comparison <- bind_rows(results)

# ==============================================================================
# SECTION 4: Display Results
# ==============================================================================

message("\n")
message("=" |> strrep(100))
message("BEFORE vs AFTER COMPARISON")
message("=" |> strrep(100))

message(glue("\n{'RXNORM'<10} | {'OLD (properties)'<45} | {'NEW (normalized)'<30} | {'EXCEL'<25} | MATCH"))
message("-" |> strrep(120))

for (j in seq_len(nrow(comparison))) {
  row <- comparison[j, ]
  old_display <- if (is.na(row$old_name)) glue("[{row$old_status}]") else row$old_name
  new_display <- if (is.na(row$new_normalized)) glue("[{row$new_status}]") else row$new_normalized
  excel_display <- if (is.na(row$excel_name)) "[NOT IN EXCEL]" else row$excel_name
  match_icon <- if (row$matches_excel) "YES" else "NO"

  message(glue("{row$rxnorm_code<10} | {old_display<45} | {new_display<30} | {excel_display<25} | {match_icon}"))
}

# ==============================================================================
# SECTION 5: Summary Statistics
# ==============================================================================

n_old_resolved    <- sum(comparison$old_status == "success")
n_new_resolved    <- sum(comparison$new_status %in% c("success", "success_historystatus"))
n_via_historystatus <- sum(comparison$new_status == "success_historystatus")
n_matches_excel   <- sum(comparison$matches_excel)

message(glue("\n{'='|>strrep(60)}"))
message("SUMMARY")
message(glue("{'='|>strrep(60)}"))
message(glue("  Total codes tested:          {length(target_codes)}"))
message(glue("  BEFORE (properties only):    {n_old_resolved} resolved"))
message(glue("  AFTER  (+ historystatus):    {n_new_resolved} resolved ({n_via_historystatus} via historystatus)"))
message(glue("  Newly recovered:             {n_new_resolved - n_old_resolved}"))
message(glue("  Match Excel name:            {n_matches_excel}/{n_new_resolved}"))

if (n_matches_excel < n_new_resolved) {
  mismatches <- comparison %>%
    filter(!matches_excel & new_status %in% c("success", "success_historystatus"))
  if (nrow(mismatches) > 0) {
    message("\n  Name differences (new vs excel):")
    for (k in seq_len(nrow(mismatches))) {
      m <- mismatches[k, ]
      message(glue("    {m$rxnorm_code}: \"{m$new_normalized}\" vs \"{m$excel_name}\""))
    }
    message("  Note: Tier 1 (MEDICATION_LOOKUP) wins via coalesce, so Excel name will be used.")
  }
}

# ==============================================================================
# SECTION 6: Save comparison to CSV
# ==============================================================================

output_path <- file.path(CONFIG$output_dir, "drug_resolution_comparison.csv")
write.csv(comparison, output_path, row.names = FALSE)
message(glue("\nComparison saved: {output_path}"))
