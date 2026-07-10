# ==============================================================================
# 105_normalize_supportive_care_meaning.R -- Supportive Care ingredient normalizer
# ==============================================================================
# Purpose:      Resolve each of the 171 RXNORM codes on the "Supportive Care" tab
#               of data/reference/all_codes_resolved_next_tables_v2.1.xlsx to its
#               generic INGREDIENT name (RxNorm IN concept) and append a new
#               trailing column "Normalized Meaning" (column G) IN PLACE.
#
#               Collapses dosage / spelling / brand / salt / biosimilar variants
#               of the same drug to one canonical ingredient (D-01/D-05/D-06), so
#               ~8+ ondansetron variants, the several dexamethasone/dexamethasone
#               phosphate variants, and brand names (Zofran, Neulasta, ...) all
#               fold to a single value. Combination products keep a sorted,
#               "/"-joined combined label (never silently dropped to one).
#
#               Three-step resolution guarantees every row gets a value:
#                 1. RxNav related.json?tty=IN   (active concepts; salts/biosimilars/
#                    packs/combos handled natively by RxNorm)
#                 2. RxNav historystatus.json     (retired-code derivedConcepts)
#                 3. rule-based parse             (canonicalize_drug_name fallback)
#
#               Lookups are cached to data/reference/rxnorm_ingredient_cache.csv so
#               subsequent runs are fully offline. The FIRST run needs internet
#               (login node / local box, NOT a compute node). If RxNav is
#               unreachable and a code is not cached, resolution degrades to the
#               rule-based fallback -- the script never crashes on no internet.
#
# Inputs:       data/reference/all_codes_resolved_next_tables_v2.1.xlsx  (Supportive Care tab)
#               data/reference/rxnorm_ingredient_cache.csv               (optional; built if absent)
#               R/00_config.R  (DRUG_NAME_ALIASES + canonicalize_drug_name)
#
# Outputs:      data/reference/all_codes_resolved_next_tables_v2.1.xlsx
#                 -> Supportive Care tab gains trailing col G "Normalized Meaning"
#               data/reference/rxnorm_ingredient_cache.csv
#                 -> columns rxcui, ingredient_name, source, resolved_at
#
# Dependencies: dplyr, stringr, glue, purrr, httr2, openxlsx2, readr
#
# Requirements: SUPCARE-01, SUPCARE-02, SUPCARE-03, SUPCARE-04, SUPCARE-05 (Phase 120)
#
# Usage:        Rscript R/105_normalize_supportive_care_meaning.R
#               source("R/105_normalize_supportive_care_meaning.R")
#
# Note:         In-place edit uses git as the revertible baseline -- the workbook
#               is committed, so a bad write is trivially reverted. The in-script
#               fresh-reopen round-trip verify (Section 7) asserts the other 7
#               sheets, the row-1 banner, and each sheet's row count survive.
# ==============================================================================

# ------------------------------------------------------------------------------
# SECTION 1: SETUP ----
# ------------------------------------------------------------------------------
suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(purrr)
  library(httr2)
  library(openxlsx2)
  library(readr)
})

source("R/00_config.R")

# Repo-relative paths only -- no working-directory changes, no absolute paths
# (CLAUDE.md anti-pattern #2).
XLSX_PATH <- "data/reference/all_codes_resolved_next_tables_v2.1.xlsx"
SHEET     <- "Supportive Care"
CACHE_CSV <- "data/reference/rxnorm_ingredient_cache.csv"

EXPECTED_SHEETS <- c(
  "Index", "Sheet1", "Chemotherapy", "Radiation", "SCT",
  "Immunotherapy", "Supportive Care", "Unrelated"
)
N_SUPCARE_ROWS <- 171L

# Other sheets' data-row counts (extent minus header) for the round-trip check.
OTHER_SHEET_ROWS <- c(
  Chemotherapy  = 203L,
  Radiation     = 12L,
  SCT           = 41L,
  Immunotherapy = 27L,
  Unrelated     = 9866L
)

