# ==============================================================================
# 52_strange_death_source_and_enc_type.R -- Source & Encounter Type for Strange Deaths
# ==============================================================================
#
# Purpose:
#   For the ~200 patients flagged with post-death clinical activity ("strange
#   deaths"), show what data SOURCE and ENC_TYPE their post-death encounters
#   have. Helps distinguish administrative artifacts (e.g., OP billing lag)
#   from genuine data quality issues (e.g., IP admission after death).
#
# Inputs:
#   - cache/outputs/validated_death_dates.rds (from R/53)
#   - DuckDB ENCOUNTER table (ENC_TYPE, SOURCE, ADMIT_DATE)
#
# Outputs:
#   - output/strange_death_source_enc_type.xlsx (three sheets)
#     Sheet 1: "Per-Event Detail" -- one row per post-death encounter
#     Sheet 2: "ENC_TYPE Summary" -- encounter type distribution
#     Sheet 3: "SOURCE Summary" -- data source distribution
#
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(lubridate)
  library(openxlsx2)
  library(tidyr)
})

source("R/00_config.R")
source("R/utils/utils_assertions.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")

DEATH_RDS <- file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "strange_death_source_enc_type.xlsx")

message("=== Strange Deaths: Source & Encounter Type Investigation ===")
message()
message(glue("  Death RDS: {DEATH_RDS}"))
message(glue("  Output:    {OUTPUT_XLSX}"))
message()


# ==============================================================================
# SECTION 2: INPUT VALIDATION ----
# ==============================================================================

assert_rds_exists(DEATH_RDS, script_name = "R/52")


# ==============================================================================
# SECTION 3: LOAD STRANGE DEATHS ----
# ==============================================================================

message("--- Loading strange deaths ---")

validated_deaths <- readRDS(DEATH_RDS)
message(glue("  Total validated death records: {nrow(validated_deaths)}"))

strange_deaths <- validated_deaths %>%
  filter(death_valid == TRUE, post_death_activity == TRUE)

message(glue("  Patients with post-death activity (strange deaths): {nrow(strange_deaths)}"))
message()


# ==============================================================================
# SECTION 4: QUERY POST-DEATH ENCOUNTERS WITH ENC_TYPE AND SOURCE ----
# ==============================================================================

message("--- Querying post-death encounters with ENC_TYPE and SOURCE ---")

open_pcornet_con()

post_death_enc <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ENCOUNTERID, ADMIT_DATE, ENC_TYPE, SOURCE) %>%
  collect() %>%
  mutate(ADMIT_DATE = parse_pcornet_date(ADMIT_DATE)) %>%
  filter(!is.na(ADMIT_DATE)) %>%
  inner_join(
    strange_deaths %>% select(ID, DEATH_DATE, DEATH_SOURCE),
    by = "ID"
  ) %>%
  filter(ADMIT_DATE > DEATH_DATE) %>%
  mutate(
    days_after_death = as.numeric(ADMIT_DATE - DEATH_DATE),
    gap_bucket = case_when(
      days_after_death <= 30 ~ "0-30 days",
      days_after_death <= 90 ~ "31-90 days",
      days_after_death <= 365 ~ "91-365 days",
      days_after_death > 365 ~ ">1 year",
      TRUE ~ NA_character_
    )
  ) %>%
  arrange(ID, days_after_death)

close_pcornet_con()

message(glue("  Post-death encounters: {nrow(post_death_enc)} events from {n_distinct(post_death_enc$ID)} patients"))
message()


# ==============================================================================
# SECTION 5: SUMMARIES ----
# ==============================================================================

message("--- Building summary tables ---")

# ENC_TYPE distribution
enc_type_summary <- post_death_enc %>%
  count(ENC_TYPE, gap_bucket) %>%
  pivot_wider(names_from = gap_bucket, values_from = n, values_fill = 0) %>%
  mutate(total = rowSums(across(where(is.numeric)))) %>%
  arrange(desc(total))

message("  Encounter type distribution:")
enc_type_totals <- post_death_enc %>%
  count(ENC_TYPE, name = "n") %>%
  mutate(pct = sprintf("%.1f%%", 100 * n / sum(n))) %>%
  arrange(desc(n))
for (i in seq_len(nrow(enc_type_totals))) {
  message(glue("    {enc_type_totals$ENC_TYPE[i]}: {enc_type_totals$n[i]} ({enc_type_totals$pct[i]})"))
}

# SOURCE distribution
source_summary <- post_death_enc %>%
  count(SOURCE, gap_bucket) %>%
  pivot_wider(names_from = gap_bucket, values_from = n, values_fill = 0) %>%
  mutate(total = rowSums(across(where(is.numeric)))) %>%
  arrange(desc(total))

message()
message("  Data source distribution:")
source_totals <- post_death_enc %>%
  count(SOURCE, name = "n") %>%
  mutate(pct = sprintf("%.1f%%", 100 * n / sum(n))) %>%
  arrange(desc(n))
for (i in seq_len(nrow(source_totals))) {
  message(glue("    {source_totals$SOURCE[i]}: {source_totals$n[i]} ({source_totals$pct[i]})"))
}

# DEATH_SOURCE distribution (which death record source feeds these strange deaths)
message()
message("  Death record source (DEATH_SOURCE) for these patients:")
death_source_totals <- strange_deaths %>%
  filter(ID %in% post_death_enc$ID) %>%
  count(DEATH_SOURCE, name = "patients") %>%
  mutate(pct = sprintf("%.1f%%", 100 * patients / sum(patients))) %>%
  arrange(desc(patients))
