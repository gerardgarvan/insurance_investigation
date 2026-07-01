# ==============================================================================
# 52_strange_death_source_and_enc_type.R -- Source & Encounter Type for Strange Deaths
# ==============================================================================
#
# Purpose:
#   Compare ALL deceased patients against the "strange deaths" subset to reveal
#   whether certain DEATH_SOURCE values or encounter types are over-represented
#   among patients with post-death clinical activity.
#
# Definitions:
#   - "All deaths": Patients in validated_death_dates.rds with death_valid == TRUE
#   - "Strange deaths": Subset of all deaths where post_death_activity == TRUE,
#     meaning they have encounters, diagnoses, or treatments recorded AFTER their
#     death date. (~200 patients flagged by R/53 Section 5)
#   - DEATH_SOURCE: PCORnet CDM field on the DEATH table indicating where the
#     death record originated (e.g., death certificates, Social Security Death
#     Master File, EHR, tumor registry). Raw values from the extract, no mapping
#     applied.
#
# Inputs:
#   - cache/outputs/validated_death_dates.rds (from R/53)
#   - DuckDB ENCOUNTER table (ENC_TYPE, SOURCE, ADMIT_DATE)
#
# Outputs:
#   - output/strange_death_source_enc_type.xlsx (four sheets)
#     Sheet 1: "DEATH_SOURCE Comparison" -- all deaths vs strange deaths by DEATH_SOURCE
#     Sheet 2: "ENC_TYPE Comparison" -- all deaths encounters vs strange post-death encounters
#     Sheet 3: "SOURCE Comparison" -- all deaths encounters vs strange post-death encounters
#     Sheet 4: "Post-Death Detail" -- one row per post-death encounter for strange deaths
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
# SECTION 3: LOAD AND SPLIT DEATHS ----
# ==============================================================================

message("--- Loading death records ---")

validated_deaths <- readRDS(DEATH_RDS)
message(glue("  Total validated death records: {nrow(validated_deaths)}"))

all_deaths <- validated_deaths %>%
  filter(death_valid == TRUE)

strange_deaths <- all_deaths %>%
  filter(post_death_activity == TRUE)

message(glue("  All valid deaths:   {nrow(all_deaths)}"))
message(glue("  Strange deaths:     {nrow(strange_deaths)} ({sprintf('%.1f%%', 100 * nrow(strange_deaths) / nrow(all_deaths))} of all valid deaths)"))
message(glue("  Non-strange deaths: {nrow(all_deaths) - nrow(strange_deaths)}"))
message()


# ==============================================================================
# SECTION 4: QUERY ENCOUNTERS FOR ALL DECEASED PATIENTS ----
# ==============================================================================

message("--- Querying encounters for all deceased patients ---")

open_pcornet_con()

# Pull encounters for ALL valid deaths (not just strange ones)
all_death_enc <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ENCOUNTERID, ADMIT_DATE, ENC_TYPE, SOURCE) %>%
  collect() %>%
  mutate(ADMIT_DATE = parse_pcornet_date(ADMIT_DATE)) %>%
  filter(!is.na(ADMIT_DATE)) %>%
  inner_join(all_deaths %>% select(ID, DEATH_DATE, DEATH_SOURCE), by = "ID")

close_pcornet_con()

message(glue("  Total encounters for all deceased patients: {nrow(all_death_enc)}"))
message(glue("  Patients with at least one encounter: {n_distinct(all_death_enc$ID)}"))

# Tag encounters as pre-death or post-death
all_death_enc <- all_death_enc %>%
  mutate(
    is_post_death = ADMIT_DATE > DEATH_DATE,
    is_strange = ID %in% strange_deaths$ID,
    days_after_death = if_else(is_post_death, as.numeric(ADMIT_DATE - DEATH_DATE), NA_real_),
    gap_bucket = case_when(
      !is_post_death ~ NA_character_,
      days_after_death <= 30 ~ "0-30 days",
      days_after_death <= 90 ~ "31-90 days",
      days_after_death <= 365 ~ "91-365 days",
      days_after_death > 365 ~ ">1 year"
    )
  )

# Post-death encounters (strange deaths only)
post_death_enc <- all_death_enc %>%
  filter(is_post_death, is_strange)

message(glue("  Post-death encounters (strange deaths): {nrow(post_death_enc)} events from {n_distinct(post_death_enc$ID)} patients"))
message()


# ==============================================================================
# SECTION 5: COMPARISON TABLES ----
# ==============================================================================

message("--- Building comparison tables ---")

# ----- 5A: DEATH_SOURCE comparison (patient-level) -----

all_death_source <- all_deaths %>%
  count(DEATH_SOURCE, name = "all_deaths") %>%
  mutate(all_deaths_pct = sprintf("%.1f%%", 100 * all_deaths / sum(all_deaths)))

strange_death_source <- strange_deaths %>%
  count(DEATH_SOURCE, name = "strange_deaths") %>%
  mutate(strange_deaths_pct = sprintf("%.1f%%", 100 * strange_deaths / sum(strange_deaths)))

