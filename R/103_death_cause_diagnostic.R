# ==============================================================================
# 103_death_cause_diagnostic.R -- Cause-of-Death Signal Inventory (Phase 119)
# ==============================================================================
# Purpose:     READ-ONLY diagnostic that determines WHERE a populated
#              cause-of-death signal lives for the deceased patient set
#              (patients with a valid DEATH_DATE). Phase 118's R/102 produced
#              an all-blank cause_of_death_is_nhl column because it read a
#              DEATH_CAUSE field that does not exist inside the DEATH table.
#
#              This is the Wave 0 GATE for Phase 119. RESEARCH confirmed the
#              PCORnet CDM keeps cause of death in a SEPARATE DEATH_CAUSE table
#              (ID, DEATH_CAUSE, DEATH_CAUSE_CODE, DEATH_CAUSE_TYPE, ...), and
#              that the TUMOR_REGISTRY tables carry NAACCR cause fields
#              (TR1.CAUSE_OF_DEATH #1910, TR2/TR3.DCAUSE #1910). The population
#              of each of these is UNKNOWN until this script runs on HiPerGator.
#
#              This script inventories every candidate source restricted to the
#              deceased PATID set, classifies each with classify_codes(), and
#              prints a single RECOMMENDATION line telling the user which source
#              Wave 2's R/102 rewrite should read. It does NOT modify any
#              pipeline output; it writes ONE small diagnostic CSV.
#
# Inputs:      DuckDB DEATH table (deceased-set derivation)
#              DuckDB DEATH_CAUSE table (NULL until Plan 02 loads it)
#              DuckDB TUMOR_REGISTRY_ALL view (TR1/TR2/TR3 union)
#              CSV probe: DEATH_CAUSE_Mailhot_V1.csv in CONFIG$data_dir
#
# Outputs:     output/diagnostics/death_cause_source_inventory.csv
#                Columns: source_name, column, n_nonnull, deceased_coverage, n_nhl
#                One row per candidate cause-of-death source.
#              (Console) per-source non-null / coverage / NHL-classify report
#              plus a single-line recommendation.
#
# Dependencies: R/00_config.R (auto-sources utils_duckdb, utils_dates,
#               utils_cancer; provides CONFIG$data_dir, CONFIG$output_dir)
#               R/utils/utils_duckdb.R  (open_pcornet_con, get_pcornet_table,
#                                        TUMOR_REGISTRY_ALL view, close_pcornet_con)
#               R/utils/utils_dates.R   (parse_pcornet_date)
#               R/utils/utils_cancer.R  (classify_codes)
#               tidyverse ecosystem: dplyr, glue, stringr, lubridate
#
# Requirements: Phase 119 -- NHLFIX-01 (investigation gate)
#
# Usage:       Rscript R/103_death_cause_diagnostic.R
#              source("R/103_death_cause_diagnostic.R")
#
# Note:        READ-ONLY investigation. Structural-only verification on Windows
#              (no data). Full run with counts + recommendation is HiPerGator
#              only (requires DuckDB PCORnet data). This script must NOT touch
#              R/102, R/00_config, or the real death-cause NHL flag output.
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND LIBRARIES ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(lubridate)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")

# utils_cancer is auto-sourced by R/00_config; source defensively if classify_codes
# is not on the search path (e.g. a partial/standalone source of this file).
if (!exists("classify_codes")) {
  source("R/utils/utils_cancer.R")
}

message("=== Phase 119 Diagnostic: Cause-of-Death Signal Inventory ===\n")


# ==============================================================================
# SECTION 2: CONSTANTS ----
# ==============================================================================

NHL_CATEGORY <- "Non-Hodgkin Lymphoma"  # exact classify_codes() label (D-06)

# NAACCR item #1910 cause-of-death sentinels to EXCLUDE before classify_codes():
#   0000 = patient alive, 7777 = cert unavailable, 7797 = cert available but uncoded
NAACCR_DEATH_SENTINELS <- c("0000", "7777", "7797")

