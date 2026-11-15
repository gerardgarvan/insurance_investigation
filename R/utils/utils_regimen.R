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
#   - dplyr, tidyr, tibble
#   - R/00_config.R: REGIMEN_DICT, CONCURRENCY_WINDOW_DAYS, LOT_GAP_DAYS,
#                    MAINTENANCE_DRUG_CLASSES, BEAM_SCT_WINDOW_DAYS
#
# Requirements: REGL-01, REGL-02, REGL-03, REGL-04, REGL-08
# Revised quick 261114-sir: episode-level fallback (regimen_basis), regimen_detail,
#   new dictionary fields (optional, any_of, subset_min, loose, detectable,
#   requires_near_sct, requires_immune, label, detail), recognized-only LOT.
#
# ==============================================================================


# ------------------------------------------------------------------------------
# split_drug_names()
# Split an episode drug_names string into trimmed, non-blank drug tokens.
# The stage2 RDS separates drugs with commas; the Gantt CSV uses semicolons.
# Both separators are accepted everywhere.
# ------------------------------------------------------------------------------
split_drug_names <- function(x) {
  if (length(x) == 0L || is.na(x[1L])) return(character(0))
  tok <- trimws(unlist(strsplit(as.character(x[1L]), "[,;]")))
  unique(normalize_regimen_drug(tok[nzchar(tok)]))
}

# Strip a trailing parenthetical ("Pembrolizumab (IV)") and salt words so stray
# variants still match dictionary names. Canonical names pass through unchanged.
normalize_regimen_drug <- function(x) {
  x <- as.character(x)
  y <- trimws(sub("\\s*\\([^)]*\\)\\s*$", "", x))
  y <- trimws(sub("\\s+(sulfate|hydrochloride|hcl|phosphate|citrate|acetate)$", "", y,
                  ignore.case = TRUE))
  y[!nzchar(y)] <- x[!nzchar(y)]
  y
}


# ------------------------------------------------------------------------------
# match_regimen_family()
# Internal helper: test whether a character vector of canonical drug names
# satisfies a single REGIMEN_DICT entry.
#
# Entry fields used: drugs (all required), optional (allowed extras),
#   any_of (at least one required), exclusive (no drug outside drugs + optional +
#   any_of), subset_min (drugs is a universe; match if >= subset_min distinct
#   drugs present and none outside it), detectable = FALSE (never auto-match).
# ------------------------------------------------------------------------------
match_regimen_family <- function(canonical_drugs, family_def) {
  if (identical(family_def$detectable, FALSE)) return(FALSE)
  cd     <- unique(tolower(canonical_drugs))
  req    <- tolower(family_def$drugs)
  opt    <- tolower(family_def$optional)
  any_of <- tolower(family_def$any_of)

  if (!is.null(family_def$subset_min)) {
    return(length(cd) >= family_def$subset_min && all(cd %in% req))
  }
  if (length(req) == 0L && length(any_of) == 0L) return(FALSE)
  if (!all(req %in% cd)) return(FALSE)
  if (length(any_of) > 0L && !any(any_of %in% cd)) return(FALSE)
  if (isTRUE(family_def$exclusive)) {
    if (length(setdiff(cd, c(req, opt, any_of))) > 0L) return(FALSE)
  }
  TRUE
}


# Treatment types that can carry a regimen label. Radiation, SCT and Proton
# episodes always get NA. Episode numbers are unique only within
# (ID, treatment_type), so treatment_type is part of every join key.
REGIMEN_SYSTEMIC_TYPES     <- c("Chemotherapy", "Immunotherapy")
REGIMEN_UNRECOGNIZED_LABEL <- "Unrecognized systemic"
REGIMEN_SUPPORTIVE_LABEL   <- "Non-lymphoma / supportive"
REGIMEN_CONDITIONING_LABEL <- "Conditioning (BEAM)"

