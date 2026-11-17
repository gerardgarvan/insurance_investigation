# ==============================================================================
# R/utils/utils_206_direct.R
# Phase 213 (DEC-213-01): pure helpers for R/206 R206_MODE = "direct".
# Verify the decision rules on a gantt_episodes_180 file produced by R/142 at HEAD.
# No file I/O, no patient data in messages. Needs split_drug_names(),
# classify_abvd_set() and compute_abvd_avd_flags() (utils loaded by R/00_config.R).
# ==============================================================================

# Own-drug re-check of D-201-01. Returns the row indices of ABVD_PLUS Chemotherapy
# rows where (a) the row's own drug_names contain a supportive agent and (b) the
# row, with supportive agents removed, is NOT ABVD_PLUS under classify_abvd_set().
# Such a row was made "plus" by a supportive agent alone. Rows made "plus" by
# agents pooled from other rows within the concurrency window cannot be re-derived
# from drug_names alone and are not tested here.
direct_supportive_plus_rows <- function(abvd_class, drug_names, treatment_type,
                                        supportive = if (exists("SUPPORTIVE_AGENTS")) SUPPORTIVE_AGENTS else
                                          c("Leuprolide", "Goserelin", "Triptorelin", "Histrelin", "Nafarelin", "Buserelin")) {
  cand <- which(!is.na(abvd_class) & abvd_class == "ABVD_PLUS" &
                  !is.na(treatment_type) & treatment_type == "Chemotherapy")
  sup_l <- tolower(supportive)
  bad <- integer(0)
  for (i in cand) {
    tok <- split_drug_names(drug_names[i])
    if (!any(tolower(tok) %in% sup_l)) next
    if (!classify_abvd_set(tok, supportive = supportive)$label %in% "ABVD_PLUS") bad <- c(bad, i)
  }
  bad
}

# Returns a named list of TRUE/FALSE results for the direct-mode checks on a
# character-typed gantt data frame `d` (as read by R/206 read_chr()).
# `schema` = expected column vector; `expected_hl` = HL Diagnosis row count.
direct_mode_checks <- function(d, schema, expected_hl, flags = NULL) {
  chemo <- !is.na(d$treatment_type) & d$treatment_type == "Chemotherapy"
  if (is.null(flags)) {
    flags <- compute_abvd_avd_flags(d$drug_names, d$treatment_type,
                                    abvd_class = d$abvd_class, code_text = d$triggering_codes)
  }
  tf <- function(x) ifelse(x, "TRUE", "FALSE")
  const_in_pt <- function(col) !any(tapply(d[[col]], d$patient_id, function(x) length(unique(x))) != 1L)
  list(
    schema_in_order      = identical(names(d), schema),
    hl_diagnosis_rows    = sum(!is.na(d$treatment_type) & d$treatment_type == "HL Diagnosis") == expected_hl,
    abvd_flag_matches    = identical(d$abvd_episode, tf(flags$abvd_episode)),
    avd_flag_matches     = identical(d$avd_episode,  tf(flags$avd_episode)),
    ever_abvd_matches    = identical(d$ever_abvd, tf(patient_ever_flag(d$patient_id, flags$abvd_episode))),
    ever_avd_matches     = identical(d$ever_avd,  tf(patient_ever_flag(d$patient_id, flags$avd_episode))),
    no_row_both_flags    = !any(d$abvd_episode == "TRUE" & d$avd_episode == "TRUE"),
    flags_only_on_chemo  = !any((d$abvd_episode == "TRUE" | d$avd_episode == "TRUE") & !chemo),
    ever_constant_in_pt  = const_in_pt("ever_abvd") && const_in_pt("ever_avd"),
    no_supportive_only_plus = length(direct_supportive_plus_rows(d$abvd_class, d$drug_names, d$treatment_type)) == 0L
  )
}