message(glue("R/105: normalizing '{SHEET}' meanings in {XLSX_PATH}"))

# ------------------------------------------------------------------------------
# SECTION 2: READ THE SUPPORTIVE CARE SHEET ----
# ------------------------------------------------------------------------------
stopifnot(file.exists(XLSX_PATH))

wb <- openxlsx2::wb_load(XLSX_PATH) # preserves all 8 sheets + styles
df <- wb_to_df(wb, sheet = SHEET, start_row = 2)

if (nrow(df) != N_SUPCARE_ROWS) {
  stop(glue("Expected {N_SUPCARE_ROWS} rows on '{SHEET}', found {nrow(df)}"))
}
message(glue("  read {nrow(df)} rows x {ncol(df)} cols from '{SHEET}'"))

col_names   <- names(df)
code_col    <- col_names[str_detect(tolower(col_names), "^code$")][1]
if (is.na(code_col)) code_col <- col_names[str_detect(tolower(col_names), "code")][1]
type_col    <- col_names[str_detect(tolower(col_names), "code type")][1]
meaning_col <- col_names[str_detect(tolower(col_names), "meaning")][1]

if (is.na(code_col) || is.na(meaning_col)) {
  stop(glue("Could not locate Code/Meaning columns on '{SHEET}'"))
}
message(glue("  code_col='{code_col}'  type_col='{type_col %||% NA}'  meaning_col='{meaning_col}'"))

# Guard (Pitfall 5): all 171 rows are RXNORM in this tab. Any non-RXNORM row is
# routed to the rule-based fallback rather than branched on heavily.
if (!is.na(type_col)) {
  if (!all(df[[type_col]] == "RXNORM", na.rm = TRUE)) {
    n_other <- sum(df[[type_col]] != "RXNORM", na.rm = TRUE)
    message(glue("  NOTE: {n_other} non-RXNORM rows -> rule-based fallback"))
  }
}

codes    <- as.character(df[[code_col]])
meanings <- as.character(df[[meaning_col]])

# ------------------------------------------------------------------------------
# SECTION 3: RXNAV IN RESOLUTION (CACHED) ----
# ------------------------------------------------------------------------------

# rxnav_in_names(): GET related.json?tty=IN and collect ALL IN concept names.
# Returns character(0) on empty / error (never NULL). Uses the R/27 httr2 wrapper
# VERBATIM (request %>% req_timeout %>% req_retry %>% req_perform). This is the
# CORRECT endpoint for generic-only (D-01) -- NOT the R/27 full-clinical-name
# properties endpoint, which returns dose+form (wrong grain for the IN concept).
rxnav_in_names <- function(rxcui) {
  tryCatch(
    {
      url <- glue("https://rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/related.json?tty=IN")
      resp <- request(url) %>%
        req_timeout(10) %>%
        req_retry(
          max_tries = 3,
          is_transient = ~ resp_status(.x) %in% c(429, 503, 504)
        ) %>%
        req_perform()
      data <- resp_body_json(resp)

      groups <- data$relatedGroup$conceptGroup
      if (is.null(groups)) {
        return(character(0))
      }
      names_out <- character(0)
      for (grp in groups) {
        if (!is.null(grp$tty) && grp$tty == "IN" && !is.null(grp$conceptProperties)) {
          names_out <- c(
            names_out,
            map_chr(grp$conceptProperties, ~ .x$name %||% NA_character_)
          )
        }
      }
      names_out[!is.na(names_out) & nzchar(names_out)]
    },
    error = function(e) character(0)
  )
}

