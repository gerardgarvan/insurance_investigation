# ==============================================================================
# 97_validate_r60_migration.R -- Phase 97 benchmark + parity validation
# ==============================================================================
#
# Purpose:
#   Benchmarks R/60 old (dplyr) vs new (data.table) code paths side-by-side,
#   then diffs all 12 CSV outputs to prove parity. One-time script per D-02.
#
# Usage:
#   source("R/97_validate_r60_migration.R")
#
# Expected output:
#   - Timing comparison (old vs new elapsed seconds)
#   - Speedup factor
#   - [PASS]/[FAIL] for each of 12 CSV files
#
# Requirements:
#   - PERF-01: data.table by= aggregation in R/60
#   - PERF-02: CSV outputs identical pre/post optimization
#   - VALID-02: Runtime benchmark logged
#
# ==============================================================================

source("R/00_config.R")
library(dplyr)
library(data.table)
library(readr)
library(glue)
library(lubridate)

# ==============================================================================
# Section 1: Setup
# ==============================================================================

pass_count <- 0L
fail_count <- 0L

check <- function(description, condition) {
  if (isTRUE(condition)) {
    message(sprintf("[PASS] %s", description))
    pass_count <<- pass_count + 1L
  } else {
    message(sprintf("[FAIL] %s", description))
    fail_count <<- fail_count + 1L
  }
}

message("\n======================================================================")
message("Phase 97: R/60 Migration Benchmark + Parity Validation")
message("======================================================================\n")

# Create temporary output directories
dir_old <- tempfile("r60_old_")
dir_new <- tempfile("r60_new_")
dir.create(dir_old, recursive = TRUE)
dir.create(dir_new, recursive = TRUE)

message(sprintf("Old path output: %s", dir_old))
message(sprintf("New path output: %s", dir_new))

# Load encounter data once
message("\n--- Loading ENCOUNTER data ---")
enc_raw <- get_pcornet_table("ENCOUNTER") %>% materialize()

# Input validation (same as R/60 Section 1b)
assert_df_valid(
  enc_raw, "ENCOUNTER",
  required_cols = c("ID", "ENCOUNTERID", "ADMIT_DATE", "ENC_TYPE",
                    "PAYER_TYPE_PRIMARY"),
  script_name = "R/97"
)
message(sprintf("Loaded %s encounters", format(nrow(enc_raw), big.mark = ",")))

# ==============================================================================
# Section 2: OLD path benchmark (dplyr)
# ==============================================================================

message("\n=== BENCHMARK: Old path (dplyr) ===")