death_source_comparison <- all_death_source %>%
  full_join(strange_death_source, by = "DEATH_SOURCE") %>%
  mutate(
    all_deaths = if_else(is.na(all_deaths), 0L, all_deaths),
    strange_deaths = if_else(is.na(strange_deaths), 0L, strange_deaths),
    all_deaths_pct = if_else(is.na(all_deaths_pct), "0.0%", all_deaths_pct),
    strange_deaths_pct = if_else(is.na(strange_deaths_pct), "0.0%", strange_deaths_pct),
    strange_rate = sprintf("%.1f%%", 100 * strange_deaths / all_deaths)
  ) %>%
  arrange(desc(all_deaths))

message("  DEATH_SOURCE comparison (patient-level):")
for (i in seq_len(nrow(death_source_comparison))) {
  r <- death_source_comparison[i, ]
  message(glue("    {r$DEATH_SOURCE}: all={r$all_deaths} ({r$all_deaths_pct}), strange={r$strange_deaths} ({r$strange_deaths_pct}), strange rate={r$strange_rate}"))
}

# ----- 5B: ENC_TYPE comparison (encounter-level) -----

# All encounters for all deceased patients
all_enc_type <- all_death_enc %>%
  count(ENC_TYPE, name = "all_deaths_enc") %>%
  mutate(all_deaths_enc_pct = sprintf("%.1f%%", 100 * all_deaths_enc / sum(all_deaths_enc)))

# Post-death encounters for strange deaths
strange_enc_type <- post_death_enc %>%
  count(ENC_TYPE, name = "post_death_enc") %>%
  mutate(post_death_enc_pct = sprintf("%.1f%%", 100 * post_death_enc / sum(post_death_enc)))

enc_type_comparison <- all_enc_type %>%
  full_join(strange_enc_type, by = "ENC_TYPE") %>%
  mutate(
    all_deaths_enc = if_else(is.na(all_deaths_enc), 0L, all_deaths_enc),
    post_death_enc = if_else(is.na(post_death_enc), 0L, post_death_enc),
    all_deaths_enc_pct = if_else(is.na(all_deaths_enc_pct), "0.0%", all_deaths_enc_pct),
    post_death_enc_pct = if_else(is.na(post_death_enc_pct), "0.0%", post_death_enc_pct)
  ) %>%
  arrange(desc(all_deaths_enc))

message()
message("  ENC_TYPE comparison (all encounters vs post-death encounters):")
for (i in seq_len(nrow(enc_type_comparison))) {
  r <- enc_type_comparison[i, ]
  message(glue("    {r$ENC_TYPE}: all={r$all_deaths_enc} ({r$all_deaths_enc_pct}), post-death={r$post_death_enc} ({r$post_death_enc_pct})"))
}

# ----- 5C: SOURCE comparison (encounter-level) -----

all_source <- all_death_enc %>%
  count(SOURCE, name = "all_deaths_enc") %>%
  mutate(all_deaths_enc_pct = sprintf("%.1f%%", 100 * all_deaths_enc / sum(all_deaths_enc)))

strange_source <- post_death_enc %>%
  count(SOURCE, name = "post_death_enc") %>%
  mutate(post_death_enc_pct = sprintf("%.1f%%", 100 * post_death_enc / sum(post_death_enc)))

source_comparison <- all_source %>%
  full_join(strange_source, by = "SOURCE") %>%
  mutate(
    all_deaths_enc = if_else(is.na(all_deaths_enc), 0L, all_deaths_enc),
    post_death_enc = if_else(is.na(post_death_enc), 0L, post_death_enc),
    all_deaths_enc_pct = if_else(is.na(all_deaths_enc_pct), "0.0%", all_deaths_enc_pct),
    post_death_enc_pct = if_else(is.na(post_death_enc_pct), "0.0%", post_death_enc_pct)
  ) %>%
  arrange(desc(all_deaths_enc))

message()
message("  SOURCE comparison (all encounters vs post-death encounters):")
for (i in seq_len(nrow(source_comparison))) {
  r <- source_comparison[i, ]
  message(glue("    {r$SOURCE}: all={r$all_deaths_enc} ({r$all_deaths_enc_pct}), post-death={r$post_death_enc} ({r$post_death_enc_pct})"))
}

message()


# ==============================================================================
# SECTION 6: STYLED XLSX OUTPUT ----
# ==============================================================================

message("--- Creating styled xlsx ---")

wb <- wb_workbook()

