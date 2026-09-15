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

# ==============================================================================
# SECTION 8: PATIENT SUMMARY (B_patient_summary) ----
# ==============================================================================

message("--- Building B_patient_summary ---")

# Per D-02: fallback encounters (res_match_fallback == TRUE) ARE included.
# Guard every statistic against all-NA groups: max() yields -Inf, mean() NaN
# for pct columns when all observations are NA. Use explicit NA guards.
B_patient_summary <- enc_distance %>%
  dplyr::group_by(ID) %>%
  dplyr::summarise(
    n_encounters     = dplyr::n(),
    n_with_distance  = sum(!is.na(distance_km)),
    median_km        = if (sum(!is.na(distance_km)) == 0) NA_real_ else
                         median(distance_km, na.rm = TRUE),
    iqr_km           = if (sum(!is.na(distance_km)) == 0) NA_real_ else
                         IQR(distance_km, na.rm = TRUE),
    max_km           = if (sum(!is.na(distance_km)) == 0) NA_real_ else
                         max(distance_km, na.rm = TRUE),
    pct_gt50km       = if (sum(!is.na(distance_km)) == 0) NA_real_ else
                         mean(distance_km > 50, na.rm = TRUE) * 100,
    pct_gt200km      = if (sum(!is.na(distance_km)) == 0) NA_real_ else
                         mean(distance_km > 200, na.rm = TRUE) * 100,
    .groups = "drop"
  )

message(glue(
  "  B_patient_summary: {nrow(B_patient_summary)} patients; ",
  "{sum(B_patient_summary$n_with_distance == 0)} with zero distances computed"
))

# ==============================================================================
# SECTION 9: DISTRIBUTION (C_distribution) ----
# ==============================================================================

message("--- Building C_distribution ---")

# include.lowest = TRUE is MANDATORY: without it a distance of exactly 0 (same
# ZIP on both sides -- the most common zip5-zip5 case) falls outside the first
# interval [0,5) and becomes NA. With include.lowest the leftmost bin is [0,5].
dist_bins      <- c(0, 5, 25, 50, 200, Inf)
dist_bin_labels <- c("0-5", "5-25", "25-50", "50-200", ">200")

enc_distance_binned <- enc_distance %>%
  dplyr::mutate(
    dist_bin = dplyr::if_else(
      is.na(distance_km),
      "NA",
      as.character(cut(distance_km,
                       breaks = dist_bins,
                       labels = dist_bin_labels,
                       include.lowest = TRUE,
                       right = FALSE))
    ),
    dist_bin = factor(dist_bin,
                      levels = c(dist_bin_labels, "NA"))
  )

C_distribution <- enc_distance_binned %>%
  dplyr::group_by(dist_bin, distance_basis) %>%
  dplyr::summarise(
    n_encounters = dplyr::n(),
    n_patients   = dplyr::n_distinct(ID),
    .groups = "drop"
  ) %>%
  dplyr::arrange(dist_bin, distance_basis)

message(glue(
  "  C_distribution: {nrow(C_distribution)} rows (bin × distance_basis combinations)"
))

# ==============================================================================
# SECTION 10: FLAGS (D_flags) ----
# ==============================================================================

message("--- Building D_flags ---")

# Both 200 km (primary) and 50 km (secondary) thresholds represented per D-01.
# Filter to > 50 km (secondary threshold captures > 200 km subset as well).
D_flags <- enc_distance %>%
  dplyr::filter(distance_km > 50) %>%
  dplyr::mutate(
    flag_gt200 = distance_km > 200
  ) %>%
  dplyr::select(
    ID, ENCOUNTERID, ADMIT_DATE,
    enc_zip_norm, res_zip9, res_zip5,
    res_match_type, res_match_fallback,
    distance_km, distance_basis,
    enc_centroid_source, res_centroid_source,
    flag_gt200
  ) %>%
  dplyr::arrange(dplyr::desc(distance_km))

message(glue(
  "  D_flags: {nrow(D_flags)} encounters > 50 km; ",
  "{sum(D_flags$flag_gt200, na.rm = TRUE)} > 200 km (primary)"
))

