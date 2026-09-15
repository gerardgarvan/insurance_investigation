# ==============================================================================
# 122a_build_zip9_centroid_crosswalk.R -- One-off builder: ZIP9 -> block-group
#                                          centroid crosswalk (Phase 152, Plan 00)
# ==============================================================================
#
# Purpose:
#   Reads the 51 Neighborhood Atlas per-state ZIP+4 -> ADI files from
#   CONFIG$atlas_zip4_dir, normalizes each ZIP+4 identifier to a 9-digit string
#   (ZIP9), truncates the block-group FIPS to 12 digits (GEOID), then joins to a
#   block-group internal-point table (NHGIS or TIGER/Line) to attach
#   INTPTLAT/INTPTLON.  Writes:
#     - data/reference/zip9_bg_centroid_crosswalk.csv  (consumed by R/122)
#     - data/reference/zip9_bg_centroid_crosswalk_BUILDLOG_<date>.txt
#
# Output contract (consumed by get_zip_centroid() in Plan 01):
#   ZIP9      character  9 digits, no hyphen, leading zeros preserved
#   GEOID     character  12-digit block-group FIPS
#   INTPTLAT  double     decimal degrees, CONUS/AK/HI/PR range [17, 72]
#   INTPTLON  double     decimal degrees, negative for USA [-180, -64]
#
# Column name placeholders (CONFIRM on HiPerGator via Task 1 head inspection
# before running this script):
#   ZIP4_COL  -- the Atlas column holding the ZIP+4 identifier
#                (e.g. "ZIP9", "ZIPID", "ZIPplusfour", "ZIP_CODE_PLUS_FOUR")
#   FIPS_COL  -- the Atlas column holding the block-group FIPS
#                (e.g. "FIPS", "FIPS_BG", "GEOID", "BLOCKGROUP")
#
# After Task 1 confirms the real names, replace ZIP4_COL / FIPS_COL throughout
# this file with the confirmed strings and remove these placeholder comments.
#
# Run:
#   sbatch slurm/122a_build_zip9_centroid_crosswalk.sbatch
#   -- or interactively on HiPerGator --
#   Rscript R/122a_build_zip9_centroid_crosswalk.R
#
# One-time builder: does NOT modify any production pipeline tables or RDS cache.
# After the crosswalk is built, Plan 01 (R/122) reads it on every subsequent run.
#
# Memory budget: ~7.5 GB Atlas files; with col_select (2 columns) the in-memory
# footprint is < 2 GB.  SLURM allocation: 32 GB, 4 CPUs, 4 h (ample).
#
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP AND LIBRARIES ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(vroom)
  library(stringr)
  library(glue)
})

source("R/00_config.R")

# Build date stamp (used for output file names and log)
BUILD_DATE <- format(Sys.Date(), "%Y%m%d")

# ---------------------------------------------------------------------------
# Column name placeholders — UPDATE after Task 1 head inspection on HiPerGator
# ---------------------------------------------------------------------------
# These two constants are the ONLY place ZIP4_COL and FIPS_COL appear as
# string literals.  Replace with the confirmed column names from the real file
# header before submitting the SLURM job.
ZIP4_COL <- "ZIP9"        # PLACEHOLDER — confirm from: head -2 <state_file>.csv
FIPS_COL <- "FIPS"        # PLACEHOLDER — confirm from: head -2 <state_file>.csv
# Note: ADI_NATRANK and ADI_STATERNK are expected alongside ZIP4_COL/FIPS_COL
# but are NOT read by this builder (col_select below selects only what is needed).

# ---------------------------------------------------------------------------
# Probe gate: atlas_zip4_dir must be set and exist
# ---------------------------------------------------------------------------
if (is.null(CONFIG$atlas_zip4_dir)) {
  stop(
    "CONFIG$atlas_zip4_dir is NULL.\n",
    "On HiPerGator: update R/00_config.R with the actual Atlas ZIP+4 directory.\n",
    "Hint: ls /blue/erin.mobley.precision/ to locate the Atlas download directory."
  )
}
if (!dir.exists(CONFIG$atlas_zip4_dir)) {
  stop(
    glue("CONFIG$atlas_zip4_dir does not exist: {CONFIG$atlas_zip4_dir}\n"),
    "Verify the path with: ls /blue/erin.mobley.precision/\n",
    "Then update CONFIG$atlas_zip4_dir in R/00_config.R."
  )
}