OUTPUT_CSV <- file.path(CONFIG$output_dir, "diagnostics",
                        "death_cause_source_inventory.csv")
dir.create(dirname(OUTPUT_CSV), recursive = TRUE, showWarnings = FALSE)

message(glue("Inventory artifact target: {OUTPUT_CSV}\n"))


# ==============================================================================
# SECTION 3: SELF-BOOTSTRAP DUCKDB ----
# ==============================================================================

# Self-bootstrap the DuckDB connection so R/103 runs standalone in a fresh
# session (consistent with sibling scripts R/27-R/36, R/102). open_pcornet_con()
# is idempotent — it closes any existing connection first.
USE_DUCKDB <- TRUE
if (!exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}


# ==============================================================================
# SECTION 4: DECEASED PATID SET (reuse R/102 derivation) ----
# ==============================================================================

# Reuse R/102 Section 4 derivation verbatim: parse DEATH_DATE, coerce the 1900
# sentinel to NA, drop patients with no valid death date. This is the set every
# candidate source is restricted to.
message("--- Deriving deceased patient set from DEATH table ---")

deceased_ids <- get_pcornet_table("DEATH") %>%
  collect() %>%
  mutate(DEATH_DATE = parse_pcornet_date(DEATH_DATE)) %>%
  mutate(DEATH_DATE = if_else(year(DEATH_DATE) == 1900L, as.Date(NA), DEATH_DATE)) %>%
  filter(!is.na(DEATH_DATE)) %>%
  pull(ID) %>%
  unique()

n_deceased <- length(deceased_ids)
message(glue("Deceased patient set (valid DEATH_DATE): {n_deceased}\n"))


# ==============================================================================
# SECTION 5: SOURCE 1 -- DEATH_CAUSE TABLE ----
# ==============================================================================

message("--- Source 1: DEATH_CAUSE table ---")

# Probe the raw CSV first (does not assume PCORNET_PATHS has DEATH_CAUSE yet;
# that entry is only added by Plan 02). Then probe DuckDB.
dc_path <- file.path(CONFIG$data_dir, "DEATH_CAUSE_Mailhot_V1.csv")
message(glue("  CSV exists at {dc_path}? {file.exists(dc_path)}"))

dc_tbl <- get_pcornet_table("DEATH_CAUSE")  # NULL if not yet loaded into DuckDB

# Source-1 inventory values (NA until proven otherwise)
s1_nonnull  <- NA_integer_
s1_coverage <- NA_integer_
s1_nhl      <- NA_integer_

