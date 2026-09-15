# ==============================================================================
# 122_encounter_distance.R -- Encounter-ZIP to Residence Distance (Phase 152)
# ==============================================================================
# Purpose:     For every HL-cohort ENCOUNTER row in the DuckDB CDM (scoped to
#              COHORT_IDS), computes the haversine (great-circle) distance in km
#              between the encounter's FACILITY_LOCATION ZIP and the patient's
#              residential address in effect on ADMIT_DATE. Produces an
#              encounter-level distance tibble (enc_distance) and a dated summary
#              xlsx plus rds deliverable.
#
# Inputs:      ENCOUNTER table (via DuckDB), scoped to HL cohort IDs + ADMIT_DATE
#              LDS_ADDRESS_HISTORY_Mailhot_V1.csv (via get_zip9_at_date())
#              data/reference/zcta_gazetteer_centroids.csv   (ZIP5 centroids)
#              data/reference/zip9_bg_centroid_crosswalk.csv (ZIP9 centroids)
#
# Outputs:     output/encounter_distance_YYYYMMDD.xlsx
#              output/encounter_distance_YYYYMMDD.rds
#
# Dependencies: R/00_config.R (auto-sources utils_address.R, utils_duckdb.R, etc.)
#               dplyr, glue, stringr, openxlsx2, tibble, vroom
#
# Requirements: Phase 152 -- DIST-SCRIPT-CORE, DIST-PROBE, DIST-ENCOUNTER-PULL,
#               DIST-RESIDENCE, DIST-CENTROID, DIST-COMPUTE
#
# Usage:       Rscript R/122_encounter_distance.R
#              source("R/122_encounter_distance.R")
#
# Note:        READ-ONLY investigation. Structural verification is runnable locally
#              (grep-based checks). Runtime (DuckDB + HiPerGator reference files)
#              requires HiPerGator with ENCOUNTER table and both centroid CSVs present.
# ==============================================================================

# SECTION 1: SETUP AND LIBRARIES ----

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(openxlsx2)
  library(tibble)
  library(vroom)
})

source("R/00_config.R")
# R/00_config.R auto-sources R/utils/utils_address.R, which provides:
#   haversine_km()       -- vectorized great-circle distance (km)
#   get_zip_centroid()   -- resolves ZIP5/ZIP9 to lat/lon (with memoized cache)
#   get_zip9_at_date()   -- residence ZIP at query date, ONE row per DISTINCT (ID, query_date)
#   normalize_zip9()     -- 9-digit string or NA
#   normalize_zip5_raw() -- 5-digit string or NA (free-text safe)

message("=== Phase 152: Encounter-ZIP to Residence Distance ===")

# SECTION 1B: TESTABLE CORE FUNCTIONS ----
# haversine_km() and get_zip_centroid() live in R/utils/utils_address.R (auto-sourced
# above) and are NOT redefined here. See utils_address.R SECTION 1B for their
# definitions and roxygen documentation.
#
# The one R/122-local pure helper below (level_from_source) is defined here so it
# is testable (no file I/O) and in scope before SECTION 2's probe gates fire.

#' Derive the distance_basis level label from a centroid_source value.
#'
#' Maps centroid_source strings to the coarser "zip9" | "zip5" level used in
#' distance_basis. A ZIP9 that fell back to the ZCTA gazetteer centroid is
#' reported as "zip5" basis, not "zip9", because the precision is ZIP5-level.
#'
#' @param src Character. centroid_source from get_zip_centroid().
#' @return Character: "zip9", "zip5", or NA_character_.
level_from_source <- function(src) {
  dplyr::case_when(
    src == "zip9_bg"                               ~ "zip9",
    src %in% c("zip5_gazetteer", "zip5_fallback")  ~ "zip5",
    TRUE                                           ~ NA_character_
  )
}

# ==============================================================================
# SECTION 2: CONSTANTS AND PROBE GATES ----
# ==============================================================================

RUN_DATE    <- format(Sys.Date(), "%Y%m%d")
OUTPUT_RDS  <- file.path(CONFIG$output_dir, glue("encounter_distance_{RUN_DATE}.rds"))
OUTPUT_XLSX <- file.path(CONFIG$output_dir, glue("encounter_distance_{RUN_DATE}.xlsx"))