for (i in seq_len(nrow(death_source_totals))) {
  message(glue("    {death_source_totals$DEATH_SOURCE[i]}: {death_source_totals$patients[i]} patients ({death_source_totals$pct[i]})"))
}

message()


# ==============================================================================
# SECTION 6: STYLED XLSX OUTPUT ----
# ==============================================================================

message("--- Creating styled xlsx ---")

# Prepare detail sheet data
detail_df <- post_death_enc %>%
  select(ID, DEATH_DATE, DEATH_SOURCE, ENCOUNTERID, ADMIT_DATE,
         ENC_TYPE, SOURCE, days_after_death, gap_bucket)

wb <- wb_workbook()

# --- Sheet 1: Per-Event Detail ---
wb$add_worksheet("Per-Event Detail")

wb$add_data(
  sheet = "Per-Event Detail",
  x = "Post-Death Encounters: Source & Encounter Type",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Per-Event Detail", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Per-Event Detail", dims = "A1:I1")

subtitle <- glue("Generated: {Sys.Date()} | {nrow(detail_df)} encounters from {n_distinct(detail_df$ID)} patients with post-death activity")
wb$add_data(sheet = "Per-Event Detail", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(
  sheet = "Per-Event Detail", dims = "A2",
  name = "Calibri", size = 10, color = wb_color("FF6B7280")
)
wb$merge_cells(sheet = "Per-Event Detail", dims = "A2:I2")

wb$add_data(sheet = "Per-Event Detail", x = detail_df, start_row = 4, start_col = 1)

wb$add_fill(sheet = "Per-Event Detail", dims = "A4:I4", color = wb_color("FF374151"))
wb$add_font(
  sheet = "Per-Event Detail", dims = "A4:I4",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)
wb$add_numfmt(sheet = "Per-Event Detail", dims = "H5:H9999", numfmt = "#,##0")
wb$set_col_widths(
  sheet = "Per-Event Detail",
  cols = 1:9,
  widths = c(15, 15, 15, 22, 15, 12, 15, 16, 14)
)
wb$freeze_pane(sheet = "Per-Event Detail", firstActiveRow = 5)

# --- Sheet 2: ENC_TYPE Summary ---
wb$add_worksheet("ENC_TYPE Summary")

wb$add_data(
  sheet = "ENC_TYPE Summary",
  x = "Post-Death Encounters by Encounter Type",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "ENC_TYPE Summary", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
ncol_enc <- ncol(enc_type_summary)
last_col_enc <- LETTERS[ncol_enc]
wb$merge_cells(sheet = "ENC_TYPE Summary", dims = glue("A1:{last_col_enc}1"))

wb$add_data(sheet = "ENC_TYPE Summary", x = enc_type_summary, start_row = 4, start_col = 1)
wb$add_fill(sheet = "ENC_TYPE Summary", dims = glue("A4:{last_col_enc}4"), color = wb_color("FF374151"))
wb$add_font(
  sheet = "ENC_TYPE Summary", dims = glue("A4:{last_col_enc}4"),
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)
wb$add_numfmt(sheet = "ENC_TYPE Summary", dims = glue("B5:{last_col_enc}999"), numfmt = "#,##0")
wb$set_col_widths(sheet = "ENC_TYPE Summary", cols = 1:ncol_enc, widths = c(15, rep(14, ncol_enc - 1)))
wb$freeze_pane(sheet = "ENC_TYPE Summary", firstActiveRow = 5)

# --- Sheet 3: SOURCE Summary ---
wb$add_worksheet("SOURCE Summary")

wb$add_data(
  sheet = "SOURCE Summary",
  x = "Post-Death Encounters by Data Source",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "SOURCE Summary", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
ncol_src <- ncol(source_summary)
last_col_src <- LETTERS[ncol_src]
wb$merge_cells(sheet = "SOURCE Summary", dims = glue("A1:{last_col_src}1"))

wb$add_data(sheet = "SOURCE Summary", x = source_summary, start_row = 4, start_col = 1)
wb$add_fill(sheet = "SOURCE Summary", dims = glue("A4:{last_col_src}4"), color = wb_color("FF374151"))
wb$add_font(
  sheet = "SOURCE Summary", dims = glue("A4:{last_col_src}4"),
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)
wb$add_numfmt(sheet = "SOURCE Summary", dims = glue("B5:{last_col_src}999"), numfmt = "#,##0")
wb$set_col_widths(sheet = "SOURCE Summary", cols = 1:ncol_src, widths = c(20, rep(14, ncol_src - 1)))
wb$freeze_pane(sheet = "SOURCE Summary", firstActiveRow = 5)

# Save
wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
message(glue("  Saved: {OUTPUT_XLSX}"))
message()


# ==============================================================================
# SECTION 7: FINAL SUMMARY ----
# ==============================================================================

message("--- Summary ---")
message(glue("  Patients with strange deaths: {n_distinct(post_death_enc$ID)}"))
message(glue("  Total post-death encounters:  {nrow(post_death_enc)}"))
message(glue("  Distinct ENC_TYPEs seen:      {n_distinct(post_death_enc$ENC_TYPE)}"))
message(glue("  Distinct SOURCEs seen:         {n_distinct(post_death_enc$SOURCE)}"))
message()
message("Done.")