# Labels that are not a lymphoma regimen: no LOT, never first-line.
# Checkpoint / agents not used in HL: excluded from LOT and first-line.
REGIMEN_NON_HL_LABELS <- c("Other checkpoint (non-HL)", "Non-HL agent")
REGIMEN_NOT_RECOGNIZED_LABELS <- c(REGIMEN_UNRECOGNIZED_LABEL, REGIMEN_SUPPORTIVE_LABEL,
                                   REGIMEN_NON_HL_LABELS)

# LOT regimen family per label. Same family = same line unless a gap >=
# LOT_GAP_DAYS separates the episodes. Labels not listed are their own family.
REGIMEN_LOT_FAMILY_MAP <- c(
  ABVD = "ABVD family", AVD = "ABVD family", `BV+AVD` = "ABVD family",
  `Nivo+AVD` = "ABVD family", ABVD_PLUS = "ABVD family",
  `ABVD/AVD partial` = "ABVD family", JCODE_ABVD = "ABVD family",
  BEACOPP = "BEACOPP family", escBEACOPP = "BEACOPP family",
  `R-CHOP` = "CHOP family", CHOP = "CHOP family", CHOEP = "CHOP family",
  `R-CVP` = "CHOP family",
  BR = "Bendamustine family", `Bendamustine mono` = "Bendamustine family"
)

regimen_lot_family <- function(label) {
  fam <- unname(REGIMEN_LOT_FAMILY_MAP[as.character(label)])
  ifelse(is.na(fam), as.character(label), fam)
}

# Labels counted as a recognized first-line lymphoma regimen (R/29). Excludes
# Unrecognized, Non-lymphoma, Salvage, Conditioning, maintenance and NA.
REGIMEN_FIRST_LINE_LABELS <- c("ABVD", "AVD", "ABVD_PLUS", "ABVD/AVD partial",
                               "BV+AVD", "Nivo+AVD", "JCODE_ABVD",
                               "BEACOPP", "escBEACOPP",
                               "R-CHOP", "CHOP", "CHOEP", "R-CVP",
                               "BR", "Bendamustine mono", "Pediatric")

first_line_eligible <- function(label) {
  !is.na(label) & label %in% REGIMEN_FIRST_LINE_LABELS
}


# ------------------------------------------------------------------------------
# label_one_regimen_episode()
# Internal helper: label a single systemic episode from a set of drugs.
#
# Args:
#   pooled_drugs  drugs considered present (pooled over the concurrency window)
#   own_drugs     subset recorded on this episode's own treatment type
#   ep_type       "Chemotherapy" or "Immunotherapy"
#   post_sct      TRUE if an SCT episode precedes this episode within the window
#   regimen_dict  REGIMEN_DICT
#   near_sct      TRUE if an SCT episode is near (BEAM conditioning anchor)
#   immune        TRUE if the patient has the autoimmune flag
#
# Returns: list(label, detail, loose). label is a dictionary label,
#   REGIMEN_UNRECOGNIZED_LABEL when any drug is present but nothing matched
#   (Immunotherapy episodes match only when all own drugs belong to the entry),
#   or NA only when no drugs are present.
# ------------------------------------------------------------------------------
label_one_regimen_episode <- function(pooled_drugs, own_drugs, ep_type,
                                      post_sct, regimen_dict,
                                      near_sct = FALSE, immune = FALSE) {
  for (nm in names(regimen_dict)) {
    fam <- regimen_dict[[nm]]
    if (isTRUE(fam$requires_prior_sct) && !isTRUE(post_sct)) next
    if (isTRUE(fam$requires_near_sct)  && !isTRUE(near_sct)) next
    if (isTRUE(fam$requires_immune)    && !isTRUE(immune))   next
    if (!match_regimen_family(pooled_drugs, fam)) next

    if (identical(ep_type, "Immunotherapy")) {
      allowed <- tolower(c(fam$drugs, fam$optional, fam$any_of))
      if (!(length(own_drugs) > 0L && all(tolower(own_drugs) %in% allowed))) next
    }
    detail <- if (is.null(fam$detail)) NA_character_ else fam$detail
    if (isTRUE(fam$detail_agents)) {
      ag <- c(fam$drugs, fam$any_of)
      ag <- ag[tolower(ag) %in% tolower(pooled_drugs)]
      if (length(ag) > 0L) {
        detail <- paste(ag, collapse = " + ")
        if (length(ag) > 1L && identical(nm, "PD-1 mono")) detail <- paste(detail, "(switch)")
      }
    }
    return(list(label  = if (is.null(fam$label)) nm else fam$label,
                detail = detail,
                loose  = isTRUE(fam$loose)))
  }
  if (length(pooled_drugs) > 0L) {
    return(list(label = REGIMEN_UNRECOGNIZED_LABEL, detail = NA_character_,
                loose = FALSE))
  }
  list(label = NA_character_, detail = NA_character_, loose = FALSE)
}


