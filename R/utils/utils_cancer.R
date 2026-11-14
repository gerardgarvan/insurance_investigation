# ==============================================================================
# utils/utils_cancer.R -- Cancer site classification utilities
# ==============================================================================
#
# Purpose:
#   Provides is_cancer_code() for detecting cancer/neoplasm codes and
#   classify_codes() for mapping ICD-10/ICD-O-3/ICD-9 codes to cancer site
#   categories using the CANCER_SITE_MAP and ICD9_CANCER_SITE_MAP constants
#   from R/00_config.R. Used by 10+ cancer analysis scripts (R/28, R/40,
#   R/43-R/49, R/51, R/56).
#
# Inputs:
#   - None (utility function library, not a standalone script)
#
# Outputs:
#   - None (defines functions loaded into calling scripts' environment)
#
# Dependencies:
#   - CANCER_SITE_MAP from R/00_config.R (ICD-10 prefix-to-category mapping)
#   - ICD9_CANCER_SITE_MAP from R/00_config.R (ICD-9 prefix-to-category mapping)
#   - stringr package (for str_remove in code normalization)
#
# Requirements: DRY-02 (extract repeated pattern to shared utility), CANCER-01,
#               ICD-06 (shared is_cancer_code utility)
#
# ==============================================================================

#' Detect whether diagnosis codes are cancer/neoplasm codes (vectorized)
#'
#' Uses map-based detection: checks if code prefix exists in CANCER_SITE_MAP
#' (ICD-10) or ICD9_CANCER_SITE_MAP (ICD-9). This ensures gap-free coverage --
#' every code detected as cancer can be classified by classify_codes().
#'
#' WHY map-based (not range-based): Range-based detection (140-239) would include
#' benign/in-situ/uncertain ICD-9 codes (210-239) that classify_codes() cannot
#' classify, creating "detected but unclassified" records. Map-based detection
#' only detects codes that have map entries (140-209 malignant range).
#'
#' @param dx Character vector of diagnosis codes (any format -- dotted or undotted)
#' @return Logical vector (TRUE if cancer code, FALSE otherwise)
#'
#' @examples
#' is_cancer_code(c("C81.90", "201.90", "J44.1", "250.00"))
#' # Returns: c(TRUE, TRUE, FALSE, FALSE)
#'
# Internal: strip ALL dots and uppercase — matches normalize_icd() contract.
# Used by is_cancer_code() and classify_codes() so every caller gets identical
# normalization regardless of input format.
.normalize_code <- function(x) toupper(gsub("\\.", "", x, fixed = FALSE))

is_cancer_code <- function(dx) {
  dx_clean <- .normalize_code(dx)  # Normalize: strip all dots + uppercase for prefix matching

  # ICD-10: check 4-char then 3-char prefix against CANCER_SITE_MAP keys
  icd10_match <- substr(dx_clean, 1, 4) %in% names(CANCER_SITE_MAP) |
                 substr(dx_clean, 1, 3) %in% names(CANCER_SITE_MAP)

  # ICD-9: check 4-char then 3-char prefix against ICD9_CANCER_SITE_MAP keys
  icd9_match <- substr(dx_clean, 1, 4) %in% names(ICD9_CANCER_SITE_MAP) |
                substr(dx_clean, 1, 3) %in% names(ICD9_CANCER_SITE_MAP)

  icd10_match | icd9_match
}