time_old <- system.time({

  # Classify with dplyr version
  enc_old <- enc_raw %>%
    classify_payer_tier(include_dual = TRUE, flm_override = FALSE) %>%
    mutate(admit_date_parsed = as.Date(ADMIT_DATE, format = "%Y-%m-%d"))

  enc_all_old <- enc_old
  enc_av_th_old <- enc_old %>% filter(ENC_TYPE %in% c("AV", "TH"))

  # --- OLD build_frequency_tables (dplyr version) ---
  build_frequency_tables_old <- function(enc_scope, suffix, output_dir) {
    total_enc <- nrow(enc_scope)

    # PRIMARY frequency table
    primary_freq <- enc_scope %>%
      mutate(
        code = case_when(
          is.na(PAYER_TYPE_PRIMARY) ~ "<NA>",
          PAYER_TYPE_PRIMARY == "" ~ "<EMPTY>",
          TRUE ~ PAYER_TYPE_PRIMARY
        )
      ) %>%
      count(code, name = "n") %>%
      mutate(
        amc_category = case_when(
          code %in% c("<NA>", "<EMPTY>") ~ "Missing",
          !is.na(AMC_PAYER_LOOKUP[code]) ~ unname(AMC_PAYER_LOOKUP[code]),
          substr(code, 1, 1) == "1" ~ "Medicare",
          substr(code, 1, 1) == "2" ~ "Medicaid",
          substr(code, 1, 1) %in% c("5", "6", "7") ~ "Private",
          substr(code, 1, 1) %in% c("3", "4") ~ "Other govt",
          substr(code, 1, 1) == "8" ~ "Uninsured",
          substr(code, 1, 1) == "9" ~ "Other",
          TRUE ~ "Other"
        ),
        pct = round(100 * n / total_enc, 2)
      ) %>%
      select(code, amc_category, n, pct) %>%
      arrange(desc(n))

    # SECONDARY frequency table
    secondary_freq <- enc_scope %>%
      mutate(
        code = case_when(
          is.na(PAYER_TYPE_SECONDARY) ~ "<NA>",
          PAYER_TYPE_SECONDARY == "" ~ "<EMPTY>",
          TRUE ~ PAYER_TYPE_SECONDARY
        )
      ) %>%
      count(code, name = "n") %>%
      mutate(
        amc_category = case_when(
          code %in% c("<NA>", "<EMPTY>") ~ "Missing",
          !is.na(AMC_PAYER_LOOKUP[code]) ~ unname(AMC_PAYER_LOOKUP[code]),
          substr(code, 1, 1) == "1" ~ "Medicare",
          substr(code, 1, 1) == "2" ~ "Medicaid",
          substr(code, 1, 1) %in% c("5", "6", "7") ~ "Private",
          substr(code, 1, 1) %in% c("3", "4") ~ "Other govt",
          substr(code, 1, 1) == "8" ~ "Uninsured",
          substr(code, 1, 1) == "9" ~ "Other",
          TRUE ~ "Other"
        ),
        pct = round(100 * n / total_enc, 2)
      ) %>%
      select(code, amc_category, n, pct) %>%
      arrange(desc(n))

    # Category-level summary
    primary_cat <- primary_freq %>%
      group_by(amc_category) %>%
      summarise(n = sum(n), .groups = "drop") %>%
      mutate(field = "PRIMARY", pct = round(100 * n / total_enc, 2)) %>%
      select(field, amc_category, n, pct) %>%
      arrange(desc(n))

    secondary_cat <- secondary_freq %>%
      group_by(amc_category) %>%
      summarise(n = sum(n), .groups = "drop") %>%
      mutate(field = "SECONDARY", pct = round(100 * n / total_enc, 2)) %>%
      select(field, amc_category, n, pct) %>%
      arrange(desc(n))

    category_summary <- bind_rows(primary_cat, secondary_cat)

    write_csv(primary_freq, file.path(output_dir, paste0("payer_primary_code_freq", suffix, ".csv")))
    write_csv(secondary_freq, file.path(output_dir, paste0("payer_secondary_code_freq", suffix, ".csv")))
    write_csv(category_summary, file.path(output_dir, paste0("payer_category_summary", suffix, ".csv")))
  }

  # --- OLD resolve_same_day_payer (dplyr version) ---
  resolve_same_day_payer_old <- function(enc_scope, suffix, output_dir) {
    if (sum(!is.na(enc_scope$admit_date_parsed)) == 0) {
      return(invisible(NULL))
    }

    resolved_detail <- enc_scope %>%
      filter(!is.na(admit_date_parsed)) %>%
      group_by(ID, admit_date_parsed) %>%
      summarise(
        n_encounters = n(),
        n_distinct_tiers = n_distinct(tier),
        has_flm = any(SOURCE == "FLM", na.rm = TRUE),
        has_special_code = any(PAYER_TYPE_PRIMARY %in% c("93", "14") |
          PAYER_TYPE_SECONDARY %in% c("93", "14"), na.rm = TRUE),
        original_tiers = paste(sort(unique(tier)), collapse = "+"),
        original_codes_primary = paste(sort(unique(na.omit(PAYER_TYPE_PRIMARY))), collapse = ","),
        resolved_payer = case_when(
          any(SOURCE == "FLM", na.rm = TRUE) ~ "Medicaid",
          any(PAYER_TYPE_PRIMARY %in% c("93", "14") |
            PAYER_TYPE_SECONDARY %in% c("93", "14"), na.rm = TRUE) ~ "Medicaid",
          TRUE ~ tier[which.min(tier_rank)]
        ),
        resolution_reason = case_when(
          n() == 1 ~ "single encounter",
          any(SOURCE == "FLM", na.rm = TRUE) ~ "FLM source override",
          any(PAYER_TYPE_PRIMARY %in% c("93", "14") |
            PAYER_TYPE_SECONDARY %in% c("93", "14"), na.rm = TRUE) ~ "special code override (93/14)",
          n_distinct(tier) == 1 ~ "all encounters same tier",
          TRUE ~ paste0("tier hierarchy (", n_distinct(tier), " tiers)")
        ),
        .groups = "drop"
      ) %>%
      rename(ADMIT_DATE = admit_date_parsed) %>%
      arrange(ID, ADMIT_DATE)

    write_csv(resolved_detail, file.path(output_dir, paste0("payer_resolved_detail", suffix, ".csv")))

    patient_total_dates <- resolved_detail %>%
      group_by(ID) %>%
      summarise(total_dates = n(), .groups = "drop")

    patient_summary <- resolved_detail %>%
      count(ID, resolved_payer, name = "n_dates_with_payer") %>%
      arrange(ID, desc(n_dates_with_payer), resolved_payer) %>%
      group_by(ID) %>%
      slice(1) %>%
      ungroup() %>%
      rename(modal_resolved_payer = resolved_payer) %>%
      left_join(patient_total_dates, by = "ID")

    write_csv(patient_summary, file.path(output_dir, paste0("payer_resolved_patient_summary", suffix, ".csv")))

    before_resolution <- enc_scope %>%
      filter(!is.na(admit_date_parsed)) %>%
      count(tier, name = "n_encounters_before") %>%
      arrange(match(tier, names(TIER_MAPPING)))

    after_resolution <- resolved_detail %>%
      count(resolved_payer, name = "n_patient_dates_after") %>%
      arrange(match(resolved_payer, names(TIER_MAPPING)))

    impact <- before_resolution %>%
      full_join(after_resolution, by = c("tier" = "resolved_payer")) %>%
      mutate(
        n_encounters_before = coalesce(n_encounters_before, 0L),
        n_patient_dates_after = coalesce(n_patient_dates_after, 0L),
        pct_encounters_before = round(100 * n_encounters_before / sum(n_encounters_before, na.rm = TRUE), 2),
        pct_patient_dates_after = round(100 * n_patient_dates_after / sum(n_patient_dates_after, na.rm = TRUE), 2)
      ) %>%
      rename(category = tier)

    write_csv(impact, file.path(output_dir, paste0("payer_resolved_impact", suffix, ".csv")))
  }

  # Run old path for both scopes
  build_frequency_tables_old(enc_all_old, "_all", dir_old)
  build_frequency_tables_old(enc_av_th_old, "_av_th_v2", dir_old)
  resolve_same_day_payer_old(enc_all_old, "_all", dir_old)
  resolve_same_day_payer_old(enc_av_th_old, "_av_th", dir_old)
})

