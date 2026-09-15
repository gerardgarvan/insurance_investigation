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
#   CONFIG$zip9_bg_centroid_path : ZIP9, GEOID, INTPTLAT, INTPTLON, N_BG  (one row per ZIP9)
#     N_BG = number of distinct block groups the Atlas maps this ZIP9 to. When N_BG > 1 the
#     row carries the lowest GEOID (deterministic, documented); consumers may filter N_BG == 1.
#   sibling zip9_bg_centroid_crosswalk_BUILDLOG_<date>.txt
# Run as a SLURM job (slurm/122a_build_zip9_centroid_crosswalk.sbatch); ~32 GB RAM.
# Parquet read, dedup, join and CSV write all happen inside DuckDB (already in renv);
# no extra packages required and the 68M-row table never enters R memory.
# ==============================================================================

suppressPackageStartupMessages({
  library(DBI);   library(duckdb); library(dplyr); library(stringr)
  library(glue);  library(foreign); library(tibble)
})
source("R/00_config.R")

`%||%` <- function(a, b) if (is.null(a)) b else a
ADI_PARQUET <- CONFIG$adi_zip9_parquet      %||% "/blue/erin.mobley-hl.bcu/ADI/out/adi_2024_zip9_all_dedup.parquet"
TIGER_DIR   <- CONFIG$tiger_bg_dir          %||% "/blue/erin.mobley-hl.bcu/ADI/tiger_bg"
OUT_PATH    <- CONFIG$zip9_bg_centroid_path %||% file.path("data", "reference", "zip9_bg_centroid_crosswalk.csv")
LOG_PATH    <- sub("\\.csv$", glue("_BUILDLOG_{format(Sys.Date(), '%Y%m%d')}.txt"), OUT_PATH)
sql_str     <- function(x) gsub("'", "''", x, fixed = TRUE)   # escape for single-quoted SQL literals

log_lines <- character()
logm <- function(..., .envir = parent.frame()) {   # evaluate {vars} in the caller, not in logm
  m <- glue(..., .envir = .envir); message(m); log_lines <<- c(log_lines, as.character(m))
}

# ---- Probe gates --------------------------------------------------------------
if (!file.exists(ADI_PARQUET)) stop(glue("[R/122a] ADI ZIP9 parquet not found: {ADI_PARQUET}"))
tiger_zips <- list.files(TIGER_DIR, pattern = "^tl_2020_\\d{2}_bg\\.zip$", full.names = TRUE)
if (length(tiger_zips) == 0) stop(glue(
  "[R/122a] No TIGER block-group zips in {TIGER_DIR}. ",
  "Run slurm/122a_fetch_tiger_bg.sh on a login node first."))
logm("ADI parquet: {ADI_PARQUET}")
logm("TIGER dir:   {TIGER_DIR} ({length(tiger_zips)} state files)")
dir.create(dirname(OUT_PATH), showWarnings = FALSE, recursive = TRUE)

# ---- 1. Block-group internal points from TIGER .dbf (small; ~240k rows) -------
read_bg_dbf <- function(zip_path) {
  members  <- unzip(zip_path, list = TRUE)$Name
  dbf_name <- grep("\\.dbf$", members, value = TRUE, ignore.case = TRUE)
  if (length(dbf_name) != 1L)
    stop(glue("[R/122a] Expected exactly one .dbf in {basename(zip_path)}; found {length(dbf_name)}"))
  td <- tempfile(); dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  unzip(zip_path, files = dbf_name, exdir = td, junkpaths = TRUE)
  d <- foreign::read.dbf(file.path(td, basename(dbf_name)), as.is = TRUE)
  tibble(GEOID    = as.character(d$GEOID),
         INTPTLAT = as.numeric(d$INTPTLAT),   # stored as "+29.6516344"
         INTPTLON = as.numeric(d$INTPTLON))   # stored as "-082.3248262"
}
cent <- bind_rows(lapply(tiger_zips, read_bg_dbf)) %>% distinct(GEOID, .keep_all = TRUE)
if (nrow(cent) == 0L) stop("[R/122a] No block-group centroids read from TIGER files")
logm("Block-group centroids loaded: {nrow(cent)} (states: {length(tiger_zips)})")

