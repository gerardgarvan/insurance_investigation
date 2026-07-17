# ==============================================================================
# 131_update_xlsx_med_admin_and_normalized_name.R
# ==============================================================================
# Purpose:  Update data/reference/all_codes_resolved_next_tables_v2.1_new.xlsx:
#             1. Append MED_ADMIN-exclusive RxNorm CUI rows to Chemotherapy,
#                Immunotherapy, and Supportive Care tabs (D-01..D-04).
#             2. Add a normalized_name column to all code tabs (D-05..D-08).
#                Supportive Care: rename existing "Normalized Meaning" header only.
#             3. Overwrite canonical all_codes_resolved_next_tables_v2.1.xlsx
#                after round-trip verification (D-09, D-10).
#
# Inputs:   data/reference/all_codes_resolved_next_tables_v2.1_new.xlsx
#           data/reference/rxnorm_ingredient_cache.csv   (optional; built if absent)
#           DuckDB PCORnet tables via safe_table() [HiPerGator only]
#
# Outputs:  data/reference/all_codes_resolved_next_tables_v2.1_new.xlsx  (working copy)
#           data/reference/all_codes_resolved_next_tables_v2.1.xlsx      (canonical)
#           data/reference/rxnorm_ingredient_cache.csv                   (updated cache)
#
# Dependencies: openxlsx2, dplyr, readr, httr2, glue, here, stringr
#               R/00_config.R, R/utils/utils_treatment.R
#
# Usage:    Rscript R/131_update_xlsx_med_admin_and_normalized_name.R
#           source("R/131_update_xlsx_med_admin_and_normalized_name.R")
#
# Phase:    131
# ==============================================================================

# SECTION 1: SETUP + PATHS ----
suppressPackageStartupMessages({
  library(openxlsx2)
  library(dplyr)
  library(readr)
  library(httr2)
  library(glue)
  library(here)
  library(stringr)
})

source(here("R/00_config.R"))
source(here("R/utils/utils_treatment.R"))

# Resolve the column-index -> letter helper defensively across openxlsx2 versions
int_to_col <- if (exists("int2col", where = asNamespace("openxlsx2"))) {
  openxlsx2::int2col
} else if (requireNamespace("openxlsx", quietly = TRUE)) {
  openxlsx::int2col
} else {
  function(i) {                      # base-26 fallback, no dependency
    s <- ""
    while (i > 0) { r <- (i - 1) %% 26; s <- paste0(LETTERS[r + 1], s); i <- (i - 1) %/% 26 }
    s
  }
}
stopifnot(int_to_col(10) == "J")   # smoke-check the helper resolves correctly

# Paths
XLSX_NEW       <- here("data/reference/all_codes_resolved_next_tables_v2.1_new.xlsx")
XLSX_CANONICAL <- here("data/reference/all_codes_resolved_next_tables_v2.1.xlsx")
CACHE_PATH     <- here("data/reference/rxnorm_ingredient_cache.csv")

EXPECTED_SHEETS <- c(
  "Index", "Sheet1", "Chemotherapy", "Radiation", "SCT",
  "Immunotherapy", "Supportive Care", "Unrelated"
)

message(glue("R/131: updating {XLSX_NEW}"))

# SECTION 2: LOAD WORKBOOK + READ ALL CODE TABS ----
stopifnot(file.exists(XLSX_NEW))

wb <- openxlsx2::wb_load(XLSX_NEW)

# Assert all 8 sheets present in exact order
if (!identical(as.character(wb$sheet_names), EXPECTED_SHEETS)) {
  stop(glue(
    "Sheet names mismatch. Expected: {paste(EXPECTED_SHEETS, collapse=', ')}\n",
    "Got: {paste(wb$sheet_names, collapse=', ')}"
  ))
}
message(glue("  Loaded workbook: {length(wb$sheet_names)} sheets confirmed"))

# Read all code tabs (start_row=2: row 1 is banner, row 2 is header)
chemo_df     <- wb_to_df(wb, sheet = "Chemotherapy",    start_row = 2)
rad_df       <- wb_to_df(wb, sheet = "Radiation",       start_row = 2)
sct_df       <- wb_to_df(wb, sheet = "SCT",             start_row = 2)
immuno_df    <- wb_to_df(wb, sheet = "Immunotherapy",   start_row = 2)
supcare_df   <- wb_to_df(wb, sheet = "Supportive Care", start_row = 2)
unrelated_df <- wb_to_df(wb, sheet = "Unrelated",       start_row = 2)