# Helper: add a styled comparison sheet
add_comparison_sheet <- function(wb, sheet_name, title, subtitle_text, df) {
  wb$add_worksheet(sheet_name)

  # Title
  wb$add_data(sheet = sheet_name, x = title, start_row = 1, start_col = 1)
  wb$add_font(
    sheet = sheet_name, dims = "A1",
    name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
  )
  nc <- ncol(df)
  last_col <- LETTERS[nc]
  wb$merge_cells(sheet = sheet_name, dims = glue("A1:{last_col}1"))

  # Subtitle
  wb$add_data(sheet = sheet_name, x = subtitle_text, start_row = 2, start_col = 1)
  wb$add_font(
    sheet = sheet_name, dims = "A2",
    name = "Calibri", size = 10, color = wb_color("FF6B7280")
  )
  wb$merge_cells(sheet = sheet_name, dims = glue("A2:{last_col}2"))

  # Data at row 4
  wb$add_data(sheet = sheet_name, x = df, start_row = 4, start_col = 1)

  # Header styling
  wb$add_fill(sheet = sheet_name, dims = glue("A4:{last_col}4"), color = wb_color("FF374151"))
  wb$add_font(
    sheet = sheet_name, dims = glue("A4:{last_col}4"),
    name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
  )

  # Column widths
  wb$set_col_widths(sheet = sheet_name, cols = 1:nc, widths = c(20, rep(18, nc - 1)))

  # Freeze below header
  wb$freeze_pane(sheet = sheet_name, firstActiveRow = 5)

  invisible(wb)
}

# --- Sheet 1: DEATH_SOURCE Comparison ---
add_comparison_sheet(
  wb, "DEATH_SOURCE Comparison",
  "DEATH_SOURCE: All Deaths vs Strange Deaths (Patient-Level)",
  glue("Generated: {Sys.Date()} | All valid deaths: {nrow(all_deaths)}, Strange deaths: {nrow(strange_deaths)} | strange_rate = % of that DEATH_SOURCE's patients who are strange"),
  death_source_comparison
)

# --- Sheet 2: ENC_TYPE Comparison ---
add_comparison_sheet(
  wb, "ENC_TYPE Comparison",
  "ENC_TYPE: All Deaths Encounters vs Strange Post-Death Encounters",
  glue("Generated: {Sys.Date()} | All deaths encounters: {nrow(all_death_enc)}, Post-death encounters (strange): {nrow(post_death_enc)}"),
  enc_type_comparison
)

# --- Sheet 3: SOURCE Comparison ---
add_comparison_sheet(
  wb, "SOURCE Comparison",
  "SOURCE: All Deaths Encounters vs Strange Post-Death Encounters",
  glue("Generated: {Sys.Date()} | All deaths encounters: {nrow(all_death_enc)}, Post-death encounters (strange): {nrow(post_death_enc)}"),
  source_comparison
)

# --- Sheet 4: Post-Death Detail ---
detail_df <- post_death_enc %>%
  select(ID, DEATH_DATE, DEATH_SOURCE, ENCOUNTERID, ADMIT_DATE,
         ENC_TYPE, SOURCE, days_after_death, gap_bucket) %>%
  arrange(ID, days_after_death)

wb$add_worksheet("Post-Death Detail")

wb$add_data(
  sheet = "Post-Death Detail",
  x = "Post-Death Encounters: Per-Event Detail (Strange Deaths Only)",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Post-Death Detail", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Post-Death Detail", dims = "A1:I1")

subtitle <- glue("Generated: {Sys.Date()} | {nrow(detail_df)} encounters from {n_distinct(detail_df$ID)} patients with post-death activity")
wb$add_data(sheet = "Post-Death Detail", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(
  sheet = "Post-Death Detail", dims = "A2",
  name = "Calibri", size = 10, color = wb_color("FF6B7280")
)
wb$merge_cells(sheet = "Post-Death Detail", dims = "A2:I2")

wb$add_data(sheet = "Post-Death Detail", x = detail_df, start_row = 4, start_col = 1)

wb$add_fill(sheet = "Post-Death Detail", dims = "A4:I4", color = wb_color("FF374151"))
wb$add_font(
  sheet = "Post-Death Detail", dims = "A4:I4",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)
wb$add_numfmt(sheet = "Post-Death Detail", dims = "H5:H9999", numfmt = "#,##0")
wb$set_col_widths(
  sheet = "Post-Death Detail",
  cols = 1:9,
  widths = c(15, 15, 15, 22, 15, 12, 15, 16, 14)
)
wb$freeze_pane(sheet = "Post-Death Detail", firstActiveRow = 5)

# Save
wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
message(glue("  Saved: {OUTPUT_XLSX}"))
message()


# ==============================================================================
# SECTION 7: FINAL SUMMARY ----
# ==============================================================================

message("--- Summary ---")
message(glue("  All valid deaths:             {nrow(all_deaths)}"))
message(glue("  Strange deaths:               {nrow(strange_deaths)}"))
message(glue("  Strange rate:                 {sprintf('%.1f%%', 100 * nrow(strange_deaths) / nrow(all_deaths))}"))
message(glue("  Post-death encounters:        {nrow(post_death_enc)}"))
message(glue("  Distinct DEATH_SOURCEs:       {n_distinct(all_deaths$DEATH_SOURCE)}"))
message(glue("  Distinct ENC_TYPEs:           {n_distinct(all_death_enc$ENC_TYPE)}"))
message(glue("  Distinct SOURCEs:             {n_distinct(all_death_enc$SOURCE)}"))
message()
message("Done.")
