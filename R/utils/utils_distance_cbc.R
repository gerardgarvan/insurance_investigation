# ==============================================================================
# utils/utils_distance_cbc.R -- Phase 165 shared helpers for distance-CBC analysis
# ==============================================================================
#
# Purpose:
#   Pure-function helpers shared by R/163 (prototype) and R/165 (production).
#   Builds the encounter- and patient-level analysis sets for the far_from_care_100mi
#   indicator and CBC association analysis. Auto-sourced by 00_config.R via the
#   utils glob (list.files("R/utils")).
#
# Inputs (all provided by callers; no global state read here):
#   con          -- DBI/DuckDB connection (open, read-only)
#   enc_distance -- tibble from readRDS(enc_distance RDS); R/122 output
#   cbc_events   -- tibble(ID, cbc_date) returned by build_cbc_events()
#   anchors      -- tibble(ID, hl_anchor_date) from get_hl_any_dx_ids()
#   enc_dates    -- tibble(ENCOUNTERID, ADMIT_DATE, DISCHARGE_DATE, SOURCE)
#                   pulled from ENCOUNTER via DuckDB by the caller
#   cutoff       -- numeric scalar (CONFIG$far_from_care_cutoff_mi)
#
# Outputs (returned values, no I/O):
#   build_cbc_events()   -> tibble(ID, cbc_date)
#   build_enc_analysis() -> tibble with encounter-level analysis set
#   build_pat_analysis() -> tibble with patient-level analysis set
#   suppress_small_vec() -> integer vector with 1-10 replaced by NA_integer_
#   suppress_display()   -> character vector with 1-10 replaced by "<11"
#   naive_or_se()        -> list(log_or, se, haldane)
#
# Dependencies:
#   dplyr, lubridate (both loaded via 00_config -> library chain)
#   DBI (for DuckDB queries in build_cbc_events)
#   utils_duckdb.R (auto-sourced: safe_table())
#
# Requirements: ACC-01, ACC-02 (Phase 165)
#
# ==============================================================================

# ------------------------------------------------------------------------------
# suppress_small_vec() -- vectorized integer suppression (analysis use)
# Returns NA_integer_ for counts 1-10; 0 and counts > 10 are unchanged.
# WHY separate from utils_surveillance::suppress_small(): that version returns
# the "<11" string for HIPAA table display. This version preserves integer type
# for arithmetic while masking small cells before tabulation.
# ------------------------------------------------------------------------------
suppress_small_vec <- function(n) {
  ifelse(!is.na(n) & n >= 1L & n <= 10L, NA_integer_, as.integer(n))
}

# ------------------------------------------------------------------------------
# suppress_display() -- vectorized display suppression (table output use)
# Returns "<11" string for counts 1-10; 0 and counts > 10 returned as character.
# Matches the pipeline convention in utils_surveillance::suppress_small().
# ------------------------------------------------------------------------------
suppress_display <- function(n) {
  ifelse(!is.na(n) & n >= 1L & n <= 10L, "<11", as.character(n))
}

# ------------------------------------------------------------------------------
# naive_or_se() -- Woolf log-OR and SE from a 2x2 contingency table
#
# @param ct  2x2 matrix: rows = exposure (0 = not far, 1 = far), cols = outcome
#            (0 = no CBC, 1 = CBC). Produced by table(far, cbc) with those levels.
# @return    list(log_or, se, haldane)
#              log_or  -- log odds ratio (Woolf)
#              se      -- SE of log_or
#              haldane -- TRUE if any cell was zero (Haldane 0.5 correction applied)
#
# WHY Haldane correction: a zero cell makes the log-OR undefined. Adding 0.5 to
# all cells is the standard continuity correction when expected cells are small.
# The flag ensures the correction is visible in printed output and the memo.
# ------------------------------------------------------------------------------
naive_or_se <- function(ct) {
  stopifnot(
    "ct must be a 2x2 matrix" = is.matrix(ct),
    "ct must have dim c(2,2)"  = all(dim(ct) == c(2L, 2L))
  )
  haldane <- any(ct == 0)
  m <- if (haldane) ct + 0.5 else ct
  log_or <- log((m[2L, 2L] * m[1L, 1L]) / (m[2L, 1L] * m[1L, 2L]))
  se     <- sqrt(sum(1 / m))
  list(log_or = log_or, se = se, haldane = haldane)
}