# ---------------------------------------------------------------------------
# Probe gate 1: ZCTA Gazetteer centroids (ZIP5 path) -- BLOCKING
# ---------------------------------------------------------------------------
gaz_path <- if (!is.null(CONFIG$zcta_gazetteer_path)) {
  CONFIG$zcta_gazetteer_path
} else if (requireNamespace("here", quietly = TRUE)) {
  here::here("data", "reference", "zcta_gazetteer_centroids.csv")
} else {
  file.path("data", "reference", "zcta_gazetteer_centroids.csv")
}

message(glue("  [ZCTA gazetteer] Checking: {gaz_path}"))
if (file.exists(gaz_path)) {
  message("  [ZCTA gazetteer] found -- OK")
} else {
  message("  [ZCTA gazetteer] NOT FOUND")
  stop(
    "[R/122] Stage data/reference/zcta_gazetteer_centroids.csv from the Census ZCTA Gazetteer Files ",
    "(https://www.census.gov/geographies/reference-files/2020/geo/gazetteer-file.html) before running.",
    call. = FALSE
  )
}

# ---------------------------------------------------------------------------
# Probe gate 2: ZIP9 block-group centroid crosswalk -- DEGRADING (not blocking)
# Absence sets ZIP9_CROSSWALK_AVAILABLE <- FALSE; all centroids resolve at ZIP5.
# ---------------------------------------------------------------------------
bg_path <- if (!is.null(CONFIG$zip9_bg_centroid_path)) {
  CONFIG$zip9_bg_centroid_path
} else if (requireNamespace("here", quietly = TRUE)) {
  here::here("data", "reference", "zip9_bg_centroid_crosswalk.csv")
} else {
  file.path("data", "reference", "zip9_bg_centroid_crosswalk.csv")
}

message(glue("  [ZIP9 crosswalk] Checking: {bg_path}"))
if (file.exists(bg_path)) {
  message("  [ZIP9 crosswalk] found -- ZIP9 centroid resolution available")
  ZIP9_CROSSWALK_AVAILABLE <- TRUE
} else {
  message("  [ZIP9 crosswalk] NOT FOUND")
  warning(
    "[R/122] zip9_bg_centroid_crosswalk.csv not found. ",
    "Build it with R/122a_build_zip9_centroid_crosswalk.R (Plan 00) from the Neighborhood Atlas ",
    "files under /blue/erin.mobley.precision/ before running the ZIP9 centroid path. ",
    "Continuing with ZIP5-only centroid resolution (all centroid_source values will be ",
    "'zip5_gazetteer' or 'zip5_fallback'; distance_basis will only contain 'zip5-zip5'). ",
    "QC sheet will record zip9_crosswalk_present = FALSE.",
    call. = FALSE
  )
  ZIP9_CROSSWALK_AVAILABLE <- FALSE
}

# ---------------------------------------------------------------------------
# Probe gate 3: DuckDB ENCOUNTER table -- BLOCKING
# Mirror R/116's DuckDB connection pattern exactly.
# ---------------------------------------------------------------------------
if (!exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}

enc_test <- tryCatch(
  get_pcornet_table("ENCOUNTER"),
  error = function(e) NULL
)
if (is.null(enc_test)) {
  stop(
    "[R/122] DuckDB ENCOUNTER table not available. ",
    "Confirm DuckDB connection is open and the ENCOUNTER table is present before running.",
    call. = FALSE
  )
}
message("  [DuckDB ENCOUNTER] available -- OK")

# ==============================================================================
# SECTION 3: ENCOUNTER PULL ----
# ==============================================================================

message("--- Pulling HL cohort ENCOUNTER rows ---")

# Source get_hl_patient_ids() if not yet loaded (R/115/R/116 pattern)
if (!exists("get_hl_patient_ids")) {
  source("R/utils/utils_treatment.R")
}
COHORT_IDS <- get_hl_patient_ids()
message(glue("  HL cohort IDs: {length(COHORT_IDS)}"))

enc_tbl <- get_pcornet_table("ENCOUNTER") %>% dplyr::rename_with(toupper)

# Capture raw cohort ENCOUNTER count for QC waterfall (before date filters).
n_enc_cohort_raw <- enc_tbl %>%
  dplyr::filter(ID %in% !!COHORT_IDS) %>%
  dplyr::count() %>%
  dplyr::pull(n)

message(glue("  Raw cohort ENCOUNTER rows (any ADMIT_DATE): {n_enc_cohort_raw}"))

