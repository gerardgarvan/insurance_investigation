# R/22_multi_source_overlap_detection.R
# Multi-source encounter overlap detection across all 5 partner sites.
# Originally Phase 25; migrated to DuckDB backend in Phase 32.
#
# Detects same-date and same-week (7-day window) multi-source encounter
# pairs per site, produces per-site counts and source combination
# frequencies.
#
# This file is also the canonical TEMPLATE for new diagnostic scripts —
# it illustrates the full DuckDB-backend pattern. Sections flagged with
# [PATTERN] are the bits to copy.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
})

source("R/00_config.R")
source("R/utils_duckdb.R")     # [PATTERN] always source utils_duckdb
source("R/03_cohort_predicates.R")


# ------------------------------------------------------------------
# [PATTERN] Open connection + on.exit cleanup
# ------------------------------------------------------------------

con <- open_pcornet_con()
on.exit(close_pcornet_con(con), add = TRUE)


# ------------------------------------------------------------------
# [PATTERN] Access tables via get_pcornet_table(), NOT load_pcornet_table()
# ------------------------------------------------------------------

encounter <- get_pcornet_table("encounter", con = con)
# Under USE_DUCKDB = TRUE, this is a lazy tbl — no data in R memory yet.
# Under USE_DUCKDB = FALSE, this is a tibble (pre-migration behavior).
# Downstream dplyr verbs work identically in both cases.


# ------------------------------------------------------------------
# Same-date multi-source detection
#
# [PATTERN] Keep filtering / joining / grouping LAZY.
# The work pushes down to the database engine on the DuckDB path.
# Only materialize() at the end when you need the result in memory
# (to write CSV, pass to ggplot, etc.).
# ------------------------------------------------------------------

# Group encounters by (patient, date) and count distinct sources.
# Multi-source encounters are those with n_sources >= 2.
same_date_groups <- encounter |>
  filter(!is.na(ADMIT_DATE), !is.na(SOURCE)) |>
  group_by(PATID, ADMIT_DATE) |>
  summarise(
    n_sources    = n_distinct(SOURCE),
    n_encounters = n(),
    source_combo = paste(sort(unique(SOURCE)), collapse = "+"),
    .groups      = "drop"
  ) |>
  filter(n_sources >= 2)

# Per-site multi-source counts (one row per SITE + source_combo pair).
per_site_same_date <- same_date_groups |>
  # Explode source_combo back out to per-site rows — done in-DB via a
  # join against the encounter table rather than in-memory string split,
  # because string_split translation in dbplyr is inconsistent.
  inner_join(
    encounter |>
      select(PATID, ADMIT_DATE, SITE = SOURCE) |>
      distinct(),
    by = c("PATID", "ADMIT_DATE")
  ) |>
  group_by(SITE, source_combo) |>
  summarise(
    n_patient_dates = n_distinct(paste(PATID, ADMIT_DATE)),
    n_patients      = n_distinct(PATID),
    .groups         = "drop"
  ) |>
  arrange(SITE, desc(n_patient_dates))


# ------------------------------------------------------------------
# Same-week (7-day window) detection via self-join
#
# [PATTERN] Self-joins translate cleanly to DuckDB as long as the
# join predicate is expressible in SQL. `abs(date_a - date_b) <= 7`
# translates to `ABS(DATE_A - DATE_B) <= 7` which DuckDB handles via
# its date arithmetic (returns INTERVAL, compared against 7 days).
# ------------------------------------------------------------------

encounter_pairs_same_week <- encounter |>
  select(PATID, ENCOUNTERID, ADMIT_DATE, SOURCE) |>
  filter(!is.na(ADMIT_DATE), !is.na(SOURCE)) |>
  inner_join(
    encounter |>
      select(
        PATID,
        ENCOUNTERID_y = ENCOUNTERID,
        ADMIT_DATE_y  = ADMIT_DATE,
        SOURCE_y      = SOURCE
      ),
    by = "PATID"
  ) |>
  # SOURCE < SOURCE_y to avoid double-counting (A,B) and (B,A),
  # AND to exclude same-source self-matches
  filter(
    SOURCE < SOURCE_y,
    abs(as.integer(ADMIT_DATE - ADMIT_DATE_y)) <= 7,
    ADMIT_DATE != ADMIT_DATE_y  # exclude same-date (handled separately)
  )

per_site_same_week <- encounter_pairs_same_week |>
  group_by(SOURCE, SOURCE_y) |>
  summarise(
    n_patient_pairs = n_distinct(paste(PATID, ENCOUNTERID, ENCOUNTERID_y)),
    n_patients      = n_distinct(PATID),
    .groups         = "drop"
  ) |>
  arrange(desc(n_patient_pairs))


# ------------------------------------------------------------------
# [PATTERN] materialize() at the end — data enters R memory here
# ------------------------------------------------------------------

per_site_same_date_df <- materialize(per_site_same_date)
per_site_same_week_df <- materialize(per_site_same_week)


# ------------------------------------------------------------------
# Write outputs
# ------------------------------------------------------------------

dir.create("output/tables", showWarnings = FALSE, recursive = TRUE)

write_csv(per_site_same_date_df,
          "output/tables/per_site_same_date_overlap.csv")
write_csv(per_site_same_week_df,
          "output/tables/per_site_same_week_overlap.csv")

message(glue(
  "\n",
  "Same-date multi-source groups (per site, combo):\n",
  "  {nrow(per_site_same_date_df)} rows -> output/tables/per_site_same_date_overlap.csv\n",
  "\n",
  "Same-week (7-day) cross-source pairs (per source pair):\n",
  "  {nrow(per_site_same_week_df)} rows -> output/tables/per_site_same_week_overlap.csv"
))


# ==================================================================
# [PATTERN SUMMARY — checklist for new diagnostic scripts]
#
# [ ] source() utils_duckdb.R
# [ ] open_pcornet_con() + on.exit(close_pcornet_con(con))
# [ ] get_pcornet_table("name", con = con) instead of load_pcornet_table()
# [ ] Chain filter/join/group/summarize lazily
# [ ] materialize() as LATE as possible, right before write_csv or plot
# [ ] Parity-test the output against a baseline before committing
#
# See docs/DUCKDB_MIGRATION_GUIDE.md for the full workflow.
# ==================================================================