# Internal: SCT proximity flags per episode key (post_sct, near_sct).
.regimen_sct_flags <- function(keys, sct_df, post_days, near_days) {
  keys$post_sct <- FALSE
  keys$near_sct <- FALSE
  if (is.null(sct_df) || nrow(sct_df) == 0L || nrow(keys) == 0L) return(keys)
  hits <- keys %>%
    dplyr::select("ID", "treatment_type", "episode_number", "start_date") %>%
    dplyr::inner_join(sct_df, by = "ID", relationship = "many-to-many") %>%
    dplyr::mutate(
      p = .data$start_date >= .data$sct_start &
          .data$start_date <= .data$sct_stop + as.integer(post_days),
      n = .data$start_date >= .data$sct_start - as.integer(near_days) &
          .data$start_date <= .data$sct_stop  + as.integer(near_days)
    ) %>%
    dplyr::group_by(.data$ID, .data$treatment_type, .data$episode_number) %>%
    dplyr::summarise(post_sct = any(.data$p, na.rm = TRUE),
                     near_sct = any(.data$n, na.rm = TRUE), .groups = "drop")
  keys$post_sct <- NULL
  keys$near_sct <- NULL
  keys <- dplyr::left_join(keys, hits,
                           by = c("ID", "treatment_type", "episode_number"))
  keys$post_sct <- dplyr::coalesce(keys$post_sct, FALSE)
  keys$near_sct <- dplyr::coalesce(keys$near_sct, FALSE)
  keys
}


# Internal: one labeling pass. rows = (ID, treatment_date, treatment_type,
# canonical_drug, episode_number, start_date). pool_own_only = TRUE restricts
# the pooled drugs to the episode's own rows (no cross-episode pooling).
# Returns one row per systemic episode key: label, detail, loose.
.regimen_pass <- function(rows, regimen_dict, window_days, sct_df,
                          sct_window_days, beam_window_days, immune_ids,
                          pool_own_only = FALSE) {
  rows <- rows %>%
    dplyr::filter(.data$treatment_type %in% REGIMEN_SYSTEMIC_TYPES,
                  !is.na(.data$canonical_drug), nzchar(.data$canonical_drug)) %>%
    dplyr::mutate(canonical_drug = normalize_regimen_drug(.data$canonical_drug))
  empty <- tibble::tibble(ID = character(), treatment_type = character(),
                          episode_number = integer(), label = character(),
                          detail = character(), loose = logical())
  if (nrow(rows) == 0L) return(empty)

  keys <- rows %>%
    dplyr::group_by(.data$ID, .data$treatment_type, .data$episode_number) %>%
    dplyr::summarise(start_date = .data$start_date[1L], .groups = "drop")

  pool <- rows %>%
    dplyr::select("ID", pool_date = "treatment_date",
                  pool_type = "treatment_type", pool_drug = "canonical_drug",
                  pool_ep = "episode_number")

  ep_drugs <- keys %>%
    dplyr::inner_join(pool, by = "ID", relationship = "many-to-many") %>%
    dplyr::mutate(days_from_start = as.integer(.data$pool_date - .data$start_date),
                  own_row = .data$pool_type == .data$treatment_type &
                            .data$pool_ep == .data$episode_number)
  ep_drugs <- if (pool_own_only) {
    dplyr::filter(ep_drugs, .data$own_row)
  } else {
    dplyr::filter(ep_drugs, abs(.data$days_from_start) <= as.integer(window_days))
  }
  ep_drugs <- ep_drugs %>%
    dplyr::group_by(.data$ID, .data$treatment_type, .data$episode_number,
                    .data$start_date) %>%
    dplyr::summarise(
      pooled_drugs = list(unique(.data$pool_drug)),
      own_drugs    = list(unique(.data$pool_drug[.data$own_row])),
      .groups = "drop"
    )

  ep_drugs <- .regimen_sct_flags(ep_drugs, sct_df, sct_window_days,
                                 beam_window_days)
  ep_drugs$immune <- ep_drugs$ID %in% immune_ids

  res <- lapply(seq_len(nrow(ep_drugs)), function(i) {
    label_one_regimen_episode(
      pooled_drugs = ep_drugs$pooled_drugs[[i]],
      own_drugs    = ep_drugs$own_drugs[[i]],
      ep_type      = ep_drugs$treatment_type[i],
      post_sct     = ep_drugs$post_sct[i],
      regimen_dict = regimen_dict,
      near_sct     = ep_drugs$near_sct[i],
      immune       = ep_drugs$immune[i])
  })
  ep_drugs$label  <- vapply(res, function(r) r$label,  character(1L))
  ep_drugs$detail <- vapply(res, function(r) r$detail, character(1L))
  ep_drugs$loose  <- vapply(res, function(r) r$loose,  logical(1L))
  ep_drugs %>%
    dplyr::select("ID", "treatment_type", "episode_number",
                  "label", "detail", "loose")
}


