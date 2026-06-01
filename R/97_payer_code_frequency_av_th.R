# ==============================================================================
# 97_payer_code_frequency_av_th.R -- Payer code frequency summary (AV+TH only)
# ==============================================================================
#
# Phase 34: Insurance Code Frequency Summary of ENCOUNTER table
# Requirements: PAYFREQ-01, PAYFREQ-02, PAYFREQ-03, PAYFREQ-04, PAYFREQ-05, PAYFREQ-06
#
# Purpose: Produce frequency tables of raw PAYER_TYPE_PRIMARY and
#          PAYER_TYPE_SECONDARY codes in AV+TH encounters, cross-referenced
#          against PayerVariable.xlsx to show each code's description (col B:
#          "What old value means") and mapped category (col C: "New Value").
#
#          Codes present in the encounter data but absent from the xlsx are
#          flagged as "NOT IN XLSX". This uses the xlsx's own category scheme
#          (Medicare, Medicaid, Other govt, Private, Uninsured, Other, Impute),
#          NOT the R pipeline's PAYER_MAPPING.
#
# Output: 3 CSV files in output/tables/:
#   - payer_primary_code_freq_av_th.csv    (PAYFREQ-01, PAYFREQ-02)
#   - payer_secondary_code_freq_av_th.csv  (PAYFREQ-01, PAYFREQ-02)
#   - payer_category_summary_av_th.csv     (PAYFREQ-06)
#
# Usage: source("R/97_payer_code_frequency_av_th.R")
#
# Dependencies: Sources R/00_config.R (CONFIG, output_dir, USE_DUCKDB).
#   Conditionally sources R/01_load_pcornet.R for pcornet tables.
#   Requires: get_pcornet_table("ENCOUNTER") (ID, ENCOUNTERID, ENC_TYPE,
#     PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY)
#   Requires: readxl package for reading PayerVariable.xlsx
#
# DuckDB migration (Phase 32): Uses get_pcornet_table() for backend-transparent
#   access. Materializes immediately after loading because all downstream logic
#   (count, left_join, group_by) requires in-memory data.
#
# Standalone script -- NOT part of the main pipeline sequence.
# ==============================================================================

# ==============================================================================
# SECTION 0: Setup
# ==============================================================================

source("R/00_config.R")
library(dplyr)
library(glue)
library(readr)
library(readxl)

# Path to PayerVariable.xlsx (repo root)
PAYER_XLSX_PATH <- "PayerVariable.xlsx"

# Load tables if not already loaded (RDS mode)
if (!USE_DUCKDB && !exists("pcornet")) source("R/01_load_pcornet.R")
# DuckDB mode: open connection if needed
if (USE_DUCKDB && !exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}

message(glue("\n{strrep('=', 70)}"))
message("PAYER CODE FREQUENCY SUMMARY (AV+TH ONLY)")
message("Phase 34: Cross-reference encounter payer codes against PayerVariable.xlsx")
message(glue("{strrep('=', 70)}\n"))

# ==============================================================================
# SECTION 1: Load PayerVariable.xlsx
# ==============================================================================

message("--- SECTION 1: Load PayerVariable.xlsx ---")

payer_lookup <- readxl::read_excel(PAYER_XLSX_PATH, sheet = "Sheet2")

# Rename columns for R-friendliness
names(payer_lookup) <- c("code", "description", "category")

# Trim whitespace and convert all to character
payer_lookup <- payer_lookup %>%
  mutate(across(everything(), ~trimws(as.character(.))))

message(glue("Loaded {nrow(payer_lookup)} rows from PayerVariable.xlsx (Sheet2)"))
message(glue("Unique categories in xlsx: {paste(sort(unique(payer_lookup$category)), collapse = ', ')}"))
message(glue("Number of unique categories: {n_distinct(payer_lookup$category)}"))

message("\nFirst 5 rows:")
for (i in seq_len(min(5, nrow(payer_lookup)))) {
  r <- payer_lookup[i, ]
  message(glue("  code={r$code} | desc={r$description} | cat={r$category}"))
}
message("Last 3 rows:")
for (i in seq(max(1, nrow(payer_lookup) - 2), nrow(payer_lookup))) {
  r <- payer_lookup[i, ]
  message(glue("  code={r$code} | desc={r$description} | cat={r$category}"))
}

