# ==============================================================================
# 179_cbc_patient_year.R -- CBC receipt within each follow-up year (patient-year analysis)
# ==============================================================================
#
# Purpose:
#   Build a patient-year table for HL cohort members (anchored from R/147) and
#   assess whether patients living >100 mi from care are less likely to have a
#   CBC in each post-diagnosis follow-up year. This is the patient-year re-
#   specification of the Phase 165 encounter-level question.
#
#   Sections 0-3 (data assembly) are implemented here.
#   Plan 02 (R/179b) will add GEE modeling and workbook output.
#   Phase 180 reads the internal RDS written in Section 3.
#
# Inputs:
#   CONFIG$output_dir/surveillance_modality_patient_<date>.rds  (R/147 anchor RDS; D-02)
#   CONFIG$output_dir/encounter_distance_*.rds                  (R/122 enc_distance)
#   R/121 zip_problem_inventory_*.rds                           (triage)
#   DuckDB: LAB_RESULT_CM (CBC re-derive via build_cbc_events() + broad LOINCs)
#   DuckDB: DEATH (death dates; optional)
#   EXTRACT_DATE from R/00_config.R                             (CDM data cutoff; D-04)
#
# Outputs:
#   output/internal/cbc_patient_year_<YYYYMMDD>.rds  (one row per patient-year; D-17)
#
# Requirements: CBCY-01, CBCY-02, CBCY-03, CBCY-04, CBCY-05
#
# Decisions honored:
#   D-01: Year k = (anchor + 365*(k-1), anchor + 365*k], half-open, anchor day = pre
#   D-02: Anchor from R/147 surveillance_modality_patient RDS
#   D-03: Universe = ALL cohort patients with known hl_anchor_date
#   D-04: Fully observed year = year_end <= CDM cutoff AND patient alive at year_end
#   D-05: Primary CBC via build_cbc_events() as-is (no redefinition)
#   D-06: Broad hematology via 15-LOINC SQL push-down, no same-date requirement
#   D-07: Exposure = patient-level median post-anchor distance_mi (computed only)
#   D-08: exposure_missing = TRUE when no computed post-anchor encounter
#   D-09: far_year_median = per-year median distance; NA if no computed enc in year
#   D-17: RDS schema: ID, year_index, year_start, year_end, cbc_year, cbc_year_broad,
#         median_distance, far, far_year_median, exposure_missing, triage
#   D-18: Interactive R on HiPerGator: source("R/179_cbc_patient_year.R", local = new.env(...))
#   D-19: Registered in R/39 (one-off)
#
# Usage:
#   module load R/4.5
#   source("R/179_cbc_patient_year.R", local = new.env(parent = globalenv()))
#
# ==============================================================================

# ==============================================================================
# SECTION 0: SETUP ----
# ==============================================================================

source(here::here("R/00_config.R"))
# 00_config.R auto-sources utils_distance_cbc.R, utils_duckdb.R, utils_treatment.R.
# build_cbc_events(), suppress_small_vec(), suppress_display(), naive_or_se() available.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(geepack)
  library(openxlsx)
  library(glue)
})

RUN_DATE <- format(Sys.Date(), "%Y%m%d")

message(glue(
  "================================================================================\n",
  "R/179 cbc_patient_year -- RUN DATE {RUN_DATE}\n",
  "================================================================================"
))

# --- CONFIG-sourced analysis parameters ----------------------------------------

CUTOFF <- CONFIG$far_from_care_cutoff_mi
stopifnot(
  "CONFIG$far_from_care_cutoff_mi must be set (not NA)" = !is.na(CUTOFF),
  "CONFIG$far_from_care_cutoff_mi must be positive"     = is.numeric(CUTOFF) && CUTOFF > 0
)

GEE_CORSTR <- CONFIG$distance_gee_corstr
stopifnot(
  "CONFIG$distance_gee_corstr must be a non-empty string" =
    is.character(GEE_CORSTR) && nzchar(GEE_CORSTR)
)

# --- CDM data cutoff (D-04) ----------------------------------------------------
# Source: EXTRACT_DATE in R/00_config.R (line 85) — the PCORnet CDM data pull date
# (Mailhot_V1_20250915). This is the documented end-of-data boundary.
# No hard-coded fallback date; script stops if EXTRACT_DATE is not found or malformed.
stopifnot(
  "EXTRACT_DATE must exist in the sourced environment (R/00_config.R)" =
    exists("EXTRACT_DATE") && is.character(EXTRACT_DATE) && nzchar(EXTRACT_DATE)
)
CDM_CUTOFF <- as.Date(EXTRACT_DATE)
stopifnot(
  "CDM_CUTOFF could not be parsed from EXTRACT_DATE (check R/00_config.R)" =
    !is.na(CDM_CUTOFF)
)
message(glue("  CDM cutoff : {CDM_CUTOFF}  (source: EXTRACT_DATE in R/00_config.R)"))
message(glue("  far cutoff : {CUTOFF} mi   (source: CONFIG$far_from_care_cutoff_mi)"))
message(glue("  GEE corstr : {GEE_CORSTR}  (source: CONFIG$distance_gee_corstr)"))

# --- Broad hematology LOINCs (D-06) --------------------------------------------
# 15 LOINCs; no same-date requirement for the broad sensitivity outcome.
BROAD_LOINCS <- c(
  "6690-2",   # WBC
  "718-7",    # Hemoglobin
  "777-3",    # Platelets
  "4544-3",   # Hematocrit
  "789-8",    # RBC count
  "787-2",    # MCV
  "785-6",    # MCH
  "786-4",    # MCHC
  "788-0",    # RDW
  "770-8",    # Neutrophils
  "26499-4",  # Granulocytes
  "731-0",    # Lymphocytes
  "58410-2",  # CBC panel
  "57021-8",  # CBC w/ auto differential
  "57782-5"   # CBC w/ manual differential
)

# ==============================================================================
# SECTION 1: INPUTS ----
# ==============================================================================