#' Classify ICD-10, ICD-O-3, or ICD-9 codes into cancer site categories
#'
#' Maps codes to cancer site categories using hierarchical prefix matching with
#' unified 4-tier cascade:
#' 1. Try 4-character prefix in CANCER_SITE_MAP (ICD-10 subcategory, e.g., C810 -> NLPHL)
#' 2. Fall back to 3-character prefix in CANCER_SITE_MAP (ICD-10 category, e.g., C81 -> classical HL)
#' 3. Try 4-character prefix in ICD9_CANCER_SITE_MAP (ICD-9 subcategory, e.g., 2014 -> NLPHL)
#' 4. Fall back to 3-character prefix in ICD9_CANCER_SITE_MAP (ICD-9 category, e.g., 201 -> classical HL)
#' 5. Return NA for unclassified codes
#'
#' Codes are normalized (dots stripped) at entry for consistent prefix extraction
#' across dotted (201.40) and undotted (20140) formats.
#'
#' WHY 4-char before 3-char: Enables C810/2014 -> "NLPHL" without C81/201 ->
#' "Hodgkin Lymphoma (non-NLPHL)" intercepting first. Checking longer prefix
#' first ensures subcategory specificity.
#'
#' WHY unified cascade: Replaces old ICD-9 201.x exact-match logic with map
#' lookup. The 4-char key "2014" in ICD9_CANCER_SITE_MAP catches NLPHL
#' (formerly handled by ICD9_NLPHL_CODES exact match). The 3-char key "201"
#' catches remaining HL (formerly handled by regex).
#'
#' @param codes Character vector of diagnosis codes (dotted or undotted format)
#' @return Character vector of category names (NA for unclassified codes)
#'
#' @examples
#' classify_codes(c("C810", "C501", "D051"))
#' # Returns: c("NLPHL", "Breast", "In Situ Neoplasms")
#'
#' classify_codes(c("201.40", "162.0", "153"))
#' # Returns: c("NLPHL", "Lung and Bronchus", "Colon")
#'
classify_codes <- function(codes) {
  # Step 0: Normalize all codes (strip ALL dots + toupper for consistent prefix extraction)
  # WHY: ICD-9 codes appear in dotted (201.90) and undotted (20190) formats;
  # lowercase input (c81.90) must match the same as uppercase (C8190). Stripping
  # all dots and uppercasing at entry ensures consistent substr() results.
  codes_clean <- .normalize_code(codes)

  # Step 1: Extract prefixes at both specificity levels
  prefix4 <- substr(codes_clean, 1, 4)  # Subcategory (C810, 2014)
  prefix3 <- substr(codes_clean, 1, 3)  # Category (C81, 201)

  # Step 2: ICD-10 4-char match (most specific -- e.g., C810 -> NLPHL)
  match_icd10_4 <- CANCER_SITE_MAP[prefix4]

  # Step 3: ICD-10 3-char fallback (e.g., C81 -> Hodgkin Lymphoma (non-NLPHL))
  match_icd10_3 <- CANCER_SITE_MAP[prefix3]

  # Step 4: ICD-9 4-char match (e.g., 2014 -> NLPHL, 2015 -> classical HL)
  match_icd9_4 <- ICD9_CANCER_SITE_MAP[prefix4]

  # Step 5: ICD-9 3-char fallback (e.g., 201 -> Hodgkin Lymphoma, 162 -> Lung)
  match_icd9_3 <- ICD9_CANCER_SITE_MAP[prefix3]

  # Step 6: Apply priority cascade (per D-05 detection order)
  categories <- ifelse(!is.na(match_icd10_4), match_icd10_4,
                ifelse(!is.na(match_icd10_3), match_icd10_3,
                ifelse(!is.na(match_icd9_4),  match_icd9_4,
                ifelse(!is.na(match_icd9_3),  match_icd9_3,
                       NA_character_))))

  # Remove names from vector indexing to return clean character vector
  unname(categories)
}


# ==============================================================================
# Phase 201: ABVD classification and tumor-registry lymphoma flags
# ==============================================================================