# FACILITY_LOCATION is the ONLY ZIP-like column in ENCOUNTER (confirmed R/01_load_pcornet.R:176).
# There is no ZIP / ZIPCODE / FACILITY_ZIP column in this PCORnet CDM extract.
encounters_raw <- enc_tbl %>%
  dplyr::filter(ID %in% !!COHORT_IDS, !is.na(ADMIT_DATE)) %>%
  dplyr::select(ID, ENCOUNTERID, ADMIT_DATE, enc_zip_raw = FACILITY_LOCATION) %>%
  dplyr::collect() %>%
  dplyr::mutate(ADMIT_DATE = parse_pcornet_date(ADMIT_DATE)) %>%
  dplyr::filter(!is.na(ADMIT_DATE))

n_enc_admit_missing <- n_enc_cohort_raw - nrow(encounters_raw)
message(glue(
  "  After ADMIT_DATE filters: {nrow(encounters_raw)} encounters for ",
  "{dplyr::n_distinct(encounters_raw$ID)} patients ",
  "({n_enc_admit_missing} dropped for missing/unparseable ADMIT_DATE)"
))

# ==============================================================================
# SECTION 4: RESIDENCE ZIP RESOLUTION ----
# ==============================================================================

message("--- Resolving residence ZIP at ADMIT_DATE via get_zip9_at_date() ---")

# get_zip9_at_date() returns ONE row per DISTINCT (ID, query_date).
# NEVER cbind -- Pitfall 2; Phase 145 documented 1,950,696 -> 2,210,904 row blowup
# when cbind was used instead of a join.
res_lookup <- get_zip9_at_date(encounters_raw$ID, encounters_raw$ADMIT_DATE)

message(glue(
  "  res_lookup: {nrow(res_lookup)} distinct (ID, query_date) pairs"
))

# Join back on (ID, ADMIT_DATE = query_date) to restore one row per ENCOUNTERID.
encounters <- encounters_raw %>%
  dplyr::left_join(
    res_lookup,
    by = c("ID" = "ID", "ADMIT_DATE" = "query_date")
  ) %>%
  dplyr::rename(
    res_zip9        = ZIP9,
    res_zip5        = ZIP5,
    res_match_type  = match_type
  ) %>%
  dplyr::mutate(
    res_match_fallback = res_match_type == "most_recent_before"
  )

# Fan-out assertion: the join must NEVER increase the row count.
stopifnot(
  "get_zip9_at_date left_join fanned out -- review join keys" =
    nrow(encounters) == nrow(encounters_raw)
)

message(glue(
  "  Residence match breakdown: ",
  "{sum(encounters$res_match_type == 'interval', na.rm=TRUE)} interval, ",
  "{sum(encounters$res_match_type == 'most_recent_before', na.rm=TRUE)} most_recent_before, ",
  "{sum(encounters$res_match_type == 'none', na.rm=TRUE)} none, ",
  "{sum(is.na(encounters$res_match_type))} NA"
))

# ==============================================================================
# SECTION 5: ENCOUNTER ZIP NORMALIZATION ----
# ==============================================================================

message("--- Normalizing FACILITY_LOCATION (enc_zip_raw) ---")

# FACILITY_LOCATION is free-text in PCORnet CDM (Pitfall 3). normalize_zip9() and
# normalize_zip5_raw() return NA for non-numeric or non-ZIP values -- correct behavior.
encounters <- encounters %>%
  dplyr::mutate(
    enc_zip9 = normalize_zip9(enc_zip_raw),
    enc_zip5 = normalize_zip5_raw(enc_zip_raw)
  )

n_enc_with_norm_zip9 <- sum(!is.na(encounters$enc_zip9))
n_enc_with_norm_zip5 <- sum(!is.na(encounters$enc_zip5))
n_enc_zip_na         <- sum(is.na(encounters$enc_zip5) & is.na(encounters$enc_zip9))

message(glue(
  "  enc_zip9 resolved: {n_enc_with_norm_zip9}  ",
  "enc_zip5 resolved: {n_enc_with_norm_zip5}  ",
  "both NA: {n_enc_zip_na}"
))

# ==============================================================================
# SECTION 6: CENTROID RESOLUTION ----
# ==============================================================================

message("--- Resolving centroids (encounter side + residence side) ---")

# Resolve encounter-side centroids.
# When ZIP9_CROSSWALK_AVAILABLE is FALSE, skip the ZIP9 call entirely; all
# centroids resolve at ZIP5 (centroid_source = "zip5_gazetteer" or "zip5_fallback").

