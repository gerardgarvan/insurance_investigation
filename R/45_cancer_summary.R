# ==============================================================================
# 45_cancer_summary.R
# ==============================================================================
# Purpose: Patient-code level cancer summary dataset with date-based confirmation
#          metrics (date count, date span, first/last dates). All patients in
#          DIAGNOSIS with neoplasm codes included (not restricted to HL cohort).
#
# Inputs:  DIAGNOSIS DuckDB table (all coding systems via is_cancer_code())
#
# Outputs: output/tables/cancer_summary.xlsx (single "Cancer Summary" sheet)
#          output/tables/cancer_summary.csv
#
# Dependencies: R/00_config.R, R/01_load_pcornet.R, CANCER_SITE_MAP (R/00_config.R),
#               classify_codes() (R/utils/utils_cancer.R)
#
# Requirements: Per-patient per-code summary with columns:
#               - ID, cancer_code, description
#               - two_or_more_unique_dates, two_or_more_unique_dates_gt_7
#               - unique_dates_total, unique_dates_with_sep_gt_7
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")
source("R/utils/utils_cancer.R")

# SECTION 0: INPUT VALIDATION ----
# SAFE-02: Validate DIAGNOSIS table is available
assert_df_valid(
  pcornet$DIAGNOSIS, "DIAGNOSIS",
  required_cols = c("ID", "DX", "DX_TYPE", "DX_DATE"),
  script_name = "R/45"
)

OUTPUT_XLSX <- build_output_path("tables", "cancer_summary.xlsx")
OUTPUT_CSV <- build_output_path("tables", "cancer_summary.csv")

message("=== Phase 6: Cancer Summary Dataset ===")
message(glue("Output XLSX: {OUTPUT_XLSX}"))
message(glue("Output CSV:  {OUTPUT_CSV}"))

# CANCER_SITE_MAP and classify_codes() provided by R/00_config.R + R/utils/utils_cancer.R
#
# WHY date-based metrics are computed: Span between first and last diagnosis
#   indicates whether cancer was a single workup (short span) or ongoing condition
#   (long span). Date count shows diagnostic certainty (more dates = more confidence).

message(glue("Defined {length(unique(CANCER_SITE_MAP))} cancer site categories covering {length(CANCER_SITE_MAP)} prefixes"))

# ==============================================================================
# SECTION 3: LOAD AND CLASSIFY DIAGNOSIS DATA ----
# ==============================================================================
# Per D-01: All coding systems (ICD-9 + ICD-10), filtered to cancer codes via is_cancer_code()
# Per D-14: All patients in DIAGNOSIS (not restricted to HL cohort)
# Per D-08: All malignant cancer codes (ICD-10 C-codes + ICD-9 140-209)

message("\nLoading DIAGNOSIS table (all coding systems, all patients)...")

dx_all <- get_pcornet_table("DIAGNOSIS") %>%
  select(ID, DX, DX_TYPE, DX_DATE) %>%
  collect()

message(glue("  Total DIAGNOSIS rows: {format(nrow(dx_all), big.mark=',')}"))

# Normalize codes (remove dots, uppercase)
dx_all <- dx_all %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\.")))

# Filter to cancer codes using map-based detection (ICD-9 malignant 140-209 + ICD-10 C/D)
dx_cancer <- dx_all %>%
  filter(is_cancer_code(DX))

message(glue("  Cancer codes (ICD-9 + ICD-10): {format(nrow(dx_cancer), big.mark=',')} rows"))

# Classify by prefix
dx_cancer <- dx_cancer %>%
  mutate(category = classify_codes(DX_norm))

# Handle unclassified codes (label for visibility, same as R/47)
n_unclassified <- sum(is.na(dx_cancer$category))
if (n_unclassified > 0) {
  unclass_codes <- dx_cancer %>%
    filter(is.na(category)) %>%
    pull(DX_norm) %>%
    unique()
  message(glue("  WARNING: {n_unclassified} rows ({length(unclass_codes)} unique codes) unclassified"))
  message(glue("    Codes: {paste(head(unclass_codes, 20), collapse=', ')}"))
  dx_cancer <- dx_cancer %>%
    mutate(category = ifelse(is.na(category), "Unclassified", category))
}

message(glue("  Classified into {n_distinct(dx_cancer$category)} categories"))
message(glue("  Unique patients: {format(n_distinct(dx_cancer$ID), big.mark=',')}"))
message(glue("  Unique codes: {format(n_distinct(dx_cancer$DX_norm), big.mark=',')}"))

# ==============================================================================
# SECTION 4: BUILD DESCRIPTION LOOKUP ----
# ==============================================================================
# Per D-10: Description column includes both cancer site category name (from
# PREFIX_MAP) and code-level description where available.
# Multi-source cascade from R/52 pattern:
#   1. Phase 39-41 RDS artifacts (optional)
#   2. Phase 45 hardcoded radiation descriptions
#   3. R/00_config.R inline comments
#   4. Fallback: category name only

message("\nBuilding description lookup from multi-source cascade...")

