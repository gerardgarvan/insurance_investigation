# ==============================================================================
# utils_cohort_rule.R -- Phase 212 cohort rule (v3.15) helpers
# ==============================================================================
# Pure functions: no file I/O, no DuckDB, no patient-level output.
# Column names are arguments; defaults (ID, ENCOUNTERID, DX_DATE) must be
# confirmed against the Phase 212 schema probe before use in R/212 and R/47.
#
# Rule A (user decisions 2026-11-17):
#   >= 2 HL diagnoses on distinct encounters. With require_diff_dates = TRUE
#   (config DISTINCT_ENC_REQUIRE_DIFF_DATES, default TRUE) the two encounters must
#   also fall on different dates; FALSE = distinct ENCOUNTERIDs only.
#   A diagnosis row with missing ENCOUNTERID counts as its own encounter keyed by
#   its diagnosis date (DX_DATE, else fallback_date_col, e.g. ADMIT_DATE).
#
# Uses fmt_sup() from utils_abvd_impact.R (not redefined here).
# ==============================================================================

#' Patients meeting rule A (distinct encounters, optionally on different dates).
#'
#' @param dx_hl data frame of HL diagnosis rows.
#' @param require_diff_dates TRUE: >= 2 distinct encounters AND >= 2 distinct dates.
#' @param fallback_date_col optional column used when date_col is NA (e.g. "ADMIT_DATE").
#' @return tibble with one column `ID` (qualifying patients). Attributes:
#'   `fallback_rows`: tibble(ID, n_rows) of rows whose ENCOUNTERID was missing
#'     (counted as their own encounter keyed by date), only rows with a usable date key;
#'   `n_rows_no_key`: rows with neither ENCOUNTERID nor any date (dropped);
#'   `fallback_only_ids`: IDs that qualify only because of fallback rows.
hl_confirmed_two_encounters <- function(dx_hl,
                                        id_col = "ID",
                                        enc_col = "ENCOUNTERID",
                                        date_col = "DX_DATE",
                                        require_diff_dates = TRUE,
                                        fallback_date_col = NULL) {
  stopifnot(is.data.frame(dx_hl),
            all(c(id_col, enc_col, date_col) %in% names(dx_hl)),
            is.logical(require_diff_dates), length(require_diff_dates) == 1L)
  if (!is.null(fallback_date_col) && !fallback_date_col %in% names(dx_hl))
    stop("fallback_date_col not in dx_hl: ", fallback_date_col)

  d <- dplyr::tibble(
    ID   = as.character(dx_hl[[id_col]]),
    enc  = as.character(dx_hl[[enc_col]]),
    date = as.Date(dx_hl[[date_col]])
  )
  if (!is.null(fallback_date_col)) {
    fb <- as.Date(dx_hl[[fallback_date_col]])
    d$date <- dplyr::coalesce(d$date, fb)
  }
  d$enc[!is.na(d$enc) & !nzchar(trimws(d$enc))] <- NA_character_
  d <- d[!is.na(d$ID), , drop = FALSE]

  d$is_fallback <- is.na(d$enc)
  n_rows_no_key <- sum(d$is_fallback & is.na(d$date))
  d <- d[!(d$is_fallback & is.na(d$date)), , drop = FALSE]
  d$enc_key <- ifelse(d$is_fallback, paste0("NOENC|", format(d$date)), d$enc)

  qualify <- function(x) {
    x |>
      dplyr::distinct(ID, enc_key, date) |>
      dplyr::group_by(ID) |>
      dplyr::summarise(
        n_enc = dplyr::n_distinct(enc_key),
        n_dates = dplyr::n_distinct(date[!is.na(date)]),
        .groups = "drop"
      ) |>
      dplyr::filter(n_enc >= 2L, !require_diff_dates | n_dates >= 2L) |>
      dplyr::pull(ID)
  }

  ids_all    <- qualify(d)
  ids_strict <- qualify(d[!d$is_fallback, , drop = FALSE])

  out <- dplyr::tibble(ID = sort(ids_all))
  attr(out, "fallback_rows") <- d[d$is_fallback, , drop = FALSE] |>
    dplyr::count(ID, name = "n_rows")
  attr(out, "n_rows_no_key") <- n_rows_no_key
  attr(out, "fallback_only_ids") <- setdiff(ids_all, ids_strict)
  out
}

