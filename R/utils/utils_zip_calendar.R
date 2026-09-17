# ==============================================================================
# utils/utils_zip_calendar.R -- Patient ZIP calendar and best-ZIP selection
#                                (Phase 153)
# ==============================================================================
#
# Purpose:
#   Three exported pure functions implementing AM cleaning rules 2 and 3
#   (DIST-02: ZIP9 reduced to ZIP5 before distance; DIST-03: encounters with no
#   in-range patient ZIP receive the temporally nearest ZIP from the same
#   patient's address history, with provenance).
#
#   All logic follows MILESTONE_encounter_distance.md Appendix A, with the
#   pick_best_zip() arrange() revised per D-07 (two-zone ranking) and D-03
#   (equal-|days_offset| tie-break: prefer the earlier period).
#
# Inputs:
#   build_patient_zip_calendar(addr, study_end):
#     addr -- LDS_ADDRESS_HISTORY tibble with columns:
#             ID, ADDRESS_ZIP9, ADDRESS_ZIP5, ADDRESS_PERIOD_START,
#             ADDRESS_PERIOD_END
#     study_end -- Date; open ADDRESS_PERIOD_END entries are closed at this
#                  date (default 2025-03-31 = CONFIG$analysis$date_range_max)
#
#   pick_best_zip(enc, cal):
#     enc -- tibble with columns: ID, ENCOUNTERID, ADMIT_DATE
#     cal -- output of build_patient_zip_calendar()
#
#   compute_encounter_distance(enc, cal):
#     enc -- tibble with columns: ID, ENCOUNTERID, ADMIT_DATE, zip5_facility
#            (facility ZIP5 already normalized upstream by R/122)
#     cal -- output of build_patient_zip_calendar()
#
# Outputs:
#   build_patient_zip_calendar() -- tibble: ID, zip9, zip5, zip_len, start, end
#     One row per (ID, ZIP, period). Exact duplicates and touching/overlapping
#     periods with the same ZIP merged into one run. Open periods closed at
#     study_end. Sentinel and NA ZIP5 rows excluded.
#
#   pick_best_zip() -- tibble: ID, ENCOUNTERID, ADMIT_DATE,
#     zip9_patient, zip5_patient, zip5_patient_source, days_offset,
#     n_candidates_in_range
#     zip5_patient_source in {in_range_zip9, in_range_zip5, nearest_zip9,
#     nearest_zip5}. days_offset is a signed integer: 0 for in-range, negative
#     when the encounter precedes the period (period is after), positive when
#     the encounter follows the period (period is before).
#
#   compute_encounter_distance() -- tibble: ID, ENCOUNTERID, zip9_patient,
#     zip5_patient, zip5_patient_source, days_offset, n_candidates_in_range,
#     zip5_facility, distance_mi, distance_km, distance_status
#     (ADMIT_DATE is NOT returned; use pick_best_zip() directly if needed).
#     distance_status in {computed, facility_zip_missing, patient_zip_missing,
#     zip_not_in_db}. days_offset, zip5_patient_source, and
#     n_candidates_in_range are carried through from pick_best_zip() for
#     provenance.
#
# Dependencies:
#   - normalize_zip9(), normalize_zip5(), normalize_zip5_raw(),
#     is_sentinel_zip5(), parse_pcornet_date() from R/utils/utils_address.R
#     (auto-sourced by R/00_config.R; do NOT redefine here)
#   - dplyr (via suppressPackageStartupMessages below)
#   - zipcodeR::zip_distance() for centroid great-circle distance (miles)
#
# Requirements: Phase 153 -- DIST-02, DIST-03
#
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(zipcodeR)
})

# ---- A. Patient ZIP calendar ------------------------------------------------
#
# Build one row per (ID, ZIP, period) from LDS_ADDRESS_HISTORY.
# - ZIP9 rows carry their ZIP5 (derived from normalize_zip5(ADDRESS_ZIP5) or
#   from the leading 5 characters of the normalized ZIP9).
# - ZIP5-only rows kept with zip_len = 5; ZIP9 rows carry zip_len = 9.
# - Rows with NA or sentinel ZIP5 are excluded.
# - Exact duplicates and touching/overlapping same-ZIP periods are merged into
#   one run per (ID, ZIP).
# - Open ADDRESS_PERIOD_END values are closed at study_end.
#
# NOTE: normalize_zip9 / normalize_zip5 / is_sentinel_zip5 come from
# utils_address.R (auto-sourced by R/00_config.R). They are NOT redefined here.
#
.report_zip5_disagreement <- function(d) {
  n_disagree <- sum(!is.na(d$zip9) & !is.na(d$zip5_col) &
                    substr(d$zip9, 1, 5) != d$zip5_col)
  if (n_disagree > 0) {
    message(sprintf("  [zip_calendar] %d rows where ADDRESS_ZIP5 != first 5 of ADDRESS_ZIP9; ZIP9 prefix used",
                    n_disagree))
  }
  d
}