# --- 1a. Anchor dates from R/147 RDS (D-02) ------------------------------------
# Pattern: surveillance_modality_patient_<YYYYMMDD>.rds in CONFIG$output_dir.
# Most recent by mtime; columns include ID and hl_anchor_date.
anchor_candidates <- list.files(
  CONFIG$output_dir,
  pattern = "^surveillance_modality_patient.*\\.rds$",
  full.names = TRUE
)
if (length(anchor_candidates) == 0L)
  stop(
    "R/147 anchor RDS not found in ", CONFIG$output_dir,
    " -- run R/147_surveillance_modality_frequency.R first."
  )
anchor_rds_path <- anchor_candidates[which.max(file.mtime(anchor_candidates))]
message(glue("  Loading R/147 anchor RDS: {basename(anchor_rds_path)}"))
r147_raw <- readRDS(anchor_rds_path)

# Extract one row per patient with ID and hl_anchor_date
anchors <- r147_raw |>
  dplyr::distinct(ID, hl_anchor_date) |>
  dplyr::mutate(hl_anchor_date = as.Date(hl_anchor_date))

n_anchors      <- nrow(anchors)
n_anchor_na    <- sum(is.na(anchors$hl_anchor_date))
message(glue("  Anchors from R/147: {n_anchors} patients; {n_anchor_na} missing hl_anchor_date."))

# Cross-check against Phase 165's cohort source (get_hl_any_dx_ids()).
# R/165 derives cohort from enc_distance IDs + get_hl_any_dx_ids(); we log counts only.
# Any cohort difference does not block execution (D-02 specifies R/147 as the authority).
tryCatch({
  anchors_165 <- get_hl_any_dx_ids()
  ids_179     <- unique(anchors$ID[!is.na(anchors$hl_anchor_date)])
  ids_165     <- unique(anchors_165$ID[!is.na(anchors_165$hl_anchor_date)])
  n_in_179_not_165 <- sum(!ids_179 %in% ids_165)
  n_in_165_not_179 <- sum(!ids_165 %in% ids_179)
  message(glue(
    "  Phase 165 cohort cross-check (get_hl_any_dx_ids()): ",
    "{length(ids_165)} patients with anchor.\n",
    "    In R/179 (R/147 RDS) but not R/165: {n_in_179_not_165}\n",
    "    In R/165 but not R/179 (R/147 RDS): {n_in_165_not_179}"
  ))
}, error = function(e) {
  message("  [INFO] Phase 165 cross-check skipped (get_hl_any_dx_ids() unavailable): ",
          conditionMessage(e))
})

# --- 1b. enc_distance from R/122 RDS -------------------------------------------
# Override via env var R179_R122_RDS; otherwise most recent by mtime.
r122_override <- Sys.getenv("R179_R122_RDS", unset = "")
if (nzchar(r122_override) && file.exists(r122_override)) {
  enc_dist_path <- r122_override
  message(glue("  [R/122 RDS] Using R179_R122_RDS override: {enc_dist_path}"))
} else {
  enc_dist_candidates <- list.files(
    CONFIG$output_dir,
    pattern = "^encounter_distance.*\\.rds$",
    full.names = TRUE
  )
  if (length(enc_dist_candidates) == 0L)
    stop(
      "enc_distance RDS not found in ", CONFIG$output_dir,
      " -- run R/122_encounter_distance.R first, or set R179_R122_RDS."
    )
  enc_dist_path <- enc_dist_candidates[which.max(file.mtime(enc_dist_candidates))]
  message(glue("  NOTE: Pin enc_distance path in R179_R122_RDS once validated."))
}
message(glue("  Loading enc_distance: {basename(enc_dist_path)}"))
enc_distance <- readRDS(enc_dist_path)
message(glue("  enc_distance rows: {format(nrow(enc_distance), big.mark = ',')}"))

# --- 1c. R/121 triage (override via R179_R121_RDS, else most recent by mtime) --
r121_override <- Sys.getenv("R179_R121_RDS", unset = "")
if (nzchar(r121_override) && file.exists(r121_override)) {
  r121_path <- r121_override
  message(glue("  [R/121 RDS] Using R179_R121_RDS override: {r121_path}"))
} else {
  r121_candidates <- list.files(
    CONFIG$output_dir,
    pattern = "^zip_problem_inventory.*\\.rds$",
    full.names = TRUE
  )
  if (length(r121_candidates) == 0L) {
    warning(
      "R/121 zip_problem_inventory RDS not found in ", CONFIG$output_dir,
      " -- triage will be NA for all patients. Run R/121 first or set R179_R121_RDS."
    )
    r121_path <- NULL
  } else {
    r121_path <- r121_candidates[which.max(file.mtime(r121_candidates))]
    message(glue("  Loading R/121 triage: {basename(r121_path)}"))
  }
}

if (!is.null(r121_path)) {
  r121_raw  <- readRDS(r121_path)
  # R/121 RDS is a list with $patients; key column = PATID (see R/177 line 104)
  pat121    <- if (is.list(r121_raw) && "patients" %in% names(r121_raw)) {
    r121_raw$patients
  } else {
    r121_raw  # flat tibble fallback
  }
  triage_map <- pat121 |>
    dplyr::select(PATID, triage) |>
    dplyr::mutate(ID = as.character(PATID)) |>
    dplyr::select(ID, triage)
  message(glue("  R/121 triage: {nrow(triage_map)} patients"))
} else {
  triage_map <- dplyr::tibble(ID = character(0L), triage = character(0L))
}

# --- 1d. DuckDB connection -----------------------------------------------------
if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()

# --- 1e. Primary CBC events via build_cbc_events() (D-05) ----------------------
# Called as-is; LOINCs and same-date logic are defined in utils_distance_cbc.R.
message("  Building CBC events (whole record) via build_cbc_events() ...")
cohort_ids <- unique(anchors$ID)
cbc_events <- build_cbc_events(pcornet_con, cohort_ids)
message(glue("  cbc_events rows: {format(nrow(cbc_events), big.mark = ',')} (patient x date)"))