# ==============================================================================
# SECTION 2: Load and filter ENCOUNTER table
# ==============================================================================

message(glue("\n--- SECTION 2: Load and Filter ENCOUNTER Table (AV+TH) ---"))

enc <- get_pcornet_table("ENCOUNTER") %>%
  materialize() %>%
  filter(ENC_TYPE %in% c("AV", "TH"))

total_enc <- nrow(enc)
total_patients <- n_distinct(enc$ID)

message(glue("Total AV+TH encounters: {format(total_enc, big.mark = ',')}"))
message(glue("Total unique patients:  {format(total_patients, big.mark = ',')}"))

# Ensure payer columns are character (DuckDB may return different types)
enc <- enc %>%
  mutate(
    PAYER_TYPE_PRIMARY   = as.character(PAYER_TYPE_PRIMARY),
    PAYER_TYPE_SECONDARY = as.character(PAYER_TYPE_SECONDARY)
  )

# Quick peek at non-NA payer values
n_primary_non_na   <- sum(!is.na(enc$PAYER_TYPE_PRIMARY) & enc$PAYER_TYPE_PRIMARY != "")
n_secondary_non_na <- sum(!is.na(enc$PAYER_TYPE_SECONDARY) & enc$PAYER_TYPE_SECONDARY != "")
message(glue("PRIMARY non-NA/non-empty:   {format(n_primary_non_na, big.mark = ',')} ({round(100 * n_primary_non_na / total_enc, 1)}%)"))
message(glue("SECONDARY non-NA/non-empty: {format(n_secondary_non_na, big.mark = ',')} ({round(100 * n_secondary_non_na / total_enc, 1)}%)"))

# ==============================================================================
# SECTION 3: PAYER_TYPE_PRIMARY frequency table
# ==============================================================================

message(glue("\n--- SECTION 3: PAYER_TYPE_PRIMARY Frequency Table ---"))

# Build frequency of each distinct value, representing NA and empty explicitly
primary_freq <- enc %>%
  mutate(
    code = case_when(
      is.na(PAYER_TYPE_PRIMARY)           ~ "<NA>",
      PAYER_TYPE_PRIMARY == ""            ~ "<EMPTY>",
      TRUE                                ~ PAYER_TYPE_PRIMARY
    )
  ) %>%
  count(code, name = "n") %>%
  arrange(desc(n))

# Left join to payer_lookup to get description and category
primary_freq <- primary_freq %>%
  left_join(payer_lookup, by = "code") %>%
  mutate(
    description = ifelse(is.na(description) & !code %in% c("<NA>", "<EMPTY>"),
                         "NOT IN XLSX", description),
    category    = ifelse(is.na(category) & !code %in% c("<NA>", "<EMPTY>"),
                         "NOT IN XLSX", category),
    pct = round(100 * n / total_enc, 2)
  ) %>%
  select(code, description, category, n, pct) %>%
  arrange(desc(n))

message(glue("Distinct PRIMARY codes: {nrow(primary_freq)}"))
n_not_in_xlsx_primary <- sum(primary_freq$description == "NOT IN XLSX", na.rm = TRUE)
message(glue("Codes NOT in xlsx: {n_not_in_xlsx_primary}"))

# ==============================================================================
# SECTION 4: PAYER_TYPE_SECONDARY frequency table
# ==============================================================================

message(glue("\n--- SECTION 4: PAYER_TYPE_SECONDARY Frequency Table ---"))

secondary_freq <- enc %>%
  mutate(
    code = case_when(
      is.na(PAYER_TYPE_SECONDARY)           ~ "<NA>",
      PAYER_TYPE_SECONDARY == ""            ~ "<EMPTY>",
      TRUE                                ~ PAYER_TYPE_SECONDARY
    )
  ) %>%
  count(code, name = "n") %>%
  arrange(desc(n))