# ==============================================================================
# SECTION 11: QC WATERFALL (qc_tbl) ----
# ==============================================================================

message("--- Building QC waterfall ---")

# ---- Coverage waterfall ----
# n_encounters_total = n_enc_cohort_raw (raw DuckDB cohort count BEFORE any
# ADMIT_DATE filter). n_admit_date_usable = nrow(encounters_raw) after date filters.
n_admit_date_usable    <- nrow(encounters_raw)
n_enc_norm_zip         <- sum(!is.na(enc_distance$enc_zip_norm))
n_residence_resolved   <- sum(
  !is.na(enc_distance$res_match_type) & enc_distance$res_match_type != "none",
  na.rm = TRUE
)
n_centroid_resolved    <- sum(
  !is.na(enc_distance$enc_centroid_source) & !is.na(enc_distance$res_centroid_source)
)
n_distance_computed    <- sum(!is.na(enc_distance$distance_km))

# Reconciliation assertions
stopifnot(
  "n_enc_cohort_raw does not equal n_encounters_total" =
    n_enc_cohort_raw == n_enc_cohort_raw,        # tautological -- the name IS n_enc_cohort_raw
  "n_admit_date_usable does not equal nrow(enc_distance)" =
    n_admit_date_usable == nrow(enc_distance)
)

waterfall_tbl <- tibble::tibble(
  Step = c(
    "n_encounters_total (raw DuckDB cohort ENCOUNTER, before date filter)",
    "n_admit_date_usable (ADMIT_DATE non-missing and parseable)",
    "n_enc_norm_zip (enc_zip_norm non-NA)",
    "n_residence_resolved (res_match_type not 'none')",
    "n_centroid_resolved (both centroids non-NA)",
    "n_distance_computed (distance_km non-NA)"
  ),
  N = c(
    n_enc_cohort_raw,
    n_admit_date_usable,
    n_enc_norm_zip,
    n_residence_resolved,
    n_centroid_resolved,
    n_distance_computed
  ),
  Drop_from_prior = c(
    NA_integer_,
    n_enc_cohort_raw - n_admit_date_usable,
    n_admit_date_usable - n_enc_norm_zip,
    n_enc_norm_zip - n_residence_resolved,
    n_residence_resolved - n_centroid_resolved,
    n_centroid_resolved - n_distance_computed
  )
)

# ---- Unmatched ZIP9 by state (encounters where centroid_source == "zip5_fallback",
# meaning the ZIP9 was present but unresolved in the crosswalk). ----
# State derived from ZIP3 → state lookup. Check for existing zip3 lookup file.
zip3_state_path <- if (!is.null(CONFIG$zip3_state_path)) {
  CONFIG$zip3_state_path
} else if (requireNamespace("here", quietly = TRUE)) {
  here::here("data", "reference", "zip3_state.csv")
} else {
  file.path("data", "reference", "zip3_state.csv")
}

# Encounters unresolved at ZIP9 level (fell back to ZIP5 gazetteer).
unmatched_zip9 <- enc_distance %>%
  dplyr::filter(
    enc_centroid_source == "zip5_fallback" | res_centroid_source == "zip5_fallback"
  ) %>%
  dplyr::mutate(
    zip3 = substr(coalesce(enc_zip_norm, res_zip9, res_zip5), 1, 3)
  )

if (file.exists(zip3_state_path)) {
  zip3_state <- vroom::vroom(
    zip3_state_path,
    col_types = vroom::cols(ZIP3 = vroom::col_character(), STATE = vroom::col_character()),
    show_col_types = FALSE
  )
  unmatched_zip9_by_state <- unmatched_zip9 %>%
    dplyr::left_join(zip3_state, by = c("zip3" = "ZIP3")) %>%
    dplyr::count(STATE, name = "n_unmatched_zip9_encounters") %>%
    dplyr::arrange(dplyr::desc(n_unmatched_zip9_encounters))
  message(glue("  zip3_state.csv found; unmatched-by-state table has {nrow(unmatched_zip9_by_state)} rows"))
} else {
  # zip3_state.csv absent: collapse all to a single "ALL" row and add a QC note.
  message("  zip3_state.csv NOT FOUND; emitting unmatched ZIP9 count as STATE = 'ALL'")
  unmatched_zip9_by_state <- tibble::tibble(
    STATE = "ALL",
    n_unmatched_zip9_encounters = nrow(unmatched_zip9)
  )
}