#' Classify a Chemotherapy episode as ABVD, AVD, JCODE_ABVD, ABVD_PLUS, or NA
#'
#' Vectorized over episode rows. `drug_names` is the post-Section-4D semicolon
#' string (already canonicalized by canonicalize_drug_name). `regimen_label_r28`
#' is R/28's regimen_label (used only for the J-code fallback).
#'
#' Rules (D-01 in 201-CONTEXT.md; broadened in Phase 201b):
#'   ABVD       — all four components, no excluding drug, n_families <= 4
#'   AVD        — Doxorubicin + Vinblastine + Dacarbazine, no Bleomycin and no
#'                excluding drug, n_families <= 3
#'   JCODE_ABVD — blank drug_names AND regimen_label_r28 == "ABVD" (J-code path)
#'   ABVD_PLUS  — Dox+Vin+Dac present (Bleomycin optional) plus at least one
#'                non-component drug other than Brentuximab/Nivolumab (QC marker;
#'                not counted as abvd_episode). BV+AVD and Nivo+AVD remain NA.
#'   NA         — none of the above
#'
#' Drug-family matching is case-insensitive prefix so stray salt/brand variants
#' still match (e.g., "Bleomycin Sulfate" matches ^bleomycin).
#'
#' @param drug_names Character vector of semicolon-separated canonical drug names
#' @param regimen_label_r28 Character vector of R/28 regimen labels (NA allowed)
#' @return Character vector: "ABVD" | "AVD" | "JCODE_ABVD" | "ABVD_PLUS" | NA_character_.
#'   ABVD_PLUS — Dox+Vin+Dac present (Bleomycin optional) plus at least one
#'   non-component drug other than Brentuximab/Nivolumab.
classify_abvd_episode <- function(drug_names, regimen_label_r28) {
  stopifnot(length(drug_names) == length(regimen_label_r28))

  # Family-to-regex patterns (case-insensitive prefix match)
  fam_patterns <- c(
    doxorubicin  = "^doxorubicin",
    bleomycin    = "^bleomycin",
    vinblastine  = "^vinblastine",
    dacarbazine  = "^dacarbazine",
    brentuximab  = "^brentuximab",
    nivolumab    = "^nivolumab"
  )

  vapply(seq_along(drug_names), function(i) {
    dn  <- drug_names[i]
    r28 <- regimen_label_r28[i]

    # J-code fallback: blank drug_names, rely on R/28 label
    if (is.na(dn) || trimws(dn) == "") {
      if (!is.na(r28) && r28 == "ABVD") return("JCODE_ABVD")
      return(NA_character_)
    }

    # Split and deduplicate tokens
    toks <- trimws(strsplit(dn, ";", fixed = TRUE)[[1]])
    toks <- toks[nzchar(toks)]
    if (length(toks) == 0) {
      if (!is.na(r28) && r28 == "ABVD") return("JCODE_ABVD")
      return(NA_character_)
    }

    # Map each token to its drug family (first matching pattern wins)
    map_token <- function(t) {
      for (nm in names(fam_patterns)) {
        if (grepl(fam_patterns[nm], t, ignore.case = TRUE)) return(nm)
      }
      t  # keep as-is if no family match
    }
    families <- unique(vapply(toks, map_token, character(1), USE.NAMES = FALSE))
    n_fam    <- length(families)

    has_dox  <- "doxorubicin" %in% families
    has_bleo <- "bleomycin"   %in% families
    has_vin  <- "vinblastine" %in% families
    has_dac  <- "dacarbazine" %in% families
    has_excl <- any(c("brentuximab", "nivolumab") %in% families)
    all_four <- has_dox & has_bleo & has_vin & has_dac

    if (all_four) {
      if (!has_excl && n_fam <= 4L) return("ABVD")
      if (!has_excl) return("ABVD_PLUS")  # all 4 cores + extra non-excl drug
      return(NA_character_)               # has BV or Nivo — BV+ABVD follows R/28 rules
    }
    # Three-core (Dox+Vin+Dac), Bleomycin absent
    if (has_dox && has_vin && has_dac && !has_bleo && !has_excl) {
      if (n_fam <= 3L) return("AVD")
      return("ABVD_PLUS")  # three cores + extra non-excl drug (Bleomycin optional per spec)
    }
    NA_character_
  }, character(1))
}