if (is.null(dc_tbl)) {
  message("  DEATH_CAUSE table NOT in DuckDB (expected before Plan 02 loads it).")
  message("  Source-1 counts set to NA.\n")
} else {
  dc <- dc_tbl %>% collect()

  n_dc_rows <- nrow(dc)
  message(glue("  Row count: {n_dc_rows}"))

  # Non-null DEATH_CAUSE
  dc_nonmissing <- !is.na(dc$DEATH_CAUSE) & trimws(dc$DEATH_CAUSE) != ""
  s1_nonnull <- sum(dc_nonmissing)
  pct_nonnull <- if (n_dc_rows > 0) round(100 * s1_nonnull / n_dc_rows, 1) else 0
  message(glue("  Non-null DEATH_CAUSE: {s1_nonnull} ({pct_nonnull}%)"))

  # DEATH_CAUSE_TYPE distribution
  if ("DEATH_CAUSE_TYPE" %in% names(dc)) {
    type_dist <- dc %>% count(DEATH_CAUSE_TYPE)
    message("  DEATH_CAUSE_TYPE distribution:")
    for (i in seq_len(nrow(type_dist))) {
      message(glue("    {type_dist$DEATH_CAUSE_TYPE[i]}: {type_dist$n[i]}"))
    }
    n_underlying <- sum(dc$DEATH_CAUSE_TYPE == "U", na.rm = TRUE)
    message(glue("  Rows with DEATH_CAUSE_TYPE == \"U\" (underlying): {n_underlying}"))
  } else {
    message("  DEATH_CAUSE_TYPE column not present.")
  }

  # Deceased-set coverage
  s1_coverage <- n_distinct(intersect(dc$ID, deceased_ids))
  message(glue("  Deceased-set coverage: {s1_coverage} / {n_deceased}"))

  # Sample non-null values
  sample_vals <- head(dc$DEATH_CAUSE[dc_nonmissing], 10)
  message(glue("  Sample DEATH_CAUSE values (first 10): {paste(sample_vals, collapse = ', ')}"))

  # Classify on the underlying-cause-preferred one-per-ID set.
  # Prefer DEATH_CAUSE_TYPE == "U"; fall back to first available cause per ID.
  if ("DEATH_CAUSE_TYPE" %in% names(dc)) {
    dc_one <- dc %>%
      filter(dc_nonmissing) %>%
      filter(!DEATH_CAUSE %in% NAACCR_DEATH_SENTINELS) %>%
      arrange(ID, DEATH_CAUSE_TYPE != "U") %>%
      group_by(ID) %>%
      summarise(DEATH_CAUSE = first(DEATH_CAUSE), .groups = "drop")
  } else {
    dc_one <- dc %>%
      filter(dc_nonmissing) %>%
      filter(!DEATH_CAUSE %in% NAACCR_DEATH_SENTINELS) %>%
      group_by(ID) %>%
      summarise(DEATH_CAUSE = first(DEATH_CAUSE), .groups = "drop")
  }

  if (nrow(dc_one) > 0) {
    dc_one <- dc_one %>%
      mutate(cause_category = classify_codes(DEATH_CAUSE))
    s1_nhl        <- sum(dc_one$cause_category == NHL_CATEGORY, na.rm = TRUE)
    s1_non_nhl    <- sum(!is.na(dc_one$cause_category) &
                           dc_one$cause_category != NHL_CATEGORY)
    s1_unclass    <- sum(is.na(dc_one$cause_category))
    message(glue("  classify_codes() -> NHL: {s1_nhl}"))
    message(glue("  classify_codes() -> non-NHL: {s1_non_nhl}"))
    message(glue("  classify_codes() -> NA/unclassified: {s1_unclass}"))
  } else {
    s1_nhl <- 0L
    message("  No classifiable (non-sentinel) DEATH_CAUSE rows.")
  }
  message("")
}


# ==============================================================================
# SECTION 6: SOURCES 2 & 3 -- TUMOR_REGISTRY CAUSE FIELDS ----
# ==============================================================================

message("--- Sources 2 & 3: TUMOR_REGISTRY cause-of-death fields ---")

tr <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>% collect()

# Pitfall 5: UNION ALL BY NAME keeps BOTH CAUSE_OF_DEATH (TR1) and DCAUSE
# (TR2/TR3) with NULLs where a table lacks the column. Guard conditionally.
has_cod    <- "CAUSE_OF_DEATH" %in% names(tr)
has_dcause <- "DCAUSE" %in% names(tr)
message(glue("  CAUSE_OF_DEATH column present? {has_cod}"))
message(glue("  DCAUSE column present? {has_dcause}"))

# Add a unified cause_code (CAUSE_OF_DEATH preferred, DCAUSE fallback)
tr <- tr %>%
  mutate(cause_code = coalesce(
    if (has_cod) CAUSE_OF_DEATH else NA_character_,
    if (has_dcause) DCAUSE else NA_character_
  ))