# ---- 2. Dedup ZIP9, join centroids, write CSV — all inside DuckDB -------------
build_in_duckdb <- function() {
  con <- dbConnect(duckdb::duckdb())
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
  dbExecute(con, glue("PRAGMA threads={max(1L, as.integer(Sys.getenv('SLURM_CPUS_PER_TASK', '4')))}"))
  dbExecute(con, "PRAGMA memory_limit='24GB'")
  dbWriteTable(con, "cent", cent, temporary = TRUE)

  # Distinct (zip9, bg_geoid, state) triples with the two ID-format filters applied once.
  dbExecute(con, glue("
    CREATE TEMP TABLE pairs AS
    SELECT DISTINCT zip9, bg_geoid, state
    FROM read_parquet('{sql_str(ADI_PARQUET)}')
    WHERE zip9 IS NOT NULL AND bg_geoid IS NOT NULL
      AND regexp_matches(zip9, '^[0-9]{{9}}$')
      AND regexp_matches(bg_geoid, '^[0-9]{{12}}$')"))
  n_pairs <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM pairs")$n
  if (n_pairs == 0L) stop("[R/122a] No valid ZIP9/GEOID records remained after filtering")

  # One row per ZIP9: the whole row with the lowest GEOID (state travels with it), plus N_BG.
  dbExecute(con, "
    CREATE TEMP TABLE zip9_dedup AS
    SELECT zip9, bg_geoid, state, n_bg
    FROM (
      SELECT zip9, bg_geoid, state,
             ROW_NUMBER() OVER (PARTITION BY zip9 ORDER BY bg_geoid, state) AS rn,
             COUNT(DISTINCT bg_geoid) OVER (PARTITION BY zip9)              AS n_bg
      FROM pairs)
    WHERE rn = 1")
  n_zip9  <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM zip9_dedup")$n
  n_ambig <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM zip9_dedup WHERE n_bg > 1")$n
  logm("Distinct (zip9, bg_geoid, state) triples: {n_pairs}; distinct ZIP9: {n_zip9}")
  logm("ZIP9 mapped to >1 block group: {n_ambig} ({round(100 * n_ambig / n_zip9, 3)}%) — ",
       "lowest GEOID kept; N_BG column records the count")
  if (n_ambig / n_zip9 > 0.05)
    logm("WARNING: >5% of ZIP9 are multi-block-group — review before relying on ZIP9 centroids")

  dbExecute(con, glue("
    COPY (
      SELECT z.zip9 AS ZIP9, z.bg_geoid AS GEOID, c.INTPTLAT, c.INTPTLON, z.n_bg AS N_BG
      FROM zip9_dedup z LEFT JOIN cent c ON z.bg_geoid = c.GEOID
      ORDER BY z.zip9
    ) TO '{sql_str(OUT_PATH)}' (HEADER, DELIMITER ',')"))
  logm("Wrote {OUT_PATH} ({n_zip9} rows)")

  list(
    n_matched    = dbGetQuery(con, "
      SELECT COUNT(*) AS n FROM zip9_dedup z JOIN cent c ON z.bg_geoid = c.GEOID
      WHERE c.INTPTLAT IS NOT NULL AND c.INTPTLON IS NOT NULL")$n,
    n_zip9       = n_zip9,
    state_counts = dbGetQuery(con, "SELECT state, COUNT(*) AS n_zip9 FROM zip9_dedup GROUP BY state ORDER BY state"),
    unmatched    = dbGetQuery(con, "
      SELECT z.state, COUNT(*) AS n_unmatched
      FROM zip9_dedup z LEFT JOIN cent c ON z.bg_geoid = c.GEOID
      WHERE c.INTPTLAT IS NULL OR c.INTPTLON IS NULL
      GROUP BY z.state ORDER BY z.state"),
    states_seen  = dbGetQuery(con, "SELECT DISTINCT state FROM zip9_dedup")$state
  )
}
res <- build_in_duckdb()

# ---- 3. Log --------------------------------------------------------------------
n_unmatched <- res$n_zip9 - res$n_matched
logm("ZIP9 with centroid: {res$n_matched}; without: {n_unmatched} ({round(100 * n_unmatched / res$n_zip9, 3)}%)")
if (n_unmatched / res$n_zip9 > 0.01)
  logm("WARNING: >1% unmatched — check TIGER vintage vs Atlas block groups, or missing state zips")

writeLines(c(log_lines, "", "ZIP9 count by state:",
             capture.output(print(res$state_counts, row.names = FALSE)),
             "", "Unmatched-centroid ZIP9 by state:",
             capture.output(print(res$unmatched, row.names = FALSE)),
             "", "States absent from Atlas (expected WV):",
             paste(setdiff(c(state.abb, "DC", "PR"), res$states_seen), collapse = ", ")),
           LOG_PATH)
message(glue("Build log: {LOG_PATH}"))
