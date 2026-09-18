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
#              data/reference/zip9_bg_centroid_crosswalk.parquet (ZIP9 centroids;
#                the .csv is used only when the parquet twin is absent)
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
# Usage:       sbatch slurm/122_encounter_distance.sbatch   (preferred)
#              Rscript R/122_encounter_distance.R            (compute node only)
#              Do NOT run interactively on a login/OnDemand session: the ~2M-row
#              encounter pull and get_zip9_at_date() need a batch allocation.
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

# Phase 153: AM-rule-2/3 nearest-in-time patient ZIP calendar path.
# build_patient_zip_calendar() / pick_best_zip() / compute_encounter_distance()
# These replace the get_zip9_at_date() residence lookup in SECTION 4 with a
# bidirectional nearest-ZIP approach (DIST-02/DIST-03). get_zip9_at_date() is
# kept in utils_address.R for Phase 139/141 consumers -- it is NOT called here.
source("R/utils/utils_zip_calendar.R")
source("R/utils/utils_distance_hist.R")

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

# Per-section wall-clock timing so a slow step is identifiable from the SLURM log.
.t_section <- Sys.time()
section_done <- function(label) {
  el <- round(as.numeric(difftime(Sys.time(), .t_section, units = "mins")), 1)
  message(glue("  [{label}] done in {el} min"))
  .t_section <<- Sys.time()
  invisible(el)
}

# ==============================================================================
# SECTION 2: CONSTANTS AND PROBE GATES ----
# ==============================================================================

RUN_DATE     <- format(Sys.Date(), "%Y%m%d")
XLSX_ROW_CAP <- 1000000L   # Excel hard limit is 1,048,576 rows/sheet; A sheet is capped below it
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

