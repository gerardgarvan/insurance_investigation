# ==============================================================================
# utils/utils_regimen.R -- Regimen classification and line-of-therapy helpers
# ==============================================================================
#
# Purpose:
#   Pure functions for assigning regimen labels and line-of-therapy (LOT) numbers
#   to treatment episode data frames. No I/O, no side effects. Intended to be
#   sourced via R/00_config.R auto-sourcing. Phase: 205.
#
# Inputs:
#   - None (utility function library, not a standalone script)
#
# Outputs:
#   - None (defines functions loaded into calling scripts' environment)
#
# Dependencies:
#   - dplyr: group_by, arrange, mutate, summarise
#   - tibble: tibble construction
#   - R/00_config.R: REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS, LOT_GAP_DAYS,
#                    MAINTENANCE_DRUG_CLASSES
#
# Requirements: REGL-01, REGL-02, REGL-03, REGL-04, REGL-08
#
# ==============================================================================


# ------------------------------------------------------------------------------
# match_regimen_family()
# Internal helper: test whether a character vector of canonical drug names
# satisfies a single REGIMEN_DICT family definition.
#
# Args:
#   canonical_drugs  character vector — drugs present in the episode window
#   family_def       one element of REGIMEN_DICT (a list with $drugs, $exclusive)
#
# Returns: TRUE/FALSE
# ------------------------------------------------------------------------------
match_regimen_family <- function(canonical_drugs, family_def) {
  required   <- family_def$drugs
  exclusive  <- isTRUE(family_def$exclusive)

  # All required drugs must be present (case-insensitive).
  all_present <- all(tolower(required) %in% tolower(canonical_drugs))
  if (!all_present) return(FALSE)

  # For exclusive families, no drug outside the required set may be present.
  # Compare lowercased drug tokens; ignore drugs that ARE in the required set.
  if (exclusive) {
    extra <- setdiff(tolower(canonical_drugs), tolower(required))
    if (length(extra) > 0L) return(FALSE)
  }

  TRUE
}


# Treatment types that can carry a regimen label. Radiation, SCT and Proton
# episodes always get NA. Episode numbers are unique only within
# (ID, treatment_type), so treatment_type is part of every join key.
REGIMEN_SYSTEMIC_TYPES    <- c("Chemotherapy", "Immunotherapy")
REGIMEN_UNRECOGNIZED_LABEL <- "Unrecognized systemic"


# ------------------------------------------------------------------------------
# label_one_regimen_episode()
# Internal helper: label a single systemic episode.
#
# Args:
#   pooled_drugs  drugs (Chemotherapy + Immunotherapy rows of the patient) within
#                 the window of the episode start
#   own_drugs     subset of pooled_drugs recorded on this episode's own type
#   ep_type       "Chemotherapy" or "Immunotherapy"
#   post_sct      TRUE if an SCT episode precedes this episode within the window
#   regimen_dict  REGIMEN_DICT
#
# Returns: family name, REGIMEN_UNRECOGNIZED_LABEL, or NA_character_
#   - Chemotherapy: matched family; else "Unrecognized systemic" if any drug name
#     is present; else NA.
#   - Immunotherapy: matched family only when every drug on the episode belongs
#     to the matched family; otherwise NA.
# ------------------------------------------------------------------------------
label_one_regimen_episode <- function(pooled_drugs, own_drugs, ep_type,
                                      post_sct, regimen_dict) {
  matched <- NA_character_
  for (family_name in names(regimen_dict)) {
    fam <- regimen_dict[[family_name]]
    if (isTRUE(fam$requires_prior_sct) && !isTRUE(post_sct)) next
    if (match_regimen_family(pooled_drugs, fam)) {
      matched <- family_name
      break
    }
  }

  if (!is.na(matched)) {
    if (identical(ep_type, "Immunotherapy")) {
      in_family <- length(own_drugs) > 0L &&
        all(tolower(own_drugs) %in% tolower(regimen_dict[[matched]]$drugs))
      return(if (in_family) matched else NA_character_)
    }
    return(matched)
  }

  if (identical(ep_type, "Chemotherapy") && length(pooled_drugs) > 0L) {
    return(REGIMEN_UNRECOGNIZED_LABEL)
  }
  NA_character_
}