if (ZIP9_CROSSWALK_AVAILABLE) {
  # Encounter side: prefer ZIP9 centroid; fall back to ZIP5.
  enc_zip9_vals <- encounters$enc_zip9
  enc_zip5_vals <- encounters$enc_zip5

  # Resolve ZIP9 centroids for encounters that have a ZIP9.
  enc_has_zip9     <- !is.na(enc_zip9_vals)
  enc_zip9_lookup  <- if (any(enc_has_zip9)) {
    get_zip_centroid(enc_zip9_vals[enc_has_zip9], level = "zip9")
  } else {
    tibble(zip = character(), level = character(),
           lat = double(), lon = double(), centroid_source = character())
  }

  # Resolve ZIP5 centroids for encounters that lack ZIP9.
  enc_has_zip5_only <- !enc_has_zip9 & !is.na(enc_zip5_vals)
  enc_zip5_lookup   <- if (any(enc_has_zip5_only)) {
    get_zip_centroid(enc_zip5_vals[enc_has_zip5_only], level = "zip5")
  } else {
    tibble(zip = character(), level = character(),
           lat = double(), lon = double(), centroid_source = character())
  }

  # Assemble per-encounter columns enc_lat, enc_lon, enc_centroid_source.
  enc_lat             <- rep(NA_real_,      nrow(encounters))
  enc_lon             <- rep(NA_real_,      nrow(encounters))
  enc_centroid_source <- rep(NA_character_, nrow(encounters))

  enc_lat[enc_has_zip9]      <- enc_zip9_lookup$lat
  enc_lon[enc_has_zip9]      <- enc_zip9_lookup$lon
  enc_centroid_source[enc_has_zip9] <- enc_zip9_lookup$centroid_source

  enc_lat[enc_has_zip5_only]      <- enc_zip5_lookup$lat
  enc_lon[enc_has_zip5_only]      <- enc_zip5_lookup$lon
  enc_centroid_source[enc_has_zip5_only] <- enc_zip5_lookup$centroid_source

  # Residence side: prefer ZIP9 centroid; fall back to ZIP5.
  res_zip9_vals <- encounters$res_zip9
  res_zip5_vals <- encounters$res_zip5

  res_has_zip9     <- !is.na(res_zip9_vals)
  res_zip9_lookup  <- if (any(res_has_zip9)) {
    get_zip_centroid(res_zip9_vals[res_has_zip9], level = "zip9")
  } else {
    tibble(zip = character(), level = character(),
           lat = double(), lon = double(), centroid_source = character())
  }

  res_has_zip5_only <- !res_has_zip9 & !is.na(res_zip5_vals)
  res_zip5_lookup   <- if (any(res_has_zip5_only)) {
    get_zip_centroid(res_zip5_vals[res_has_zip5_only], level = "zip5")
  } else {
    tibble(zip = character(), level = character(),
           lat = double(), lon = double(), centroid_source = character())
  }

  res_lat             <- rep(NA_real_,      nrow(encounters))
  res_lon             <- rep(NA_real_,      nrow(encounters))
  res_centroid_source <- rep(NA_character_, nrow(encounters))

  res_lat[res_has_zip9]      <- res_zip9_lookup$lat
  res_lon[res_has_zip9]      <- res_zip9_lookup$lon
  res_centroid_source[res_has_zip9] <- res_zip9_lookup$centroid_source

  res_lat[res_has_zip5_only]      <- res_zip5_lookup$lat
  res_lon[res_has_zip5_only]      <- res_zip5_lookup$lon
  res_centroid_source[res_has_zip5_only] <- res_zip5_lookup$centroid_source

} else {
  # ZIP9_CROSSWALK_AVAILABLE == FALSE: resolve everything at ZIP5 level.
  # Use enc_zip5 (or first 5 of enc_zip9 if enc_zip5 is NA) for encounter side.
  message("  ZIP9 crosswalk absent -- resolving both sides at ZIP5 only")

  enc_zip5_eff <- dplyr::coalesce(encounters$enc_zip5,
                                   substr(as.character(encounters$enc_zip9), 1, 5))
  res_zip5_eff <- dplyr::coalesce(encounters$res_zip5,
                                   substr(as.character(encounters$res_zip9), 1, 5))

  enc_has_zip5 <- !is.na(enc_zip5_eff)
  enc_zip5_lookup <- if (any(enc_has_zip5)) {
    get_zip_centroid(enc_zip5_eff[enc_has_zip5], level = "zip5")
  } else {
    tibble(zip = character(), level = character(),
           lat = double(), lon = double(), centroid_source = character())
  }

  res_has_zip5 <- !is.na(res_zip5_eff)
  res_zip5_lookup <- if (any(res_has_zip5)) {
    get_zip_centroid(res_zip5_eff[res_has_zip5], level = "zip5")
  } else {
    tibble(zip = character(), level = character(),
           lat = double(), lon = double(), centroid_source = character())
  }

  enc_lat             <- rep(NA_real_,      nrow(encounters))
  enc_lon             <- rep(NA_real_,      nrow(encounters))
  enc_centroid_source <- rep(NA_character_, nrow(encounters))

  enc_lat[enc_has_zip5]             <- enc_zip5_lookup$lat
  enc_lon[enc_has_zip5]             <- enc_zip5_lookup$lon
  enc_centroid_source[enc_has_zip5] <- enc_zip5_lookup$centroid_source

  res_lat             <- rep(NA_real_,      nrow(encounters))
  res_lon             <- rep(NA_real_,      nrow(encounters))
  res_centroid_source <- rep(NA_character_, nrow(encounters))

  res_lat[res_has_zip5]             <- res_zip5_lookup$lat
  res_lon[res_has_zip5]             <- res_zip5_lookup$lon
  res_centroid_source[res_has_zip5] <- res_zip5_lookup$centroid_source
}