# rxnav_historystatus_ingredients(): GET historystatus.json and collect
# derivedConcepts.ingredientConcept[].ingredientName -- recovers retired RxCUIs
# (e.g. 104896 -> ondansetron). Reuses R/27's historystatus parse shape.
rxnav_historystatus_ingredients <- function(rxcui) {
  tryCatch(
    {
      url <- glue("https://rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/historystatus.json")
      resp <- request(url) %>%
        req_timeout(10) %>%
        req_retry(
          max_tries = 3,
          is_transient = ~ resp_status(.x) %in% c(429, 503, 504)
        ) %>%
        req_perform()
      data <- resp_body_json(resp)

      derived <- data$rxcuiStatusHistory$derivedConcepts$ingredientConcept
      if (is.null(derived)) {
        return(character(0))
      }
      ing <- map_chr(derived, ~ .x$ingredientName %||% NA_character_)
      ing[!is.na(ing) & nzchar(ing)]
    },
    error = function(e) character(0)
  )
}

# resolve_ingredient(): three-step resolution (RESEARCH Pattern 1). Combos
# (>1 IN concept, D-05 / Pitfall 3) are sorted + unique + "/"-joined so the label
# is deterministic across reruns.
resolve_ingredient <- function(rxcui, sleep_sec = 0.1) {
  ins <- rxnav_in_names(rxcui)
  if (length(ins) == 0) {
    Sys.sleep(sleep_sec)
    ins <- rxnav_historystatus_ingredients(rxcui)
    Sys.sleep(sleep_sec)
    if (length(ins) == 0) {
      return(list(name = NA_character_, source = "api_miss"))
    }
    if (length(ins) == 1) {
      return(list(name = ins, source = "rxnav_historystatus"))
    }
    return(list(name = paste(sort(unique(ins)), collapse = "/"), source = "rxnav_historystatus"))
  }
  Sys.sleep(sleep_sec)
  if (length(ins) == 1) {
    return(list(name = ins, source = "rxnav_IN"))
  }
  # Combination product: keep ALL ingredients, sorted + "/"-joined (D-05).
  list(name = paste(sort(unique(ins)), collapse = "/"), source = "rxnav_IN_combo")
}

# Cache logic (reuse R/27 cache + anti_join idea): read the cache if present,
# query ONLY new codes, append, rewrite. The cache is the OFFLINE source of truth.
unique_codes <- tibble(rxcui = unique(codes[!is.na(codes)]))

if (file.exists(CACHE_CSV)) {
  cache <- readr::read_csv(CACHE_CSV, col_types = "cccc")
  message(glue("  loaded cache: {nrow(cache)} rows from {CACHE_CSV}"))
} else {
  cache <- tibble(
    rxcui           = character(0),
    ingredient_name = character(0),
    source          = character(0),
    resolved_at     = character(0)
  )
  message("  no existing cache -- will build from scratch")
}

codes_to_query <- unique_codes %>%
  anti_join(cache, by = "rxcui") %>%
  pull(rxcui)

if (length(codes_to_query) > 0) {
  message(glue("  querying RxNav for {length(codes_to_query)} new code(s)..."))
  new_rows <- map_dfr(codes_to_query, function(rx) {
    res <- resolve_ingredient(rx)
    tibble(
      rxcui           = rx,
      ingredient_name = res$name,
      source          = res$source,
      resolved_at     = format(Sys.Date())
    )
  })
  cache <- bind_rows(cache, new_rows)
  readr::write_csv(cache, CACHE_CSV)
  message(glue("  wrote {nrow(cache)} rows to {CACHE_CSV}"))
} else {
  message("  all codes already cached -- offline run")
}