for (tab_name in c("Chemotherapy", "Radiation", "SCT", "Immunotherapy", "Supportive Care", "Unrelated")) {
  df_tmp <- wb_to_df(wb, sheet = tab_name, start_row = 2)
  message(glue("  {tab_name}: {nrow(df_tmp)} rows x {ncol(df_tmp)} cols | cols: {paste(names(df_tmp), collapse=', ')}"))
}

# SECTION 3: DUCKDB: MED_ADMIN EXCLUSIVE CUI ANTI-JOIN ----

# Discover TREATMENT_CODES keys for immunotherapy and supportive care
message("\n  Discovering TREATMENT_CODES keys (for anti-join universe):")
available_keys <- grep("rxnorm|immuno|supportive|chemo",
                       names(TREATMENT_CODES),
                       ignore.case = TRUE,
                       value = TRUE)
print(available_keys)

# Initialize empty result tibbles (used as fallback if DuckDB unavailable)
new_rows_chemo   <- tibble::tibble()
new_rows_immuno  <- tibble::tibble()
new_rows_supcare <- tibble::tibble()

tryCatch({
  message("\n  Connecting to MED_ADMIN via DuckDB...")

  med_admin_tbl <- safe_table("MED_ADMIN")
  if (is.null(med_admin_tbl)) stop("safe_table('MED_ADMIN') returned NULL")

  # Helper: query MED_ADMIN counts for a given code universe
  query_med_admin_counts <- function(med_admin_tbl, universe_codes) {
    med_admin_tbl %>%
      dplyr::filter(MEDADMIN_TYPE == "RX",
                    MEDADMIN_CODE %in% universe_codes) %>%
      dplyr::group_by(MEDADMIN_CODE) %>%
      dplyr::summarise(
        Records  = dplyr::n(),
        Patients = dplyr::n_distinct(ID),
        .groups  = "drop"
      ) %>%
      dplyr::collect()
  }

  # Helper: get RxNorm display name for a single CUI
  get_rxnorm_name <- function(rxcui) {
    tryCatch({
      resp <- httr2::request(glue("https://rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/name.json")) %>%
        httr2::req_timeout(10) %>%
        httr2::req_retry(
          max_tries = 3,
          is_transient = ~ httr2::resp_status(.x) %in% c(429, 503, 504)
        ) %>%
        httr2::req_perform()
      nm <- httr2::resp_body_json(resp)$name
      if (!is.null(nm) && nzchar(nm)) nm else as.character(rxcui)
    }, error = function(e) as.character(rxcui))
  }

  # --- Chemotherapy ---
  chemo_universe <- TREATMENT_CODES$chemo_rxnorm
  chemo_existing <- chemo_df %>%
    dplyr::filter(`Code Type` == "RXNORM") %>%
    dplyr::pull(Code)
  chemo_hits      <- query_med_admin_counts(med_admin_tbl, chemo_universe)
  new_chemo_hits  <- chemo_hits %>%
    dplyr::filter(!MEDADMIN_CODE %in% chemo_existing)
  if (nrow(new_chemo_hits) > 0) {
    new_chemo_hits$Meaning <- vapply(new_chemo_hits$MEDADMIN_CODE, get_rxnorm_name, character(1))
    Sys.sleep(0.1)
    new_rows_chemo <- new_chemo_hits %>%
      dplyr::transmute(
        Code                        = MEDADMIN_CODE,
        Meaning                     = Meaning,
        Medication                  = NA_character_,
        `Code Type`                 = "RXNORM",
        `Source Table`              = "MED_ADMIN",
        Records                     = Records,
        Patients                    = Patients,
        `First line/...`            = NA_character_,
        `SCT or Immunotherapy also?` = NA_character_
      )
  }
  message(glue("  Chemotherapy: {nrow(new_rows_chemo)} new MED_ADMIN-exclusive CUIs"))

  # --- Immunotherapy ---
  if ("immunotherapy_rxnorm" %in% names(TREATMENT_CODES)) {
    immuno_universe <- TREATMENT_CODES$immunotherapy_rxnorm
    message("  Immunotherapy: using TREATMENT_CODES$immunotherapy_rxnorm (named key found)")
  } else {
    immuno_universe <- immuno_df %>%
      dplyr::filter(`Code Type` == "RXNORM") %>%
      dplyr::pull(Code)
    message("  Immunotherapy: FALLBACK — no named key in TREATMENT_CODES; using tab RXNORM codes (anti-join produces 0 new rows)")
  }
  immuno_existing <- immuno_df %>%
    dplyr::filter(`Code Type` == "RXNORM") %>%
    dplyr::pull(Code)
  immuno_hits     <- query_med_admin_counts(med_admin_tbl, immuno_universe)
  new_immuno_hits <- immuno_hits %>%
    dplyr::filter(!MEDADMIN_CODE %in% immuno_existing)
  if (nrow(new_immuno_hits) > 0) {
    new_immuno_hits$Meaning <- vapply(new_immuno_hits$MEDADMIN_CODE, get_rxnorm_name, character(1))
    Sys.sleep(0.1)
    new_rows_immuno <- new_immuno_hits %>%
      dplyr::transmute(
        Code           = MEDADMIN_CODE,
        Meaning        = Meaning,
        `Code Type`    = "RXNORM",
        `Source Table` = "MED_ADMIN",
        Records        = Records,
        Patients       = Patients,
        `(None)`       = NA_character_
      )
  }
  message(glue("  Immunotherapy: {nrow(new_rows_immuno)} new MED_ADMIN-exclusive CUIs"))

  # --- Supportive Care ---
  if ("supportive_care_rxnorm" %in% names(TREATMENT_CODES)) {
    supcare_universe <- TREATMENT_CODES$supportive_care_rxnorm
    message("  Supportive Care: using TREATMENT_CODES$supportive_care_rxnorm (named key found)")
  } else {
    supcare_universe <- supcare_df %>%
      dplyr::filter(`Code Type` == "RXNORM") %>%
      dplyr::pull(Code)
    message("  Supportive Care: FALLBACK — no named key in TREATMENT_CODES; using tab RXNORM codes (anti-join produces 0 new rows)")
  }
  supcare_existing <- supcare_df %>%
    dplyr::filter(`Code Type` == "RXNORM") %>%
    dplyr::pull(Code)
  supcare_hits     <- query_med_admin_counts(med_admin_tbl, supcare_universe)
  new_supcare_hits <- supcare_hits %>%
    dplyr::filter(!MEDADMIN_CODE %in% supcare_existing)
  if (nrow(new_supcare_hits) > 0) {
    new_supcare_hits$Meaning <- vapply(new_supcare_hits$MEDADMIN_CODE, get_rxnorm_name, character(1))
    Sys.sleep(0.1)
    new_rows_supcare <- new_supcare_hits %>%
      dplyr::transmute(
        Code                 = MEDADMIN_CODE,
        Meaning              = Meaning,
        `Code Type`          = "RXNORM",
        `Source Table`       = "MED_ADMIN",
        Records              = Records,
        Patients             = Patients,
        `Normalized Meaning` = NA_character_
      )
  }
  message(glue("  Supportive Care: {nrow(new_rows_supcare)} new MED_ADMIN-exclusive CUIs"))

}, error = function(e) {
  message(glue(
    "  WARNING: DuckDB/MED_ADMIN unavailable — skipping MED_ADMIN anti-join.\n",
    "  Error: {e$message}\n",
    "  Continuing with normalized_name section only."
  ))
})