# ------------------------------------------------------------------------------
# build_cbc_events() -- derive CBC events (whole record) from DuckDB
#
# A CBC event = WBC (6690-2) + Hgb (718-7) + PLT (777-3) resulted on the SAME
# calendar date for the SAME patient. This matches R/147's locked definition
# (D-22 sensitivity tier; CONTEXT.md D-05).
#
# Date column priority matches R/147 (line 183):
#   coalesce(RESULT_DATE, SPECIMEN_DATE, LAB_ORDER_DATE)
#
# Pre-anchor events are included (whole-record coverage per CONTEXT.md D-06a).
# R/147's saved RDS files are post-anchor only, so we always re-derive here.
#
# @param con  Open DBI/DuckDB connection (read-only; caller opens and closes)
# @param ids  Character vector of patient IDs to scope the query (HL cohort)
#
# @return tibble(ID chr, cbc_date Date) — DISTINCT rows; one row per patient x date
#         that had all three CBC components resulted.
#
# WHY DuckDB SQL push-down: LAB_RESULT_CM is large; filtering by ID and LOINC
# before collect() avoids pulling millions of rows into R memory.
# ------------------------------------------------------------------------------
build_cbc_events <- function(con, ids) {
  stopifnot(
    "con must be a DBI connection" = inherits(con, "DBIConnection"),
    "ids must be a non-empty character vector" = is.character(ids) && length(ids) > 0
  )

  cbc_loincs <- c("6690-2", "718-7", "777-3")  # WBC, Hgb, PLT (R/147 D-22)

  # Build a parameterised IN clause. DuckDB handles up to ~65k values safely.
  id_list    <- paste(sprintf("'%s'", ids),    collapse = ", ")
  loinc_list <- paste(sprintf("'%s'", cbc_loincs), collapse = ", ")

  sql <- sprintf("
    SELECT
      ID,
      LAB_LOINC,
      COALESCE(
        TRY_CAST(RESULT_DATE   AS DATE),
        TRY_CAST(SPECIMEN_DATE AS DATE),
        TRY_CAST(LAB_ORDER_DATE AS DATE)
      ) AS cbc_date
    FROM LAB_RESULT_CM
    WHERE ID       IN (%s)
      AND LAB_LOINC IN (%s)
  ", id_list, loinc_list)

  raw <- DBI::dbGetQuery(con, sql)
  raw$cbc_date <- as.Date(raw$cbc_date)

  # Keep only dates where all three LOINC codes are present for the same ID x date
  # (matches R/147 D-22 "all same calendar date" rule).
  three_present <- raw |>
    dplyr::filter(!is.na(cbc_date)) |>
    dplyr::distinct(ID, LAB_LOINC, cbc_date) |>
    dplyr::count(ID, cbc_date, name = "n_loincs") |>
    dplyr::filter(n_loincs == 3L) |>  # all three components on the same day
    dplyr::select(ID, cbc_date)

  three_present
}

# ------------------------------------------------------------------------------
# build_enc_analysis() -- encounter-level analysis set (both windows as columns)
#
# Constructs the primary analysis tibble for R/163 and R/165. Carries
# far_from_care_100mi and post_anchor as 0/1 integer columns so the caller can
# subset by window (post_anchor == 1) without a separate build step.
#
# Encounter-level CBC definition (CONTEXT.md D-06):
#   cbc_in_encounter = 1 if any cbc_date falls in [ADMIT_DATE, coalesce(DISCHARGE_DATE, ADMIT_DATE)]
#   Non-equi join via dplyr::join_by(between()). De-duplicated to ONE row per
#   ENCOUNTERID after the join (stopifnot guard enforced).
#
# @param enc_distance tibble from readRDS(enc_distance path) — R/122 output.
#          Must contain: ID, ENCOUNTERID, ADMIT_DATE (Date), distance_mi, distance_status
# @param cbc_events   tibble(ID, cbc_date) from build_cbc_events()
# @param anchors      tibble(ID, hl_anchor_date) from get_hl_any_dx_ids()
# @param enc_dates    tibble(ENCOUNTERID, DISCHARGE_DATE (Date or NA), SOURCE)
#          pulled from ENCOUNTER by caller (DuckDB query, cohort-scoped)
# @param cutoff       numeric scalar — CONFIG$far_from_care_cutoff_mi
#
# @return tibble (one row per ENCOUNTERID with distance_status == "computed" and
#           known anchor date):
#   ID, ENCOUNTERID, ADMIT_DATE, ENC_TYPE, SOURCE,
#   distance_mi, far_from_care_100mi (int 0/1), post_anchor (int 0/1),
#   cbc_in_encounter (int 0/1)
#
# WHY distance_status == "computed" filter: only computed distances support the
# binary indicator; other statuses (facility_zip_missing, patient_zip_missing,
# zip_not_in_db) would produce NA distance_mi and meaningless indicators.
#
# WHY anchor-date drop: encounters for patients without an anchor date cannot be
# assigned to a window. The count is logged by the caller (QC).
# ------------------------------------------------------------------------------
build_enc_analysis <- function(enc_distance, cbc_events, anchors, enc_dates, cutoff) {
  stopifnot(
    "enc_distance must be a data.frame" = is.data.frame(enc_distance),
    "cbc_events must be a data.frame"   = is.data.frame(cbc_events),
    "anchors must be a data.frame"      = is.data.frame(anchors),
    "enc_dates must be a data.frame"    = is.data.frame(enc_dates),
    "cutoff must be a positive numeric" = is.numeric(cutoff) && length(cutoff) == 1L && cutoff > 0
  )

  # Step 1: Keep only computed-distance encounters
  enc_computed <- enc_distance |>
    dplyr::filter(distance_status == "computed")

  # Step 2: Attach DISCHARGE_DATE and SOURCE from ENCOUNTER
  enc_with_dates <- enc_computed |>
    dplyr::left_join(
      enc_dates |> dplyr::select(ENCOUNTERID, DISCHARGE_DATE, SOURCE),
      by = "ENCOUNTERID"
    )

  # Step 3: Compute far_from_care_100mi
  enc_with_dates <- enc_with_dates |>
    dplyr::mutate(
      far_from_care_100mi = as.integer(distance_mi > cutoff),
      enc_end              = dplyr::coalesce(DISCHARGE_DATE, ADMIT_DATE)
    )

  # Step 4: Join anchor dates; drop patients with no anchor (logged by caller)
  n_before_anchor <- nrow(enc_with_dates)
  enc_anchored <- enc_with_dates |>
    dplyr::inner_join(
      anchors |> dplyr::select(ID, hl_anchor_date),
      by = "ID"
    )
  n_dropped_no_anchor <- n_before_anchor - nrow(enc_anchored)
  if (n_dropped_no_anchor > 0)
    message(glue::glue(
      "  build_enc_analysis(): {n_dropped_no_anchor} encounters dropped ",
      "(patient has no anchor date)."
    ))

  # Step 5: Compute post_anchor (anchor day = pre, per CONTEXT.md D-13 / R/147 D-25)
  enc_anchored <- enc_anchored |>
    dplyr::mutate(post_anchor = as.integer(ADMIT_DATE > hl_anchor_date))

  # Step 6: CBC-in-encounter flag.
  # Join enc_anchored (with ID) to cbc_events on ID + date range.
  cbc_flag <- enc_anchored |>
    dplyr::select(ID, ENCOUNTERID, ADMIT_DATE, enc_end) |>
    dplyr::left_join(cbc_events, by = "ID",
                     relationship = "many-to-many") |>
    dplyr::filter(is.na(cbc_date) | (cbc_date >= ADMIT_DATE & cbc_date <= enc_end)) |>
    dplyr::group_by(ENCOUNTERID) |>
    dplyr::summarise(cbc_in_encounter = as.integer(any(!is.na(cbc_date))),
                     .groups = "drop")

  # Step 7: Attach CBC flag back to the encounter set
  out <- enc_anchored |>
    dplyr::left_join(cbc_flag, by = "ENCOUNTERID") |>
    dplyr::mutate(cbc_in_encounter = dplyr::coalesce(cbc_in_encounter, 0L))

  # Guard: one row per ENCOUNTERID (no fan-out from the join)
  stopifnot(
    "build_enc_analysis(): duplicate ENCOUNTERIDs in output (fan-out)" =
      !anyDuplicated(out$ENCOUNTERID)
  )

  # Step 8: Select and return canonical columns
  out |>
    dplyr::select(
      ID, ENCOUNTERID, ADMIT_DATE, ENC_TYPE, SOURCE,
      distance_mi, far_from_care_100mi, post_anchor, cbc_in_encounter
    )
}

# ------------------------------------------------------------------------------
# build_pat_analysis() -- patient-level analysis set for one window
#
# Aggregates the encounter-level set to one row per patient. Denominator =
# patients with >= 1 computed-distance encounter in the chosen window.
#
# @param enc_analysis tibble returned by build_enc_analysis()
# @param cbc_events   tibble(ID, cbc_date) from build_cbc_events()
# @param anchors      tibble(ID, hl_anchor_date) from get_hl_any_dx_ids()
# @param window       "whole" (all encounters) or "post" (post_anchor == 1)
#
# @return tibble (one row per patient with >= 1 encounter in window):
#   ID, any_far (int 0/1), any_cbc (int 0/1), n_encounters (int)
#
# Definitions:
#   whole window:  any_far = max(far_from_care_100mi) across all encounters
#                  any_cbc = 1 if any CBC event in the whole record (any date)
#   post window:   any_far = max(far_from_care_100mi) among post_anchor == 1 encounters
#                  any_cbc = 1 if any cbc_date > hl_anchor_date
# ------------------------------------------------------------------------------
build_pat_analysis <- function(enc_analysis, cbc_events, anchors,
                               window = c("whole", "post")) {
  window <- match.arg(window)

  # Subset encounters by window
  enc_win <- if (window == "post") {
    enc_analysis |> dplyr::filter(post_anchor == 1L)
  } else {
    enc_analysis
  }

  # Patients in denominator (>= 1 encounter in window)
  pat_enc <- enc_win |>
    dplyr::group_by(ID) |>
    dplyr::summarise(
      any_far     = as.integer(any(far_from_care_100mi == 1L, na.rm = TRUE)),
      n_encounters = dplyr::n(),
      .groups = "drop"
    )

  # any_cbc: whole = any CBC in record; post = any CBC after anchor date
  if (window == "whole") {
    pat_cbc <- cbc_events |>
      dplyr::distinct(ID) |>
      dplyr::mutate(any_cbc = 1L)
  } else {
    # post: need anchor dates to determine post-anchor CBC
    pat_cbc <- cbc_events |>
      dplyr::inner_join(anchors |> dplyr::select(ID, hl_anchor_date), by = "ID") |>
      dplyr::filter(cbc_date > hl_anchor_date) |>
      dplyr::distinct(ID) |>
      dplyr::mutate(any_cbc = 1L)
  }

  # Combine: patients in denominator with CBC flag (0 if no CBC in window)
  pat_enc |>
    dplyr::left_join(pat_cbc |> dplyr::select(ID, any_cbc), by = "ID") |>
    dplyr::mutate(any_cbc = dplyr::coalesce(any_cbc, 0L)) |>
    dplyr::select(ID, any_far, any_cbc, n_encounters)
}