# ------------------------------------------------------------------------------
# assign_regimen()
# REGL-01, REGL-02, REGL-04 (revised quick 261114-sir)
#
# Labels each systemic-therapy episode (Chemotherapy, Immunotherapy). Drugs are
# pooled across the patient's Chemotherapy and Immunotherapy rows within
# window_days of the episode start so combinations such as BV+AVD are seen.
#
# Up to three candidate labels per episode, in priority order:
#   1. date-level pass over date_level_df                  (regimen_basis "date")
#   2. episode-level pass over episode_df$drug_names,
#      pooled across episodes                              (regimen_basis "episode")
#   3. episode-level pass over the episode's own drugs     (regimen_basis "episode")
# The first strict recognized regimen wins; else the first loose one (ABVD_PLUS,
# ABVD/AVD partial); else "Unrecognized systemic". An episode with any drug name
# is never NA. This covers episodes that have drug_names but no date-level rows
# (they were silently dropped before) and episodes whose date-level pool was
# polluted by neighbouring drugs.
#
# Args:
#   date_level_df  ID, treatment_date, treatment_type, canonical_drug,
#                  episode_number, start_date
#   regimen_dict   REGIMEN_DICT
#   window_days    half-width of concurrency window in days
#   sct_df         NULL or (ID, sct_start, sct_stop)
#   sct_window_days  days after sct_stop within which BV consolidation may start
#   episode_df     NULL or (ID, treatment_type, episode_number, start_date,
#                  drug_names); drug_names separated by "," or ";"
#   immune_ids     NULL or IDs with the autoimmune flag (methotrexate-alone rule)
#   beam_window_days  days around an SCT episode where BEAM = conditioning
#
# Returns: tibble, one row per systemic episode:
#   ID, treatment_type, episode_number, regimen_label, regimen_detail,
#   regimen_basis ("date" / "episode")
# ------------------------------------------------------------------------------
assign_regimen <- function(date_level_df,
                           regimen_dict    = REGIMEN_DICT,
                           window_days     = CONCURRENCY_WINDOW_DAYS,
                           sct_df          = NULL,
                           sct_window_days = if (exists("BV_CONSOLIDATION_SCT_WINDOW_DAYS"))
                             BV_CONSOLIDATION_SCT_WINDOW_DAYS else 90L,
                           episode_df      = NULL,
                           immune_ids      = NULL,
                           beam_window_days = if (exists("BEAM_SCT_WINDOW_DAYS"))
                             BEAM_SCT_WINDOW_DAYS else 30L) {

  stopifnot(
    is.data.frame(date_level_df),
    all(c("ID", "treatment_date", "treatment_type", "canonical_drug",
          "episode_number", "start_date") %in% names(date_level_df)),
    is.numeric(window_days) || is.integer(window_days),
    length(window_days) == 1L,
    is.null(sct_df) || (is.data.frame(sct_df) &&
      all(c("ID", "sct_start", "sct_stop") %in% names(sct_df))),
    is.null(episode_df) || (is.data.frame(episode_df) &&
      all(c("ID", "treatment_type", "episode_number", "start_date",
            "drug_names") %in% names(episode_df)))
  )
  immune_ids <- if (is.null(immune_ids)) character(0) else as.character(immune_ids)

  date_res <- .regimen_pass(date_level_df, regimen_dict, window_days, sct_df,
                            sct_window_days, beam_window_days, immune_ids)
  ep_res  <- NULL
  own_res <- NULL
  ep_rows_all <- NULL
  if (!is.null(episode_df)) {
    ep_sys <- episode_df %>%
      dplyr::filter(.data$treatment_type %in% REGIMEN_SYSTEMIC_TYPES,
                    !is.na(.data$drug_names), nzchar(trimws(.data$drug_names)))
    if (nrow(ep_sys) > 0L) {
      ep_rows <- ep_sys %>%
        dplyr::mutate(canonical_drug = lapply(.data$drug_names, split_drug_names)) %>%
        tidyr::unnest("canonical_drug") %>%
        dplyr::mutate(treatment_date = .data$start_date) %>%
        dplyr::select("ID", "treatment_date", "treatment_type", "canonical_drug",
                      "episode_number", "start_date")
      ep_rows_all <- ep_rows
      ep_res  <- .regimen_pass(ep_rows, regimen_dict, window_days, sct_df,
                               sct_window_days, beam_window_days, immune_ids)
      own_res <- .regimen_pass(ep_rows, regimen_dict, window_days, sct_df,
                               sct_window_days, beam_window_days, immune_ids,
                               pool_own_only = TRUE)
    }
  }

  tag <- function(df, basis, prio) {
    if (is.null(df) || nrow(df) == 0L) return(NULL)
    df$basis <- basis
    df$prio  <- prio
    df
  }
  cands <- dplyr::bind_rows(tag(date_res, "date", 1L),
                            tag(ep_res,   "episode", 2L),
                            tag(own_res,  "episode", 3L))
  if (is.null(cands) || nrow(cands) == 0L) {
    return(tibble::tibble(ID = character(), treatment_type = character(),
                          episode_number = integer(), regimen_label = character(),
                          regimen_detail = character(), regimen_basis = character()))
  }

  # rank 1 = strict recognized, 2 = loose recognized, 3 = Unrecognized systemic
  cands <- cands %>%
    dplyr::filter(!is.na(.data$label)) %>%
    dplyr::mutate(rank = dplyr::case_when(
      .data$label == REGIMEN_UNRECOGNIZED_LABEL ~ 3L,
      .data$loose                               ~ 2L,
      TRUE                                      ~ 1L)) %>%
    dplyr::arrange(.data$ID, .data$treatment_type, .data$episode_number,
                   .data$rank, .data$prio) %>%
    dplyr::group_by(.data$ID, .data$treatment_type, .data$episode_number) %>%
    dplyr::slice(1L) %>%
    dplyr::ungroup()

  out <- cands %>%
    dplyr::transmute(
      ID = .data$ID, treatment_type = .data$treatment_type,
      episode_number = .data$episode_number,
      regimen_label  = .data$label,
      regimen_detail = .data$detail,
      regimen_basis  = .data$basis
    )
  adjust_abvd_family(out, date_level_df, ep_rows_all, window_days)
}