# SECTION 4: APPEND NEW MED_ADMIN ROWS TO APPLICABLE TABS ----

append_rows_to_sheet <- function(wb, sheet_name, existing_df, new_rows_df) {
  if (nrow(new_rows_df) == 0) {
    message(glue("  {sheet_name}: no new MED_ADMIN rows to append"))
    return(wb)
  }
  # next data row = header row (2) + existing data rows + 1
  next_data_row <- 2 + nrow(existing_df) + 1
  wb$add_data(
    sheet     = sheet_name,
    x         = new_rows_df,
    dims      = paste0("A", next_data_row),
    col_names = FALSE
  )
  message(glue("  {sheet_name}: appended {nrow(new_rows_df)} MED_ADMIN rows starting at row {next_data_row}"))
  wb
}

wb <- append_rows_to_sheet(wb, "Chemotherapy",    chemo_df,   new_rows_chemo)
wb <- append_rows_to_sheet(wb, "Immunotherapy",   immuno_df,  new_rows_immuno)
wb <- append_rows_to_sheet(wb, "Supportive Care", supcare_df, new_rows_supcare)

# SECTION 5: LOAD/BUILD RXNORM INGREDIENT CACHE ----
# Functions copied verbatim from R/105 sections 3-4

rxnav_in_names <- function(rxcui) {
  tryCatch(
    {
      url  <- glue("https://rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/related.json?tty=IN")
      resp <- httr2::request(url) %>%
        httr2::req_timeout(10) %>%
        httr2::req_retry(
          max_tries = 3,
          is_transient = ~ httr2::resp_status(.x) %in% c(429, 503, 504)
        ) %>%
        httr2::req_perform()
      data   <- httr2::resp_body_json(resp)
      groups <- data$relatedGroup$conceptGroup
      if (is.null(groups)) return(character(0))
      names_out <- character(0)
      for (grp in groups) {
        if (!is.null(grp$tty) && grp$tty == "IN" && !is.null(grp$conceptProperties)) {
          names_out <- c(
            names_out,
            vapply(grp$conceptProperties, function(p) p$name %||% NA_character_, character(1))
          )
        }
      }
      names_out[!is.na(names_out) & nzchar(names_out)]
    },
    error = function(e) character(0)
  )
}