bg_parquet <- sub("\\.csv$", ".parquet", bg_path)
message(glue("  [ZIP9 crosswalk] Checking: {bg_path} (or .parquet twin)"))
if (file.exists(bg_parquet)) {
  message("  [ZIP9 crosswalk] parquet found -- ZIP9 centroid resolution available (fast path)")
  ZIP9_CROSSWALK_AVAILABLE <- TRUE
} else if (file.exists(bg_path)) {
  message("  [ZIP9 crosswalk] csv found (no parquet twin) -- ZIP9 available via read_csv; ",
          "rerun R/122a to create the parquet for faster lookups")
  ZIP9_CROSSWALK_AVAILABLE <- TRUE
} else {
  message("  [ZIP9 crosswalk] NOT FOUND")
  warning(
    "[R/122] zip9_bg_centroid_crosswalk.csv not found. ",
    "Build it with R/122a_build_zip9_centroid_crosswalk.R (Plan 00) from the ADI ZIP9 parquet ",
    "under /blue/erin.mobley-hl.bcu/ADI/ before running the ZIP9 centroid path. ",
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
section_done("SECTION 2 probe gates")

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
  dplyr::select(ID, ENCOUNTERID, ADMIT_DATE, ENC_TYPE, enc_zip_raw = FACILITY_LOCATION) %>%
  dplyr::collect() %>%
  dplyr::mutate(ADMIT_DATE = parse_pcornet_date(ADMIT_DATE)) %>%
  dplyr::filter(!is.na(ADMIT_DATE))

n_enc_admit_missing <- n_enc_cohort_raw - nrow(encounters_raw)
message(glue(
  "  After ADMIT_DATE filters: {nrow(encounters_raw)} encounters for ",
  "{dplyr::n_distinct(encounters_raw$ID)} patients ",
  "({n_enc_admit_missing} dropped for missing/unparseable ADMIT_DATE)"
))

section_done("SECTION 3 encounter pull")

# ==============================================================================
# SECTION 4: RESIDENCE ZIP RESOLUTION (Phase 153: calendar + compute_encounter_distance) ----
# ==============================================================================

message("--- Building patient ZIP calendar from LDS_ADDRESS_HISTORY ---")

# Load LDS_ADDRESS_HISTORY restricted to COHORT_IDS for performance.
# Use vroom with all-character col_types (same as utils_address.R's get_zip9_at_date).
addr_raw <- vroom::vroom(
  file.path(CONFIG$data_dir, "LDS_ADDRESS_HISTORY_Mailhot_V1.csv"),
  col_types = vroom::cols(.default = "c"),
  show_col_types = FALSE
) %>%
  dplyr::filter(as.character(ID) %in% as.character(COHORT_IDS))

message(glue("  addr_raw: {nrow(addr_raw)} address records for {dplyr::n_distinct(addr_raw$ID)} patients"))

# Build the patient ZIP calendar (one row per (ID, ZIP, period)).
# Sentinel and NA ZIP5 rows excluded; open periods closed at 2025-03-31.
# NA-start and reversed periods are dropped with a message (see .drop_bad_periods()).
cal <- build_patient_zip_calendar(addr_raw)
message(glue("  cal: {nrow(cal)} calendar rows for {dplyr::n_distinct(cal$ID)} patients"))

# Compute zip5_facility inline (normalize the raw FACILITY_LOCATION column)
# so it is available before compute_encounter_distance(). SECTION 5 also runs
# the same normalization for enc_zip9 -- the columns are additive, not duplicated.
encounters_raw <- encounters_raw %>%
  dplyr::mutate(ID = as.character(ID))
COHORT_IDS <- as.character(COHORT_IDS)

enc_for_dist <- encounters_raw %>%
  dplyr::mutate(zip5_facility = normalize_zip5_raw(enc_zip_raw))

message("--- Computing encounter distances via compute_encounter_distance() ---")

dist_result <- compute_encounter_distance(enc_for_dist, cal)

message(glue(
  "  dist_result: {nrow(dist_result)} rows; distance_status breakdown:\n",
  paste(
    utils::capture.output(print(table(dist_result$distance_status, useNA = "ifany"))),
    collapse = "\n"
  )
))

message(glue(
  "  zip5_patient_source breakdown:\n",
  paste(
    utils::capture.output(print(table(dist_result$zip5_patient_source, useNA = "ifany"))),
    collapse = "\n"
  )
))

# Join dist_result back onto encounters_raw to restore one row per ENCOUNTERID.
# NEVER cbind -- use a keyed join (Pitfall 2).
stopifnot(
  "encounters_raw has duplicate (ID, ENCOUNTERID)" =
    !anyDuplicated(encounters_raw[c("ID", "ENCOUNTERID")]),
  "dist_result has duplicate (ID, ENCOUNTERID)" =
    !anyDuplicated(dist_result[c("ID", "ENCOUNTERID")]),
  "dist_result still carries ADMIT_DATE -- apply utils_zip_calendar.R fix A5" =
    !"ADMIT_DATE" %in% names(dist_result)
)
encounters <- encounters_raw %>%
  dplyr::left_join(dist_result, by = c("ID", "ENCOUNTERID"))

# Fan-out assertion: the join must never increase the row count.
stopifnot(
  "compute_encounter_distance join fanned out -- review join keys" =
    nrow(encounters) == nrow(encounters_raw)
)

message(glue(
  "  encounters after join: {nrow(encounters)} rows (matches encounters_raw: {nrow(encounters_raw)})"
))

section_done("SECTION 4 residence ZIP (patient ZIP calendar + compute_encounter_distance)")

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

section_done("SECTION 5 ZIP normalization")

# ==============================================================================
# SECTION 6: CENTROID RESOLUTION ----
# ==============================================================================

message("--- Resolving centroids (encounter side + residence side) ---")
# get_zip_centroid() is fully vectorized (distinct keys internally; ONE DuckDB query
# per call for ZIP9). Four calls total below -- never per element, never in a loop.

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
  stopifnot("get_zip_centroid(zip9) row count != input length (enc side)" =
              nrow(enc_zip9_lookup) == sum(enc_has_zip9))

  # Resolve ZIP5 centroids for encounters that lack ZIP9.
  enc_has_zip5_only <- !enc_has_zip9 & !is.na(enc_zip5_vals)
  enc_zip5_lookup   <- if (any(enc_has_zip5_only)) {
    get_zip_centroid(enc_zip5_vals[enc_has_zip5_only], level = "zip5")
  } else {
    tibble(zip = character(), level = character(),
           lat = double(), lon = double(), centroid_source = character())
  }
  stopifnot("get_zip_centroid(zip5) row count != input length (enc side)" =
              nrow(enc_zip5_lookup) == sum(enc_has_zip5_only))

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
  # Phase 153: zip9_patient / zip5_patient come from compute_encounter_distance()
  # (dist_result joined in SECTION 4); res_zip9/res_zip5 no longer exist.
  res_zip9_vals <- encounters$zip9_patient
  res_zip5_vals <- encounters$zip5_patient

  res_has_zip9     <- !is.na(res_zip9_vals)
  res_zip9_lookup  <- if (any(res_has_zip9)) {
    get_zip_centroid(res_zip9_vals[res_has_zip9], level = "zip9")
  } else {
    tibble(zip = character(), level = character(),
           lat = double(), lon = double(), centroid_source = character())
  }
  stopifnot("get_zip_centroid(zip9) row count != input length (res side)" =
              nrow(res_zip9_lookup) == sum(res_has_zip9))

  res_has_zip5_only <- !res_has_zip9 & !is.na(res_zip5_vals)
  res_zip5_lookup   <- if (any(res_has_zip5_only)) {
    get_zip_centroid(res_zip5_vals[res_has_zip5_only], level = "zip5")
  } else {
    tibble(zip = character(), level = character(),
           lat = double(), lon = double(), centroid_source = character())
  }
  stopifnot("get_zip_centroid(zip5) row count != input length (res side)" =
              nrow(res_zip5_lookup) == sum(res_has_zip5_only))

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
  res_zip5_eff <- dplyr::coalesce(encounters$zip5_patient,
                                   substr(as.character(encounters$zip9_patient), 1, 5))

  enc_has_zip5 <- !is.na(enc_zip5_eff)
  enc_zip5_lookup <- if (any(enc_has_zip5)) {
    get_zip_centroid(enc_zip5_eff[enc_has_zip5], level = "zip5")
  } else {
    tibble(zip = character(), level = character(),
           lat = double(), lon = double(), centroid_source = character())
  }
  stopifnot("get_zip_centroid(zip5) row count != input length (enc side, ZIP5-only path)" =
              nrow(enc_zip5_lookup) == sum(enc_has_zip5))

  res_has_zip5 <- !is.na(res_zip5_eff)
  res_zip5_lookup <- if (any(res_has_zip5)) {
    get_zip_centroid(res_zip5_eff[res_has_zip5], level = "zip5")
  } else {
    tibble(zip = character(), level = character(),
           lat = double(), lon = double(), centroid_source = character())
  }
  stopifnot("get_zip_centroid(zip5) row count != input length (res side, ZIP5-only path)" =
              nrow(res_zip5_lookup) == sum(res_has_zip5))

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

section_done("SECTION 6 centroid resolution")

# ==============================================================================
# SECTION 7: DISTANCE COMPUTATION ----
# ==============================================================================

message("--- Computing haversine distance ---")

encounters <- encounters %>%
  dplyr::mutate(
    # Phase 153: zipcodeR distance_km from compute_encounter_distance() is canonical
    # (D-01 from Phase 152 milestone). Haversine distance is computed for reference
    # and for distance_basis (enc/res centroid tier) but is NOT the authoritative distance.
    distance_km_haversine = haversine_km(enc_lat, enc_lon, res_lat, res_lon),
    distance_basis = dplyr::case_when(
      enc_level == "zip9" & res_level == "zip9" ~ "zip9-zip9",
      enc_level == "zip9" & res_level == "zip5" ~ "zip9-zip5",
      enc_level == "zip5" & res_level == "zip9" ~ "zip5-zip9",
      enc_level == "zip5" & res_level == "zip5" ~ "zip5-zip5",
      TRUE                                       ~ NA_character_
    )
  )

# Assemble the encounter-level tibble.
# Phase 153: distance_km / distance_status / distance_mi come from
# compute_encounter_distance() (zipcodeR, canonical per D-01 from Phase 152 milestone).
# The haversine distance_km computed above is retained as distance_km_haversine for
# reference and for sheets that depend on enc/res centroid columns, but is NOT the
# authoritative distance reported to Erin/Amy.
# enc_zip_norm = finest normalized encounter ZIP (ZIP9 preferred, ZIP5 fallback).
enc_distance <- encounters %>%
  dplyr::mutate(
    enc_zip_norm = dplyr::coalesce(enc_zip9, enc_zip5)
    # Note: distance_km_haversine is already in encounters from SECTION 7;
    # distance_km (zipcodeR, canonical per D-01) comes from dist_result via SECTION 4 join.
  ) %>%
  dplyr::select(
    ID,
    ENCOUNTERID,
    ADMIT_DATE,
    ENC_TYPE,
    enc_zip_norm,
    zip5_facility,
    zip9_patient,
    zip5_patient,
    zip5_patient_source,
    days_offset,
    n_candidates_in_range,
    distance_mi,
    distance_km,
    distance_km_haversine,
    distance_status,
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

section_done("SECTION 7 distance")

# ==============================================================================
# SECTION 8: PATIENT SUMMARY (B_patient_summary) ----
# ==============================================================================

message("--- Building B_patient_summary ---")

# Per D-03: nearest-fill encounters (zip5_patient_source nearest-*) ARE included.
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

# Both 200 km (primary) and 50 km (secondary) thresholds represented (reference thresholds; the reportable cutoff is D-06, pending).
# Filter to > 50 km (secondary threshold captures > 200 km subset as well).
D_flags <- enc_distance %>%
  dplyr::filter(distance_km > 50) %>%
  dplyr::mutate(
    flag_gt200 = distance_km > 200
  ) %>%
  dplyr::select(
    ID, ENCOUNTERID, ADMIT_DATE,
    enc_zip_norm, zip5_facility,
    zip9_patient, zip5_patient,
    zip5_patient_source, days_offset,
    distance_mi, distance_km, distance_status, distance_basis,
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

# ---- Completeness waterfall (Phase 153: distance_status-based) ----
# Five-step waterfall keyed on distance_status from compute_encounter_distance().
# Each step is independently counted (not derived by subtraction) so a row-for-row
# reconciliation stopifnot can verify consistency.
n_admit_date_usable     <- nrow(encounters_raw)
n_with_facility_zip     <- sum(!is.na(enc_distance$zip5_facility))
n_with_in_range_patient <- sum(
  enc_distance$zip5_patient_source %in% c("in_range_zip9", "in_range_zip5"),
  na.rm = TRUE
)
n_with_nearest_patient  <- sum(
  enc_distance$zip5_patient_source %in% c("nearest_zip9", "nearest_zip5"),
  na.rm = TRUE
)
n_distance_computed     <- sum(enc_distance$distance_status == "computed", na.rm = TRUE)

# Independent per-status counts (used in row-for-row reconciliation stopifnot).
n_facility_missing  <- sum(enc_distance$distance_status == "facility_zip_missing", na.rm = TRUE)
n_patient_missing   <- sum(enc_distance$distance_status == "patient_zip_missing",  na.rm = TRUE)
n_zip_not_in_db     <- sum(enc_distance$distance_status == "zip_not_in_db",        na.rm = TRUE)
n_status_computed   <- sum(enc_distance$distance_status == "computed",              na.rm = TRUE)

# Row-for-row reconciliation: four independent status counts must sum to nrow(enc_distance).
# distance_status always has one of the four values (no NA expected; assert here).
stopifnot(
  "waterfall does not reconcile with distance_status counts" =
    n_status_computed == n_distance_computed,
  "distance_status categories do not sum to nrow(enc_distance)" =
    nrow(enc_distance) == (n_facility_missing + n_patient_missing +
                           n_zip_not_in_db    + n_status_computed),
  "n_admit_date_usable does not equal nrow(enc_distance)" =
    n_admit_date_usable == nrow(enc_distance)
)

completeness_tbl <- tibble::tibble(
  Step = c(
    "n_encounters_total (raw DuckDB cohort ENCOUNTER, before date filter)",
    "n_admit_date_usable (ADMIT_DATE non-missing and parseable)",
    "n_with_facility_zip (zip5_facility non-NA; facility_zip_missing otherwise)",
    "n_with_in_range_patient_zip (zip5_patient_source in_range_zip9 or in_range_zip5)",
    "n_with_nearest_patient_zip (zip5_patient_source nearest_zip9 or nearest_zip5)",
    "n_distance_computed (distance_status == 'computed')"
  ),
  N = c(
    n_enc_cohort_raw,
    n_admit_date_usable,
    n_with_facility_zip,
    n_with_in_range_patient,
    n_with_nearest_patient,
    n_distance_computed
  ),
  Drop_from_prior = c(
    NA_integer_,
    n_enc_cohort_raw - n_admit_date_usable,
    n_admit_date_usable - n_with_facility_zip,
    NA_integer_,   # in-range and nearest are parallel fill paths, not sequential drops
    NA_integer_,
    NA_integer_
  )
)

# Status breakdown table to accompany the waterfall.
status_breakdown_tbl <- tibble::tibble(
  distance_status = c(
    "computed", "facility_zip_missing", "patient_zip_missing", "zip_not_in_db"
  ),
  N = c(n_status_computed, n_facility_missing, n_patient_missing, n_zip_not_in_db)
)

# ---- Standard QC waterfall (encounter ZIP side) ----
n_enc_norm_zip          <- sum(!is.na(enc_distance$enc_zip_norm))
n_centroid_resolved     <- sum(
  !is.na(enc_distance$enc_centroid_source) & !is.na(enc_distance$res_centroid_source)
)

waterfall_tbl <- tibble::tibble(
  Step = c(
    "n_encounters_total (raw DuckDB cohort ENCOUNTER, before date filter)",
    "n_admit_date_usable (ADMIT_DATE non-missing and parseable)",
    "n_enc_norm_zip (enc_zip_norm non-NA)",
    "n_centroid_resolved (both enc+res centroids non-NA)",
    "n_distance_computed (distance_status == 'computed')"
  ),
  N = c(
    n_enc_cohort_raw,
    n_admit_date_usable,
    n_enc_norm_zip,
    n_centroid_resolved,
    n_distance_computed
  ),
  Drop_from_prior = c(
    NA_integer_,
    n_enc_cohort_raw - n_admit_date_usable,
    n_admit_date_usable - n_enc_norm_zip,
    n_enc_norm_zip - n_centroid_resolved,
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
# Phase 153: res_zip9/res_zip5 replaced by zip9_patient/zip5_patient.
unmatched_zip9 <- enc_distance %>%
  dplyr::filter(
    enc_centroid_source == "zip5_fallback" | res_centroid_source == "zip5_fallback"
  ) %>%
  dplyr::mutate(
    unmatched_zip = dplyr::case_when(
      enc_centroid_source == "zip5_fallback" ~ enc_zip_norm,
      res_centroid_source == "zip5_fallback" ~ dplyr::coalesce(zip9_patient, zip5_patient),
      TRUE                                   ~ NA_character_
    ),
    zip3 = substr(unmatched_zip, 1, 3)
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

# ---- Nearest-fill sensitivity row: distances from nearest-* fills only ----
# Phase 153: res_match_fallback replaced by zip5_patient_source nearest-* fills.
nearest_distances <- enc_distance %>%
  dplyr::filter(
    zip5_patient_source %in% c("nearest_zip9", "nearest_zip5"),
    !is.na(distance_km)
  )
nearest_median <- if (nrow(nearest_distances) == 0) NA_real_ else
  median(nearest_distances$distance_km)
nearest_max <- if (nrow(nearest_distances) == 0) NA_real_ else
  max(nearest_distances$distance_km)

# Days offset distribution for nearest-* fills (QC: how far from the encounter date?).
nearest_offset_summary <- if (nrow(nearest_distances) > 0) {
  q <- quantile(abs(nearest_distances$days_offset), probs = c(0.25, 0.5, 0.75), na.rm = TRUE)
  glue::glue(
    "n={nrow(nearest_distances)} nearest fills; |days_offset| p25={q[1]}, p50={q[2]}, p75={q[3]}, ",
    "min={min(abs(nearest_distances$days_offset), na.rm=TRUE)}, ",
    "max={max(abs(nearest_distances$days_offset), na.rm=TRUE)}"
  )
} else {
  "no nearest-* fills"
}

# ---- n_candidates_in_range > 1 QC count ----
n_candidates_gt1 <- sum(enc_distance$n_candidates_in_range > 1, na.rm = TRUE)

# ---- Assemble full qc_tbl ----
qc_tbl <- dplyr::bind_rows(
  # Standard encounter-ZIP waterfall rows
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
  # Phase 153: n_candidates_in_range > 1 (patients with multiple ZIPs active on same date)
  tibble::tibble(
    Metric = "n_candidates_in_range > 1 (patients with multiple ZIPs active on same date)",
    Value  = as.numeric(n_candidates_gt1),
    Note   = "Encounters where the patient had >1 active address period covering ADMIT_DATE; pick_best_zip() selects ZIP9 > ZIP5 within Zone 1 (D-07)."
  ),
  # Phase 153: nearest-fill days_offset distribution (replaces Phase 152 fallback sensitivity)
  tibble::tibble(
    Metric = "NEAREST-FILL SENSITIVITY: zip5_patient_source nearest-* encounters",
    Value  = as.numeric(nrow(nearest_distances)),
    Note   = as.character(nearest_offset_summary)
  ),
  tibble::tibble(
    Metric = "NEAREST-FILL SENSITIVITY: nearest-fill distance_km",
    Value  = as.numeric(nearest_median),
    Note   = as.character(glue::glue(
      "median_km = {round(nearest_median, 1)}, max_km = {round(nearest_max, 1)}; ",
      "nearest fills are INCLUDED in B/C summaries (no address period covers ADMIT_DATE)"
    ))
  )
)

message(glue("  qc_tbl: {nrow(qc_tbl)} rows"))
message(glue(
  "  Waterfall: {n_enc_cohort_raw} total -> {n_admit_date_usable} admit-usable -> ",
  "{n_enc_norm_zip} norm-zip -> {n_centroid_resolved} centroid-resolved -> ",
  "{n_distance_computed} distance-computed"
))
message(glue(
  "  Completeness (distance_status): computed={n_status_computed}, ",
  "facility_missing={n_facility_missing}, patient_missing={n_patient_missing}, ",
  "zip_not_in_db={n_zip_not_in_db}; n_candidates_gt1={n_candidates_gt1}"
))

section_done("SECTIONS 8-11 summaries + QC")

# ==============================================================================
# add_styled_sheet() -- copied VERBATIM from R/115 lines 2126-2174 per this
# project's "copy, don't source" convention for this helper.
# Colors used by add_styled_sheet() -- kept adjacent to the function definition.
WHITE     <- wb_color(hex = "#FFFFFF")
DARK_TEXT <- wb_color(hex = "#1F2937")

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
  width_tbl <- if (is.null(extra_tbl)) data_tbl else extra_tbl
  wb$set_col_widths(sheet = sheet_name, cols = seq_len(max(n_cols, ncol(width_tbl))),
                    widths = "auto")
}

# ==============================================================================
# SECTION 12: HISTOGRAMS, PATIENT RDS, AND 6-SHEET XLSX (Phase 154) ----
# ==============================================================================

message("--- Phase 154: histogram PNGs, patient rds, 6-sheet xlsx ---")

# ---- 12.0 Facility-state join (for A_distribution_summary by_facility_state breakout) ----
# zipcodeR::zip_code_db is a data frame bundled with the package.
# Join on zip5_facility (character, 5-digit) to state.
zip_state_lkp <- zipcodeR::zip_code_db %>%
  dplyr::transmute(zipcode = as.character(zipcode), facility_state = state) %>%
  dplyr::distinct(zipcode, .keep_all = TRUE)

n_before_state_join <- nrow(enc_distance)
enc_distance <- enc_distance %>%
  dplyr::left_join(zip_state_lkp, by = c("zip5_facility" = "zipcode"))
stopifnot("facility-state join changed row count" = nrow(enc_distance) == n_before_state_join)

# ---- 12.0a Input invariants -- checked BEFORE any file is written ----
stopifnot(
  "computed status has missing distance_mi" =
    !any(enc_distance$distance_status == "computed" & is.na(enc_distance$distance_mi)),
  "non-computed status has non-missing distance_mi" =
    !any(enc_distance$distance_status != "computed" & !is.na(enc_distance$distance_mi)),
  "distance_mi has negative or non-finite values" =
    all(is.finite(enc_distance$distance_mi[!is.na(enc_distance$distance_mi)]) &
        enc_distance$distance_mi[!is.na(enc_distance$distance_mi)] >= 0),
  "nearest-fill rows contain days_offset == 0" =
    !any(enc_distance$zip5_patient_source %in% c("nearest_zip9", "nearest_zip5") &
         enc_distance$days_offset == 0, na.rm = TRUE)
)

# Single canonical definition used by every table, figure, and check below.
computed_rows <- enc_distance %>% dplyr::filter(distance_status == "computed")

cutoffs_mi <- if (!is.null(CONFIG$distance_candidate_cutoffs_mi)) {
  CONFIG$distance_candidate_cutoffs_mi
} else {
  c(30, 50)
}
stopifnot(
  "distance_candidate_cutoffs_mi must be finite, non-negative, unique numerics" =
    is.numeric(cutoffs_mi) && all(is.finite(cutoffs_mi)) && all(cutoffs_mi >= 0) &&
    !anyDuplicated(cutoffs_mi)
)

message(glue(
  "  facility_state join: {sum(!is.na(enc_distance$facility_state))} of ",
  "{nrow(enc_distance)} rows matched a state ({sum(is.na(enc_distance$facility_state))} unmatched)"
))

# ---- 12.2 A_distribution_summary via summarise_distance() ----
# breakout column identifies which slice: "overall", "year_<YYYY>", "enc_type_<X>", "state_<XX>"
A_distribution_summary <- dplyr::bind_rows(
  summarise_distance(enc_distance, by = "overall"),
  summarise_distance(enc_distance, by = "year"),
  summarise_distance(enc_distance, by = "ENC_TYPE"),
  summarise_distance(enc_distance, by = "facility_state")
)

message(glue("  A_distribution_summary: {nrow(A_distribution_summary)} rows"))

# ---- 12.3 D_fill_offsets ----
# Signed-integer bin distribution of days_offset for nearest-* fill rows.
# No [0] bin — nearest-fill rows are always nonzero by construction.
nearest_rows <- enc_distance %>%
  dplyr::filter(zip5_patient_source %in% c("nearest_zip9", "nearest_zip5"),
                !is.na(days_offset))

# 13 breaks -> 12 intervals, matching 12 labels. right = FALSE gives [-7,0) = -7..-1
# (past) and [0,7) = 1..6 (future); 0 itself never occurs for nearest fills.
fill_breaks <- c(-Inf, -365, -180, -90, -30, -7, 0, 7, 30, 90, 180, 365, Inf)
fill_labels <- c(
  "[-Inf,-365)", "[-365,-180)", "[-180,-90)", "[-90,-30)",
  "[-30,-7)", "[-7,0)", "[0,7)", "[7,30)",
  "[30,90)", "[90,180)", "[180,365)", "[365,+Inf)"
)
stopifnot(length(fill_breaks) - 1L == length(fill_labels))

D_fill_offsets_bins <- tibble::tibble(
  bin = fill_labels,
  n   = as.integer(table(cut(nearest_rows$days_offset,
                              breaks = fill_breaks,
                              labels = fill_labels,
                              right = FALSE,
                              include.lowest = FALSE)))
) %>%
  dplyr::mutate(pct = 100 * n / sum(n))

# Summary metrics go in a separate metric/value table (written via extra_tbl),
# not into the pct column of the bin table.
D_fill_offsets_summary <- tibble::tibble(
  metric = c("median_signed_offset_days", "median_abs_offset_days", "p90_abs_offset_days",
             "share_past_pct (days_offset > 0)", "share_future_pct (days_offset < 0)"),
  value  = if (nrow(nearest_rows) > 0) c(
    median(nearest_rows$days_offset),
    median(abs(nearest_rows$days_offset)),
    unname(quantile(abs(nearest_rows$days_offset), 0.90)),
    100 * mean(nearest_rows$days_offset > 0),
    100 * mean(nearest_rows$days_offset < 0)
  ) else rep(NA_real_, 5)
)

D_fill_offsets <- D_fill_offsets_bins

message(glue(
  "  D_fill_offsets: {nrow(nearest_rows)} nearest-fill rows; ",
  "{nrow(D_fill_offsets_bins)} bins"
))

# ---- 12.3a Completeness waterfall and status breakdown (C_completeness) ----
n_enc_total     <- nrow(enc_distance)
n_fac_zip       <- sum(!is.na(enc_distance$zip5_facility))
n_inrange_pat   <- sum(!is.na(enc_distance$zip5_facility) &
                       enc_distance$zip5_patient_source %in% c("in_range_zip9", "in_range_zip5"))
n_nearest_pat   <- sum(!is.na(enc_distance$zip5_facility) &
                       enc_distance$zip5_patient_source %in% c("nearest_zip9", "nearest_zip5"))
n_computed      <- sum(enc_distance$distance_status == "computed")

completeness_tbl <- tibble::tibble(
  Step = c("Encounters (cohort)", "With facility ZIP5", "  of which in-range patient ZIP",
           "  of which nearest-fill patient ZIP", "Distance computed"),
  N    = c(n_enc_total, n_fac_zip, n_inrange_pat, n_nearest_pat, n_computed),
  Pct_of_total = round(100 * N / n_enc_total, 2)
)

status_breakdown_tbl <- enc_distance %>%
  dplyr::count(distance_status, name = "N") %>%
  dplyr::mutate(Pct = round(100 * N / sum(N), 2)) %>%
  dplyr::arrange(dplyr::desc(N))
stopifnot(sum(status_breakdown_tbl$N) == n_enc_total)

# ---- 12.4 Per-patient summary table (saved in 12.5c) ----
# One row per patient with any computed encounter.
# share_ge_<c> columns for each cutoff in CONFIG$distance_candidate_cutoffs_mi (default c(30, 50)).
# One grouped summarise; share_ge_<c> columns built from the cutoff vector.
share_exprs <- setNames(
  lapply(cutoffs_mi, function(cm) rlang::expr(mean(distance_mi >= !!cm))),
  paste0("share_ge_", cutoffs_mi)
)

distance_patient <- computed_rows %>%
  dplyr::group_by(ID) %>%
  dplyr::summarise(
    n_enc_computed = dplyr::n(),
    median_mi      = median(distance_mi),
    min_mi         = min(distance_mi),
    max_mi         = max(distance_mi),
    !!!share_exprs,
    .groups = "drop"
  )

message(glue("  distance_patient built: {nrow(distance_patient)} patients (saved after reconciliation)"))

# ---- 12.5 Table reconciliation stopifnot (nothing has been written yet) ----
n_A_overall <- A_distribution_summary %>%
  dplyr::filter(breakout == "overall") %>%
  dplyr::pull(n)

stopifnot(
  "A_distribution_summary overall n != nrow(computed_rows)" =
    n_A_overall == nrow(computed_rows),
  "distance_patient nrow != n_distinct(ID) among computed rows" =
    nrow(distance_patient) == dplyr::n_distinct(computed_rows$ID),
  "D_fill_offsets bin n != number of nearest-fill rows" =
    sum(D_fill_offsets_bins$n) == nrow(nearest_rows),
  "completeness_tbl 'Distance computed' != nrow(computed_rows)" =
    completeness_tbl$N[completeness_tbl$Step == "Distance computed"] == nrow(computed_rows)
)
message("  Table reconciliation stopifnot PASSED")

# ---- 12.5b Histogram PNGs via make_distance_histograms() (first files written) ----
# Returns list(bins = <tibble>, stats = <tibble>) where bins is B_histogram_bins content.
hist_result <- make_distance_histograms(
  dist         = enc_distance,
  out_dir      = CONFIG$output_dir,
  run_date     = RUN_DATE,
  cutoffs      = NULL,  # dotted candidate-cutoff lines are a Phase 155 addition (154-CONTEXT)
  linear_width = 10,    # 154-D7: chosen after the 2026-09-18 first run (median 15 mi, p90 196 mi)
  linear_cap   = 350    # 154-D7: keeps the Florida body readable; out-of-state mass goes to "350+"
)

message(glue(
  "  make_distance_histograms(): {nrow(hist_result$bins)} bin rows; ",
  "4 PNGs written to {file.path(CONFIG$output_dir, 'figures')}"
))

# Bin counts must contain every computed observation, at every level/scale.
n_pat_computed <- dplyr::n_distinct(computed_rows$ID)
for (lv in c("encounter", "patient")) {
  for (sc in c("linear", "log")) {
    n_bins <- sum(hist_result$bins$n[hist_result$bins$level == lv & hist_result$bins$scale == sc])
    n_expect <- if (lv == "encounter") nrow(computed_rows) else n_pat_computed
    if (n_bins != n_expect) stop(sprintf("bin count mismatch: %s/%s has %d, expected %d", lv, sc, n_bins, n_expect))
  }
}
n_hist_enc_stats <- hist_result$stats %>% dplyr::filter(level == "encounter") %>% dplyr::pull(n)
stopifnot("make_distance_histograms() encounter stats$n != nrow(computed_rows)" =
            n_hist_enc_stats == nrow(computed_rows))
message("  histogram bin-count reconciliation PASSED")

# ---- 12.5b-ii Long-distance tail tabulation (>= linear_cap) for AM §4 Observed Issues ----
zip_state_pat <- zipcodeR::zip_code_db %>%
  dplyr::transmute(zipcode = as.character(zipcode), patient_state = state) %>%
  dplyr::distinct(zipcode, .keep_all = TRUE)

tail_rows <- computed_rows %>%
  dplyr::filter(distance_mi >= 350) %>%
  dplyr::left_join(zip_state_pat, by = c("zip5_patient" = "zipcode"))

tail_by_state <- tail_rows %>%
  dplyr::count(patient_state, facility_state, name = "N") %>%
  dplyr::arrange(dplyr::desc(N)) %>%
  dplyr::mutate(Pct_of_tail = round(100 * N / sum(N), 2)) %>%
  dplyr::slice_head(n = 25)

tail_by_patient_zip <- tail_rows %>%
  dplyr::count(zip5_patient, patient_state, name = "N") %>%
  dplyr::arrange(dplyr::desc(N)) %>%
  dplyr::slice_head(n = 20)

message(glue("  tail >= 350 mi: {nrow(tail_rows)} encounters ({round(100 * nrow(tail_rows) / nrow(computed_rows), 2)}% of computed)"))

# ---- 12.5c Per-patient rds write ----
OUTPUT_PATIENT_RDS <- file.path(CONFIG$output_dir,
                                 glue("distance_patient_{RUN_DATE}.rds"))
saveRDS(distance_patient, OUTPUT_PATIENT_RDS)
message(glue(
  "  distance_patient rds written: {OUTPUT_PATIENT_RDS} ({nrow(distance_patient)} patients)"
))

# ---- 12.6 encounter_distance rds (full table, before xlsx) ----
# OUTPUT_RDS is defined in the constants block near the top of the script.
saveRDS(enc_distance, OUTPUT_RDS)
message(glue("  rds written: {OUTPUT_RDS} ({nrow(enc_distance)} rows, full encounter-level table)"))

# ---- 12.7 Updated KEY sheet data (6-sheet spec) ----
key_tbl <- tibble::tibble(
  Field = c(
    "Script",
    "Phase",
    "Run date",
    "Cohort",
    "Encounter ZIP source",
    "Residence ZIP source",
    "Distance method",
    "Histogram PNGs",
    "Patient rds",
    "A_distribution_summary breakouts",
    "A_distribution_summary statistics",
    "B_histogram_bins columns",
    "C_completeness waterfall",
    "D_fill_offsets scope",
    "QC sheet contents"
  ),
  Description = c(
    "R/122_encounter_distance.R",
    "Phase 154 — distribution and histogram deliverable",
    RUN_DATE,
    glue("HL cohort (N = {length(COHORT_IDS)}), IDs from DuckDB via CONFIG"),
    "FACILITY_LOCATION column in PCORnet CDM ENCOUNTER table",
    "LDS_ADDRESS_HISTORY via build_patient_zip_calendar() + compute_encounter_distance() (Phase 153 bidirectional nearest-in-time ZIP5)",
    "zipcodeR::zip_distance() (miles); canonical per D-01 from Phase 152 milestone. No km in this deliverable (154-D3).",
    glue("4 PNGs in {file.path(CONFIG$output_dir, 'figures')}: encounter_distance_hist_{{level}}_{{scale}}_{RUN_DATE}.png for level in (encounter, patient), scale in (linear, log)"),
    glue("distance_patient_{RUN_DATE}.rds: one row per patient with any computed encounter; columns: ID, n_enc_computed, median_mi, min_mi, max_mi, share_ge_<c> for c in ({paste(cutoffs_mi, collapse=', ')})"),
    "overall | year_<YYYY> (by ADMIT_DATE year) | enc_type_<X> (by ENC_TYPE) | state_<XX> (by facility_state from zipcodeR::zip_code_db)",
    "n, median_mi, IQR_mi, p90_mi, p95_mi, p99_mi, max_mi — all in miles (154-D3); no mean/SD",
    "level, scale, bin, lower, upper, lower_mi, upper_mi, n, pct. Linear: 10-mile bins to 350, then [350, Inf). Log: first bin [0,1) mi (includes same-ZIP zeros), then quarter-decade bins on log10(mi); lower/upper are in log10(mi) units for log rows (first bin lower = -0.25), lower_mi/upper_mi are in miles for all rows.",
    "Five-step waterfall keyed on distance_status (encounters → facility ZIP → in-range patient ZIP → nearest patient ZIP → distance computed)",
    "Nearest-* fill rows (zip5_patient_source in nearest_zip9, nearest_zip5) only; signed-integer bins. SIGN: positive days_offset = address period ended BEFORE the encounter (past); negative = period began AFTER (future). 0 never occurs.",
    "Coverage waterfall; n_candidates_in_range>1; nearest-fill offset distribution; unmatched ZIP9 by state; zip9_crosswalk_present flag"
  )
)

# ---- 12.8 Build 6-sheet workbook ----
message("--- Writing 6-sheet xlsx (Phase 154 spec) ---")

wb <- wb_workbook()

add_styled_sheet(
  wb, "KEY",
  "Phase 154: Encounter Distance — Workbook KEY",
  glue("Run date: {RUN_DATE} | Cohort: HL (N={length(COHORT_IDS)}) | Script: R/122_encounter_distance.R"),
  key_tbl
)

add_styled_sheet(
  wb, "A_distribution_summary",
  "A: Distance Distribution Summary",
  "Rows stacked by breakout: overall, by year (ADMIT_DATE), by ENC_TYPE, by facility state. Miles only (154-D3).",
  A_distribution_summary
)

add_styled_sheet(
  wb, "B_histogram_bins",
  "B: Histogram Bin Counts",
  "Output of make_distance_histograms(): level (encounter/patient), scale (linear/log), bin edges in raw and mile units, n, pct.",
  hist_result$bins
)

add_styled_sheet(
  wb, "C_completeness",
  "C: Completeness Waterfall",
  "Five-step waterfall keyed on distance_status from compute_encounter_distance() (Phase 153).",
  completeness_tbl,
  extra_tbl   = status_breakdown_tbl,
  extra_label = "distance_status breakdown (row-for-row reconciles to nrow(enc_distance))"
)

add_styled_sheet(
  wb, "D_fill_offsets",
  "D: Nearest-Fill Days-Offset Distribution",
  "Signed-integer bins of days_offset for zip5_patient_source in {nearest_zip9, nearest_zip5}. Positive = period ended before the encounter (past); negative = period began after (future). 0 never occurs.",
  D_fill_offsets,
  extra_tbl   = D_fill_offsets_summary,
  extra_label = "Summary metrics (days; shares in percent)"
)

add_styled_sheet(
  wb, "QC",
  "QC: Coverage Waterfall and Quality Checks",
  "Waterfall from raw cohort ENCOUNTER count to distance computed; nearest-fill days_offset distribution; n_candidates_in_range>1.",
  qc_tbl,
  extra_tbl   = dplyr::bind_rows(
    dplyr::mutate(unmatched_zip9_by_state, table = "unmatched_zip9_by_state", .before = 1),
    dplyr::mutate(tail_by_state,           table = "tail_ge_350mi_by_patient_x_facility_state", .before = 1),
    dplyr::mutate(tail_by_patient_zip,     table = "tail_ge_350mi_top20_patient_zip5", .before = 1)
  ),
  extra_label = "Supplementary tables (see 'table' column): unmatched ZIP9 by state; long-distance tail by state pair; top patient ZIP5s in the tail"
)

# OUTPUT_XLSX is defined in the constants block near the top of the script.
wb_save(wb, OUTPUT_XLSX)
message(glue("  xlsx written: {OUTPUT_XLSX} (6 sheets: KEY, A_distribution_summary, B_histogram_bins, C_completeness, D_fill_offsets, QC)"))
section_done("SECTION 12 Phase 154 outputs")

message("=== R/122_encounter_distance.R complete ===")