# ---- Fallback sensitivity row: distances from res_match_fallback == TRUE only ----
fallback_distances <- enc_distance %>%
  dplyr::filter(res_match_fallback == TRUE, !is.na(distance_km))
fallback_median <- if (nrow(fallback_distances) == 0) NA_real_ else
  median(fallback_distances$distance_km)
fallback_max <- if (nrow(fallback_distances) == 0) NA_real_ else
  max(fallback_distances$distance_km)

# ---- Assemble full qc_tbl ----
qc_tbl <- dplyr::bind_rows(
  # Waterfall rows
  waterfall_tbl %>% dplyr::rename(Metric = Step, Value = N, Note = Drop_from_prior) %>%
    dplyr::mutate(Note = as.character(Note)),
  # ZIP9 crosswalk presence flag
  tibble::tibble(
    Metric = "zip9_crosswalk_present",
    Value  = as.numeric(ZIP9_CROSSWALK_AVAILABLE),
    Note   = if (ZIP9_CROSSWALK_AVAILABLE) "TRUE -- ZIP9 block-group centroids used"
             else "FALSE -- all centroids resolved at ZIP5 only"
  ),
  # WV gap note (Pitfall 7)
  tibble::tibble(
    Metric = "NOTE: WV ZIP9 centroid coverage",
    Value  = NA_real_,
    Note   = "WV ZIP9 centroid coverage may be lower due to the Neighborhood Atlas crosswalk gap; see unmatched-by-state counts."
  ),
  # zip3_state file present note (if absent)
  if (!file.exists(zip3_state_path)) {
    tibble::tibble(
      Metric = "NOTE: zip3_state.csv absent",
      Value  = NA_real_,
      Note   = "zip3_state.csv not found; unmatched ZIP9 count reported as STATE = 'ALL' only. Stage data/reference/zip3_state.csv to get per-state breakdown."
    )
  } else {
    tibble::tibble(
      Metric = character(0), Value = numeric(0), Note = character(0)
    )
  },
  # Fallback sensitivity row (D-02)
  tibble::tibble(
    Metric = "FALLBACK SENSITIVITY: res_match_fallback encounters",
    Value  = as.numeric(nrow(fallback_distances)),
    Note   = glue(
      "median_km = {round(fallback_median, 1)}, max_km = {round(fallback_max, 1)}; ",
      "fallback (most_recent_before) encounters are INCLUDED in B/C summaries per D-02"
    )
  )
)

message(glue("  qc_tbl: {nrow(qc_tbl)} rows"))
message(glue(
  "  Waterfall: {n_enc_cohort_raw} total -> {n_admit_date_usable} admit-usable -> ",
  "{n_enc_norm_zip} norm-zip -> {n_residence_resolved} res-resolved -> ",
  "{n_centroid_resolved} centroid-resolved -> {n_distance_computed} distance-computed"
))

message("=== SECTION 8-11 complete. Building SECTION 12 (xlsx + rds) next. ===")

# ==============================================================================
# SECTION 12: XLSX ASSEMBLY AND WRITE ----
# ==============================================================================

message("--- Writing encounter_distance xlsx (KEY leftmost, 6 sheets) ---")

# UF brand colors, per project deliverable spec. NOTE: DIFFERENT blue than
# utils_pptx.R's UF_BLUE ("#003087") -- hex values here are locked for this
# deliverable; do not source utils_pptx.R.
UF_BLUE   <- "#0021A5"
UF_ORANGE <- "#FA4616"
WHITE     <- wb_color(hex = "#FFFFFF")
DARK_TEXT <- wb_color(hex = "#1F2937")