# --- Helper: report a single TR column and return inventory numbers ----------
report_tr_column <- function(tr_df, colname, id_col = "ID") {
  if (!colname %in% names(tr_df)) {
    message(glue("  {colname}: column not present -- skipping."))
    return(list(nonnull = NA_integer_, coverage = NA_integer_, nhl = NA_integer_))
  }
  vals <- tr_df[[colname]]
  ids  <- tr_df[[id_col]]

  nonmissing <- !is.na(vals) & trimws(vals) != ""
  n_nonnull  <- sum(nonmissing)
  message(glue("  {colname} non-null: {n_nonnull}"))

  # Deceased-set coverage (only among non-null cause rows)
  coverage <- n_distinct(intersect(ids[nonmissing], deceased_ids))
  message(glue("  {colname} deceased-set coverage: {coverage} / {n_deceased}"))

  sample_vals <- head(vals[nonmissing], 10)
  message(glue("  {colname} sample values (first 10): {paste(sample_vals, collapse = ', ')}"))

  # Filter NAACCR sentinels + blanks, then classify
  usable <- nonmissing & !vals %in% NAACCR_DEATH_SENTINELS
  if (any(usable)) {
    cats <- classify_codes(vals[usable])
    n_nhl <- sum(cats == NHL_CATEGORY, na.rm = TRUE)
  } else {
    n_nhl <- 0L
  }
  message(glue("  {colname} classify_codes() NHL matches: {n_nhl}"))
  message("")

  list(nonnull = n_nonnull, coverage = coverage, nhl = n_nhl)
}

s2 <- report_tr_column(tr, "CAUSE_OF_DEATH")
s3 <- report_tr_column(tr, "DCAUSE")


# ==============================================================================
# SECTION 7: COVERAGE SUMMARY + RECOMMENDATION ----
# ==============================================================================

message("--- Coverage Summary ---")
message(glue("  Source 1 (DEATH_CAUSE):        covers {s1_coverage} of {n_deceased} deceased"))
message(glue("  Source 2 (TR1.CAUSE_OF_DEATH): covers {s2$coverage} of {n_deceased} deceased"))
message(glue("  Source 3 (TR2/3.DCAUSE):       covers {s3$coverage} of {n_deceased} deceased"))

# Coverage helper: treat NA (source absent) as 0 for the decision.
cov_or_zero <- function(x) if (is.na(x)) 0L else x
s1_cov <- cov_or_zero(s1_coverage)
s2_cov <- cov_or_zero(s2$coverage)
s3_cov <- cov_or_zero(s3$coverage)

message("\n--- Recommendation ---")
if (s1_cov > 0) {
  recommendation <- "[PROCEED WITH SOURCE 1: DEATH_CAUSE table]"
} else if (s2_cov > 0 || s3_cov > 0) {
  recommendation <- "[FALLBACK TO TUMOR_REGISTRY SOURCE]"
} else {
  recommendation <- "[PROXY BACKSTOP REQUIRED -- no coded cause found for deceased set]"
}
message(glue("  {recommendation}\n"))


# ==============================================================================
# SECTION 8: WRITE INVENTORY ARTIFACT ----
# ==============================================================================

# One row per candidate source. na="" renders NA (source absent / not loaded)
# as a blank cell. This is the SMALL diagnostic artifact the user pastes back;
# it is NOT the real pipeline output (the death-cause NHL flag CSV produced by
# R/102), which this script must never touch.
inventory <- tibble::tibble(
  source_name = c("DEATH_CAUSE", "TUMOR_REGISTRY1", "TUMOR_REGISTRY2_3"),
  column      = c("DEATH_CAUSE", "CAUSE_OF_DEATH", "DCAUSE"),
  n_nonnull   = c(s1_nonnull, s2$nonnull, s3$nonnull),
  deceased_coverage = c(s1_coverage, s2$coverage, s3$coverage),
  n_nhl       = c(s1_nhl, s2$nhl, s3$nhl)
)

write.csv(inventory, OUTPUT_CSV, row.names = FALSE, na = "")

close_pcornet_con()

message(glue("Wrote inventory: {OUTPUT_CSV}"))
message("\nDone. (Phase 119 -- NHLFIX-01 investigation gate)")