# ---------------------------------------------------------------------------
# Probe gate: output reference directory must exist
# ---------------------------------------------------------------------------
ref_dir <- dirname(CONFIG$zip9_bg_centroid_path)
if (!dir.exists(ref_dir)) {
  dir.create(ref_dir, recursive = TRUE, showWarnings = FALSE)
  message(glue("Created output directory: {ref_dir}"))
}

# ==============================================================================
# SECTION 2: ATLAS READ — ZIP+4 -> GEOID ----
# ==============================================================================
# Loop over all per-state CSV files in CONFIG$atlas_zip4_dir.
# For each file:
#   1. Read only ZIP4_COL and FIPS_COL (col_select keeps memory bounded).
#   2. Coerce both to character (vroom may guess numeric for all-digit fields).
#   3. Normalize ZIP4_COL to a clean 9-digit ZIP9:
#        - strip any prefix letter(s) before the first digit
#        - strip separators (underscore, hyphen, space) between 5- and 4-digit parts
#        - drop rows that are not exactly 9 digits after normalization
#   4. Truncate FIPS_COL to 12 digits -> GEOID (block-group, not block).
#   5. Log per-state n_rows_raw, n_dropped_bad_zip9, n_kept.

state_files <- list.files(
  CONFIG$atlas_zip4_dir,
  pattern    = "\\.csv$",
  full.names = TRUE
)

n_files <- length(state_files)
message(glue("Found {n_files} CSV file(s) in {CONFIG$atlas_zip4_dir}"))

if (n_files == 0) {
  stop(
    glue("No CSV files found in {CONFIG$atlas_zip4_dir}.\n"),
    "Check the directory path and confirm files are present:\n",
    glue("  ls {CONFIG$atlas_zip4_dir}")
  )
}

# Accumulator for per-state log rows
state_log <- vector("list", n_files)

# Accumulator for ZIP9->GEOID rows (bound at end, not appended row-by-row)
atlas_chunks <- vector("list", n_files)

for (i in seq_along(state_files)) {
  fpath   <- state_files[[i]]
  fname   <- basename(fpath)
  # Derive 2-letter state abbreviation from filename (first 2 chars, e.g. "AL")
  state_abbr <- substr(fname, 1, 2)

  # Read only the two needed columns; both as character to prevent leading-zero loss
  raw <- tryCatch(
    vroom(
      fpath,
      col_select  = c(!!ZIP4_COL, !!FIPS_COL),
      col_types   = vroom::cols(.default = vroom::col_character()),
      progress    = FALSE,
      show_col_types = FALSE
    ),
    error = function(e) {
      stop(glue(
        "Failed to read {fname}.\n",
        "Error: {conditionMessage(e)}\n",
        "Check that ZIP4_COL='{ZIP4_COL}' and FIPS_COL='{FIPS_COL}' match the real column names.\n",
        "Run: head -2 {fpath}"
      ))
    }
  )

  n_raw <- nrow(raw)

  # Rename to internal names for clarity
  names(raw)[names(raw) == ZIP4_COL] <- "zip4_raw"
  names(raw)[names(raw) == FIPS_COL] <- "fips_raw"

  # Normalize ZIP4: strip prefix letter(s), separators; keep 9 contiguous digits
  normalized <- raw %>%
    mutate(
      # Remove any leading non-digit characters (e.g. "Z", "zcta_")
      zip4_stripped = str_replace_all(zip4_raw, "^[^0-9]+", ""),
      # Remove separators between the 5- and 4-digit parts (_, -, space)
      zip4_clean    = str_replace_all(zip4_stripped, "[_\\- ]", ""),
      # GEOID: first 12 characters of FIPS (block-group; 15-digit block truncated here)
      GEOID         = substr(str_pad(fips_raw, width = 12, side = "left", pad = "0"), 1, 12),
      # Final ZIP9: must be exactly 9 digits
      ZIP9          = if_else(str_detect(zip4_clean, "^[0-9]{9}$"), zip4_clean, NA_character_)
    )

  n_dropped <- sum(is.na(normalized$ZIP9))
  n_kept    <- n_raw - n_dropped

  # Keep only valid rows; select final columns
  atlas_chunks[[i]] <- normalized %>%
    filter(!is.na(ZIP9)) %>%
    select(ZIP9, GEOID)

  state_log[[i]] <- tibble(
    state      = state_abbr,
    file       = fname,
    n_raw      = n_raw,
    n_dropped  = n_dropped,
    n_kept     = n_kept
  )

  message(glue("  [{i}/{n_files}] {state_abbr}: {n_raw} rows, {n_dropped} dropped (bad ZIP9), {n_kept} kept"))
}