# ------------------------------------------------------------------------------
# classify_abvd_set()
# Pure rule for a Chemotherapy episode whose own drugs include Doxorubicin,
# Vinblastine and Dacarbazine. `eff` = the episode drug set plus agents given in
# any other row within the concurrency window of the episode dates. Supportive
# agents (SUPPORTIVE_AGENTS: leuprolide, goserelin, other GnRH agonists) are
# removed first, so they never make "plus" (D-201-01, proposed).
#   no extras                          -> ABVD (bleomycin present) / AVD
#   extras only BV and/or nivolumab    -> AVD: BV+AVD (BV wins) / Nivo+AVD
#                                         ABVD: ABVD_PLUS (Phase 201 rule)
#   any other agent                    -> ABVD_PLUS, detail = the added agents
# Returns list(label, detail).
# ------------------------------------------------------------------------------
classify_abvd_set <- function(eff, supportive = if (exists("SUPPORTIVE_AGENTS")) SUPPORTIVE_AGENTS else
                                  c("Leuprolide", "Goserelin", "Triptorelin", "Histrelin", "Nafarelin", "Buserelin")) {
  eff <- unique(eff[!(tolower(eff) %in% tolower(supportive))])
  el  <- tolower(eff)
  comps <- c("doxorubicin", "bleomycin", "vinblastine", "dacarbazine")
  bv    <- "brentuximab vedotin" %in% el
  nivo  <- "nivolumab" %in% el
  bleo  <- "bleomycin" %in% el
  other <- setdiff(el, c(comps, "brentuximab vedotin", "nivolumab"))
  if (length(other) == 0L) {
    if (!bv && !nivo) {
      return(list(label = if (bleo) "ABVD" else "AVD", detail = NA_character_))
    }
    if (bleo) {
      return(list(label = "ABVD_PLUS",
                  detail = paste(eff[el %in% c("brentuximab vedotin", "nivolumab")],
                                 collapse = "; ")))
    }
    return(list(label = if (bv) "BV+AVD" else "Nivo+AVD", detail = NA_character_))
  }
  list(label = "ABVD_PLUS", detail = paste(eff[!(el %in% comps)], collapse = "; "))
}