# Left join to payer_lookup to get description and category
secondary_freq <- secondary_freq %>%
  left_join(payer_lookup, by = "code") %>%
  mutate(
    description = ifelse(is.na(description) & !code %in% c("<NA>", "<EMPTY>"),
                         "NOT IN XLSX", description),
    category    = ifelse(is.na(category) & !code %in% c("<NA>", "<EMPTY>"),
                         "NOT IN XLSX", category),
    pct = round(100 * n / total_enc, 2)
  ) %>%
  select(code, description, category, n, pct) %>%
  arrange(desc(n))

message(glue("Distinct SECONDARY codes: {nrow(secondary_freq)}"))
n_not_in_xlsx_secondary <- sum(secondary_freq$description == "NOT IN XLSX", na.rm = TRUE)
message(glue("Codes NOT in xlsx: {n_not_in_xlsx_secondary}"))

# ==============================================================================
# SECTION 5: Category-level summary CSV
# ==============================================================================

message(glue("\n--- SECTION 5: Category-Level Summary ---"))

# Primary category summary
primary_cat <- primary_freq %>%
  group_by(category) %>%
  summarise(n = sum(n), .groups = "drop") %>%
  mutate(
    field = "PRIMARY",
    pct   = round(100 * n / total_enc, 2)
  ) %>%
  select(field, category, n, pct) %>%
  arrange(desc(n))

# Secondary category summary
secondary_cat <- secondary_freq %>%
  group_by(category) %>%
  summarise(n = sum(n), .groups = "drop") %>%
  mutate(
    field = "SECONDARY",
    pct   = round(100 * n / total_enc, 2)
  ) %>%
  select(field, category, n, pct) %>%
  arrange(desc(n))

category_summary <- bind_rows(primary_cat, secondary_cat)

message(glue("PRIMARY categories:   {nrow(primary_cat)}"))
message(glue("SECONDARY categories: {nrow(secondary_cat)}"))

# ==============================================================================
# SECTION 6: Write CSV outputs
# ==============================================================================

message(glue("\n--- SECTION 6: Writing CSV Outputs ---"))

output_dir <- file.path(CONFIG$output_dir, "tables")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# CSV 1: Primary code frequency
csv1_path <- file.path(output_dir, "payer_primary_code_freq_av_th.csv")
write_csv(primary_freq, csv1_path)
message(glue("  Written: payer_primary_code_freq_av_th.csv ({nrow(primary_freq)} rows)"))

# CSV 2: Secondary code frequency
csv2_path <- file.path(output_dir, "payer_secondary_code_freq_av_th.csv")
write_csv(secondary_freq, csv2_path)
message(glue("  Written: payer_secondary_code_freq_av_th.csv ({nrow(secondary_freq)} rows)"))

# CSV 3: Category-level summary
csv3_path <- file.path(output_dir, "payer_category_summary_av_th.csv")
write_csv(category_summary, csv3_path)
message(glue("  Written: payer_category_summary_av_th.csv ({nrow(category_summary)} rows)"))

# ==============================================================================
# SECTION 7: Console summary
# ==============================================================================

message(glue("\n{strrep('=', 70)}"))
message("PAYER CODE FREQUENCY SUMMARY -- RESULTS")
message(glue("{strrep('=', 70)}"))

message(glue("\nTotal AV+TH encounters analyzed: {format(total_enc, big.mark = ',')}"))
message(glue("Total unique patients:           {format(total_patients, big.mark = ',')}"))

# --- PRIMARY ---
message(glue("\n--- PAYER_TYPE_PRIMARY ---"))
message(glue("Distinct raw codes found:  {nrow(primary_freq)}"))
message(glue("Codes NOT in xlsx:         {n_not_in_xlsx_primary}"))

if (n_not_in_xlsx_primary > 0) {
  not_in_xlsx_primary <- primary_freq %>% filter(description == "NOT IN XLSX")
  message("  Codes NOT in xlsx:")
  for (i in seq_len(nrow(not_in_xlsx_primary))) {
    r <- not_in_xlsx_primary[i, ]
    message(glue("    code={r$code} | n={format(r$n, big.mark = ',')} | pct={r$pct}%"))
  }
}