.drop_bad_periods <- function(d) {
  n_na_start <- sum(is.na(d$start))
  n_reversed <- sum(!is.na(d$start) & d$start > d$end)
  if (n_na_start > 0) message(sprintf("  [zip_calendar] dropping %d rows with NA ADDRESS_PERIOD_START", n_na_start))
  if (n_reversed > 0) message(sprintf("  [zip_calendar] dropping %d rows with start > end", n_reversed))
  d |> filter(!is.na(start), start <= end)
}

build_patient_zip_calendar <- function(addr, study_end = as.Date("2025-03-31")) {
  addr |>
    mutate(ID = as.character(ID)) |>
    transmute(
      ID,
      zip9     = normalize_zip9(ADDRESS_ZIP9),
      zip5_col = normalize_zip5(ADDRESS_ZIP5),
      zip5     = if_else(!is.na(zip9), substr(zip9, 1, 5), zip5_col),
      start    = parse_pcornet_date(ADDRESS_PERIOD_START),
      end      = coalesce(parse_pcornet_date(ADDRESS_PERIOD_END), study_end)
    ) |>
    .report_zip5_disagreement() |>
    select(-zip5_col) |>
    # Drop rows with no usable ZIP5
    filter(!is.na(zip5)) |>
    # Drop sentinel/placeholder ZIP5s (00000, 99999, repeated-digit, < 00501).
    # is_sentinel_zip5() returns NA for NA input; the prior filter(!is.na(zip5))
    # guarantees zip5 is non-NA here, so !is_sentinel_zip5(zip5) is NA-safe.
    filter(!is_sentinel_zip5(zip5)) |>
    .drop_bad_periods() |>
    mutate(
      zip_key = coalesce(zip9, zip5),
      zip_len = if_else(is.na(zip9), 5L, 9L)
    ) |>
    # Collapse exact duplicates and touching/overlapping same-ZIP periods into
    # one run: arrange by (ID, zip_key, start), then identify run boundaries
    # where a new period starts AFTER the cumulative max(end) + 1 day of all
    # prior rows in the same (ID, zip_key) group.
    arrange(ID, zip_key, start) |>
    group_by(ID, zip_key) |>
    mutate(
      prev_max_end = lag(cummax(as.integer(end))),
      new_run      = is.na(prev_max_end) | as.integer(start) > prev_max_end + 1L,
      run          = cumsum(new_run)
    ) |>
    group_by(ID, zip_key, zip9, zip5, zip_len, run) |>
    summarise(start = min(start), end = max(end), .groups = "drop") |>
    select(ID, zip9, zip5, zip_len, start, end) |>
    arrange(ID, start)
}


# ---- B. Best ZIP for an encounter date --------------------------------------
#
# For each (ID, ENCOUNTERID), join to all candidate calendar rows and rank by
# the D-07 two-zone priority:
#
#   Zone 1 — in-range candidates (period covers ADMIT_DATE):
#     Ranked by zip_len desc (ZIP9 > ZIP5), then abs(days_offset) (= 0 for
#     all in-range), then desc(days_offset) (D-03 tie-break: prefer earlier).
#     An in-range ZIP5 ALWAYS beats any out-of-range ZIP9.
#
#   Zone 2 — out-of-range candidates (no period covers ADMIT_DATE):
#     Ranked by abs(days_offset) only — ZIP tier is IGNORED for the nearest
#     address in time. Tie on abs(days_offset): prefer earlier period
#     (desc(days_offset), D-03).
#
# Implemented via a single arrange() that achieves the two-zone logic:
#   arrange(desc(in_range),
#           if_else(in_range, -zip_len, 0L),   # ascending: -9 < -5 (ZIP9 first)
#                                               # uniform 0 for out-of-range so
#                                               # their zip tier has no effect
#           abs(days_offset),
#           desc(days_offset))
#
# days_offset: 0 for in-range; negative when ADMIT_DATE < period start (period
# is after the encounter); positive when ADMIT_DATE > period end (period is
# before the encounter). desc(days_offset) sorts positive (earlier period) ahead
# of negative (later period) on a tie — implements D-03.
#
pick_best_zip <- function(enc, cal) {
  enc |>
    mutate(ID = as.character(ID), ADMIT_DATE = as.Date(ADMIT_DATE)) |>
    inner_join(cal, by = "ID", relationship = "many-to-many") |>
    mutate(
      in_range    = ADMIT_DATE >= start & ADMIT_DATE <= end,
      days_offset = case_when(
        in_range           ~ 0L,
        ADMIT_DATE < start ~ as.integer(ADMIT_DATE - start),  # negative: period after encounter
        TRUE               ~ as.integer(ADMIT_DATE - end)     # positive: period before encounter
      )
    ) |>
    # D-07 two-zone ranking (departure from Appendix A's single flat arrange):
    # desc(in_range)            -- Zone 1 (in-range) beats Zone 2 (out-of-range)
    # if_else(in_range,-zip_len,0L) -- within Zone 1: ZIP9 (-9) ahead of ZIP5 (-5);
    #                                  0 uniformly for Zone 2 so zip tier has no effect there
    # abs(days_offset)          -- within each zone: nearest in time first
    # desc(days_offset)         -- D-03 tie-break: positive offset (earlier period) first
    arrange(ID, ENCOUNTERID,
            desc(in_range),
            if_else(in_range, -zip_len, 0L),
            abs(days_offset),
            desc(days_offset)) |>
    group_by(ID, ENCOUNTERID) |>
    mutate(n_candidates_in_range = sum(in_range)) |>
    slice(1) |>
    ungroup() |>
    transmute(
      ID, ENCOUNTERID, ADMIT_DATE,
      zip9_patient = zip9,
      zip5_patient = zip5,
      zip5_patient_source = case_when(
        in_range & zip_len == 9 ~ "in_range_zip9",
        in_range                ~ "in_range_zip5",
        zip_len == 9            ~ "nearest_zip9",
        TRUE                    ~ "nearest_zip5"
      ),
      days_offset,
      n_candidates_in_range
    )
}