# ------------------------------------------------------------------------------
# adjust_abvd_family()
# Episode-anchored ABVD-family rule (Phase 201 / R/142 relabel, quick 261114 r4).
# For each Chemotherapy episode whose own drugs include Doxorubicin, Vinblastine
# and Dacarbazine, pool the drugs of ANY systemic row (any treatment_type) of the
# same patient dated within window_days of the episode's own administration-date
# span [first - w, last + w] (episode start only when it has no date rows), then
# apply classify_abvd_set(). Overrides the label of those episodes only.
#
# Args: res (assign_regimen output), date_level_df, ep_rows (NULL or episode-level
#   long rows with ID, treatment_type, episode_number, canonical_drug, start_date),
#   window_days.
# ------------------------------------------------------------------------------
adjust_abvd_family <- function(res, date_level_df, ep_rows, window_days) {
  core <- c("doxorubicin", "vinblastine", "dacarbazine")
  dl <- date_level_df %>%
    dplyr::filter(.data$treatment_type %in% REGIMEN_SYSTEMIC_TYPES,
                  !is.na(.data$canonical_drug), nzchar(.data$canonical_drug)) %>%
    dplyr::mutate(canonical_drug = normalize_regimen_drug(.data$canonical_drug))
  keycols <- c("ID", "treatment_type", "episode_number")
  w <- as.integer(window_days)
  # Date-level own drugs count only within the window of the episode start
  # (as in the labeling passes); episode-level drug_names are the whole episode.
  own_src <- dl %>%
    dplyr::filter(is.na(.data$treatment_date) |
                  abs(as.integer(.data$treatment_date - .data$start_date)) <= w) %>%
    dplyr::select(dplyr::all_of(c(keycols, "canonical_drug")))
  if (!is.null(ep_rows)) {
    own_src <- dplyr::bind_rows(
      own_src,
      ep_rows %>% dplyr::select(dplyr::all_of(c(keycols, "canonical_drug"))))
  }
  own <- own_src %>%
    dplyr::filter(.data$treatment_type == "Chemotherapy") %>%
    dplyr::group_by(.data$ID, .data$treatment_type, .data$episode_number) %>%
    dplyr::summarise(own_set = list(unique(.data$canonical_drug)), .groups = "drop")
  own <- own[vapply(own$own_set, function(d) all(core %in% tolower(d)), logical(1L)), ]
  if (nrow(own) == 0L) return(res)

  # Span of the episode's own administration dates; episode start if it has none.
  span_rows <- dplyr::bind_rows(
    dl %>%
      dplyr::filter(.data$treatment_type == "Chemotherapy", !is.na(.data$treatment_date)) %>%
      dplyr::select(dplyr::all_of(keycols), d = "treatment_date"),
    own %>%
      dplyr::anti_join(
        dl %>% dplyr::filter(!is.na(.data$treatment_date)) %>%
          dplyr::distinct(.data$ID, .data$treatment_type, .data$episode_number),
        by = keycols) %>%
      dplyr::select(dplyr::all_of(keycols)) %>%
      dplyr::inner_join(
        dplyr::bind_rows(
          dl %>% dplyr::select(dplyr::all_of(keycols), d = "start_date"),
          if (!is.null(ep_rows)) {
            ep_rows %>% dplyr::select(dplyr::all_of(keycols), d = "start_date")
          }) %>% dplyr::distinct(),
        by = keycols))
  span <- span_rows %>%
    dplyr::group_by(.data$ID, .data$treatment_type, .data$episode_number) %>%
    dplyr::summarise(first = min(.data$d), last = max(.data$d), .groups = "drop")
  own <- dplyr::inner_join(own, span, by = keycols)
  if (nrow(own) == 0L) return(res)

  # Pool: every systemic date-level row, plus episode-level rows (dated at the
  # episode start) for episodes that have no date-level rows.
  pool <- dl %>% dplyr::select(dplyr::all_of(keycols), pool_date = "treatment_date",
                               pool_drug = "canonical_drug")
  if (!is.null(ep_rows)) {
    ep_only <- ep_rows %>%
      dplyr::anti_join(dl %>% dplyr::distinct(.data$ID, .data$treatment_type,
                                              .data$episode_number), by = keycols) %>%
      dplyr::select(dplyr::all_of(keycols), pool_date = "treatment_date",
                    pool_drug = "canonical_drug")
    pool <- dplyr::bind_rows(pool, ep_only)
  }
  near <- own %>%
    dplyr::select(dplyr::all_of(keycols), "first", "last") %>%
    dplyr::inner_join(
      pool %>% dplyr::select("ID", "pool_date", "pool_drug"),
      by = "ID", relationship = "many-to-many") %>%
    dplyr::filter(!is.na(.data$pool_date),
                  .data$pool_date >= .data$first - w,
                  .data$pool_date <= .data$last + w) %>%
    dplyr::group_by(.data$ID, .data$treatment_type, .data$episode_number) %>%
    dplyr::summarise(near_set = list(unique(.data$pool_drug)), .groups = "drop")
  own <- dplyr::left_join(own, near, by = keycols)
  cls <- lapply(seq_len(nrow(own)), function(i) {
    ns <- own$near_set[[i]]
    classify_abvd_set(c(own$own_set[[i]], if (!is.null(ns)) ns))
  })
  own$adj_label  <- vapply(cls, function(r) r$label,  character(1L))
  own$adj_detail <- vapply(cls, function(r) r$detail, character(1L))

  res <- dplyr::left_join(
    res, own %>% dplyr::select(dplyr::all_of(keycols), "adj_label", "adj_detail"),
    by = keycols)
  hit <- !is.na(res$adj_label)
  res$regimen_label[hit]  <- res$adj_label[hit]
  res$regimen_detail[hit] <- res$adj_detail[hit]
  res$adj_label  <- NULL
  res$adj_detail <- NULL
  res
}