message(sprintf("Old path runtime: %.2f seconds", time_old["elapsed"]))

# ==============================================================================
# Section 3: NEW path benchmark (data.table)
# ==============================================================================

message("\n=== BENCHMARK: New path (data.table) ===")

time_new <- system.time({

  # Classify with data.table version
  enc_new <- enc_raw %>%
    classify_payer_tier_dt(include_dual = TRUE, flm_override = FALSE) %>%
    mutate(admit_date_parsed = as.Date(ADMIT_DATE, format = "%Y-%m-%d"))

  enc_all_new <- enc_new
  enc_av_th_new <- enc_new %>% filter(ENC_TYPE %in% c("AV", "TH"))

  # --- NEW build_frequency_tables (data.table version) ---
  build_frequency_tables_dt <- function(enc_scope, suffix, output_dir) {
    total_enc <- nrow(enc_scope)

    # PRIMARY frequency table
    enc_dt <- copy(ensure_dt(enc_scope, name = "enc_scope", script_name = "R/97"))
    enc_dt[, code := fcase(
      is.na(PAYER_TYPE_PRIMARY), "<NA>",
      PAYER_TYPE_PRIMARY == "", "<EMPTY>",
      default = PAYER_TYPE_PRIMARY
    )]
    primary_freq_dt <- enc_dt[, .(n = .N), by = .(code)]
    amc_lookup <- get_lookup_dt("AMC_PAYER_LOOKUP")
    primary_freq_dt[amc_lookup, on = .(code), amc_category := i.payer_category]
    primary_freq_dt[code %in% c("<NA>", "<EMPTY>"), amc_category := "Missing"]
    primary_freq_dt[is.na(amc_category), amc_category := fcase(
      startsWith(code, "1"), "Medicare",
      startsWith(code, "2"), "Medicaid",
      startsWith(code, "5") | startsWith(code, "6") | startsWith(code, "7"), "Private",
      startsWith(code, "3") | startsWith(code, "4"), "Other govt",
      startsWith(code, "8"), "Uninsured",
      startsWith(code, "9"), "Other",
      default = "Other"
    )]
    primary_freq_dt[, pct := round(100 * n / total_enc, 2)]
    setorder(primary_freq_dt, -n)
    primary_freq_dt <- primary_freq_dt[, .(code, amc_category, n, pct)]
    primary_freq <- to_tibble_safe(primary_freq_dt, name = "primary_freq", script_name = "R/97")

    # SECONDARY frequency table
    enc_dt2 <- copy(ensure_dt(enc_scope, name = "enc_scope", script_name = "R/97"))
    enc_dt2[, code := fcase(
      is.na(PAYER_TYPE_SECONDARY), "<NA>",
      PAYER_TYPE_SECONDARY == "", "<EMPTY>",
      default = PAYER_TYPE_SECONDARY
    )]
    secondary_freq_dt <- enc_dt2[, .(n = .N), by = .(code)]
    secondary_freq_dt[amc_lookup, on = .(code), amc_category := i.payer_category]
    secondary_freq_dt[code %in% c("<NA>", "<EMPTY>"), amc_category := "Missing"]
    secondary_freq_dt[is.na(amc_category), amc_category := fcase(
      startsWith(code, "1"), "Medicare",
      startsWith(code, "2"), "Medicaid",
      startsWith(code, "5") | startsWith(code, "6") | startsWith(code, "7"), "Private",
      startsWith(code, "3") | startsWith(code, "4"), "Other govt",
      startsWith(code, "8"), "Uninsured",
      startsWith(code, "9"), "Other",
      default = "Other"
    )]
    secondary_freq_dt[, pct := round(100 * n / total_enc, 2)]
    setorder(secondary_freq_dt, -n)
    secondary_freq_dt <- secondary_freq_dt[, .(code, amc_category, n, pct)]
    secondary_freq <- to_tibble_safe(secondary_freq_dt, name = "secondary_freq", script_name = "R/97")

    # Category-level summary
    primary_cat_dt <- primary_freq_dt[, .(n = sum(n)), by = .(amc_category)]
    primary_cat_dt[, `:=`(field = "PRIMARY", pct = round(100 * n / total_enc, 2))]
    primary_cat_dt <- primary_cat_dt[, .(field, amc_category, n, pct)]
    setorder(primary_cat_dt, -n)

    secondary_cat_dt <- secondary_freq_dt[, .(n = sum(n)), by = .(amc_category)]
    secondary_cat_dt[, `:=`(field = "SECONDARY", pct = round(100 * n / total_enc, 2))]
    secondary_cat_dt <- secondary_cat_dt[, .(field, amc_category, n, pct)]
    setorder(secondary_cat_dt, -n)

    category_summary <- to_tibble_safe(
      rbindlist(list(primary_cat_dt, secondary_cat_dt)),
      name = "category_summary", script_name = "R/97"
    )

    write_csv(primary_freq, file.path(output_dir, paste0("payer_primary_code_freq", suffix, ".csv")))
    write_csv(secondary_freq, file.path(output_dir, paste0("payer_secondary_code_freq", suffix, ".csv")))
    write_csv(category_summary, file.path(output_dir, paste0("payer_category_summary", suffix, ".csv")))
  }

  # --- NEW resolve_same_day_payer (data.table version) ---
  resolve_same_day_payer_dt <- function(enc_scope, suffix, output_dir) {
    if (sum(!is.na(enc_scope$admit_date_parsed)) == 0) {
      return(invisible(NULL))
    }

    enc_dt <- copy(ensure_dt(enc_scope, name = "enc_scope", script_name = "R/97"))
    enc_dt <- enc_dt[!is.na(admit_date_parsed)]
    setkey(enc_dt, ID, admit_date_parsed)

    resolved_detail_dt <- enc_dt[, .(
      n_encounters = .N,
      n_distinct_tiers = length(unique(tier)),
      has_flm = any(SOURCE == "FLM", na.rm = TRUE),
      has_special_code = any(PAYER_TYPE_PRIMARY %in% c("93", "14") |
        PAYER_TYPE_SECONDARY %in% c("93", "14"), na.rm = TRUE),
      original_tiers = paste(sort(unique(tier)), collapse = "+"),
      original_codes_primary = paste(sort(unique(na.omit(PAYER_TYPE_PRIMARY))), collapse = ","),
      resolved_payer = fcase(
        any(SOURCE == "FLM", na.rm = TRUE), "Medicaid",
        any(PAYER_TYPE_PRIMARY %in% c("93", "14") |
          PAYER_TYPE_SECONDARY %in% c("93", "14"), na.rm = TRUE), "Medicaid",
        default = tier[which.min(tier_rank)]
      ),
      resolution_reason = {
        n_enc <- .N
        n_tiers <- length(unique(tier))
        fcase(
          n_enc == 1L, "single encounter",
          any(SOURCE == "FLM", na.rm = TRUE), "FLM source override",
          any(PAYER_TYPE_PRIMARY %in% c("93", "14") |
            PAYER_TYPE_SECONDARY %in% c("93", "14"), na.rm = TRUE), "special code override (93/14)",
          n_tiers == 1L, "all encounters same tier",
          default = paste0("tier hierarchy (", n_tiers, " tiers)")
        )
      }
    ), by = .(ID, admit_date_parsed)]

    setnames(resolved_detail_dt, "admit_date_parsed", "ADMIT_DATE")
    setorder(resolved_detail_dt, ID, ADMIT_DATE)
    resolved_detail <- to_tibble_safe(resolved_detail_dt, name = "resolved_detail", script_name = "R/97")

    write_csv(resolved_detail, file.path(output_dir, paste0("payer_resolved_detail", suffix, ".csv")))

    # Patient-level modal summary
    rd_dt <- copy(ensure_dt(resolved_detail, name = "resolved_detail", script_name = "R/97"))
    patient_total_dates <- rd_dt[, .(total_dates = .N), by = .(ID)]

    patient_summary_dt <- rd_dt[, .(n_dates_with_payer = .N), by = .(ID, resolved_payer)]
    setorder(patient_summary_dt, ID, -n_dates_with_payer, resolved_payer)
    patient_summary_dt <- patient_summary_dt[, .SD[1], by = .(ID)]
    setnames(patient_summary_dt, "resolved_payer", "modal_resolved_payer")
    patient_summary_dt[patient_total_dates, on = .(ID), total_dates := i.total_dates]
    patient_summary <- to_tibble_safe(patient_summary_dt, name = "patient_summary", script_name = "R/97")

    write_csv(patient_summary, file.path(output_dir, paste0("payer_resolved_patient_summary", suffix, ".csv")))

    # Before vs after impact
    enc_dt_impact <- copy(ensure_dt(enc_scope, name = "enc_scope", script_name = "R/97"))
    enc_dt_impact <- enc_dt_impact[!is.na(admit_date_parsed)]

    tier_order <- names(TIER_MAPPING)
    before_dt <- enc_dt_impact[, .(n_encounters_before = .N), by = .(tier)]
    before_dt[, tier_ord := match(tier, tier_order)]
    setorder(before_dt, tier_ord)
    before_dt[, tier_ord := NULL]

    rd_dt2 <- copy(ensure_dt(resolved_detail, name = "resolved_detail", script_name = "R/97"))
    after_dt <- rd_dt2[, .(n_patient_dates_after = .N), by = .(resolved_payer)]
    after_dt[, payer_ord := match(resolved_payer, tier_order)]
    setorder(after_dt, payer_ord)
    after_dt[, payer_ord := NULL]

    impact_dt <- merge(before_dt, after_dt, by.x = "tier", by.y = "resolved_payer", all = TRUE)
    impact_dt[is.na(n_encounters_before), n_encounters_before := 0L]
    impact_dt[is.na(n_patient_dates_after), n_patient_dates_after := 0L]
    total_before <- sum(impact_dt$n_encounters_before)
    total_after <- sum(impact_dt$n_patient_dates_after)
    impact_dt[, `:=`(
      pct_encounters_before = round(100 * n_encounters_before / total_before, 2),
      pct_patient_dates_after = round(100 * n_patient_dates_after / total_after, 2)
    )]
    setnames(impact_dt, "tier", "category")
    impact <- to_tibble_safe(impact_dt, name = "impact", script_name = "R/97")

    write_csv(impact, file.path(output_dir, paste0("payer_resolved_impact", suffix, ".csv")))
  }

  # Run new path for both scopes
  build_frequency_tables_dt(enc_all_new, "_all", dir_new)
  build_frequency_tables_dt(enc_av_th_new, "_av_th_v2", dir_new)
  resolve_same_day_payer_dt(enc_all_new, "_all", dir_new)
  resolve_same_day_payer_dt(enc_av_th_new, "_av_th", dir_new)
})