#' Apply the v3.15 membership rule and return the sequential waterfall sets.
#'
#' Steps (each patient counted once): old -> lost_2enc (old, not rule A, not TR-HL)
#' -> gained_drop7 (rule A, not old) -> gained_trhl (TR-HL, not old, not rule A)
#' -> lost_trnhl (TR-NHL and not TR-HL) -> new.
#' TR-HL IDs are intersected with ids_demog (D-212-01).
apply_cohort_rule_v315 <- function(ids_dx2, ids_tr_hl, ids_tr_nhl, ids_old, ids_demog) {
  ids_dx2    <- unique(as.character(ids_dx2))
  ids_old    <- unique(as.character(ids_old))
  # TR-NHL exclusion uses all TR-HL IDs (D-212-03): a TR-HL patient is never excluded,
  # even if absent from DEMOGRAPHIC and therefore not included.
  nhl_only   <- setdiff(unique(as.character(ids_tr_nhl)), unique(as.character(ids_tr_hl)))
  ids_tr_hl  <- intersect(unique(as.character(ids_tr_hl)), as.character(ids_demog))

  lost_2enc    <- setdiff(ids_old, union(ids_dx2, ids_tr_hl))
  gained_drop7 <- setdiff(ids_dx2, ids_old)
  gained_trhl  <- setdiff(ids_tr_hl, union(ids_old, ids_dx2))
  pre_nhl      <- union(union(setdiff(ids_old, lost_2enc), gained_drop7), gained_trhl)
  lost_trnhl   <- intersect(pre_nhl, nhl_only)
  new          <- setdiff(pre_nhl, lost_trnhl)

  new_direct <- setdiff(union(ids_dx2, ids_tr_hl), nhl_only)
  if (!setequal(new, new_direct) ||
      length(ids_old) - length(lost_2enc) + length(gained_drop7) +
        length(gained_trhl) - length(lost_trnhl) != length(new)) {
    stop("apply_cohort_rule_v315: waterfall steps do not reconcile to new cohort")
  }
  list(old = ids_old, lost_2enc = lost_2enc, gained_drop7 = gained_drop7,
       gained_trhl = gained_trhl, lost_trnhl = lost_trnhl, new = new)
}

COHORT_WATERFALL_STEPS <- c(
  old          = "Old cohort (>= 2 HL dates, >= 7 days apart, + TR)",
  lost_2enc    = "Lost: old member without 2 distinct HL encounters (not TR-HL)",
  gained_drop7 = "Gained: 2 distinct HL encounters (7-day rule removed)",
  gained_trhl  = "Gained: TR-HL patient not otherwise included",
  lost_trnhl   = "Lost: TR-NHL and not TR-HL",
  new          = "New cohort"
)

#' Counts per waterfall step x site (+ ALL). 1-10 shown "<11". No rates.
#' @param sets output of apply_cohort_rule_v315().
#' @param site_map data frame with columns ID and site.
#' @return long tibble: step, label, site, n, n_display.
cohort_waterfall_by_site <- function(sets, site_map) {
  stopifnot(is.data.frame(site_map), all(c("ID", "site") %in% names(site_map)))
  sm <- site_map |>
    dplyr::mutate(ID = as.character(ID), site = as.character(site)) |>
    dplyr::distinct(ID, .keep_all = TRUE)
  rows <- lapply(names(COHORT_WATERFALL_STEPS), function(s) {
    ids <- unique(as.character(sets[[s]]))
    site <- sm$site[match(ids, sm$ID)]
    site[is.na(site)] <- "Not in DEMOGRAPHIC"
    by_site <- as.data.frame(table(site), stringsAsFactors = FALSE)
    dplyr::bind_rows(
      dplyr::tibble(site = "ALL", n = length(ids)),
      dplyr::tibble(site = by_site$site, n = as.numeric(by_site$Freq))
    ) |>
      dplyr::mutate(step = s, label = unname(COHORT_WATERFALL_STEPS[s]))
  })
  dplyr::bind_rows(rows) |>
    dplyr::mutate(n_display = fmt_sup(n)) |>
    dplyr::select(step, label, site, n, n_display)
}