rxnav_historystatus_ingredients <- function(rxcui) {
  tryCatch(
    {
      url  <- glue("https://rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/historystatus.json")
      resp <- httr2::request(url) %>%
        httr2::req_timeout(10) %>%
        httr2::req_retry(
          max_tries = 3,
          is_transient = ~ httr2::resp_status(.x) %in% c(429, 503, 504)
        ) %>%
        httr2::req_perform()
      data    <- httr2::resp_body_json(resp)
      derived <- data$rxcuiStatusHistory$derivedConcepts$ingredientConcept
      if (is.null(derived)) return(character(0))
      ing <- vapply(derived, function(d) d$ingredientName %||% NA_character_, character(1))
      ing[!is.na(ing) & nzchar(ing)]
    },
    error = function(e) character(0)
  )
}

rule_based_ingredient <- function(drug_string) {
  if (is.na(drug_string) || !nzchar(str_trim(drug_string))) return(NA_character_)
  s <- drug_string
  s <- str_remove(s, "^\\{.*\\}\\s*")
  s <- str_remove_all(s, "\\d+\\s*\\([^)]*\\)")
  s <- str_remove(s, "^\\d+(\\.\\d+)?\\s+(ML|HR)\\s+")
  s <- str_remove_all(s, "\\s*\\[[^\\]]*\\]")
  s <- str_remove_all(s, "\\(Base Equivalent\\)")
  s <- str_remove_all(
    s,
    regex("\\b(MG/ML|MCG/ML|UNT/ML|UNT/MG|MG/MG|MG/HR|MG|MCG|ML)\\b", ignore_case = TRUE)
  )
  s <- str_remove_all(s, "\\d+(\\.\\d+)?")
  s <- str_remove_all(s, "%")
  formulations <- c(
    "Oral Tablet", "Disintegrating", "Oral Capsule", "Oral Solution",
    "Oral Film", "Injectable Solution", "Injection Solution", "Injection",
    "Inj", "Prefilled Syringe", "Ophthalmic Solution", "Ophthalmic Suspension",
    "Ophthalmic Ointment", "Ophth Oint", "Otic Suspension", "Transdermal System",
    "Pack", "Soln", "IV"
  )
  for (f in formulations) {
    s <- str_remove_all(s, regex(paste0("\\b", f, "\\b"), ignore_case = TRUE))
  }
  salts <- c("sodium phosphate", "phosphate", "hydrochloride", "HCl")
  for (sw in salts) {
    s <- str_remove_all(s, regex(paste0("\\b", sw, "\\b"), ignore_case = TRUE))
  }
  s <- str_squish(s)
  s <- str_remove(s, "^[/,\\-\\s]+")
  s <- str_remove(s, "[/,\\-\\s]+$")
  s <- str_trim(s)
  s <- tolower(s)
  if (!nzchar(s)) s <- tolower(str_trim(word(drug_string, 1)))
  s
}