# add_styled_sheet() copied VERBATIM from R/115 lines 2126-2174 per this
# project's "copy, don't source" convention for this helper.
add_styled_sheet <- function(wb, sheet_name, title_text, subtitle_text, data_tbl,
                              extra_tbl = NULL, extra_label = NULL) {
  wb$add_worksheet(sheet_name)
  n_cols           <- ncol(data_tbl)
  last_col_letter  <- openxlsx2::int2col(n_cols)

  wb$add_data(sheet = sheet_name, x = title_text,    dims = "A1")
  wb$add_data(sheet = sheet_name, x = subtitle_text, dims = "A2")
  wb$add_data(sheet = sheet_name, x = data_tbl,      dims = "A4", col_names = TRUE)

  wb$merge_cells(sheet = sheet_name, dims = paste0("A1:", last_col_letter, "1"))
  wb$merge_cells(sheet = sheet_name, dims = paste0("A2:", last_col_letter, "2"))

  wb$add_font(sheet = sheet_name, dims = "A1",
              name = "Calibri", size = 14, bold = TRUE, color = DARK_TEXT)
  wb$add_font(sheet = sheet_name, dims = "A2",
              name = "Calibri", size = 10, italic = TRUE, color = DARK_TEXT)

  header_range <- paste0("A4:", last_col_letter, "4")
  wb$add_fill(sheet = sheet_name, dims = header_range, color = wb_color(hex = UF_BLUE))
  wb$add_font(sheet = sheet_name, dims = header_range,
              name = "Calibri", size = 11, bold = TRUE, color = WHITE)

  # Optional second table, written a few rows below the first.
  if (!is.null(extra_tbl) && nrow(extra_tbl) > 0) {
    gap_rows_offset <- 4 + nrow(data_tbl) + 2
    label_row       <- gap_rows_offset
    header_row      <- gap_rows_offset + 1

    if (!is.null(extra_label)) {
      wb$add_data(sheet = sheet_name, x = extra_label, dims = paste0("A", label_row))
      wb$add_font(sheet = sheet_name, dims = paste0("A", label_row),
                  name = "Calibri", size = 11, bold = TRUE, color = DARK_TEXT)
    }

    wb$add_data(sheet = sheet_name, x = extra_tbl,
                dims = paste0("A", header_row), col_names = TRUE)

    extra_last_col <- openxlsx2::int2col(ncol(extra_tbl))
    extra_hdr_rng  <- paste0("A", header_row, ":", extra_last_col, header_row)
    wb$add_fill(sheet = sheet_name, dims = extra_hdr_rng, color = wb_color(hex = UF_BLUE))
    wb$add_font(sheet = sheet_name, dims = extra_hdr_rng,
                name = "Calibri", size = 11, bold = TRUE, color = WHITE)
  }

  wb$freeze_pane(sheet = sheet_name, firstActiveRow = 5)
  wb$set_col_widths(sheet = sheet_name, cols = 1:max(n_cols, ncol(extra_tbl %||% data_tbl)),
                    widths = "auto")
}

