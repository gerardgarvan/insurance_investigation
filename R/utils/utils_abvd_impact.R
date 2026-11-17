# ==============================================================================
# R/utils/utils_abvd_impact.R
# Phase 211: pure helpers for the ABVD/AVD flag impact tables (old vs new episodes).
# No file I/O and no patient-level output; functions return aggregate counts only.
# Reuses split_drug_names() (utils_regimen.R) and SUPPORTIVE_AGENTS; flag logic
# itself lives in compute_abvd_avd_flags() (utils_abvd_flags.R) and is not repeated.
# ==============================================================================

# Column names (R/142 EPISODES_SCHEMA; see 210-04-SUMMARY.md)
ABVD_IMPACT_COLS <- list(
  id = "patient_id", type = "treatment_type", drugs = "drug_names",
  cls = "abvd_class", abvd_ep = "abvd_episode", avd_ep = "avd_episode",
  ever_abvd = "ever_abvd", ever_avd = "ever_avd"
)

ABVD_FOUR_DRUGS <- c("Doxorubicin", "Bleomycin", "Vinblastine", "Dacarbazine")

# BEACOPP components (doxorubicin, bleomycin, etoposide, cyclophosphamide,
# vincristine, procarbazine, prednisone), canonical capitalised names.
BEACOPP_COMPONENTS_DEFAULT <- c("Doxorubicin", "Bleomycin", "Etoposide",
                                "Cyclophosphamide", "Vincristine",
                                "Procarbazine", "Prednisone")

.abvd_supportive <- function() {
  if (exists("SUPPORTIVE_AGENTS")) get("SUPPORTIVE_AGENTS") else
    c("Leuprolide", "Goserelin", "Triptorelin", "Histrelin", "Nafarelin", "Buserelin")
}

#' Format a count with small-cell suppression: 1-10 -> "<11"; 0 -> "0"; NA -> NA.
fmt_sup <- function(n) {
  n <- as.numeric(n)
  out <- ifelse(is.na(n), NA_character_,
         ifelse(n >= 1 & n <= 10, "<11",
                formatC(n, format = "d", big.mark = ",")))
  as.character(out)
}

.abvd_check_aligned <- function(old, new, cols) {
  if (nrow(old) != nrow(new))
    stop("old and new episode tables must have the same number of rows (row-aligned)")
  miss <- setdiff(cols, names(new))
  if (length(miss)) stop("new table missing columns: ", paste(miss, collapse = ", "))
}

#' Counts of old abvd_episode x new abvd_episode x new avd_episode by new class.
#' Assumes old and new are row-aligned (same episode order).
episode_crosstab <- function(old, new, cols = ABVD_IMPACT_COLS) {
  .abvd_check_aligned(old, new, c(cols$cls, cols$abvd_ep, cols$avd_ep))
  if (!cols$abvd_ep %in% names(old)) stop("old table missing ", cols$abvd_ep)
  tibble::tibble(
    abvd_class  = as.character(new[[cols$cls]]),
    old_abvd    = as.logical(old[[cols$abvd_ep]]),
    new_abvd    = as.logical(new[[cols$abvd_ep]]),
    new_avd     = as.logical(new[[cols$avd_ep]])
  ) |>
    dplyr::count(abvd_class, old_abvd, new_abvd, new_avd, name = "n_episodes")
}

#' Old -> new abvd_episode transitions (FALSE->TRUE, TRUE->FALSE) by new class.
episode_transitions <- function(old, new, cols = ABVD_IMPACT_COLS) {
  ct <- episode_crosstab(old, new, cols)
  ct |>
    dplyr::filter(!is.na(old_abvd), !is.na(new_abvd), old_abvd != new_abvd) |>
    dplyr::mutate(transition = ifelse(old_abvd, "TRUE->FALSE", "FALSE->TRUE")) |>
    dplyr::group_by(abvd_class, transition) |>
    dplyr::summarise(n_episodes = sum(n_episodes), .groups = "drop")
}

#' Patient-level any() of old/new flags -> counts by (old ever_abvd, new ever_abvd,
#' new ever_avd). Old ever_abvd is derived from old abvd_episode.
patient_flag_compare <- function(old, new, cols = ABVD_IMPACT_COLS) {
  .abvd_check_aligned(old, new, c(cols$id, cols$abvd_ep, cols$avd_ep))
  tibble::tibble(
    id = new[[cols$id]],
    o  = as.logical(old[[cols$abvd_ep]]),
    a  = as.logical(new[[cols$abvd_ep]]),
    v  = as.logical(new[[cols$avd_ep]])
  ) |>
    dplyr::group_by(id) |>
    dplyr::summarise(old_ever_abvd = any(o %in% TRUE),
                     new_ever_abvd = any(a %in% TRUE),
                     new_ever_avd  = any(v %in% TRUE), .groups = "drop") |>
    dplyr::count(old_ever_abvd, new_ever_abvd, new_ever_avd, name = "n_patients")
}

#' Pattern/count table of sorted non-supportive drug sets (no patient identifiers).
drug_set_patterns <- function(drug_names) {
  sup <- tolower(.abvd_supportive())
  pat <- vapply(drug_names, function(x) {
    tok <- split_drug_names(x)
    tok <- sort(tok[!tolower(tok) %in% sup])
    if (length(tok) == 0L) "(none)" else paste(tok, collapse = " + ")
  }, character(1), USE.NAMES = FALSE)
  tibble::tibble(pattern = pat) |>
    dplyr::count(pattern, name = "n_episodes") |>
    dplyr::arrange(dplyr::desc(n_episodes), pattern)
}

#' TRUE per episode when a BEACOPP component outside the four ABVD drugs is present.
beacopp_extra_components <- function(drug_names, components = BEACOPP_COMPONENTS_DEFAULT) {
  sup   <- tolower(.abvd_supportive())
  extra <- tolower(setdiff(components, ABVD_FOUR_DRUGS))
  vapply(drug_names, function(x) {
    tok <- tolower(split_drug_names(x))
    any(tok[!tok %in% sup] %in% extra)
  }, logical(1), USE.NAMES = FALSE)
}

#' 2x2 patient counts of ever_abvd x ever_avd.
ever_cross <- function(ever_abvd, ever_avd) {
  tibble::tibble(ever_abvd = as.logical(ever_abvd), ever_avd = as.logical(ever_avd)) |>
    dplyr::count(ever_abvd, ever_avd, name = "n_patients")
}

#' Apply fmt_sup to count columns. If total_col is given, it is suppressed
#' (as "<11") whenever any count in that row is 1-10, or the total itself is 1-10,
#' so a hidden cell cannot be back-calculated from the total.
suppress_impact_table <- function(df, count_cols, total_col = NULL) {
  small <- function(x) !is.na(x) & x >= 1 & x <= 10
  hide_total <- if (is.null(total_col)) NULL else {
    Reduce(`|`, lapply(count_cols, function(cc) small(df[[cc]])), small(df[[total_col]]))
  }
  for (cc in setdiff(count_cols, total_col)) df[[cc]] <- fmt_sup(df[[cc]])
  if (!is.null(total_col)) {
    tot <- fmt_sup(df[[total_col]])
    tot[hide_total] <- "<11"
    df[[total_col]] <- tot
  }
  df
}
