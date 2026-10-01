# ==============================================================================
# utils/utils_death.R -- Credible death-date resolution per patient (Phase 161)
# ==============================================================================
#
# Purpose:
#   Defines resolve_death_date() and death_sensitivity_table(), the single
#   canonical source for death dates in person-time and survival analyses (D4).
#   Implements D1 (grace period), D2 (implausible -> NA, not censored at last
#   contact), and D3 (source-priority then earliest among consistent dates).
#
# Inputs:
#   - death_tbl    tibble: ID, DEATH_DATE, DEATH_SOURCE (one row per DEATH record)
#   - activity_tbl output of get_last_activity(); defines cohort IDs + last_observed
#   - grace_days   integer; D1 threshold (default 30L)
#
# Outputs:
#   - resolve_death_date():      tibble, one row per cohort ID
#   - death_sensitivity_table(): tibble, one row per grace_days value
#
# Dependencies:
#   - dplyr, tibble, purrr
#
# Requirements: N/A (utility module)
#
# ==============================================================================

library(dplyr)
library(tibble)
library(purrr)

#' PCORnet DEATH_SOURCE priority (lower = more credible). Codes not listed
#' (NI, UN, OT, missing) rank last. Confirm codes against 161-02 source distribution.
DEATH_SOURCE_PRIORITY <- c(N = 1L, S = 2L, D = 3L, L = 4L, T = 5L)

#' Resolve one credible death date per patient (Phase 161, D1-D3)
#'
#' @param death_tbl    tibble: ID, DEATH_DATE (Date), DEATH_SOURCE (optional),
#'                     one row per DEATH record
#' @param activity_tbl output of get_last_activity(); defines the cohort (its IDs)
#' @param grace_days   D1 grace period; activity > grace_days after death is implausible
#' @param source_priority named integer vector; lower = more credible
#' @return one row per cohort ID:
#'   death_date_raw           earliest recorded DEATH_DATE (NA if none)
#'   n_death_dates            distinct recorded dates
#'   death_date_resolved      credible death date, or NA (D2: no credible date)
#'   death_source_resolved    DEATH_SOURCE of the resolved date
#'   death_flag               plausible | conflicting_resolved |
#'                            implausible_post_activity | conflicting_unresolved |
#'                            no_death_record
#'   post_death_activity_days days from death_date_raw to last_observed (0 if none)
resolve_death_date <- function(death_tbl, activity_tbl, grace_days = 30L,
                               source_priority = DEATH_SOURCE_PRIORITY) {
  stopifnot(all(c("ID", "DEATH_DATE") %in% names(death_tbl)),
            all(c("ID", "last_observed") %in% names(activity_tbl)))
  if (!"DEATH_SOURCE" %in% names(death_tbl)) death_tbl$DEATH_SOURCE <- NA_character_

  cohort <- dplyr::distinct(activity_tbl, ID, last_observed)

  rows <- death_tbl |>
    dplyr::semi_join(cohort, by = "ID") |>
    dplyr::filter(!is.na(DEATH_DATE)) |>
    dplyr::mutate(DEATH_DATE = as.Date(DEATH_DATE),
                  src_code   = toupper(trimws(as.character(DEATH_SOURCE))),
                  src_rank   = dplyr::coalesce(unname(source_priority[src_code]), 99L)) |>
    dplyr::left_join(cohort, by = "ID") |>
    # D1: activity strictly more than grace_days after death is implausible.
    # No activity on record (last_observed NA) is treated as consistent because
    # the clinical record gives no evidence the patient was alive post-death.
    dplyr::mutate(consistent = is.na(last_observed) |
                    DEATH_DATE >= last_observed - grace_days)

  per_id <- rows |>
    dplyr::group_by(ID) |>
    dplyr::summarise(death_date_raw = min(DEATH_DATE),
                     n_death_dates  = dplyr::n_distinct(DEATH_DATE),
                     last_observed  = dplyr::first(last_observed),
                     any_consistent = any(consistent),
                     .groups = "drop")

  # D3: among consistent dates, highest-priority source first, then earliest date.
  # arrange() on src_rank then DEATH_DATE guarantees the right row is first
  # so distinct(ID, .keep_all = TRUE) picks it without any further tie-breaking.
  chosen <- rows |>
    dplyr::filter(consistent) |>
    dplyr::arrange(ID, src_rank, DEATH_DATE) |>
    dplyr::distinct(ID, .keep_all = TRUE) |>
    dplyr::transmute(ID, death_date_consistent = DEATH_DATE,
                     death_source_resolved = src_code)

  resolved <- per_id |>
    dplyr::left_join(chosen, by = "ID") |>
    dplyr::mutate(
      death_flag = dplyr::case_when(
        n_death_dates == 1 &  any_consistent ~ "plausible",
        n_death_dates == 1 & !any_consistent ~ "implausible_post_activity",
        n_death_dates  > 1 &  any_consistent ~ "conflicting_resolved",
        TRUE                                 ~ "conflicting_unresolved"),
      # D2: no credible date -> NA; patient is censored at last_observed, not dead
      death_date_resolved   = dplyr::if_else(any_consistent, death_date_consistent, as.Date(NA)),
      death_source_resolved = dplyr::if_else(any_consistent, death_source_resolved, NA_character_),
      post_death_activity_days = dplyr::coalesce(
        pmax(0L, as.integer(last_observed - death_date_raw)), 0L))

  no_rec <- cohort |>
    dplyr::anti_join(per_id, by = "ID") |>
    dplyr::transmute(ID,
                     death_date_raw           = as.Date(NA),
                     n_death_dates            = 0L,
                     death_date_resolved      = as.Date(NA),
                     death_source_resolved    = NA_character_,
                     death_flag               = "no_death_record",
                     post_death_activity_days = 0L)

  dplyr::bind_rows(
    dplyr::select(resolved, ID, death_date_raw, n_death_dates, death_date_resolved,
                  death_source_resolved, death_flag, post_death_activity_days),
    no_rec)
}

#' Flag counts across grace periods (documents the D1 choice)
#'
#' @param death_tbl    See resolve_death_date()
#' @param activity_tbl See resolve_death_date()
#' @param grace_values integer vector of grace-period thresholds to evaluate
#' @return tibble, one row per grace_days with counts by death_flag
death_sensitivity_table <- function(death_tbl, activity_tbl,
                                    grace_values = c(0L, 30L, 60L, 90L, 365L)) {
  levels_ <- c("plausible", "conflicting_resolved", "implausible_post_activity",
                "conflicting_unresolved", "no_death_record")
  purrr::map_dfr(grace_values, function(g) {
    r   <- resolve_death_date(death_tbl, activity_tbl, grace_days = g)
    cnt <- table(factor(r$death_flag, levels = levels_))
    tibble::tibble(grace_days                  = g,
                   n_plausible                 = cnt[["plausible"]],
                   n_conflicting_resolved      = cnt[["conflicting_resolved"]],
                   n_implausible_post_activity = cnt[["implausible_post_activity"]],
                   n_conflicting_unresolved    = cnt[["conflicting_unresolved"]],
                   # n_no_credible_death = patients whose death_date_resolved is NA
                   n_no_credible_death         = cnt[["implausible_post_activity"]] +
                                                 cnt[["conflicting_unresolved"]],
                   n_no_death_record           = cnt[["no_death_record"]])
  })
}