#' Rows and patients that needed the missing-ENCOUNTERID fallback, by site. <11 suppressed.
#' @param fallback_rows tibble(ID, n_rows) (attribute of hl_confirmed_two_encounters()).
fallback_summary_by_site <- function(fallback_rows, site_map) {
  sm <- site_map |>
    dplyr::mutate(ID = as.character(ID), site = as.character(site)) |>
    dplyr::distinct(ID, .keep_all = TRUE)
  f <- fallback_rows |>
    dplyr::mutate(ID = as.character(ID), site = sm$site[match(ID, sm$ID)]) |>
    dplyr::mutate(site = dplyr::coalesce(site, "Not in DEMOGRAPHIC"))
  by_site <- f |>
    dplyr::group_by(site) |>
    dplyr::summarise(n_rows = sum(n_rows), n_patients = dplyr::n_distinct(ID), .groups = "drop")
  all_row <- dplyr::tibble(site = "ALL", n_rows = sum(f$n_rows),
                           n_patients = dplyr::n_distinct(f$ID))
  dplyr::bind_rows(all_row, by_site) |>
    dplyr::mutate(rows_display = fmt_sup(n_rows), patients_display = fmt_sup(n_patients))
}

#' Site attribution by R/169 primary_source (D-212-06). DEMOGRAPHIC SOURCE is not used
#' because it includes 'LNK' (linked multi-site records), which is not a site.
#' Patients with an R/169 row and non-NA primary_source keep it. Others get the R/169
#' logic (R/169_single_source_care.R build_single_source_result): most common non-blank
#' encounter SOURCE (upper-cased, trimmed), alphabetical tiebreak. Patients with no
#' non-blank encounter SOURCE are labelled "unassigned".
#' @param ids character vector of patient IDs.
#' @param ssc data frame with ID, primary_source (R/169 output).
#' @param source_counts data frame with ID, SOURCE, n_enc_at_source (any case/blank allowed).
#' @return tibble(ID, site, origin) with origin in r169 / computed / unassigned.
assign_primary_source <- function(ids, ssc, source_counts) {
  stopifnot(all(c("ID", "primary_source") %in% names(ssc)),
            all(c("ID", "SOURCE", "n_enc_at_source") %in% names(source_counts)))
  ids <- unique(as.character(ids))
  r169 <- dplyr::tibble(ID = as.character(ssc$ID),
                        site = as.character(ssc$primary_source)) |>
    dplyr::filter(!is.na(site), nzchar(trimws(site))) |>
    dplyr::distinct(ID, .keep_all = TRUE)
  comp <- dplyr::tibble(ID = as.character(source_counts$ID),
                        SOURCE = toupper(trimws(as.character(source_counts$SOURCE))),
                        n = as.numeric(source_counts$n_enc_at_source)) |>
    dplyr::filter(!is.na(SOURCE), nzchar(SOURCE)) |>
    dplyr::group_by(ID, SOURCE) |>
    dplyr::summarise(n = sum(n), .groups = "drop") |>
    dplyr::group_by(ID) |>
    dplyr::arrange(dplyr::desc(n), SOURCE, .by_group = TRUE) |>
    dplyr::slice_head(n = 1) |>
    dplyr::ungroup() |>
    dplyr::transmute(ID, site = SOURCE)
  out <- dplyr::tibble(ID = ids)
  out$site <- r169$site[match(ids, r169$ID)]
  out$origin <- ifelse(is.na(out$site), NA_character_, "r169")
  need <- is.na(out$site)
  out$site[need] <- comp$site[match(ids[need], comp$ID)]
  out$origin[need & !is.na(out$site)] <- "computed"
  out$origin[is.na(out$site)] <- "unassigned"
  out$site[is.na(out$site)] <- "unassigned"
  out
}