resolve_ingredient <- function(rxcui, sleep_sec = 0.15) {
  ins <- rxnav_in_names(rxcui)
  if (length(ins) == 0) {
    Sys.sleep(sleep_sec)
    ins <- rxnav_historystatus_ingredients(rxcui)
    Sys.sleep(sleep_sec)
    if (length(ins) == 0) return(list(name = NA_character_, source = "api_miss"))
    if (length(ins) == 1) return(list(name = ins, source = "rxnav_historystatus"))
    return(list(name = paste(sort(unique(ins)), collapse = "/"), source = "rxnav_historystatus"))
  }
  Sys.sleep(sleep_sec)
  if (length(ins) == 1) return(list(name = ins, source = "rxnav_IN"))
  list(name = paste(sort(unique(ins)), collapse = "/"), source = "rxnav_IN_combo")
}

# Load or create cache
if (file.exists(CACHE_PATH)) {
  cache_df <- readr::read_csv(CACHE_PATH, col_types = "cccc", show_col_types = FALSE)
  message(glue("  Loaded RxNorm cache: {nrow(cache_df)} entries from {CACHE_PATH}"))
} else {
  cache_df <- tibble::tibble(
    rxcui           = character(0),
    ingredient_name = character(0),
    source          = character(0),
    resolved_at     = character(0)
  )
  message("  No existing RxNorm cache — will build from scratch")
}
cache_size_before <- nrow(cache_df)

# SECTION 6: ASSEMBLE normalized_name VECTORS (per tab) ----
# Re-read each tab AFTER Section 4 appends so vector length matches post-append row count

resolve_tab_normalized_name <- function(wb, sheet_name, cache_df, sleep_sec = 0.15,
                                        flush_every = 250) {
  # Re-read from wb (post-append state)
  current_df <- wb_to_df(wb, sheet = sheet_name, start_row = 2)
  n_rows     <- nrow(current_df)

  # Identify Code, Code Type, and Meaning columns defensively
  col_names <- names(current_df)
  code_col  <- col_names[tolower(col_names) == "code"][1]
  if (is.na(code_col)) code_col <- col_names[grepl("\\bcode\\b", tolower(col_names))][1]
  type_col  <- col_names[grepl("code type", tolower(col_names))][1]
  mean_col  <- col_names[grepl("^meaning$", tolower(col_names))][1]
  if (is.na(mean_col)) mean_col <- col_names[grepl("meaning", tolower(col_names))][1]

  codes    <- as.character(current_df[[code_col]])
  meanings <- as.character(current_df[[mean_col]])
  types    <- if (!is.na(type_col)) as.character(current_df[[type_col]]) else rep("RXNORM", n_rows)

  normalized_vec <- character(n_rows)
  is_rxnorm      <- !is.na(types) & types == "RXNORM"

  # Non-RXNORM rows: copy Meaning verbatim (D-08)
  normalized_vec[!is_rxnorm] <- meanings[!is_rxnorm]

  # RXNORM rows: resolve via cache + RxNav
  rxnorm_codes  <- codes[is_rxnorm]
  rxnorm_idxs   <- which(is_rxnorm)
  uncached_cuis <- setdiff(unique(rxnorm_codes[!is.na(rxnorm_codes)]), cache_df$rxcui)

  if (sheet_name == "Unrelated") {
    message(glue(
      "  Unrelated: {length(uncached_cuis)} CUIs to resolve via RxNav ",
      "(cached: {nrow(cache_df)}). This may take 30-60 min on first run."
    ))
  }

  if (length(uncached_cuis) > 0) {
    n_uncached <- length(uncached_cuis)
    message(glue("  {sheet_name}: resolving {n_uncached} uncached RXNORM CUIs via RxNav..."))
    for (i in seq_along(uncached_cuis)) {
      rx  <- uncached_cuis[i]
      res <- resolve_ingredient(rx, sleep_sec = sleep_sec)
      new_entry <- tibble::tibble(
        rxcui           = rx,
        ingredient_name = res$name %||% NA_character_,
        source          = res$source,
        resolved_at     = format(Sys.Date())
      )
      cache_df <- dplyr::bind_rows(cache_df, new_entry) |>
        dplyr::distinct(rxcui, .keep_all = TRUE)

      if (i %% flush_every == 0) {
        readr::write_csv(cache_df, CACHE_PATH)
        message(glue("    checkpoint: cache flushed at {i}/{n_uncached} ({sheet_name})"))
      }
    }
    # Final cache flush for this tab
    readr::write_csv(cache_df, CACHE_PATH)
    message(glue("  {sheet_name}: cache updated, now {nrow(cache_df)} entries"))
  }

  # Build normalized vector for RXNORM rows
  for (j in seq_along(rxnorm_idxs)) {
    idx <- rxnorm_idxs[j]
    cui <- rxnorm_codes[j]
    if (is.na(cui)) {
      normalized_vec[idx] <- meanings[idx]
      next
    }
    cached_row <- cache_df[cache_df$rxcui == cui, ]
    if (nrow(cached_row) > 0 &&
        !is.na(cached_row$ingredient_name[1]) &&
        nzchar(cached_row$ingredient_name[1])) {
      normalized_vec[idx] <- cached_row$ingredient_name[1]
    } else {
      # Rule-based fallback
      fb <- rule_based_ingredient(meanings[idx])
      normalized_vec[idx] <- if (!is.null(fb) && !is.na(fb) && nzchar(fb)) fb else meanings[idx]
    }
  }

  # Final safety net: no blank values
  blank_mask <- is.na(normalized_vec) | !nzchar(trimws(normalized_vec))
  if (any(blank_mask)) {
    normalized_vec[blank_mask] <- meanings[blank_mask]
    still_blank <- is.na(normalized_vec) | !nzchar(trimws(normalized_vec))
    if (any(still_blank)) {
      normalized_vec[still_blank] <- tolower(trimws(word(meanings[still_blank], 1)))
    }
  }

  stopifnot(length(normalized_vec) == n_rows)
  list(vec = normalized_vec, cache_df = cache_df, n_rows = n_rows)
}