# Bind all state chunks
atlas_all <- bind_rows(atlas_chunks)
state_log_df <- bind_rows(state_log)

message(glue("\nAtlas read complete: {nrow(atlas_all)} total ZIP9->GEOID rows across {n_files} files"))

# ==============================================================================
# SECTION 3: BLOCK-GROUP INTERNAL POINTS ----
# ==============================================================================
# Discover the centroid source in order of preference:
#   (a) NHGIS block-group table with GISJOIN/GEOID + INTPTLAT/INTPTLON columns
#   (b) TIGER/Line 2020 block-group DBF files (tl_2020_<ss>_bg.zip or .dbf)
# Stops if neither is found — no network downloads allowed inside SLURM jobs.

# Common candidate directories to search (update if Atlas data is elsewhere)
candidate_dirs <- c(
  "/blue/erin.mobley.precision",
  "/blue/erin.mobley-hl.bcu/reference",
  "/blue/erin.mobley-hl.bcu/clean/reference"
)

# ---------------------------------------------------------------------------
# (a) NHGIS block-group table
# ---------------------------------------------------------------------------
nhgis_candidates <- unlist(lapply(candidate_dirs, function(d) {
  if (dir.exists(d)) {
    list.files(d, pattern = "nhgis.*blck_grp.*\\.csv$|blkgrp.*nhgis.*\\.csv$",
               recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
  }
}))

centroid_source <- "none"
centroid_df     <- NULL

if (length(nhgis_candidates) > 0) {
  nhgis_path <- nhgis_candidates[[1]]
  message(glue("Using NHGIS block-group centroid table: {nhgis_path}"))

  # Read the NHGIS file; keep GEOID (or GISJOIN) + INTPTLAT + INTPTLON
  nhgis_raw <- vroom(
    nhgis_path,
    col_types      = vroom::cols(.default = vroom::col_character()),
    progress       = FALSE,
    show_col_types = FALSE
  )

  # Handle GISJOIN -> GEOID conversion if needed
  # NHGIS GISJOIN format: G + state(3) + county(4) + tract(7) + BG(1) = 16 chars
  # Extract 12-digit GEOID from GISJOIN: state 2-4, county 5-8, tract 9-15, BG 16
  if ("GEOID" %in% names(nhgis_raw)) {
    centroid_df <- nhgis_raw %>%
      select(GEOID, INTPTLAT, INTPTLON) %>%
      mutate(
        INTPTLAT = as.numeric(INTPTLAT),
        INTPTLON = as.numeric(INTPTLON)
      )
  } else if ("GISJOIN" %in% names(nhgis_raw)) {
    centroid_df <- nhgis_raw %>%
      mutate(
        GEOID = paste0(
          substr(GISJOIN, 2, 3),   # state 2 digits
          substr(GISJOIN, 5, 7),   # county 3 digits
          substr(GISJOIN, 9, 14),  # tract 6 digits
          substr(GISJOIN, 16, 16)  # block group 1 digit
        ),
        INTPTLAT = as.numeric(INTPTLAT),
        INTPTLON = as.numeric(INTPTLON)
      ) %>%
      select(GEOID, INTPTLAT, INTPTLON)
  } else {
    stop(
      glue("NHGIS file found ({nhgis_path}) but contains neither GEOID nor GISJOIN column.\n"),
      glue("Columns present: {paste(names(nhgis_raw), collapse = ', ')}")
    )
  }
  centroid_source <- glue("NHGIS: {nhgis_path}")
}

# ---------------------------------------------------------------------------
# (b) TIGER/Line 2020 block-group DBF files (fallback)
# ---------------------------------------------------------------------------
if (is.null(centroid_df)) {
  tiger_dbfs <- unlist(lapply(candidate_dirs, function(d) {
    if (dir.exists(d)) {
      list.files(d, pattern = "tl_2020_[0-9]+_bg\\.dbf$",
                 recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
    }
  }))

  if (length(tiger_dbfs) > 0) {
    message(glue("Using TIGER/Line block-group DBF files: {length(tiger_dbfs)} state(s) found"))
    library(foreign)  # foreign::read.dbf — no additional install needed on HiPerGator

    tiger_chunks <- lapply(tiger_dbfs, function(dbf_path) {
      dbf <- foreign::read.dbf(dbf_path, as.is = TRUE)
      # TIGER BG DBF columns: GEOID (12 digits), INTPTLAT (+DD.DDDDDD), INTPTLON (-DDD.DDDDDD)
      tibble(
        GEOID    = as.character(dbf$GEOID),
        INTPTLAT = as.numeric(dbf$INTPTLAT),
        INTPTLON = as.numeric(dbf$INTPTLON)
      )
    })

    centroid_df     <- bind_rows(tiger_chunks)
    centroid_source <- glue("TIGER/Line DBF: {length(tiger_dbfs)} state files")
  }
}

# ---------------------------------------------------------------------------
# Neither source found — stop with actionable message
# ---------------------------------------------------------------------------
if (is.null(centroid_df)) {
  stop(
    "No block-group centroid source found.\n",
    "Checked directories:\n",
    paste0("  ", candidate_dirs, collapse = "\n"), "\n\n",
    "Option (a) — NHGIS block-group CSV:\n",
    "  Download from https://www.nhgis.org -> Data Finder -> Block Groups -> 2020\n",
    "  Select 'Geographic Identifiers' dataset; download CSV; upload to /blue/erin.mobley.precision/\n\n",
    "Option (b) — TIGER/Line 2020 block-group shapefiles:\n",
    "  Download tl_2020_<ss>_bg.zip for each state from:\n",
    "  https://www.census.gov/cgi-bin/geo/shapefiles/index.php?year=2020&layergroup=Block+Groups\n",
    "  Upload and unzip into /blue/erin.mobley.precision/tiger_bg/\n",
    "  No network access available inside SLURM — download on your laptop first.\n"
  )
}

message(glue("Centroid source: {centroid_source}"))
message(glue("Centroid table: {nrow(centroid_df)} block-group rows"))

# ==============================================================================
# SECTION 4: JOIN, DEDUPE, AND WRITE ----
# ==============================================================================

# Join Atlas ZIP9->GEOID to centroid by GEOID (left join: Atlas is the driver)
joined <- atlas_all %>%
  left_join(centroid_df, by = "GEOID")

n_zip9_total    <- nrow(joined)
n_matched       <- sum(!is.na(joined$INTPTLAT))
n_unmatched     <- sum(is.na(joined$INTPTLAT))

message(glue(
  "\nJoin results:\n",
  "  ZIP9 total : {n_zip9_total}\n",
  "  Matched    : {n_matched} ({round(100 * n_matched / n_zip9_total, 1)}%)\n",
  "  Unmatched  : {n_unmatched} ({round(100 * n_unmatched / n_zip9_total, 1)}%)"
))

# Per-state unmatched breakdown (first 2 chars of GEOID = state FIPS)
if (n_unmatched > 0) {
  unmatched_by_state <- joined %>%
    filter(is.na(INTPTLAT)) %>%
    mutate(state_fips = substr(GEOID, 1, 2)) %>%
    count(state_fips, name = "n_unmatched") %>%
    arrange(desc(n_unmatched))
  message("\nUnmatched GEOID breakdown by state FIPS:")
  print(unmatched_by_state, n = 20)
  message(glue(
    "\nNOTE: If n_unmatched > 1% of total, the Atlas and centroid source may use\n",
    "different block-group vintages (e.g. 2020 Atlas FIPS vs 2010 TIGER/Line).\n",
    "In that case swap the centroid source to match the Atlas vintage."
  ))
}

# Deduplicate: one row per ZIP9 (keep first GEOID alphabetically)
# Log duplicate count before deduplication
n_dup_zip9 <- nrow(joined) - n_distinct(joined$ZIP9)
if (n_dup_zip9 > 0) {
  message(glue("\n{n_dup_zip9} ZIP9 values mapped to more than one GEOID — keeping first by GEOID order."))
}

crosswalk <- joined %>%
  arrange(ZIP9, GEOID) %>%             # deterministic order
  group_by(ZIP9) %>%
  slice(1) %>%
  ungroup() %>%
  select(ZIP9, GEOID, INTPTLAT, INTPTLON)

message(glue("\nFinal crosswalk: {nrow(crosswalk)} unique ZIP9 rows"))

# Write crosswalk CSV
vroom::vroom_write(crosswalk, CONFIG$zip9_bg_centroid_path, delim = ",")
message(glue("Crosswalk written: {CONFIG$zip9_bg_centroid_path}"))

# ==============================================================================
# SECTION 5: BUILD LOG ----
# ==============================================================================

log_path <- file.path(
  ref_dir,
  glue("zip9_bg_centroid_crosswalk_BUILDLOG_{BUILD_DATE}.txt")
)

log_lines <- c(
  glue("zip9_bg_centroid_crosswalk build log — {Sys.time()}"),
  glue("R/122a_build_zip9_centroid_crosswalk.R"),
  "",
  glue("Atlas ZIP+4 directory : {CONFIG$atlas_zip4_dir}"),
  glue("ZIP4_COL placeholder  : {ZIP4_COL}  <-- confirm from file header"),
  glue("FIPS_COL placeholder  : {FIPS_COL}  <-- confirm from file header"),
  glue("Centroid source       : {centroid_source}"),
  "",
  glue("Files processed       : {n_files}"),
  glue("ZIP9 total (pre-dedup): {n_zip9_total}"),
  glue("ZIP9 duplicates dedup : {n_dup_zip9}"),
  glue("Final unique ZIP9     : {nrow(crosswalk)}"),
  glue("Centroid matched      : {n_matched} ({round(100 * n_matched / n_zip9_total, 1)}%)"),
  glue("Centroid unmatched    : {n_unmatched} ({round(100 * n_unmatched / n_zip9_total, 1)}%)"),
  "",
  "--- Per-state row counts ---",
  capture.output(print(state_log_df, n = 60)),
  "",
  "--- Missing states (expected: West Virginia = WV) ---"
)

# Infer expected 50-state + DC = 51 abbreviations; flag any missing from the file list
expected_states <- c(
  "AL","AK","AZ","AR","CA","CO","CT","DE","DC","FL","GA","HI","ID","IL","IN","IA",
  "KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM",
  "NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VT","VA","WA",
  "WV","WI","WY"
)
present_states <- state_log_df$state
missing_states <- setdiff(expected_states, present_states)

if (length(missing_states) == 0) {
  log_lines <- c(log_lines, "All 51 state/DC files present.")
} else {
  log_lines <- c(log_lines,
    glue("Missing ({length(missing_states)}): {paste(missing_states, collapse = ', ')}"),
    "(West Virginia is expected to be absent from the 2024 Atlas release.)"
  )
}

log_lines <- c(log_lines, "", glue("Output crosswalk: {CONFIG$zip9_bg_centroid_path}"))

writeLines(log_lines, log_path)
message(glue("Build log written: {log_path}"))
message("\nDone.")