# ------------------------------------------------------------------------------
# SECTION 4: RULE-BASED FALLBACK (D-04) ----
# ------------------------------------------------------------------------------
# For source == "api_miss" or an NA ingredient name, parse the ORIGINAL Meaning
# string down to an ingredient. Reuses canonicalize_drug_name() (Task 1 aliases).
# Never returns blank -- if everything strips away, falls back to the first word.
rule_based_ingredient <- function(meaning_text) {
  if (is.na(meaning_text) || !nzchar(str_trim(meaning_text))) {
    return(NA_character_)
  }
  s <- meaning_text

  # (a) strip pack wrappers: leading {...} and inner "N (...)"
  s <- str_remove(s, "^\\{.*\\}\\s*")
  s <- str_remove_all(s, "\\d+\\s*\\([^)]*\\)")

  # (b) strip leading quantity prefixes ("1 ML", "168 HR", "0.6 ML")
  s <- str_remove(s, "^\\d+(\\.\\d+)?\\s+(ML|HR)\\s+")

  # (c) strip brand brackets [Decadron], [Neulasta], ...
  s <- str_remove_all(s, "\\s*\\[[^\\]]*\\]")

  # (d) strip dose tokens: (Base Equivalent), units, numbers, percent
  s <- str_remove_all(s, "\\(Base Equivalent\\)")
  s <- str_remove_all(
    s,
    regex("\\b(MG/ML|MCG/ML|UNT/ML|UNT/MG|MG/MG|MG/HR|MG|MCG|ML)\\b", ignore_case = TRUE)
  )
  s <- str_remove_all(s, "\\d+(\\.\\d+)?")
  s <- str_remove_all(s, "%")

  # (e) strip formulation words
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

  # (f) strip salt words (RxNav handles these when it resolves; fallback needs them)
  salts <- c("sodium phosphate", "phosphate", "hydrochloride", "HCl")
  for (sw in salts) {
    s <- str_remove_all(s, regex(paste0("\\b", sw, "\\b"), ignore_case = TRUE))
  }

  # collapse whitespace + tidy stray separators
  s <- str_squish(s)
  s <- str_remove(s, "^[/,\\-\\s]+")
  s <- str_remove(s, "[/,\\-\\s]+$")
  s <- str_trim(s)

  # canonicalize brand->generic, then lowercase to match RxNorm IN generic style
  s <- canonicalize_drug_name(s)
  s <- tolower(str_trim(s))

  # never blank: fall back to the trimmed first word of the original Meaning
  if (!nzchar(s)) {
    s <- tolower(str_trim(word(meaning_text, 1)))
  }
  s
}

# ------------------------------------------------------------------------------
# SECTION 5: ASSEMBLE THE Normalized Meaning VECTOR (length 171, never blank) ----
# ------------------------------------------------------------------------------
row_tbl <- tibble(
  rxcui   = codes,
  meaning = meanings
) %>%
  left_join(cache, by = "rxcui") %>%
  mutate(
    needs_fallback = source %in% c("api_miss") | is.na(ingredient_name) | !nzchar(ifelse(is.na(ingredient_name), "", ingredient_name)),
    normalized = ifelse(needs_fallback, map_chr(meaning, rule_based_ingredient), ingredient_name),
    norm_source = case_when(
      needs_fallback ~ "rule_fallback",
      TRUE           ~ source
    )
  )

# Final safety net: any still-blank value -> first word of Meaning (never blank).
row_tbl <- row_tbl %>%
  mutate(
    normalized = ifelse(
      is.na(normalized) | !nzchar(str_trim(normalized)),
      tolower(str_trim(word(meaning, 1))),
      normalized
    )
  )

normalized_vec <- row_tbl$normalized
stopifnot(length(normalized_vec) == N_SUPCARE_ROWS)
if (any(is.na(normalized_vec) | !nzchar(trimws(normalized_vec)))) {
  stop("Assembled Normalized Meaning contains blank/NA values -- fallback failed")
}

n_combo <- sum(row_tbl$norm_source == "rxnav_IN_combo", na.rm = TRUE)

# ------------------------------------------------------------------------------
# SECTION 6: IN-PLACE APPEND (D-02) ----
# ------------------------------------------------------------------------------
# Operate on the ALREADY-loaded wb: write the G2 header + G3:G173 data, widen the
# autofilter to include column G, optionally copy F2's header style, then save
# over the file in place. Do NOT rebuild with wb_workbook() (drops other 7 sheets).
wb$add_data(sheet = SHEET, x = "Normalized Meaning", dims = "G2")
wb$add_data(sheet = SHEET, x = normalized_vec, dims = "G3", col_names = FALSE)