# ------------------------------------------------------------------------------
# assign_regimen()
# REGL-01, REGL-02, REGL-04
#
# Labels each systemic-therapy episode (Chemotherapy, Immunotherapy) by matching
# the drugs present within window_days of the episode start against
# REGIMEN_DICT. Drugs are pooled across the patient's Chemotherapy and
# Immunotherapy rows so combinations such as BV+AVD (BV is Immunotherapy, AVD is
# Chemotherapy) are recognised; each episode is still labeled under its own
# (ID, treatment_type, episode_number) key.
#
# Args:
#   date_level_df  data frame with columns:
#                    ID, treatment_date (Date), treatment_type, canonical_drug,
#                    episode_number, start_date (Date)
#   regimen_dict   named list; defaults to REGIMEN_DICT. Families with
#                  requires_prior_sct = TRUE match only after an SCT episode.
#   window_days    half-width of concurrency window in days
#   sct_df         NULL or data frame (ID, sct_start, sct_stop) of SCT episodes
#   sct_window_days  days after sct_stop within which BV consolidation may start
#
# Returns: tibble, one row per systemic (ID, treatment_type, episode_number):
#   ID, treatment_type, episode_number, regimen_label (NA where no regimen)
# ------------------------------------------------------------------------------
assign_regimen <- function(date_level_df,
                           regimen_dict    = REGIMEN_DICT,
                           window_days     = CONCURRENCY_WINDOW_DAYS,
                           sct_df          = NULL,
                           sct_window_days = if (exists("BV_CONSOLIDATION_SCT_WINDOW_DAYS"))
                             BV_CONSOLIDATION_SCT_WINDOW_DAYS else 90L) {

  stopifnot(
    is.data.frame(date_level_df),
    all(c("ID", "treatment_date", "treatment_type", "canonical_drug",
          "episode_number", "start_date") %in% names(date_level_df)),
    is.numeric(window_days) || is.integer(window_days),
    length(window_days) == 1L,
    is.null(sct_df) || (is.data.frame(sct_df) &&
      all(c("ID", "sct_start", "sct_stop") %in% names(sct_df)))
  )

  sys_rows <- date_level_df %>%
    dplyr::filter(.data$treatment_type %in% REGIMEN_SYSTEMIC_TYPES,
                  !is.na(.data$canonical_drug))

  ep_keys <- sys_rows %>%
    dplyr::group_by(.data$ID, .data$treatment_type, .data$episode_number) %>%
    dplyr::summarise(start_date = .data$start_date[1L], .groups = "drop")

  pool <- sys_rows %>%
    dplyr::select("ID", pool_date = "treatment_date",
                  pool_type = "treatment_type", pool_drug = "canonical_drug")

  episode_drugs <- ep_keys %>%
    dplyr::inner_join(pool, by = "ID", relationship = "many-to-many") %>%
    dplyr::mutate(days_from_start = as.integer(.data$pool_date - .data$start_date)) %>%
    dplyr::filter(abs(.data$days_from_start) <= as.integer(window_days)) %>%
    dplyr::group_by(.data$ID, .data$treatment_type, .data$episode_number,
                    .data$start_date) %>%
    dplyr::summarise(
      pooled_drugs = list(unique(.data$pool_drug)),
      own_drugs    = list(unique(.data$pool_drug[.data$pool_type == dplyr::first(.data$treatment_type)])),
      .groups = "drop"
    )

  # post_sct flag per episode: an SCT episode started before and ended within
  # sct_window_days of this episode's start.
  if (!is.null(sct_df) && nrow(sct_df) > 0L) {
    sct_flag <- episode_drugs %>%
      dplyr::select("ID", "treatment_type", "episode_number", "start_date") %>%
      dplyr::inner_join(sct_df, by = "ID", relationship = "many-to-many") %>%
      dplyr::filter(.data$start_date >= .data$sct_start,
                    .data$start_date <= .data$sct_stop + as.integer(sct_window_days)) %>%
      dplyr::distinct(.data$ID, .data$treatment_type, .data$episode_number) %>%
      dplyr::mutate(post_sct = TRUE)
    episode_drugs <- dplyr::left_join(
      episode_drugs, sct_flag,
      by = c("ID", "treatment_type", "episode_number"))
    episode_drugs$post_sct <- dplyr::coalesce(episode_drugs$post_sct, FALSE)
  } else {
    episode_drugs$post_sct <- FALSE
  }

  episode_drugs$regimen_label <- vapply(seq_len(nrow(episode_drugs)), function(i) {
    label_one_regimen_episode(
      pooled_drugs = episode_drugs$pooled_drugs[[i]],
      own_drugs    = episode_drugs$own_drugs[[i]],
      ep_type      = episode_drugs$treatment_type[i],
      post_sct     = episode_drugs$post_sct[i],
      regimen_dict = regimen_dict)
  }, character(1L))

  episode_drugs %>%
    dplyr::select("ID", "treatment_type", "episode_number", "regimen_label")
}


