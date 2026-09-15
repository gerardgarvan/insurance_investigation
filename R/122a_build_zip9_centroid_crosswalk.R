# ==============================================================================
# R/122a_build_zip9_centroid_crosswalk.R
# Phase 152, Plan 00 — one-off builder for data/reference/zip9_bg_centroid_crosswalk.csv
#
# Inputs
#   CONFIG$adi_zip9_parquet : /blue/erin.mobley-hl.bcu/ADI/out/adi_2024_zip9_all_dedup.parquet
#                             (columns zip9, bg_geoid, state, ... ; 68.6M rows; built Aug 2026)
#   CONFIG$tiger_bg_dir     : directory of TIGER/Line 2020 block-group zips tl_2020_<FIPS>_bg.zip
#                             (download with slurm/122a_fetch_tiger_bg.sh on a login node)
# Output
#   CONFIG$zip9_bg_centroid_path : ZIP9, GEOID, INTPTLAT, INTPTLON  (one row per ZIP9)
#   sibling zip9_bg_centroid_crosswalk_BUILDLOG_<date>.txt
# Run as a SLURM job (slurm/122a_build_zip9_centroid_crosswalk.sbatch); ~32 GB RAM.
# Parquet is read via DuckDB (already in renv); no extra packages required.
# ==============================================================================

suppressPackageStartupMessages({
  library(DBI);   library(duckdb); library(dplyr); library(vroom); library(stringr)
  library(glue);  library(foreign); library(tibble)
})
source("R/00_config.R")

`%||%` <- function(a, b) if (is.null(a)) b else a
ADI_PARQUET <- CONFIG$adi_zip9_parquet      %||% "/blue/erin.mobley-hl.bcu/ADI/out/adi_2024_zip9_all_dedup.parquet"
TIGER_DIR   <- CONFIG$tiger_bg_dir          %||% "/blue/erin.mobley-hl.bcu/ADI/tiger_bg"
OUT_PATH    <- CONFIG$zip9_bg_centroid_path %||% file.path("data", "reference", "zip9_bg_centroid_crosswalk.csv")
LOG_PATH    <- sub("\\.csv$", glue("_BUILDLOG_{format(Sys.Date(), '%Y%m%d')}.txt"), OUT_PATH)

log_lines <- character()
logm <- function(...) { m <- glue(...); message(m); log_lines <<- c(log_lines, as.character(m)) }

# ---- Probe gates --------------------------------------------------------------
if (!file.exists(ADI_PARQUET)) stop(glue("[R/122a] ADI ZIP9 parquet not found: {ADI_PARQUET}"))
tiger_zips <- list.files(TIGER_DIR, pattern = "^tl_2020_\\d{2}_bg\\.zip$", full.names = TRUE)
if (length(tiger_zips) == 0) stop(glue(
  "[R/122a] No TIGER block-group zips in {TIGER_DIR}. ",
  "Run slurm/122a_fetch_tiger_bg.sh on a login node first."))
logm("ADI parquet: {ADI_PARQUET}")
logm("TIGER dir:   {TIGER_DIR} ({length(tiger_zips)} state files)")
dir.create(dirname(OUT_PATH), showWarnings = FALSE, recursive = TRUE)

# ---- 1. ZIP9 -> block-group GEOID from the existing parquet -------------------
# DuckDB reads the parquet out-of-core; distinct + first-GEOID-per-ZIP9 happen in SQL.
con <- dbConnect(duckdb::duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, glue("PRAGMA threads={max(1L, as.integer(Sys.getenv('SLURM_CPUS_PER_TASK', '4')))}"))
dbExecute(con, "PRAGMA memory_limit='24GB'")
n_pairs <- dbGetQuery(con, glue("
  SELECT COUNT(*) AS n FROM (
    SELECT DISTINCT zip9, bg_geoid FROM read_parquet('{ADI_PARQUET}')
    WHERE zip9 IS NOT NULL AND bg_geoid IS NOT NULL
      AND regexp_matches(zip9, '^[0-9]{{9}}$') AND regexp_matches(bg_geoid, '^[0-9]{{12}}$'))"))$n
xw <- dbGetQuery(con, glue("
  SELECT zip9, MIN(bg_geoid) AS bg_geoid, MIN(state) AS state
  FROM read_parquet('{ADI_PARQUET}')
  WHERE zip9 IS NOT NULL AND bg_geoid IS NOT NULL
    AND regexp_matches(zip9, '^[0-9]{{9}}$') AND regexp_matches(bg_geoid, '^[0-9]{{12}}$')
  GROUP BY zip9")) %>% as_tibble()
logm("ZIP9/GEOID pairs after filters: {n_pairs}; distinct ZIP9: {nrow(xw)}; ",
     "multi-BG ZIP9 collapsed to first GEOID: {n_pairs - nrow(xw)}")
state_counts <- xw %>% count(state, name = "n_zip9") %>% arrange(state)

# ---- 2. Block-group internal points from TIGER .dbf ---------------------------
read_bg_dbf <- function(zip_path) {
  dbf_name <- grep("\\.dbf$", unzip(zip_path, list = TRUE)$Name, value = TRUE)
  td <- tempfile(); dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  unzip(zip_path, files = dbf_name, exdir = td)
  d <- foreign::read.dbf(file.path(td, dbf_name), as.is = TRUE)
  tibble(GEOID    = as.character(d$GEOID),
         INTPTLAT = as.numeric(d$INTPTLAT),   # stored as "+29.6516344"
         INTPTLON = as.numeric(d$INTPTLON))   # stored as "-082.3248262"
}
cent <- bind_rows(lapply(tiger_zips, read_bg_dbf)) %>% distinct(GEOID, .keep_all = TRUE)
logm("Block-group centroids loaded: {nrow(cent)} (states: {length(tiger_zips)})")

# ---- 3. Join, log, write -------------------------------------------------------
out <- xw %>%
  left_join(cent, by = c("bg_geoid" = "GEOID")) %>%
  transmute(ZIP9 = zip9, GEOID = bg_geoid, INTPTLAT, INTPTLON, state)

unmatched <- out %>% filter(is.na(INTPTLAT)) %>% count(state, name = "n_unmatched")
logm("ZIP9 with centroid: {sum(!is.na(out$INTPTLAT))}; without: {sum(is.na(out$INTPTLAT))}")
if (sum(is.na(out$INTPTLAT)) / nrow(out) > 0.01)
  logm("WARNING: >1% unmatched — check TIGER vintage vs Atlas block groups, or missing state zips")

vroom_write(out %>% select(ZIP9, GEOID, INTPTLAT, INTPTLON), OUT_PATH, delim = ",", na = "")
logm("Wrote {OUT_PATH} ({nrow(out)} rows)")

writeLines(c(log_lines, "", "ZIP9 count by state:",
             capture.output(print(as.data.frame(state_counts), row.names = FALSE)),
             "", "Unmatched-centroid ZIP9 by state:",
             capture.output(print(as.data.frame(unmatched), row.names = FALSE)),
             "", "States absent from Atlas (expected WV):",
             paste(setdiff(c(state.abb, "DC", "PR"), unique(xw$state)), collapse = ", ")),
           LOG_PATH)
message(glue("Build log: {LOG_PATH}"))