# --- Source 1: Phase 39-41 RDS artifacts ---
rds_39_path <- file.path(CONFIG$output_dir, "unmatched_codes_classified.rds")
rds_40_path <- file.path(CONFIG$output_dir, "unmatched_ndc_classified.rds")

api_descriptions <- tibble(code = character(), description = character())

if (file.exists(rds_39_path)) {
  rds_39 <- readRDS(rds_39_path)
  message(glue("  Loaded Phase 39 RDS: {nrow(rds_39)} codes"))
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

# --- Source 2: Phase 45 hardcoded radiation descriptions ---
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
  "77418" = "Radiation treatment delivery, IMRT -- intensity modulated (DELETED 2015)",
  "77421" = "Stereoscopic x-ray guidance for target localization (DELETED 2015, replaced by 77387)",
  "77427" = "Radiation treatment management, weekly -- per 5 fractions",
  "77431" = "Radiation treatment management, 1-4 treatments (end-of-course)",
  "77432" = "Stereotactic radiation treatment management of cranial lesion",
  "77435" = "Stereotactic body radiation therapy (SBRT) management",
  "77470" = "Special treatment procedure (total body irradiation, hemibody irradiation)",
  "77520" = "Proton treatment delivery; simple, without compensation",
  "77522" = "Proton treatment delivery; simple, with compensation",
  "77523" = "Proton treatment delivery; intermediate",
  "77525" = "Proton treatment delivery; complex",
  # G-codes (deleted 2026; Medicare temporary codes for LINAC delivery)
  "G6003" = "Radiation treatment delivery, IMRT -- 1 or more sessions (DELETED 2026)",
  "G6004" = "Radiation treatment delivery, IMRT -- subsequent sessions (DELETED 2026)",
  "G6005" = "Radiation treatment delivery using electron beam -- simple (DELETED 2026)",
  "G6006" = "Radiation treatment delivery using electron beam -- intermediate (DELETED 2026)",
  "G6007" = "Radiation treatment delivery using electron beam -- complex (DELETED 2026)",
  "G6008" = "Radiation treatment delivery; simple, 2D (DELETED 2026)",
  "G6009" = "Radiation treatment delivery; intermediate, 2D (DELETED 2026)",
  "G6010" = "Radiation treatment delivery; complex, 2D (DELETED 2026)",
  "G6011" = "Radiation treatment delivery; simple, 3D (DELETED 2026)",
  "G6012" = "Radiation treatment delivery; intermediate, 3D (DELETED 2026)",
  "G6013" = "Radiation treatment delivery; complex, 3D (DELETED 2026)",
  "G6014" = "Radiation treatment delivery, IMRT -- simple (DELETED 2026)",
  "G6015" = "Radiation treatment delivery, IMRT -- complex (DELETED 2026)",
  "G6016" = "Radiation treatment delivery; custom blocks (DELETED 2026)"
)

hardcoded_desc_tbl <- tibble(
  code = names(hardcoded_descriptions),
  description = unname(hardcoded_descriptions)
)
message(glue("  Hardcoded descriptions: {nrow(hardcoded_desc_tbl)} codes"))

# --- Source 3: R/00_config.R inline comments ---
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

# --- Merge all description sources into desc_lookup ---
# Priority: RDS > hardcoded > config comments
desc_lookup <- bind_rows(
  api_descriptions %>% mutate(source = "api"),
  hardcoded_desc_tbl %>% mutate(source = "hardcoded"),
  config_comments %>% mutate(source = "config")
) %>%
  # Deduplicate by code, keeping first (highest priority) occurrence
  distinct(code, .keep_all = TRUE) %>%
  select(code, code_description = description)

message(glue("  Total description lookup: {nrow(desc_lookup)} unique codes"))

# ==============================================================================
# SECTION 5: PATIENT-CODE AGGREGATION ----
# ==============================================================================
# Per D-01: One row per patient per unique cancer code
# Per D-02: 7 columns in exact order
# Per D-03, D-04, D-05, D-06, D-07: Date-based confirmation metrics

message("\nAggregating to patient-code level...")

# Deduplicate first (per Pitfall 1 from research)
dx_dedup <- dx_cancer %>%
  distinct(ID, DX_norm, DX_DATE, category)

message(glue("  Deduplicated to {format(nrow(dx_dedup), big.mark=',')} unique (ID, code, date, category) tuples"))