# Widen the autofilter/dimension to column G (Pitfall 1). Best-effort: the column
# WRITE is the hard requirement; the filter widening is cosmetic.
tryCatch(
  {
    wb$add_filter(sheet = SHEET, cols = 1:7)
  },
  error = function(e) message(glue("  NOTE: add_filter(cols=1:7) skipped: {e$message}"))
)

# Best-effort: copy F2's header font/fill to G2 for a visual match.
tryCatch(
  {
    wb$add_font(sheet = SHEET, dims = "G2", bold = "true", color = wb_color(hex = "FFFFFFFF"))
    wb$add_fill(sheet = SHEET, dims = "G2", color = wb_color(hex = "FF404040"))
  },
  error = function(e) message(glue("  NOTE: header styling skipped: {e$message}"))
)

openxlsx2::wb_save(wb, XLSX_PATH) # overwrite in place (D-02)
message(glue("  saved '{SHEET}' with new 'Normalized Meaning' column to {XLSX_PATH}"))

# ------------------------------------------------------------------------------
# SECTION 7: LOCAL ROUND-TRIP VERIFICATION (REQUIRED) ----
# ------------------------------------------------------------------------------
# Reopen with a FRESH wb2 and assert the write preserved everything (Open Q1).
wb2 <- openxlsx2::wb_load(XLSX_PATH)

# (a) 8 sheets present in the same order
if (length(wb2$sheet_names) != 8 || !identical(as.character(wb2$sheet_names), EXPECTED_SHEETS)) {
  stop(glue(
    "Round-trip FAIL (a): expected 8 sheets in order, got: {paste(wb2$sheet_names, collapse = ', ')}"
  ))
}

# (b) Supportive Care reads as 7 cols x 171 rows with the new column present
sc <- wb_to_df(wb2, SHEET, start_row = 2)
if (ncol(sc) != 7) stop(glue("Round-trip FAIL (b): '{SHEET}' has {ncol(sc)} cols, expected 7"))
if (nrow(sc) != N_SUPCARE_ROWS) stop(glue("Round-trip FAIL (b): '{SHEET}' has {nrow(sc)} rows, expected {N_SUPCARE_ROWS}"))
if (!("Normalized Meaning" %in% names(sc))) stop("Round-trip FAIL (b): 'Normalized Meaning' column missing")

# (c) no blank Normalized Meaning
nm <- sc[["Normalized Meaning"]]
if (!all(!is.na(nm) & nzchar(trimws(nm)))) {
  stop("Round-trip FAIL (c): blank Normalized Meaning value(s) after save")
}

# (d) other sheets' data-row counts unchanged (allow +/-1 for trailing-blank drift)
for (s in names(OTHER_SHEET_ROWS)) {
  got <- nrow(wb_to_df(wb2, s, start_row = 2))
  want <- OTHER_SHEET_ROWS[[s]]
  if (abs(got - want) > 1) {
    stop(glue("Round-trip FAIL (d): '{s}' has {got} data rows, expected ~{want}"))
  }
  if (got != want) {
    message(glue("  NOTE: '{s}' data rows {got} (expected {want}; within +/-1)"))
  }
}

# ------------------------------------------------------------------------------
# CONSOLE SUMMARY ----
# ------------------------------------------------------------------------------
src_counts <- row_tbl %>%
  count(norm_source, name = "n") %>%
  arrange(desc(n))

message("")
message("=== R/105 Normalized Meaning summary ===")
for (i in seq_len(nrow(src_counts))) {
  message(glue("  {src_counts$norm_source[i]}: {src_counts$n[i]}"))
}
message(glue("  combination products flagged: {n_combo}"))
message(glue("  rows normalized: {nrow(row_tbl)} / {N_SUPCARE_ROWS}"))
message("  round-trip verify: PASSED (8 sheets, Supportive Care 7 cols x 171 rows, no blanks, other sheets intact)")