# Resolve all code tabs
message("\n--- Building normalized_name vectors ---")

res_chemo    <- resolve_tab_normalized_name(wb, "Chemotherapy",   cache_df)
cache_df     <- res_chemo$cache_df
normalized_chemo <- res_chemo$vec

res_rad      <- resolve_tab_normalized_name(wb, "Radiation",      cache_df)
cache_df     <- res_rad$cache_df
normalized_rad <- res_rad$vec

res_sct      <- resolve_tab_normalized_name(wb, "SCT",            cache_df)
cache_df     <- res_sct$cache_df
normalized_sct <- res_sct$vec

res_immuno   <- resolve_tab_normalized_name(wb, "Immunotherapy",  cache_df)
cache_df     <- res_immuno$cache_df
normalized_immuno <- res_immuno$vec

res_supcare  <- resolve_tab_normalized_name(wb, "Supportive Care", cache_df)
cache_df     <- res_supcare$cache_df
normalized_supcare <- res_supcare$vec

res_unrelated <- resolve_tab_normalized_name(wb, "Unrelated",     cache_df)
cache_df      <- res_unrelated$cache_df
normalized_unrelated <- res_unrelated$vec

# Final cache save
readr::write_csv(cache_df, CACHE_PATH)
message(glue("  Cache final: {nrow(cache_df)} entries (was {cache_size_before} before)"))

# SECTION 7: WRITE normalized_name COLUMN TO ALL CODE TABS ----

# 7a: Supportive Care — rename existing "Normalized Meaning" header to normalized_name
#     Data values in G3:G173 are UNCHANGED; only the G2 header is overwritten (D-06)
wb$add_data(sheet = "Supportive Care", x = "normalized_name", dims = "G2")

# If Section 4 appended MED_ADMIN rows to Supportive Care, fill normalized_name for
# those appended rows only (original G3:G173 data values are preserved above)
n_original_supcare <- res_supcare$n_rows - nrow(new_rows_supcare)
if (nrow(new_rows_supcare) > 0) {
  appended_norm      <- normalized_supcare[(n_original_supcare + 1):length(normalized_supcare)]
  first_appended_row <- 2 + n_original_supcare + 1
  wb$add_data(
    sheet     = "Supportive Care",
    x         = appended_norm,
    dims      = paste0("G", first_appended_row),
    col_names = FALSE
  )
  message(glue("  Supportive Care: filled normalized_name for {length(appended_norm)} appended MED_ADMIN rows"))
}
message("  Supportive Care: renamed header to 'normalized_name' at G2")