# Group by patient-code and compute metrics
cancer_summary <- dx_dedup %>%
  group_by(ID, DX_norm, category) %>%
  summarise(
    # D-05: Count of distinct non-NA dates
    unique_dates_total = as.integer(n_distinct(DX_DATE[!is.na(DX_DATE)])),

    # D-03: 1 if 2+ distinct non-NA dates, else 0
    two_or_more_unique_dates = as.integer(n_distinct(DX_DATE[!is.na(DX_DATE)]) >= 2),

    # D-04: 1 if 2+ distinct dates AND max-min >= 7 days, else 0
    two_or_more_unique_dates_gt_7 = as.integer({
      dates <- DX_DATE[!is.na(DX_DATE)]
      ud <- unique(dates)
      if (length(ud) >= 2) {
        as.numeric(max(ud) - min(ud)) >= 7
      } else {
        FALSE
      }
    }),

    # D-06: Count of dates that are >= 7 days from at least one other date
    # Interpretation: A date "contributes to spread evidence" if it is >= 7 days
    # away from at least one other date in this patient-code set.
    # If overall span < 7 days, returns 0. Otherwise, for each unique date,
    # check if distance to any other date >= 7.
    unique_dates_with_sep_gt_7 = {
      dates <- unique(sort(DX_DATE[!is.na(DX_DATE)]))
      if (length(dates) < 2) {
        0L
      } else {
        span <- as.numeric(max(dates) - min(dates))
        if (span < 7) {
          0L
        } else {
          # For each date, check if distance to any other date >= 7
          count <- 0L
          for (d in dates) {
            diffs <- abs(as.numeric(dates - d))
            # Exclude self-comparison (diff == 0)
            if (any(diffs[diffs > 0] >= 7)) {
              count <- count + 1L
            }
          }
          count
        }
      }
    },
    .groups = "drop"
  )

message(glue("  Patient-code rows: {format(nrow(cancer_summary), big.mark=',')}"))

# D-07: Safety net -- patient-code combos with all-NA dates get 0 for all metrics
cancer_summary <- cancer_summary %>%
  mutate(
    two_or_more_unique_dates = ifelse(unique_dates_total == 0L, 0L, two_or_more_unique_dates),
    two_or_more_unique_dates_gt_7 = ifelse(unique_dates_total == 0L, 0L, two_or_more_unique_dates_gt_7),
    unique_dates_with_sep_gt_7 = ifelse(unique_dates_total == 0L, 0L, unique_dates_with_sep_gt_7)
  )

# ==============================================================================
# SECTION 6: ADD DESCRIPTION AND FINALIZE COLUMNS ----
# ==============================================================================
# Per D-10: Description = "{category} | {code_description}" or "{category}" alone
# Per D-02: Final column order: ID, cancer_code, description,
#   two_or_more_unique_dates, two_or_more_unique_dates_gt_7,
#   unique_dates_total, unique_dates_with_sep_gt_7

message("\nAdding descriptions and finalizing columns...")

cancer_summary <- cancer_summary %>%
  left_join(desc_lookup, by = c("DX_norm" = "code")) %>%
  mutate(
    description = ifelse(
      !is.na(code_description),
      paste0(category, " | ", code_description),
      category
    )
  ) %>%
  # Rename DX_norm to cancer_code, select final columns in exact order
  select(
    ID,
    cancer_code = DX_norm,
    description,
    two_or_more_unique_dates,
    two_or_more_unique_dates_gt_7,
    unique_dates_total,
    unique_dates_with_sep_gt_7
  ) %>%
  # Sort for deterministic output
  arrange(ID, cancer_code)

# Log summary stats
message(glue("\n=== SUMMARY ==="))
message(glue("  Total rows: {format(nrow(cancer_summary), big.mark=',')}"))
message(glue("  Unique patients: {format(n_distinct(cancer_summary$ID), big.mark=',')}"))
message(glue("  Unique codes: {format(n_distinct(cancer_summary$cancer_code), big.mark=',')}"))
message(glue("  Rows with 2+ dates confirmed: {format(sum(cancer_summary$two_or_more_unique_dates), big.mark=',')}"))
message(glue("  Rows with 7-day gap confirmed: {format(sum(cancer_summary$two_or_more_unique_dates_gt_7), big.mark=',')}"))

# ==============================================================================
# SECTION 7: WRITE XLSX ----
# ==============================================================================
# Per D-11: Generate from scratch using openxlsx2
# Per D-12: Single flat sheet
# Per D-18: Minimal styling (no dark header fill)

message(glue("\nWriting xlsx to {OUTPUT_XLSX}..."))

wb <- wb_workbook()
wb$add_worksheet("Cancer Summary")

# Write data with headers (col_names = TRUE writes headers automatically)
wb$add_data(
  sheet = "Cancer Summary", x = as.data.frame(cancer_summary),
  start_row = 1, col_names = TRUE
)

# Integer number format for columns 4-7 (the metric columns)
if (nrow(cancer_summary) > 0) {
  last_row <- 1 + nrow(cancer_summary)
  wb$add_numfmt(
    sheet = "Cancer Summary",
    dims = glue("D2:G{last_row}"), numfmt = "0"
  )
}

# Auto column widths
wb$set_col_widths(sheet = "Cancer Summary", cols = 1:7, widths = "auto")

# Freeze top row
wb$freeze_pane(sheet = "Cancer Summary", first_row = TRUE)

wb$save(OUTPUT_XLSX)
message(glue("Wrote {OUTPUT_XLSX} ({format(nrow(cancer_summary), big.mark=',')} data rows)"))

# ==============================================================================
# SECTION 8: WRITE CSV ----
# ==============================================================================
# Per D-13, D-16: Output CSV with same data

write.csv(cancer_summary, OUTPUT_CSV, row.names = FALSE)
message(glue("Wrote {OUTPUT_CSV}"))

# ==============================================================================
# SECTION 9: CLEANUP ----
# ==============================================================================

close_pcornet_con()
message("\n=== Phase 6 complete ===")