# --- 1f. Broad hematology events (D-06) ----------------------------------------
# SQL push-down: any of the 15 LOINCs, any date (no same-date requirement).
# Returns DISTINCT (ID, lab_date).
message("  Building broad hematology events (SQL push-down, 15 LOINCs) ...")
broad_id_list    <- paste(sprintf("'%s'", cohort_ids),   collapse = ", ")
broad_loinc_list <- paste(sprintf("'%s'", BROAD_LOINCS), collapse = ", ")

broad_sql <- sprintf("
  SELECT DISTINCT
    ID,
    COALESCE(
      TRY_CAST(RESULT_DATE    AS DATE),
      TRY_CAST(SPECIMEN_DATE  AS DATE),
      TRY_CAST(LAB_ORDER_DATE AS DATE)
    ) AS lab_date
  FROM LAB_RESULT_CM
  WHERE ID       IN (%s)
    AND LAB_LOINC IN (%s)
", broad_id_list, broad_loinc_list)

broad_raw <- DBI::dbGetQuery(pcornet_con, broad_sql)
broad_raw$lab_date <- as.Date(broad_raw$lab_date)
broad_events <- broad_raw |>
  dplyr::filter(!is.na(lab_date)) |>
  dplyr::distinct(ID, lab_date)
message(glue("  broad_events rows: {format(nrow(broad_events), big.mark = ',')} (patient x date)"))

# --- 1g. Death dates from DEATH table (D-04) -----------------------------------
# Used for censoring patient-years that extend past the patient's death date.
# If DEATH table is absent from DuckDB, log a message and proceed without censoring.
death_source <- "none"
death_dates  <- dplyr::tibble(ID = character(0L), death_date = as.Date(character(0L)))

tryCatch({
  death_sql <- sprintf("
    SELECT
      ID AS ID,
      MIN(TRY_CAST(DEATH_DATE AS DATE)) AS death_date
    FROM DEATH
    WHERE ID IN (%s)
      AND DEATH_DATE IS NOT NULL
    GROUP BY ID
  ", broad_id_list)  # reuse id list (same cohort scope)
  death_raw <- DBI::dbGetQuery(pcornet_con, death_sql)
  death_raw$death_date <- as.Date(death_raw$death_date)
  death_dates  <- dplyr::tibble(ID = as.character(death_raw$ID),
                                 death_date = death_raw$death_date)
  death_source <- "DEATH table (DuckDB PCORnet)"
  message(glue(
    "  Death dates: {nrow(death_dates)} patients with a death record ",
    "({sum(!is.na(death_dates$death_date))} with non-NA DEATH_DATE)."
  ))
}, error = function(e) {
  message(glue(
    "  [INFO] DEATH table not available or query failed; ",
    "no death censoring applied. Reason: {conditionMessage(e)}"
  ))
})

# --- 1h. Close DuckDB connection -----------------------------------------------
close_pcornet_con()

# --- KEY_META: audit log of all pinned sources ---------------------------------
KEY_META <- list(
  cdm_cutoff_date   = as.character(CDM_CUTOFF),
  cdm_cutoff_source = "EXTRACT_DATE in R/00_config.R (Mailhot_V1_20250915)",
  anchor_rds        = basename(anchor_rds_path),
  anchor_source     = "R/147 surveillance_modality_patient RDS (D-02)",
  enc_distance_rds  = basename(enc_dist_path),
  r121_rds          = if (!is.null(r121_path)) basename(r121_path) else "not found",
  death_source      = death_source,
  far_cutoff_mi     = CUTOFF,
  gee_corstr        = GEE_CORSTR,
  run_date          = RUN_DATE,
  broad_loincs      = BROAD_LOINCS
)
message(glue("  KEY_META recorded ({length(KEY_META)} fields)."))

# ==============================================================================
# SECTION 2: PATIENT-YEAR TABLE (D-01, D-03, D-04) ----
# ==============================================================================

message("--- Building patient-year table ---")

# Step 1: All patients with a known anchor date (D-03)
anchors_known <- anchors |>
  dplyr::filter(!is.na(hl_anchor_date))

n_with_anchor <- nrow(anchors_known)
message(glue("  Patients with known hl_anchor_date: {n_with_anchor}"))

# Step 2: Compute k_max = floor((CDM_CUTOFF - anchor) / 365) for each patient.
# This is the number of FULLY OBSERVED years (year k is fully observed when
# year_end = anchor + 365*k <= CDM_CUTOFF). Partial final years are excluded (D-04).
# No fixed cap on years (D-03 / plan must-have).
anchors_kmax <- anchors_known |>
  dplyr::mutate(
    k_max = as.integer(floor(as.numeric(CDM_CUTOFF - hl_anchor_date) / 365))
  ) |>
  dplyr::filter(k_max >= 1L)  # at least one fully observed year

n_with_year <- nrow(anchors_kmax)
message(glue("  Patients with >= 1 fully observed year (pre-death censoring): {n_with_year}"))
message(glue("  Patients dropped (k_max < 1, too recent): ",
             "{n_with_anchor - n_with_year}"))

# Step 3: Expand to one row per patient-year using tidyr::uncount().
# year_index = k (1 to k_max); year_start = anchor + 365*(k-1); year_end = anchor + 365*k.
# The interval is half-open (year_start, year_end] following the D-01 convention.
py_raw <- anchors_kmax |>
  tidyr::uncount(k_max, .id = "year_index") |>
  dplyr::mutate(
    year_start = hl_anchor_date + 365L * (year_index - 1L),
    year_end   = hl_anchor_date + 365L * year_index
  )

n_py_before_death <- nrow(py_raw)
message(glue("  Patient-years before death censoring: {format(n_py_before_death, big.mark = ',')}"))

# Guard: all year_end values must be <= CDM_CUTOFF by construction
stopifnot(
  "year_end > CDM_CUTOFF for some patient-years (construction error)" =
    all(py_raw$year_end <= CDM_CUTOFF)
)

# Step 4: Death censoring (D-04).
# Drop patient-years where the patient died before year_end, i.e.,
# death_date is known and death_date <= year_end (patient was NOT alive at year_end).
py_with_death <- py_raw |>
  dplyr::left_join(death_dates, by = "ID")

py <- py_with_death |>
  dplyr::filter(is.na(death_date) | death_date > year_end)

n_py_after_death <- nrow(py)
message(glue(
  "  Patient-years after death censoring: {format(n_py_after_death, big.mark = ',')}",
  " ({format(n_py_before_death - n_py_after_death, big.mark = ',')} removed)"
))

# Drop death_date column (no longer needed; used only for censoring)
py <- py |> dplyr::select(-death_date)

# ==============================================================================
# SECTION 3: FLAGS AND RDS OUTPUT ----
# ==============================================================================

message("--- Computing outcome and exposure flags ---")

# Keep only the join keys from the patient-year spine to avoid fan-out in joins
py_keys <- py |> dplyr::select(ID, year_index, year_start, year_end)

# --- 3a. cbc_year: primary CBC in each patient-year (D-05) --------------------
# Interval: cbc_date > year_start & cbc_date <= year_end (half-open, D-01)
cbc_flag <- py_keys |>
  dplyr::left_join(cbc_events, by = "ID", relationship = "many-to-many") |>
  dplyr::filter(is.na(cbc_date) | (cbc_date > year_start & cbc_date <= year_end)) |>
  dplyr::group_by(ID, year_index) |>
  dplyr::summarise(cbc_year = as.integer(any(!is.na(cbc_date))), .groups = "drop")

py <- py |>
  dplyr::left_join(cbc_flag, by = c("ID", "year_index")) |>
  dplyr::mutate(cbc_year = dplyr::coalesce(cbc_year, 0L))

# --- 3b. cbc_year_broad: broad hematology in each patient-year (D-06) ---------
broad_flag <- py_keys |>
  dplyr::left_join(broad_events, by = "ID", relationship = "many-to-many") |>
  dplyr::filter(is.na(lab_date) | (lab_date > year_start & lab_date <= year_end)) |>
  dplyr::group_by(ID, year_index) |>
  dplyr::summarise(cbc_year_broad = as.integer(any(!is.na(lab_date))), .groups = "drop")

py <- py |>
  dplyr::left_join(broad_flag, by = c("ID", "year_index")) |>
  dplyr::mutate(cbc_year_broad = dplyr::coalesce(cbc_year_broad, 0L))

# --- 3c. Primary exposure: patient-level median distance (D-07, D-08) ---------
# From enc_distance, keep only computed-distance post-anchor encounters.
# One median_distance per patient (applied to all of that patient's patient-years).
pat_exposure <- enc_distance |>
  dplyr::filter(distance_status == "computed") |>
  dplyr::left_join(anchors |> dplyr::select(ID, hl_anchor_date), by = "ID") |>
  dplyr::filter(!is.na(hl_anchor_date)) |>
  dplyr::filter(ADMIT_DATE > hl_anchor_date, ADMIT_DATE <= CDM_CUTOFF) |>
  dplyr::group_by(ID) |>
  dplyr::summarise(median_distance = median(distance_mi, na.rm = TRUE), .groups = "drop")

py <- py |>
  dplyr::left_join(pat_exposure, by = "ID") |>
  dplyr::mutate(
    exposure_missing = is.na(median_distance),
    far = dplyr::if_else(
      exposure_missing,
      NA_integer_,
      as.integer(median_distance > CUTOFF)
    )
  )

n_missing_exp <- sum(py$exposure_missing[!duplicated(py$ID)])
message(glue(
  "  Patients with exposure_missing = TRUE: {n_missing_exp} ",
  "(no computed post-anchor encounter in enc_distance)."
))

# --- 3d. Sensitivity exposure: per-year median distance (D-09) ----------------
# Per (ID, year_index) median over computed-distance encounters with
# ADMIT_DATE > year_start & ADMIT_DATE <= year_end. NA if none in the year.
enc_computed <- enc_distance |>
  dplyr::filter(distance_status == "computed") |>
  dplyr::select(ID, ADMIT_DATE, distance_mi)

year_exposure <- py_keys |>
  dplyr::left_join(enc_computed, by = "ID", relationship = "many-to-many") |>
  dplyr::filter(is.na(ADMIT_DATE) | (ADMIT_DATE > year_start & ADMIT_DATE <= year_end)) |>
  dplyr::group_by(ID, year_index) |>
  dplyr::summarise(
    year_median_dist = if (all(is.na(ADMIT_DATE))) NA_real_
                       else median(distance_mi[!is.na(ADMIT_DATE)], na.rm = TRUE),
    .groups = "drop"
  )

py <- py |>
  dplyr::left_join(year_exposure |> dplyr::select(ID, year_index, year_median_dist),
                   by = c("ID", "year_index")) |>
  dplyr::mutate(
    far_year_median = dplyr::if_else(
      is.na(year_median_dist),
      NA_integer_,
      as.integer(year_median_dist > CUTOFF)
    )
  )

# Clean up intermediate column
py <- py |> dplyr::select(-year_median_dist)

# Rename for schema compatibility with D-17
# (internal name median_distance is already correct; far_year_median is set)

# --- 3e. Triage from R/121 (D-17) ---------------------------------------------
py <- py |>
  dplyr::left_join(triage_map, by = "ID") |>
  dplyr::mutate(triage = dplyr::coalesce(triage, "not in R/121"))

# --- 3f. Validate -------------------------------------------------------------
py_final <- py |>
  dplyr::select(
    ID, year_index, year_start, year_end,
    cbc_year, cbc_year_broad,
    median_distance, far, far_year_median,
    exposure_missing, triage
  )

# Row count preserved (no patient-year lost in joins)
stopifnot(
  "nrow(py_final) != nrow(py) after death censoring -- join fan-out detected" =
    nrow(py_final) == n_py_after_death
)

# No duplicate (ID, year_index) pairs
stopifnot(
  "Duplicate (ID, year_index) pairs in py_final" =
    !anyDuplicated(py_final[, c("ID", "year_index")])
)

# cbc flags must be 0 or 1
stopifnot(
  "cbc_year contains values outside {0,1}" =
    all(py_final$cbc_year %in% c(0L, 1L)),
  "cbc_year_broad contains values outside {0,1}" =
    all(py_final$cbc_year_broad %in% c(0L, 1L))
)

# far must be NA whenever exposure_missing is TRUE (D-08)
stopifnot(
  "far is not NA for all exposure_missing patients" =
    all(is.na(py_final$far[py_final$exposure_missing]))
)

# All year_end values <= CDM_CUTOFF (redundant but explicit)
stopifnot(
  "year_end > CDM_CUTOFF in py_final" =
    all(py_final$year_end <= CDM_CUTOFF)
)

message(glue(
  "  Validation PASSED:\n",
  "    nrow(py_final)              = {format(nrow(py_final), big.mark = ',')}\n",
  "    unique patients             = {format(dplyr::n_distinct(py_final$ID), big.mark = ',')}\n",
  "    max year_index              = {max(py_final$year_index)}\n",
  "    patients with exposure_missing = {sum(!duplicated(py_final$ID[py_final$exposure_missing]))}\n",
  "    patients far (median > {CUTOFF} mi) = ",
  "{sum(!duplicated(py_final$ID[!is.na(py_final$far) & py_final$far == 1L]))}"
))

# --- 3g. Write internal RDS ---------------------------------------------------
internal_dir <- file.path(CONFIG$output_dir, "internal")
if (!dir.exists(internal_dir)) {
  dir.create(internal_dir, recursive = TRUE, showWarnings = FALSE)
  message(glue("  Created directory: {internal_dir}"))
}

rds_out <- file.path(internal_dir, glue("cbc_patient_year_{RUN_DATE}.rds"))
saveRDS(py_final, rds_out)
message(glue("  Saved: {rds_out}"))
message(glue("  Rows : {format(nrow(py_final), big.mark = ',')}\n",
             "  Cols : {paste(names(py_final), collapse = ', ')}"))

message(glue(
  "================================================================================\n",
  "R/179 Sections 0-3 COMPLETE -- {RUN_DATE}\n",
  "  RDS  : {rds_out}\n",
  "  Continuing to Sections 4-7 (descriptives, GEE, workbook) ...\n",
  "================================================================================"
))

# ==============================================================================
# SECTION 4: SUBSETS AND DESCRIPTIVES ----
# ==============================================================================

message("--- Section 4: Descriptives ---")

# Load RDS (re-uses py_final if already in memory; RDS write confirmed above)
py <- py_final |>
  dplyr::mutate(
    year_index_cat = factor(
      dplyr::if_else(year_index >= 5L, "5+", as.character(year_index)),
      levels = c("1", "2", "3", "4", "5+")
    )
  )

py_all     <- dplyr::filter(py, !exposure_missing)
py_primary <- dplyr::filter(py_all, year_index >= 2L)
py_yr1     <- dplyr::filter(py_all, year_index == 1L)

n_missing_py <- sum(py$exposure_missing)
n_missing_pat <- dplyr::n_distinct(py$ID[py$exposure_missing])

message(glue(
  "  Patient-year subsets:\n",
  "    py (all rows)           : {format(nrow(py), big.mark=',')} py, ",
  "{format(dplyr::n_distinct(py$ID), big.mark=',')} patients\n",
  "    py_all (exposure known) : {format(nrow(py_all), big.mark=',')} py, ",
  "{format(dplyr::n_distinct(py_all$ID), big.mark=',')} patients\n",
  "    py_primary (years 2+)   : {format(nrow(py_primary), big.mark=',')} py, ",
  "{format(dplyr::n_distinct(py_primary$ID), big.mark=',')} patients\n",
  "    py_yr1 (year 1 only)    : {format(nrow(py_yr1), big.mark=',')} py\n",
  "    exposure_missing py     : {format(n_missing_py, big.mark=',')} py, ",
  "{format(n_missing_pat, big.mark=',')} patients"
))

# --- 4a. Exposure distribution (D-10) -----------------------------------------
# One row per patient: patient-level median_distance (already constant per patient)
pat_level <- py_all |>
  dplyr::distinct(ID, median_distance, far)

n_far     <- sum(pat_level$far == 1L, na.rm = TRUE)
n_not_far <- sum(pat_level$far == 0L, na.rm = TRUE)
n_miss_exp_pat <- sum(is.na(pat_level$far))   # should match n_missing_pat

q_probs <- c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)
dist_quantiles <- quantile(pat_level$median_distance, probs = q_probs, na.rm = TRUE)

desc_4a <- data.frame(
  Metric = c(
    paste0("Median distance (mi) — ", c("P5","P10","P25","P50","P75","P90","P95")),
    "N patients: far (>100 mi)",
    "N patients: not far (<=100 mi)",
    "N patients: missing exposure"
  ),
  Value = c(
    as.character(round(dist_quantiles, 1)),
    suppress_display(n_far),
    suppress_display(n_not_far),
    suppress_display(n_miss_exp_pat)
  ),
  stringsAsFactors = FALSE
)

message(glue(
  "  4a exposure (patient-level median distance):\n",
  "    P5={round(dist_quantiles[1],1)}, P25={round(dist_quantiles[3],1)}, ",
  "P50={round(dist_quantiles[4],1)}, P75={round(dist_quantiles[5],1)}, ",
  "P95={round(dist_quantiles[7],1)} mi\n",
  "    far={suppress_display(n_far)}, not far={suppress_display(n_not_far)}, ",
  "missing={suppress_display(n_miss_exp_pat)}"
))

# --- 4b. Per year index (D-13) -----------------------------------------------
# Patient-years far / not far, CBC rate in each, crude OR (naive_or_se).
# A rate is shown only if its numerator AND denominator are both >= 11, else "—".

show_rate <- function(num, denom) {
  if (is.na(num) || is.na(denom) || num < 11 || denom < 11) return("—")
  paste0(round(100 * num / denom, 1), "%")
}

per_year_rows <- lapply(levels(py_all$year_index_cat), function(yr) {
  d_yr <- dplyr::filter(py_all, year_index_cat == yr)

  n_far_yr    <- sum(d_yr$far == 1L, na.rm = TRUE)
  n_notfar_yr <- sum(d_yr$far == 0L, na.rm = TRUE)

  cbc_far     <- sum(d_yr$cbc_year[d_yr$far == 1L], na.rm = TRUE)
  cbc_notfar  <- sum(d_yr$cbc_year[d_yr$far == 0L], na.rm = TRUE)

  ct <- matrix(as.double(c(
    n_notfar_yr - cbc_notfar, cbc_notfar,
    n_far_yr    - cbc_far,    cbc_far
  )), nrow = 2, byrow = TRUE)

  nb <- tryCatch(naive_or_se(ct), error = function(e) list(log_or = NA_real_, se = NA_real_, haldane = NA))

  data.frame(
    Year_index   = yr,
    N_py_far     = suppress_display(n_far_yr),
    N_py_notfar  = suppress_display(n_notfar_yr),
    N_cbc_far    = suppress_display(cbc_far),
    N_cbc_notfar = suppress_display(cbc_notfar),
    Rate_far     = show_rate(cbc_far, n_far_yr),
    Rate_notfar  = show_rate(cbc_notfar, n_notfar_yr),
    Crude_OR     = if (is.na(nb$log_or)) NA_character_ else as.character(round(exp(nb$log_or), 2)),
    Haldane      = if (is.na(nb$haldane)) NA_character_ else as.character(nb$haldane),
    stringsAsFactors = FALSE
  )
})

desc_4b <- do.call(rbind, per_year_rows)

message("  4b per year-index table built (", nrow(desc_4b), " year groups).")

# --- 4c. Year 1 2x2 (far × cbc_year) with interior suppression ---------------
suppress_2x2 <- function(tab) {
  # tab: 2x2 matrix (rows = far 0/1, cols = cbc_year 0/1)
  # Interior cells: suppress_display; margins suppressed if a cell was suppressed
  inner <- matrix(suppress_display(as.integer(tab)), nrow = 2)
  # Row totals
  row_tots <- rowSums(tab)
  col_tots <- colSums(tab)
  grand    <- sum(tab)
  # Any interior suppression in a row => suppress that row total
  row_suppressed <- sapply(1:2, function(i) any(as.integer(tab[i,]) %in% 1:10))
  col_suppressed <- sapply(1:2, function(j) any(as.integer(tab[,j]) %in% 1:10))
  row_tots_d <- dplyr::if_else(row_suppressed, "<11", suppress_display(as.integer(row_tots)))
  col_tots_d <- dplyr::if_else(col_suppressed, "<11", suppress_display(as.integer(col_tots)))
  grand_d    <- suppress_display(as.integer(grand))
  df <- data.frame(
    Exposure    = c("not far (0)", "far (1)", "Total"),
    CBC_no      = c(inner[1,1], inner[2,1], col_tots_d[1]),
    CBC_yes     = c(inner[1,2], inner[2,2], col_tots_d[2]),
    Total       = c(row_tots_d[1], row_tots_d[2], grand_d),
    stringsAsFactors = FALSE
  )
  names(df) <- c("Exposure (far)", "CBC in year: No", "CBC in year: Yes", "Total")
  df
}

ct_yr1 <- table(
  factor(py_yr1$far, levels = c(0L, 1L), labels = c("not far", "far")),
  factor(py_yr1$cbc_year, levels = c(0L, 1L))
)
desc_4c <- suppress_2x2(matrix(as.integer(ct_yr1), nrow = 2))

message("  4c Year 1 2x2 suppressed table built.")

# ==============================================================================
# SECTION 5: GEE MODELS (D-11, D-12, D-13) ----
# ==============================================================================

message("--- Section 5: GEE models ---")

run_gee <- function(data, outcome, exposure, label) {
  d <- data |>
    dplyr::filter(!is.na(.data[[exposure]])) |>
    dplyr::arrange(ID, year_index) |>
    dplyr::mutate(
      year_index_cat = droplevels(year_index_cat),
      y = .data[[outcome]],
      x = .data[[exposure]]
    )

  warns <- character(0)
  fit <- tryCatch(
    withCallingHandlers(
      geepack::geeglm(
        y ~ x + year_index_cat,
        data   = d,
        id     = ID,
        family = binomial("logit"),
        corstr = GEE_CORSTR
      ),
      warning = function(w) {
        warns <<- c(warns, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) e
  )

  base <- list(
    label    = label,
    n_py     = nrow(d),
    n_pat    = dplyr::n_distinct(d$ID),
    warnings = paste(unique(warns), collapse = " | ")
  )

  if (inherits(fit, "error")) {
    # Fallback: crude OR via naive_or_se (labelled, not silent; D-13)
    ct_fb <- matrix(
      as.numeric(table(factor(d$x, 0:1), factor(d$y, 0:1))),
      nrow = 2
    )
    nb <- naive_or_se(ct_fb)
    return(c(base, list(
      method = "CRUDE FALLBACK (GEE error)",
      or     = exp(nb$log_or),
      ci_lo  = NA_real_,
      ci_hi  = NA_real_,
      p      = NA_real_,
      error  = conditionMessage(fit)
    )))
  }

  ct_coef <- summary(fit)$coefficients
  b  <- ct_coef["x", "Estimate"]
  se <- ct_coef["x", "Std.err"]    # geepack robust SE column (D-11)

  c(base, list(
    method = glue::glue("GEE ({GEE_CORSTR})"),
    or     = exp(b),
    ci_lo  = exp(b - 1.96 * se),
    ci_hi  = exp(b + 1.96 * se),
    p      = ct_coef["x", "Pr(>|W|)"],
    error  = NA_character_
  ))
}

# D-12: Primary = years 2+; Secondary = all years; Year 1 = 4c descriptive only
message("  Fitting primary GEE (years 2+, far ~ primary exposure) ...")
res_primary   <- run_gee(py_primary, "cbc_year",       "far",            "Primary: years 2+")

message("  Fitting secondary GEE (all years, far ~ primary exposure) ...")
res_secondary <- run_gee(py_all,     "cbc_year",       "far",            "Secondary: all years")

# D-09 sensitivity: per-year median distance exposure
message("  Fitting sensitivity GEE (years 2+, far_year_median) ...")
py_primary_yr_exp <- dplyr::filter(py_primary, !is.na(far_year_median))
n_dropped_yr_exp  <- nrow(py_primary) - nrow(py_primary_yr_exp)
n_pat_dropped_yr  <- dplyr::n_distinct(py_primary$ID) - dplyr::n_distinct(py_primary_yr_exp$ID)
message(glue(
  "    Per-year exposure sensitivity: dropped {format(n_dropped_yr_exp, big.mark=',')} py ",
  "and {format(n_pat_dropped_yr, big.mark=',')} patients vs primary."
))
res_sens_exposure <- run_gee(py_primary_yr_exp, "cbc_year", "far_year_median",
                              "Sensitivity (per-year median exposure, years 2+)")

# D-06 sensitivity: broad hematology outcome
message("  Fitting sensitivity GEE (years 2+, broad hematology outcome) ...")
res_sens_outcome  <- run_gee(py_primary, "cbc_year_broad", "far",
                              "Sensitivity (broad hematology outcome, years 2+)")

all_fits <- list(res_primary, res_secondary, res_sens_exposure, res_sens_outcome)

# Helper for console summary
fmt_result <- function(r) {
  if (r$method == "CRUDE FALLBACK (GEE error)") {
    glue::glue("  [{r$label}] FALLBACK OR={round(r$or,2)} [CI unavailable]; error: {r$error}")
  } else {
    glue::glue("  [{r$label}] OR={round(r$or,2)} ({round(r$ci_lo,2)}-{round(r$ci_hi,2)}), p={format.pval(r$p,3)}, method={r$method}")
  }
}

for (r in all_fits) message(fmt_result(r))

# ==============================================================================
# SECTION 6: WORKBOOK (D-16) ----
# ==============================================================================

message("--- Section 6: Workbook ---")

wb_path <- file.path(CONFIG$output_dir, glue("cbc_patient_year_{RUN_DATE}.xlsx"))

# UF style helpers
uf_blue   <- "#0021A5"
uf_orange <- "#FA4616"

uf_header_style <- openxlsx::createStyle(
  fgFill    = uf_blue,
  fontColor = "#FFFFFF",
  textDecoration = "bold",
  border    = "Bottom"
)
uf_section_style <- openxlsx::createStyle(
  fgFill    = uf_orange,
  fontColor = "#FFFFFF",
  textDecoration = "bold"
)

wb <- openxlsx::createWorkbook()

# -- Sheet 1: KEY --------------------------------------------------------------
openxlsx::addWorksheet(wb, "KEY")

# Attempt to read Phase 165 ORs from the workbook written on 2026-10-08
phase165_xlsx <- file.path(CONFIG$output_dir, "distance_cbc_association_20261008.xlsx")
phase165_or_text <- tryCatch({
  if (!file.exists(phase165_xlsx)) stop("not found")
  p165_key <- readxl::read_excel(phase165_xlsx, sheet = "KEY")
  # Locate rows by label pattern
  extract_val <- function(pattern) {
    idx <- grep(pattern, p165_key[[1]], ignore.case = TRUE)
    if (length(idx) == 0) return(NA_character_)
    paste(p165_key[[2]][idx], collapse = "; ")
  }
  whole_or  <- extract_val("whole.*or|whole.*result|whole record")
  post_or   <- extract_val("post.*or|post.*result|post.anchor")
  glue::glue("Phase 165 (encounter-level) ORs from {basename(phase165_xlsx)}: whole-record={whole_or}; post-anchor={post_or}")
}, error = function(e) {
  message(glue("  [INFO] Phase 165 workbook not readable: {conditionMessage(e)} -- writing placeholder"))
  "see Phase 165 workbook (distance_cbc_association_20261008.xlsx)"
})

# KEY rows
key_rows_179 <- list(
  c("Field", "Value"),
  c("Analysis", "far_from_care_100mi x CBC receipt (patient-year)"),
  c("Companion to Phase 165",
    paste0("Companion to Phase 165 (encounter-level: CBC drawn during the encounter). ",
           "Which analysis is primary is pending team decision (D-15, with D-165-01).")),
  c("Run date",       RUN_DATE),
  c("Unit",           "Patient-year (half-open 365-day interval after hl_anchor_date)"),
  c("Year interval",  "Year k = (anchor + 365*(k-1), anchor + 365*k]; anchor day = pre (D-01)"),
  c("CDM cutoff",     glue("{CDM_CUTOFF} (source: EXTRACT_DATE in R/00_config.R, Mailhot_V1_20250915)")),
  c("Anchor source",  glue("{KEY_META$anchor_rds} (R/147 surveillance_modality_patient RDS, D-02)")),
  c("Cohort cross-check", "get_hl_any_dx_ids() vs R/147 RDS counts logged at runtime (non-blocking, D-02)"),
  c("Death source",   KEY_META$death_source),
  c("Enc_distance src", KEY_META$enc_distance_rds),
  c("R/121 triage src", KEY_META$r121_rds),
  c("Primary outcome",     "cbc_year: >= 1 CBC (WBC+Hgb+PLT same date via build_cbc_events()) in the year"),
  c("Sensitivity outcome", "cbc_year_broad: >= 1 of 15 hematology LOINCs in the year (no same-date req., D-06)"),
  c("Primary exposure",    glue("patient-level median distance_mi (post-anchor computed encounters); far = median > {CUTOFF} mi")),
  c("Sensitivity exposure","per-year median distance_mi (computed enc. in that year's window); D-09"),
  c("GEE spec",       glue("geepack::geeglm, binomial logit, corstr={GEE_CORSTR}, id=ID, year_index_cat adj.")),
  c("Why years 2+ primary", paste0(
    "Year 1 overlaps primary HL treatment; CBCs near-universal regardless of distance. ",
    "Surveillance CBC signal is cleaner from year 2 onward. Year 1 reported as descriptive 2x2 only (D-12)."
  )),
  c("Exposure missing", glue("{suppress_display(n_missing_pat)} patients / {suppress_display(n_missing_py)} py excluded from estimates (exposure_missing = TRUE)")),
  c("Primary OR",     fmt_result(res_primary)),
  c("Secondary OR",   fmt_result(res_secondary)),
  c("Sensitivity OR (per-year exp.)", fmt_result(res_sens_exposure)),
  c("Sensitivity OR (broad outcome)", fmt_result(res_sens_outcome)),
  c("Phase 165 side-by-side", phase165_or_text),
  c("Primary choice",  "Pending team decision (D-15, with D-165-01); see D-15 in STATE.md"),
  c("Suppression rule","Counts 1-10 displayed as '<11'; rates shown only when numerator AND denominator >= 11"),
  c("RDS basename",    basename(rds_out))
)

key_df_179 <- do.call(rbind, lapply(key_rows_179, function(r) {
  data.frame(Field = r[1], Value = paste(r[-1], collapse = " "), stringsAsFactors = FALSE)
}))

openxlsx::writeData(wb, "KEY", key_df_179, startRow = 1, startCol = 1, headerStyle = uf_header_style)
openxlsx::addStyle(wb, "KEY", style = uf_header_style, rows = 1, cols = 1:2)
openxlsx::setColWidths(wb, "KEY", cols = 1:2, widths = c(32, 80))

# -- Sheet 2: Descriptives (4a then 4c) ----------------------------------------
openxlsx::addWorksheet(wb, "Descriptives")

openxlsx::writeData(wb, "Descriptives",
  data.frame(Section = "4a: Patient-level exposure distribution (D-10)"),
  startRow = 1, startCol = 1, headerStyle = uf_section_style)
openxlsx::addStyle(wb, "Descriptives", style = uf_section_style, rows = 1, cols = 1)
openxlsx::writeData(wb, "Descriptives", desc_4a, startRow = 2, startCol = 1,
                    headerStyle = uf_header_style)
openxlsx::addStyle(wb, "Descriptives", style = uf_header_style, rows = 2, cols = 1:2)

yr1_offset <- nrow(desc_4a) + 4L
openxlsx::writeData(wb, "Descriptives",
  data.frame(Section = "4c: Year 1 -- descriptive only, not in primary model"),
  startRow = yr1_offset, startCol = 1, headerStyle = uf_section_style)
openxlsx::addStyle(wb, "Descriptives", style = uf_section_style, rows = yr1_offset, cols = 1)
openxlsx::writeData(wb, "Descriptives", desc_4c, startRow = yr1_offset + 1L, startCol = 1,
                    headerStyle = uf_header_style)
openxlsx::addStyle(wb, "Descriptives", style = uf_header_style,
                   rows = yr1_offset + 1L, cols = 1:ncol(desc_4c))
openxlsx::setColWidths(wb, "Descriptives", cols = 1:4, widths = c(28, 16, 16, 16))

# -- Sheet 3: Per_Year (4b) ----------------------------------------------------
openxlsx::addWorksheet(wb, "Per_Year")
openxlsx::writeData(wb, "Per_Year", desc_4b, startRow = 1, startCol = 1,
                    headerStyle = uf_header_style)
openxlsx::addStyle(wb, "Per_Year", style = uf_header_style, rows = 1, cols = 1:ncol(desc_4b))
openxlsx::setColWidths(wb, "Per_Year", cols = 1:ncol(desc_4b), widths = 16)

# -- Sheet 4: Model_Results ----------------------------------------------------
openxlsx::addWorksheet(wb, "Model_Results")

model_df <- do.call(rbind, lapply(all_fits, function(r) {
  data.frame(
    Label         = r$label,
    Method        = r$method,
    N_patient_yrs = r$n_py,
    N_patients    = suppress_display(r$n_pat),
    OR            = if (is.na(r$or))    NA_character_ else as.character(round(r$or,    3)),
    CI_lo         = if (is.na(r$ci_lo)) NA_character_ else as.character(round(r$ci_lo, 3)),
    CI_hi         = if (is.na(r$ci_hi)) NA_character_ else as.character(round(r$ci_hi, 3)),
    p_value       = if (is.na(r$p))     NA_character_ else format.pval(r$p, digits = 3),
    Warnings      = r$warnings,
    Error         = if (is.na(r$error)) "" else r$error,
    stringsAsFactors = FALSE
  )
}))

openxlsx::writeData(wb, "Model_Results", model_df, startRow = 1, startCol = 1,
                    headerStyle = uf_header_style)
openxlsx::addStyle(wb, "Model_Results", style = uf_header_style,
                   rows = 1, cols = 1:ncol(model_df))

# Orange fill on any fallback row
fallback_rows <- which(grepl("FALLBACK", model_df$Method)) + 1L  # +1 for header
if (length(fallback_rows) > 0L) {
  openxlsx::addStyle(wb, "Model_Results", style = uf_section_style,
                     rows = fallback_rows, cols = 1:ncol(model_df), gridExpand = TRUE)
}
openxlsx::setColWidths(wb, "Model_Results", cols = 1:ncol(model_df),
                       widths = c(40, 28, 14, 12, 8, 8, 8, 10, 40, 30))

openxlsx::saveWorkbook(wb, wb_path, overwrite = TRUE)
message(glue("  Workbook saved: {wb_path}"))

# ==============================================================================
# SECTION 7: CONSOLE SUMMARY ----
# ==============================================================================

message(glue(
  "================================================================================\n",
  "R/179 COMPLETE -- {RUN_DATE}\n",
  "  RDS    : {rds_out}\n",
  "  Workbook: {wb_path}\n",
  "  Sheets : KEY | Descriptives | Per_Year | Model_Results\n",
  "\n",
  "  Primary result:\n",
  "    {fmt_result(res_primary)}\n",
  "  Secondary:\n",
  "    {fmt_result(res_secondary)}\n",
  "  Sensitivity (per-year exposure):\n",
  "    {fmt_result(res_sens_exposure)}\n",
  "  Sensitivity (broad outcome):\n",
  "    {fmt_result(res_sens_outcome)}\n",
  "\n",
  "  Phase 165 comparison: {phase165_or_text}\n",
  "\n",
  "  Primary-analysis choice (165 vs 179): PENDING team decision (D-15 / D-165-01)\n",
  "================================================================================"
))