message("\nTop 10 PRIMARY codes by frequency:")
top10_primary <- head(primary_freq, 10)
message(sprintf("  %-10s %-40s %-15s %12s %6s", "Code", "Description", "Category", "Count", "Pct"))
message(sprintf("  %-10s %-40s %-15s %12s %6s", strrep("-", 10), strrep("-", 40), strrep("-", 15), strrep("-", 12), strrep("-", 6)))
for (i in seq_len(nrow(top10_primary))) {
  r <- top10_primary[i, ]
  desc_trunc <- ifelse(nchar(as.character(r$description)) > 40,
                       paste0(substr(as.character(r$description), 1, 37), "..."),
                       as.character(r$description))
  cat_trunc  <- ifelse(nchar(as.character(r$category)) > 15,
                       paste0(substr(as.character(r$category), 1, 12), "..."),
                       as.character(r$category))
  message(sprintf("  %-10s %-40s %-15s %12s %5.2f%%",
                  r$code, desc_trunc, cat_trunc,
                  format(r$n, big.mark = ","), r$pct))
}

message("\nPRIMARY category breakdown:")
message(sprintf("  %-20s %12s %6s", "Category", "Count", "Pct"))
message(sprintf("  %-20s %12s %6s", strrep("-", 20), strrep("-", 12), strrep("-", 6)))
for (i in seq_len(nrow(primary_cat))) {
  r <- primary_cat[i, ]
  cat_label <- ifelse(is.na(r$category), "<NA>", as.character(r$category))
  message(sprintf("  %-20s %12s %5.2f%%", cat_label, format(r$n, big.mark = ","), r$pct))
}

# --- SECONDARY ---
message(glue("\n--- PAYER_TYPE_SECONDARY ---"))
message(glue("Distinct raw codes found:  {nrow(secondary_freq)}"))
message(glue("Codes NOT in xlsx:         {n_not_in_xlsx_secondary}"))

if (n_not_in_xlsx_secondary > 0) {
  not_in_xlsx_secondary <- secondary_freq %>% filter(description == "NOT IN XLSX")
  message("  Codes NOT in xlsx:")
  for (i in seq_len(nrow(not_in_xlsx_secondary))) {
    r <- not_in_xlsx_secondary[i, ]
    message(glue("    code={r$code} | n={format(r$n, big.mark = ',')} | pct={r$pct}%"))
  }
}

message("\nTop 10 SECONDARY codes by frequency:")
top10_secondary <- head(secondary_freq, 10)
message(sprintf("  %-10s %-40s %-15s %12s %6s", "Code", "Description", "Category", "Count", "Pct"))
message(sprintf("  %-10s %-40s %-15s %12s %6s", strrep("-", 10), strrep("-", 40), strrep("-", 15), strrep("-", 12), strrep("-", 6)))
for (i in seq_len(nrow(top10_secondary))) {
  r <- top10_secondary[i, ]
  desc_trunc <- ifelse(nchar(as.character(r$description)) > 40,
                       paste0(substr(as.character(r$description), 1, 37), "..."),
                       as.character(r$description))
  cat_trunc  <- ifelse(nchar(as.character(r$category)) > 15,
                       paste0(substr(as.character(r$category), 1, 12), "..."),
                       as.character(r$category))
  message(sprintf("  %-10s %-40s %-15s %12s %5.2f%%",
                  r$code, desc_trunc, cat_trunc,
                  format(r$n, big.mark = ","), r$pct))
}

message("\nSECONDARY category breakdown:")
message(sprintf("  %-20s %12s %6s", "Category", "Count", "Pct"))
message(sprintf("  %-20s %12s %6s", strrep("-", 20), strrep("-", 12), strrep("-", 6)))
for (i in seq_len(nrow(secondary_cat))) {
  r <- secondary_cat[i, ]
  cat_label <- ifelse(is.na(r$category), "<NA>", as.character(r$category))
  message(sprintf("  %-20s %12s %5.2f%%", cat_label, format(r$n, big.mark = ","), r$pct))
}

# --- CSV files written ---
message(glue("\nCSV files written to {output_dir}/:"))
message("  - payer_primary_code_freq_av_th.csv")
message("  - payer_secondary_code_freq_av_th.csv")
message("  - payer_category_summary_av_th.csv")

message(glue("\n{strrep('=', 70)}"))
message("END OF PAYER CODE FREQUENCY SUMMARY (AV+TH ONLY)")
message(glue("{strrep('=', 70)}"))