# ------------------------------------------------------------------------------
# assign_lot()
# REGL-03 (revised quick 261114-sir)
#
# Line of therapy over recognized systemic regimens only.
#   - line_of_therapy is NA for Unrecognized systemic, Non-lymphoma / supportive,
#     NA labels, and any non-systemic treatment_type (when that column is
#     present). Radiation, SCT and Proton episodes therefore carry no line.
#   - A new line starts only when the regimen family changes
#     (regimen_lot_family(); e.g. ABVD family -> Salvage), or the same family
#     restarts after a gap >= lot_gap_days since the previous line episode.
#   - Maintenance labels (maintenance_classes: BV_consolidation, Rituximab_mono)
#     and "Conditioning (BEAM)" never start a line; they take the current line
#     (NA if no line has started).
#
# Args:
#   episode_df   ID, episode_number, start_date, end_date, regimen_label;
#                optional treatment_type
#   lot_gap_days, maintenance_classes
#   sct_dates_df retained for backward compatibility; ignored (SCT no longer
#                increments a line)
#
# Returns: episode_df sorted by ID, start_date, episode_number, plus
#   line_of_therapy (integer, NA where excluded).
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

  attach_labels <- unique(c(maintenance_classes, REGIMEN_CONDITIONING_LABEL))
  has_type <- "treatment_type" %in% names(episode_df)

  lot_for_patient <- function(start, end, label, ttype) {
    n <- length(start)
    lot <- rep(NA_integer_, n)
    cur <- 0L
    prev_fam <- NA_character_
    prev_end <- as.Date(NA)
    for (i in seq_len(n)) {
      lab <- label[i]
      if (is.na(lab) || lab %in% REGIMEN_NOT_RECOGNIZED_LABELS) next
      if (!is.null(ttype) && !(ttype[i] %in% REGIMEN_SYSTEMIC_TYPES)) next
      if (lab %in% attach_labels) {
        lot[i] <- if (cur > 0L) cur else NA_integer_
        next
      }
      fam <- regimen_lot_family(lab)
      if (cur == 0L) {
        cur <- 1L
      } else {
        gap <- as.integer(start[i] - prev_end)
        if (!identical(fam, prev_fam) ||
            (!is.na(gap) && gap >= as.integer(lot_gap_days))) {
          cur <- cur + 1L
        }
      }
      lot[i]   <- cur
      prev_fam <- fam
      prev_end <- if (is.na(prev_end)) end[i] else max(prev_end, end[i], na.rm = TRUE)
    }
    lot
  }

  episode_df %>%
    dplyr::arrange(.data$ID, .data$start_date, .data$episode_number) %>%
    dplyr::group_by(.data$ID) %>%
    dplyr::mutate(line_of_therapy = lot_for_patient(
      .data$start_date, .data$end_date, .data$regimen_label,
      if (has_type) .data$treatment_type else NULL)) %>%
    dplyr::ungroup()
}


# ------------------------------------------------------------------------------
# relabel_methotrexate_autoimmune()
# Methotrexate as the only drug in a patient with the autoimmune / immune flag is
# not lymphoma therapy: relabel "Unrecognized systemic" -> "Non-lymphoma /
# supportive". Used where patient-level autoimmune flags are available (R/142).
#
# Args: label, drug_names (character vectors, same length); immune (logical).
# Returns: character vector of labels.
# ------------------------------------------------------------------------------
relabel_methotrexate_autoimmune <- function(label, drug_names, immune) {
  mtx_alone <- vapply(drug_names, function(x) {
    d <- tolower(split_drug_names(x))
    length(d) == 1L && d == "methotrexate"
  }, logical(1L), USE.NAMES = FALSE)
  hit <- !is.na(label) & label == REGIMEN_UNRECOGNIZED_LABEL & mtx_alone &
    dplyr::coalesce(as.logical(immune), FALSE)
  ifelse(hit, REGIMEN_SUPPORTIVE_LABEL, label)
}