message(sprintf("New path runtime: %.2f seconds", time_new["elapsed"]))

# ==============================================================================
# Section 4: CSV parity validation
# ==============================================================================

message("\n=== CSV PARITY VALIDATION (12 files) ===\n")

csv_files <- c(
  "payer_primary_code_freq_all.csv",
  "payer_secondary_code_freq_all.csv",
  "payer_category_summary_all.csv",
  "payer_primary_code_freq_av_th_v2.csv",
  "payer_secondary_code_freq_av_th_v2.csv",
  "payer_category_summary_av_th_v2.csv",
  "payer_resolved_detail_all.csv",
  "payer_resolved_detail_av_th.csv",
  "payer_resolved_patient_summary_all.csv",
  "payer_resolved_patient_summary_av_th.csv",
  "payer_resolved_impact_all.csv",
  "payer_resolved_impact_av_th.csv"
)

for (file in csv_files) {
  old_path <- file.path(dir_old, file)
  new_path <- file.path(dir_new, file)

  # Check both files exist
  if (!file.exists(old_path)) {
    check(sprintf("File exists (old): %s", file), FALSE)
    next
  }
  if (!file.exists(new_path)) {
    check(sprintf("File exists (new): %s", file), FALSE)
    next
  }

  old_df <- vroom::vroom(old_path, show_col_types = FALSE)
  new_df <- vroom::vroom(new_path, show_col_types = FALSE)

  # Check column names match
  check(sprintf("Columns match: %s", file), identical(names(old_df), names(new_df)))

  # Check row count match
  check(sprintf("Row count match: %s (%d rows)", file, nrow(old_df)),
        nrow(old_df) == nrow(new_df))

  # Column-by-column comparison with tolerance for numeric columns
  # Per Pitfall 5: do NOT use bare identical() on whole data frame for CSVs
  # with percentage columns
  if (nrow(old_df) == nrow(new_df) && identical(names(old_df), names(new_df))) {
    all_cols_match <- TRUE
    for (col in names(old_df)) {
      old_col <- old_df[[col]]
      new_col <- new_df[[col]]

      if (is.numeric(old_col) && is.numeric(new_col)) {
        # Numeric comparison with tolerance for floating-point rounding
        col_match <- isTRUE(all.equal(old_col, new_col, tolerance = 1e-8))
      } else {
        # Character/logical/date: exact match
        col_match <- identical(old_col, new_col)
      }

      if (!col_match) {
        all_cols_match <- FALSE
        message(sprintf("  [DETAIL] Column mismatch in %s: %s", file, col))
      }
    }
    check(sprintf("CSV match: %s", file), all_cols_match)
  } else {
    check(sprintf("CSV match: %s", file), FALSE)
  }
}

