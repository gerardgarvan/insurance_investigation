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
  "  Output: {rds_out}\n",
  "  Next  : source('R/179b_cbc_patient_year_models.R', local = new.env(...))\n",
  "          (Plan 02: GEE models + workbook output)\n",
  "================================================================================"
))