# 7b: All other code tabs — append new last column dynamically
write_normalized_col <- function(wb, tab_name, normalized_vec) {
  tryCatch({
    current_df  <- wb_to_df(wb, sheet = tab_name, start_row = 2)
    last_header <- names(current_df)[ncol(current_df)]
    # If last column header is NA/empty/"None", use that column; otherwise append new one
    if (is.na(last_header) || last_header == "" || last_header == "None" || last_header == "NA") {
      col_idx <- ncol(current_df)      # overwrite the empty trailing column
    } else {
      col_idx <- ncol(current_df) + 1  # append after last column
    }
    col_letter  <- int_to_col(col_idx)
    header_dims <- paste0(col_letter, "2")
    data_dims   <- paste0(col_letter, "3")
    wb$add_data(sheet = tab_name, x = "normalized_name", dims = header_dims)
    wb$add_data(sheet = tab_name, x = normalized_vec,    dims = data_dims, col_names = FALSE)
    message(glue("  {tab_name}: wrote normalized_name at col {col_letter} ({length(normalized_vec)} values)"))
    wb
  }, error = function(e) {
    stop(glue("ERROR writing normalized_name to {tab_name}: {e$message}"))
  })
}

wb <- write_normalized_col(wb, "Chemotherapy",  normalized_chemo)
wb <- write_normalized_col(wb, "Radiation",     normalized_rad)
wb <- write_normalized_col(wb, "SCT",           normalized_sct)
wb <- write_normalized_col(wb, "Immunotherapy", normalized_immuno)
wb <- write_normalized_col(wb, "Unrelated",     normalized_unrelated)

# SECTION 8: SAVE + ROUND-TRIP VERIFY ----

openxlsx2::wb_save(wb, XLSX_NEW)
message(glue("  Saved working copy to {XLSX_NEW}"))

wb2 <- openxlsx2::wb_load(XLSX_NEW)

# (a) all 8 sheets present in exact order
stopifnot(identical(as.character(wb2$sheet_names), EXPECTED_SHEETS))
message("  Round-trip (a): 8 sheets confirmed in correct order")

# (b) normalized_name column present and non-blank on every code tab
code_tabs <- c("Chemotherapy", "Radiation", "SCT", "Immunotherapy", "Supportive Care", "Unrelated")
for (tab in code_tabs) {
  df_check    <- wb_to_df(wb2, tab, start_row = 2)
  stopifnot("normalized_name column missing" = "normalized_name" %in% names(df_check))
  nm_vals     <- df_check[["normalized_name"]]
  blank_count <- sum(is.na(nm_vals) | !nzchar(trimws(as.character(nm_vals))))
  if (blank_count > 0) {
    stop(glue("Round-trip FAIL: {tab} has {blank_count} blank normalized_name values"))
  }
  message(glue("  OK {tab}: normalized_name present, {nrow(df_check)} rows, 0 blanks"))
}

# If round-trip passes, overwrite canonical file (D-10)
file.copy(XLSX_NEW, XLSX_CANONICAL, overwrite = TRUE)
message(glue("  Overwrote canonical file: {XLSX_CANONICAL}"))

# SECTION 9: CONSOLE SUMMARY ----

final_size_kb <- round(file.info(XLSX_CANONICAL)$size / 1024, 1)
message("")
message("=== R/131 Update Summary ===")
message(glue("  MED_ADMIN rows added:"))
message(glue("    Chemotherapy:    {nrow(new_rows_chemo)}"))
message(glue("    Immunotherapy:   {nrow(new_rows_immuno)}"))
message(glue("    Supportive Care: {nrow(new_rows_supcare)}"))
message(glue("  normalized_name coverage:"))
wb2_final <- openxlsx2::wb_load(XLSX_CANONICAL)
for (tab in code_tabs) {
  df_s  <- wb_to_df(wb2_final, tab, start_row = 2)
  n_tot <- nrow(df_s)
  n_nn  <- sum(!is.na(df_s[["normalized_name"]]) &
                 nzchar(trimws(as.character(df_s[["normalized_name"]]))))
  message(glue("    {tab}: {n_nn}/{n_tot} resolved"))
}
message(glue("  RxNorm cache: {cache_size_before} -> {nrow(cache_df)} entries"))
message(glue("  Canonical file size: {final_size_kb} KB ({XLSX_CANONICAL})"))
message("  Round-trip verify: PASSED")
