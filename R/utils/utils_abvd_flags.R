# ==============================================================================
# R/utils/utils_abvd_flags.R
# Phase 210: episode-level abvd_episode / avd_episode flags and patient ever_* flags.
# Drug evidence = drug_names tokens (supportive agents removed) union drugs implied
# by HCPCS J-codes in an optional code column (triggering_codes in the 32-col
# episode schema). abvd_class is used only for the JCODE_ABVD fallback.
# ==============================================================================

ABVD_FLAG_CHEMO_LABEL <- "Chemotherapy"   # probed treatment_type label

# HCPCS J-code -> canonical drug name (user adjustment, Phase 210 headless run)
ABVD_JCODE_MAP <- c(
  J9000 = "Doxorubicin",
  J9040 = "Bleomycin",
  J9360 = "Vinblastine",
  J9130 = "Dacarbazine",
  J9042 = "Brentuximab Vedotin",
  J9299 = "Nivolumab"
)

ABVD_FLAG_JCODE_CLASS <- "JCODE_ABVD"

.abvd_default_setting <- function() {
  if (exists("AVD_INCLUDES_BV_NIVO")) get("AVD_INCLUDES_BV_NIVO") else TRUE
}

# Split code text on [,;| ] and map recognised J-codes to lower-case drug names.
.abvd_jcode_drugs <- function(code_text_i) {
  if (length(code_text_i) == 0L || is.na(code_text_i)) return(character(0))
  tok <- toupper(trimws(unlist(strsplit(as.character(code_text_i), "[,;| ]"))))
  tok <- tok[nzchar(tok)]
  hit <- ABVD_JCODE_MAP[names(ABVD_JCODE_MAP) %in% tok]
  tolower(unname(hit))
}

#' Episode-level ABVD / AVD flags.
#' @param drug_names character vector of episode drug_names.
#' @param treatment_type character vector, same length.
#' @param avd_includes_bv_nivo single TRUE/FALSE.
#' @param abvd_class optional character vector (same length); only used for fallback.
#' @param code_text optional character vector (same length) of code strings
#'   (callers pass e.g. triggering_codes); tokens split on [,;| ].
#' @return data.frame(abvd_episode, avd_episode, abvd_jcode_fallback); logical, never NA.
compute_abvd_avd_flags <- function(
    drug_names, treatment_type,
    avd_includes_bv_nivo = .abvd_default_setting(),
    supportive = if (exists("SUPPORTIVE_AGENTS")) SUPPORTIVE_AGENTS else
      c("Leuprolide", "Goserelin", "Triptorelin", "Histrelin", "Nafarelin", "Buserelin"),
    excluding = if (exists("ABVD_EXCLUDING_DRUGS")) ABVD_EXCLUDING_DRUGS else
      c("Brentuximab Vedotin", "Nivolumab"),
    abvd_class = NULL, code_text = NULL) {

  n <- length(drug_names)
  if (length(treatment_type) != n)
    stop("drug_names and treatment_type must have the same length")
  if (!is.null(abvd_class) && length(abvd_class) != n)
    stop("abvd_class must have the same length as drug_names")
  if (!is.null(code_text) && length(code_text) != n)
    stop("code_text must have the same length as drug_names")
  if (!(is.logical(avd_includes_bv_nivo) && length(avd_includes_bv_nivo) == 1L &&
        !is.na(avd_includes_bv_nivo)))
    stop("avd_includes_bv_nivo must be a single non-NA logical")

  sup_l <- tolower(supportive)
  exc_l <- tolower(excluding)
  res <- matrix(FALSE, nrow = n, ncol = 3L)

  for (i in seq_len(n)) {
    is_chemo <- !is.na(treatment_type[i]) && treatment_type[i] == ABVD_FLAG_CHEMO_LABEL
    if (!is_chemo) next
    tok <- tolower(split_drug_names(drug_names[i]))
    tok <- tok[!tok %in% sup_l]
    jd  <- if (is.null(code_text)) character(0) else .abvd_jcode_drugs(code_text[i])
    drugs <- union(tok, jd)

    dox <- "doxorubicin" %in% drugs; bleo <- "bleomycin" %in% drugs
    vin <- "vinblastine" %in% drugs; dac  <- "dacarbazine" %in% drugs

    abvd <- dox && bleo && vin && dac
    avd  <- dox && vin && dac && !bleo &&
      (avd_includes_bv_nivo || !any(drugs %in% exc_l))

    fb <- FALSE
    if (!abvd && !avd && length(drugs) == 0L && !is.null(abvd_class) &&
        !is.na(abvd_class[i]) && abvd_class[i] == ABVD_FLAG_JCODE_CLASS) {
      abvd <- TRUE
      fb <- TRUE
    }
    res[i, ] <- c(abvd, avd, fb)
  }

  out <- data.frame(abvd_episode = res[, 1L] == 1, avd_episode = res[, 2L] == 1,
                    abvd_jcode_fallback = res[, 3L] == 1)
  stopifnot("abvd_episode and avd_episode are mutually exclusive" =
              !any(out$abvd_episode & out$avd_episode))
  out
}

#' Patient-level ever flag: any() of an episode flag over all the patient's rows.
patient_ever_flag <- function(patient_id, flag) {
  if (length(patient_id) != length(flag)) stop("patient_id and flag must have the same length")
  if (anyNA(flag)) stop("flag must not contain NA")
  as.logical(stats::ave(as.integer(flag), patient_id, FUN = max))
}

#' Flag dictionary.
abvd_flag_dictionary <- function(avd_includes_bv_nivo = .abvd_default_setting()) {
  data.frame(
    column = c("abvd_episode", "avd_episode", "ever_abvd", "ever_avd",
               "ever_abvd_plus", "abvd_class", "setting: AVD_INCLUDES_BV_NIVO"),
    level  = c("episode", "episode", "patient", "patient", "patient", "episode", "config"),
    definition = c(
      paste("Chemotherapy episode whose drug evidence includes Doxorubicin, Bleomycin,",
            "Vinblastine and Dacarbazine; other compounds allowed. Drug evidence is the",
            "drug_names tokens plus drugs implied by HCPCS J-codes (J9000, J9040, J9360,",
            "J9130). Fallback: if abvd_class is JCODE_ABVD and no drug or recognised J-code",
            "evidence is available, the episode is set TRUE and abvd_jcode_fallback is TRUE."),
      paste("Chemotherapy episode with Doxorubicin, Vinblastine and Dacarbazine present and",
            "Bleomycin absent (same drug evidence). Brentuximab or Nivolumab episodes count",
            "only when AVD_INCLUDES_BV_NIVO is TRUE."),
      "TRUE if any of the patient's episodes has abvd_episode TRUE (full history).",
      "TRUE if any of the patient's episodes has avd_episode TRUE (full history).",
      "Deprecated. Previously any abvd_class == ABVD_PLUS; kept for compatibility.",
      "Descriptive regimen label; not used to derive abvd_episode or avd_episode except the JCODE_ABVD fallback.",
      as.character(avd_includes_bv_nivo)),
    status = c("active", "active", "active", "active", "deprecated", "descriptive", "setting"),
    stringsAsFactors = FALSE
  )
}