#' Restrict Gantt episode and detail tables to confirmed-cohort patients (Phase 213).
#'
#' Removes rows (including Death rows) whose patient_id is not in cohort_ids.
#' Prints counts only (rows and patients removed), split by reason:
#' TR-NHL-only excluded by COHORT-03 vs other non-cohort. Counts 1-10 print as "<11".
#' Patient IDs are never printed.
#'
#' @param episodes,detail Data frames with a patient_id column.
#' @param cohort_ids Character vector of confirmed-cohort IDs.
#' @param nhl_only_ids Character vector of TR-NHL-only IDs (tr_nhl_dx TRUE, tr_hl_dx not TRUE),
#'   or NULL when the split is unavailable (reported as not available).
#' @param label Script label for messages.
#' @return list(episodes, detail)
filter_gantt_to_cohort <- function(episodes, detail, cohort_ids, nhl_only_ids = NULL, label = "gantt") {
  sup <- function(n) if (is.na(n)) "NA" else if (n >= 1L && n <= 10L) "<11" else format(n, big.mark = ",")
  cohort_ids <- unique(as.character(cohort_ids))
  ep_out  <- !as.character(episodes$patient_id) %in% cohort_ids
  det_out <- !as.character(detail$patient_id) %in% cohort_ids
  out_ids <- unique(c(as.character(episodes$patient_id[ep_out]),
                      as.character(detail$patient_id[det_out])))
  if (is.null(nhl_only_ids)) {
    n_nhl <- NA_integer_
  } else {
    n_nhl <- sum(out_ids %in% as.character(nhl_only_ids))
  }
  n_other <- if (is.na(n_nhl)) NA_integer_ else length(out_ids) - n_nhl
  message(sprintf("[%s] cohort-only filter (confirmed_hl_cohort.rds): episode rows removed %s, detail rows removed %s",
                  label, sup(sum(ep_out)), sup(sum(det_out))))
  message(sprintf("[%s]   patients removed %s: TR-NHL-only excluded by COHORT-03 %s; other non-cohort %s",
                  label, sup(length(out_ids)), sup(n_nhl), sup(n_other)))
  episodes <- episodes[!ep_out, , drop = FALSE]
  detail   <- detail[!det_out, , drop = FALSE]
  hl_pts <- unique(as.character(episodes$patient_id[episodes$treatment_type %in% "HL Diagnosis"]))
  ep_pts <- unique(as.character(episodes$patient_id))
  stopifnot(
    "episode patients not all in cohort" = all(ep_pts %in% cohort_ids),
    "detail patients not all in cohort"  = all(unique(as.character(detail$patient_id)) %in% cohort_ids),
    "distinct episode patients != HL Diagnosis patients" = length(ep_pts) == length(hl_pts) && setequal(ep_pts, hl_pts)
  )
  message(sprintf("[%s]   episodes %s rows, %s patients; detail %s rows; HL Diagnosis patients %s (equal)",
                  label, sup(nrow(episodes)), sup(length(ep_pts)), sup(nrow(detail)), sup(length(hl_pts))))
  list(episodes = episodes, detail = detail)
}

#' TR-NHL-only IDs among `ids` (tr_nhl_dx TRUE and tr_hl_dx not TRUE); NULL if TR unavailable.
tr_nhl_only_among <- function(ids) {
  ids <- unique(as.character(ids))
  if (length(ids) == 0L) return(character(0))
  trf <- tryCatch(build_tr_lymphoma_flags(ids), error = function(e) NULL)
  if (is.null(trf)) return(NULL)
  as.character(trf$patient_id[trf$tr_nhl_dx %in% TRUE & !(trf$tr_hl_dx %in% TRUE)])
}