#' Build tumor-registry HL/NHL flags for a set of patient IDs
#'
#' Returns one row per input patient ID with columns:
#'   patient_id, tr_present (logical), tr_hl_dx (logical|NA), tr_nhl_dx (logical|NA)
#'
#' Attributes:
#'   attr(, "tr_hl_ids_all")    — all TR-HL patient IDs in TUMOR_REGISTRY_ALL
#'                                 (not limited to patient_ids; used for D-06)
#'   attr(, "unlisted_lymphoid") — tibble: code, n_patients for 4-digit histology
#'                                 codes 9590-9999 seen in patient_ids rows that are
#'                                 in neither hl_histology nor nhl_histology (D-05)
#'
#' Stops with an error if TUMOR_REGISTRY_ALL is unavailable (all-NA would
#' silently misrepresent registry absence; D-04).
#'
#' @param patient_ids Character vector of patient IDs to flag
#' @return Tibble with columns patient_id, tr_present, tr_hl_dx, tr_nhl_dx
build_tr_lymphoma_flags <- function(patient_ids) {
  stopifnot(is.character(patient_ids) || is.factor(patient_ids))
  patient_ids <- as.character(patient_ids)
  ids_unique  <- unique(patient_ids)

  # Open connection (same pattern as build_autoimmune_dx_flags)
  open_pcornet_con()
  on.exit(try(close_pcornet_con(), silent = TRUE), add = TRUE)

  # Collect only needed columns from TUMOR_REGISTRY_ALL
  tr_tbl <- tryCatch(
    get_pcornet_table("TUMOR_REGISTRY_ALL"),
    error = function(e) {
      stop(paste0(
        "build_tr_lymphoma_flags: TUMOR_REGISTRY_ALL unavailable — ",
        conditionMessage(e),
        "\nAborting: returning all-NA would misrepresent registry membership."
      ))
    }
  )

  # Determine which histology column(s) are present
  tr_names <- colnames(tr_tbl)
  has_hist  <- "HISTOLOGICAL_TYPE" %in% tr_names  # TR1
  has_morph <- "MORPH"             %in% tr_names  # TR2/TR3

  if (!has_hist && !has_morph) {
    close_pcornet_con()
    stop("build_tr_lymphoma_flags: TUMOR_REGISTRY_ALL has neither HISTOLOGICAL_TYPE nor MORPH.")
  }

  sel_cols <- c("ID", if (has_hist) "HISTOLOGICAL_TYPE", if (has_morph) "MORPH")
  tr_data  <- tr_tbl |> dplyr::select(dplyr::all_of(sel_cols)) |> dplyr::collect()
  close_pcornet_con()

  # Gather all histology values per row (one or two columns) into a single vector
  get_codes <- function(row_df) {
    vals <- c(
      if (has_hist)  as.character(row_df$HISTOLOGICAL_TYPE) else character(0),
      if (has_morph) as.character(row_df$MORPH)             else character(0)
    )
    substr(vals[!is.na(vals) & nzchar(vals)], 1, 4)
  }

  # Build per-patient code set
  tr_long <- tr_data |>
    tidyr::pivot_longer(
      cols      = dplyr::any_of(c("HISTOLOGICAL_TYPE", "MORPH")),
      names_to  = "col",
      values_to = "raw_code"
    ) |>
    dplyr::filter(!is.na(raw_code) & nzchar(raw_code)) |>
    dplyr::mutate(code4 = substr(as.character(raw_code), 1L, 4L)) |>
    dplyr::select(ID, code4)

  # Reference lists (from R/00_config.R)
  hl_codes  <- as.character(ICD_CODES$hl_histology)
  nhl_codes <- as.character(ICD_CODES$nhl_histology)

  # All IDs that appear anywhere in TUMOR_REGISTRY_ALL
  tr_all_ids <- unique(tr_data$ID)

  # HL/NHL membership (all patients in registry, not just export patients)
  hl_ids_all <- unique(tr_long$ID[tr_long$code4 %in% hl_codes])

  # Build patient-level summary (export patients only)
  pt_in_tr <- ids_unique %in% tr_all_ids

  # For patients in TR: check HL and NHL codes
  tr_pt_long <- tr_long |> dplyr::filter(ID %in% ids_unique)

  hl_true_ids  <- unique(tr_pt_long$ID[tr_pt_long$code4 %in% hl_codes])
  nhl_true_ids <- unique(tr_pt_long$ID[tr_pt_long$code4 %in% nhl_codes])

  # D-05: unlisted lymphoid codes (9590-9999, in neither list, among export patients)
  lymphoid_codes <- tr_pt_long |>
    dplyr::filter(
      !is.na(code4),
      suppressWarnings(!is.na(as.integer(code4))),
      suppressWarnings(as.integer(code4) >= 9590L),
      suppressWarnings(as.integer(code4) <= 9999L),
      !(code4 %in% hl_codes),
      !(code4 %in% nhl_codes)
    ) |>
    dplyr::group_by(code4) |>
    dplyr::summarise(n_patients = dplyr::n_distinct(ID), .groups = "drop") |>
    dplyr::rename(code = code4) |>
    dplyr::arrange(code)

  # Build output tibble (three-state logic, D-04)
  result <- dplyr::tibble(
    patient_id = ids_unique,
    tr_present = pt_in_tr,
    tr_hl_dx   = dplyr::case_when(
      !pt_in_tr                       ~ NA,
      ids_unique %in% hl_true_ids     ~ TRUE,
      TRUE                            ~ FALSE
    ),
    tr_nhl_dx  = dplyr::case_when(
      !pt_in_tr                       ~ NA,
      ids_unique %in% nhl_true_ids    ~ TRUE,
      TRUE                            ~ FALSE
    )
  )

  attr(result, "tr_hl_ids_all")    <- hl_ids_all
  attr(result, "unlisted_lymphoid") <- lymphoid_codes
  result
}