# ------------------------------------------------------------------------------
# assign_lot()
# REGL-03
#
# Assigns a line-of-therapy (LOT) integer to each episode per patient.
# Rules:
#   1. LOT starts at 1 for the first episode.
#   2. LOT increments when the gap from the previous episode's end_date to the
#      current episode's start_date is >= lot_gap_days AND the new episode's
#      regimen_label is NOT in maintenance_classes.
#   3. Post-SCT episodes: start_date > sct_date triggers a LOT increment
#      regardless of gap length (SCT resets therapy counting).
#   4. Maintenance episodes (regimen_label in maintenance_classes) inherit the
#      current LOT — never increment.
#
# Args:
#   episode_df         data frame with columns:
#                        ID             patient identifier
#                        episode_number integer or character
#                        start_date     Date
#                        end_date       Date
#                        regimen_label  character (from assign_regimen())
#
#   lot_gap_days       integer — treatment-free gap to trigger new LOT;
#                      defaults to LOT_GAP_DAYS
#   maintenance_classes character — regimen labels that never start a new LOT;
#                      defaults to MAINTENANCE_DRUG_CLASSES
#   sct_dates_df       NULL or data frame with (ID, sct_date Date).
#                      NULL if no SCT patients in the cohort subset.
#
# Returns: episode_df with added column line_of_therapy (integer).
# ------------------------------------------------------------------------------
assign_lot <- function(episode_df,
                       lot_gap_days        = LOT_GAP_DAYS,
                       maintenance_classes = MAINTENANCE_DRUG_CLASSES,
                       sct_dates_df        = NULL) {

  stopifnot(
    is.data.frame(episode_df),
    all(c("ID", "episode_number", "start_date", "end_date",
          "regimen_label") %in% names(episode_df)),
    is.numeric(lot_gap_days) || is.integer(lot_gap_days),
    length(lot_gap_days) == 1L,
    is.character(maintenance_classes),
    is.null(sct_dates_df) || (is.data.frame(sct_dates_df) &&
      all(c("ID", "sct_date") %in% names(sct_dates_df)))
  )

  # Attach earliest SCT date per patient (NULL-safe).
  if (!is.null(sct_dates_df) && nrow(sct_dates_df) > 0L) {
    earliest_sct <- sct_dates_df %>%
      dplyr::group_by(.data$ID) %>%
      dplyr::summarise(earliest_sct = min(.data$sct_date, na.rm = TRUE),
                       .groups = "drop")
    episode_df <- dplyr::left_join(episode_df, earliest_sct, by = "ID")
  } else {
    episode_df <- dplyr::mutate(episode_df, earliest_sct = as.Date(NA))
  }

  # Sort episodes per patient by start_date, then compute LOT.
  episode_df <- episode_df %>%
    dplyr::arrange(.data$ID, .data$start_date, .data$episode_number) %>%
    dplyr::group_by(.data$ID) %>%
    dplyr::mutate(
      line_of_therapy = {
        n_ep      <- dplyr::n()
        lot_vec   <- integer(n_ep)
        lot_vec[1] <- 1L
        if (n_ep > 1L) {
          for (i in seq(2L, n_ep)) {
            prev_end    <- .data$end_date[i - 1L]
            curr_start  <- .data$start_date[i]
            curr_label  <- .data$regimen_label[i]
            is_maint    <- curr_label %in% maintenance_classes

            # Maintenance episodes inherit current LOT.
            if (is_maint) {
              lot_vec[i] <- lot_vec[i - 1L]
              next
            }

            # Post-SCT: increment if start_date > earliest_sct.
            sct_date_val <- .data$earliest_sct[1L]
            post_sct <- !is.na(sct_date_val) && curr_start > sct_date_val &&
                        (i == 2L || .data$start_date[i - 1L] <= sct_date_val)

            # Gap rule.
            gap_days <- as.integer(curr_start - prev_end)
            gap_trigger <- !is.na(gap_days) && gap_days >= as.integer(lot_gap_days)

            if (post_sct || gap_trigger) {
              lot_vec[i] <- lot_vec[i - 1L] + 1L
            } else {
              lot_vec[i] <- lot_vec[i - 1L]
            }
          }
        }
        lot_vec
      }
    ) %>%
    dplyr::ungroup() %>%
    dplyr::select(-"earliest_sct")

  episode_df
}