#' Compute patient-to-encounter distance using zipcodeR::zip_distance().
#'
#' @param enc Tibble with columns ID, ENCOUNTERID, ADMIT_DATE, zip5_facility.
#'   zip5_facility is the facility ZIP5 already normalized upstream by R/122
#'   (from ENCOUNTER.FACILITY_LOCATION); it is NEVER imputed — a blank facility
#'   ZIP is reported as distance_status = "facility_zip_missing" (D-04).
#' @param cal Output of build_patient_zip_calendar().
#'
#' @return Tibble: all columns from pick_best_zip() (ID, ENCOUNTERID,
#'   zip9_patient, zip5_patient, zip5_patient_source, days_offset,
#'   n_candidates_in_range) plus zip5_facility, distance_mi, distance_km,
#'   distance_status.
#'
#' distance_status values:
#'   "facility_zip_missing" -- ENCOUNTER.FACILITY_LOCATION was blank; patient
#'     ZIP fill (rule 3) is irrelevant — a missing facility ZIP is a separate
#'     data quality problem, not addressed by LDS_ADDRESS_HISTORY (D-04).
#'     NOTE: facility_zip_missing is classified FIRST in case_when to ensure
#'     a blank facility ZIP is never silently treated as a patient-side problem.
#'     Do NOT reorder the case_when branches to impute facility ZIPs.
#'   "patient_zip_missing" -- no address history exists for this patient at all.
#'   "zip_not_in_db"       -- ZIP5 not found in zipcodeR's zip_code_db.
#'   "computed"            -- distance_mi and distance_km are valid.
#'
#' days_offset, zip5_patient_source, and n_candidates_in_range are carried
#' through from pick_best_zip() for downstream provenance and QC reporting.
#'
compute_encounter_distance <- function(enc, cal) {
  enc <- enc |> mutate(ID = as.character(ID))
  best <- pick_best_zip(enc, cal)

  out <- enc |>
    select(ID, ENCOUNTERID, zip5_facility) |>
    left_join(best |> select(-ADMIT_DATE), by = c("ID", "ENCOUNTERID"))

  # Compute distance on DISTINCT (zip5_patient, zip5_facility) pairs for
  # performance (zip_distance() is vectorised but slow on millions of pairs).
  # Join computed distances back to the full encounter table.
  pairs <- out |>
    distinct(zip5_patient, zip5_facility) |>
    filter(!is.na(zip5_patient), !is.na(zip5_facility))

  zd <- zip_distance(pairs$zip5_patient, pairs$zip5_facility, units = "miles")
  stopifnot(
    "zip_distance() returned a different number of rows than input pairs" =
      nrow(zd) == nrow(pairs),
    "zip_distance() output order does not match input pairs" =
      identical(as.character(zd$zipcode_a), pairs$zip5_patient)
  )
  pairs$distance_mi <- zd$distance

  out |>
    left_join(pairs, by = c("zip5_patient", "zip5_facility")) |>
    mutate(
      distance_km = distance_mi * 1.609344,
      # IMPORTANT: facility_zip_missing is classified FIRST.
      # A blank facility ZIP is a data quality issue separate from patient-side
      # fill (rule 3). Do NOT reorder to impute facility location.
      distance_status = case_when(
        is.na(zip5_facility) ~ "facility_zip_missing",
        is.na(zip5_patient)  ~ "patient_zip_missing",
        is.na(distance_mi)   ~ "zip_not_in_db",
        TRUE                 ~ "computed"
      )
    )
}