# ==============================================================================
# Section 5: Benchmark summary
# ==============================================================================

message(sprintf("\n=== BENCHMARK SUMMARY ==="))
message(sprintf("Old path (dplyr):      %.2f seconds", time_old["elapsed"]))
message(sprintf("New path (data.table): %.2f seconds", time_new["elapsed"]))
speedup <- time_old["elapsed"] / time_new["elapsed"]
message(sprintf("Speedup: %.1fx", speedup))
if (speedup > 1) {
  message(sprintf("data.table is %.1fx faster", speedup))
} else {
  message("WARNING: data.table path was NOT faster (may need investigation)")
}

# ==============================================================================
# Section 6: Final summary
# ==============================================================================

message(sprintf("\n=== VALIDATION SUMMARY ==="))
message(sprintf("Total checks: %d", pass_count + fail_count))
message(sprintf("Passed: %d", pass_count))
message(sprintf("Failed: %d", fail_count))

if (fail_count == 0) {
  message("\nAll checks passed! R/60 data.table migration produces identical output.")
} else {
  message(sprintf("\nFAILURES detected: %d checks failed. Investigate mismatches above.", fail_count))
}

# Clean up temporary directories
unlink(dir_old, recursive = TRUE)
unlink(dir_new, recursive = TRUE)
message("\nTemporary directories cleaned up.")

message("\n======================================================================")
message("END OF Phase 97 Benchmark + Parity Validation")
message("======================================================================")