# Attach centroid columns to the encounters tibble.
encounters <- encounters %>%
  dplyr::mutate(
    enc_lat             = enc_lat,
    enc_lon             = enc_lon,
    enc_centroid_source = enc_centroid_source,
    res_lat             = res_lat,
    res_lon             = res_lon,
    res_centroid_source = res_centroid_source
  )

# Derive per-side centroid level from centroid_source (not from zip9 string presence).
# A ZIP9 that fell back to the gazetteer centroid is a "zip5" basis for distance_basis.
encounters <- encounters %>%
  dplyr::mutate(
    enc_level = level_from_source(enc_centroid_source),
    res_level = level_from_source(res_centroid_source)
  )

n_enc_centroid_resolved <- sum(!is.na(encounters$enc_lat))
n_res_centroid_resolved <- sum(!is.na(encounters$res_lat))
message(glue(
  "  Enc centroid resolved: {n_enc_centroid_resolved} / {nrow(encounters)}  ",
  "Res centroid resolved: {n_res_centroid_resolved} / {nrow(encounters)}"
))

# ==============================================================================
# SECTION 7: DISTANCE COMPUTATION ----
# ==============================================================================

message("--- Computing haversine distance ---")

encounters <- encounters %>%
  dplyr::mutate(
    distance_km = haversine_km(enc_lat, enc_lon, res_lat, res_lon),
    distance_basis = dplyr::case_when(
      enc_level == "zip9" & res_level == "zip9" ~ "zip9-zip9",
      enc_level == "zip9" & res_level == "zip5" ~ "zip9-zip5",
      enc_level == "zip5" & res_level == "zip9" ~ "zip5-zip9",
      enc_level == "zip5" & res_level == "zip5" ~ "zip5-zip5",
      TRUE                                       ~ NA_character_
    )
  )

# Assemble the encounter-level tibble with the exact A_encounter_distance columns
# from CONTEXT.md. enc_zip_norm = finest normalized ZIP (ZIP9 preferred, ZIP5 fallback).
enc_distance <- encounters %>%
  dplyr::mutate(
    enc_zip_norm = dplyr::coalesce(enc_zip9, enc_zip5)
  ) %>%
  dplyr::select(
    ID,
    ENCOUNTERID,
    ADMIT_DATE,
    enc_zip_norm,
    res_zip9,
    res_zip5,
    res_match_type,
    res_match_fallback,
    distance_km,
    distance_basis,
    enc_centroid_source,
    res_centroid_source
  )

n_with_distance <- sum(!is.na(enc_distance$distance_km))
message(glue(
  "  enc_distance: {nrow(enc_distance)} rows, {n_with_distance} with non-NA distance_km"
))
message(glue(
  "  distance_basis breakdown:\n",
  paste(
    utils::capture.output(print(table(enc_distance$distance_basis, useNA = "ifany"))),
    collapse = "\n"
  )
))

# NOTE: No output written in this plan (Plan 02). Output (xlsx + rds) is produced
# in Plan 03 (SECTION 8-12 of this script). enc_distance is left in memory.
message("=== SECTION 1-7 complete. enc_distance tibble ready for Plan 03 (SECTION 8-12). ===")