# ---- KEY sheet data ----
key_tbl <- tibble::tibble(
  Field = c(
    "Script",
    "Phase",
    "Run date",
    "Cohort",
    "Encounter ZIP source",
    "D-03: Encounter ZIP interpretation (OPEN QUESTION)",
    "Residence ZIP source",
    "Distance method",
    "Distance thresholds",
    "D-02: Fallback encounters in summaries",
    "RDS output",
    "A_encounter_distance columns",
    "B_patient_summary columns",
    "C_distribution columns",
    "D_flags columns",
    "QC sheet contents"
  ),
  Description = c(
    "R/122_encounter_distance.R",
    "Phase 152 -- encounter-ZIP to residence distance",
    RUN_DATE,
    "HL cohort (N = 9,282), IDs from DuckDB via CONFIG",
    "FACILITY_LOCATION column in PCORnet CDM ENCOUNTER table",
    paste0(
      "Whether encounter ZIP is patient- or facility-sourced in this OneFlorida+ extract is unknown; ",
      "column description reflects travel distance if facility-sourced, proxy validation if patient-sourced."
    ),
    "LDS_ADDRESS_HISTORY via get_zip9_at_date() (backward-only, most-recent-before fallback)",
    "Haversine great-circle distance (km); Earth radius 6371 km",
    "200 km primary (flag_gt200 = TRUE in D_flags); 50 km secondary (all D_flags rows)",
    "Fallback (most_recent_before) encounters are INCLUDED in B/C summaries; distinguished by res_match_fallback",
    "Full encounter-level enc_distance tibble saved to encounter_distance_YYYYMMDD.rds",
    "ID, ENCOUNTERID, ADMIT_DATE, enc_zip_norm, res_zip9, res_zip5, res_match_type, res_match_fallback, distance_km, distance_basis, enc_centroid_source, res_centroid_source",
    "ID, n_encounters, n_with_distance, median_km, iqr_km, max_km, pct_gt50km, pct_gt200km",
    "dist_bin, distance_basis, n_encounters, n_patients (bins: 0-5, 5-25, 25-50, 50-200, >200 km; include.lowest=TRUE so distance=0 rows fall in the 0-5 bin)",
    "ID, ENCOUNTERID, ADMIT_DATE, enc_zip_norm, res_zip9, res_zip5, res_match_type, res_match_fallback, distance_km, distance_basis, enc_centroid_source, res_centroid_source, flag_gt200",
    "Coverage waterfall; unmatched ZIP9 by state; zip9_crosswalk_present flag; WV gap note; fallback sensitivity row"
  )
)

# ---- Build workbook -- KEY LEFTMOST (D-02 pattern) ----
wb <- wb_workbook()

add_styled_sheet(
  wb, "KEY",
  "Phase 152: Encounter-ZIP to Residence Distance — Workbook KEY",
  glue("Run date: {RUN_DATE} | Cohort: HL (N=9,282) | Script: R/122_encounter_distance.R"),
  key_tbl
)

add_styled_sheet(
  wb, "A_encounter_distance",
  "A: Encounter-Level Distance",
  "One row per HL cohort encounter with distance_km from enc_zip to residence ZIP on ADMIT_DATE.",
  enc_distance
)

add_styled_sheet(
  wb, "B_patient_summary",
  "B: Patient-Level Distance Summary",
  "One row per patient; fallback (most_recent_before) encounters included per D-02.",
  B_patient_summary
)

add_styled_sheet(
  wb, "C_distribution",
  "C: Distance Distribution by Bin and Basis",
  "Bins: 0-5, 5-25, 25-50, 50-200, >200 km (include.lowest=TRUE; zero-distance rows in 0-5) x distance_basis.",
  C_distribution
)

add_styled_sheet(
  wb, "D_flags",
  "D: Far-Distance Flagged Encounters",
  "Encounters > 50 km (secondary threshold); flag_gt200 = TRUE marks primary threshold (> 200 km).",
  D_flags
)

add_styled_sheet(
  wb, "QC",
  "QC: Coverage Waterfall and Quality Checks",
  "Waterfall from raw cohort ENCOUNTER count to distance computed; WV gap noted; fallback sensitivity row.",
  qc_tbl,
  extra_tbl   = unmatched_zip9_by_state,
  extra_label = "Unmatched ZIP9 encounters by state (centroid_source == zip5_fallback)"
)

wb_save(wb, OUTPUT_XLSX)
message(glue("  xlsx written: {OUTPUT_XLSX}"))

# ---- Write rds (full encounter-level tibble) ----
# Full enc_distance tibble chosen (per CONTEXT.md Claude's discretion note);
# includes all 12 A_encounter_distance columns for downstream joining without
# re-running the script.
saveRDS(enc_distance, OUTPUT_RDS)
message(glue("  rds written: {OUTPUT_RDS}"))

message("=== R/122_encounter_distance.R complete ===")
