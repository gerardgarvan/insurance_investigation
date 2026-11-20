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

# ==============================================================================
# TUMOR-REGISTRY FIRST-COURSE TREATMENT FLAGS (shared by R/202 and R/203)
# ==============================================================================
# Moved verbatim from R/202_tr_sensitivity.R (TR_MAP, CODE_UNKNOWN, SCT_GIVEN,
# TR_HIST_COLS, tr_row_evidence, collapse_evidence). Source:
# .planning/schemas/202_schema_tr_treatment_cols_20261114.md
# TUMOR_REGISTRY_ALL has no TR1/TR2/TR3 split: stratify by SOURCE (UFH/ORL/TMH).
#
# code_scheme (the meaning of 0 is OPPOSITE between the two schemes):
#   reason_no : REASON_NO_* / R_N_* fields.  0 = treatment GIVEN; other codes =
#               reason not given.
#   naaccr_rx : NAACCR summary codes (*_CODE_SUMMARY, HORMONE_CODE, ...).
#               00 = none; listed given_values = given (01-03 chemo, 01 immuno ...).
#   rx_summ   : RX Summ fields (DRAD_SUM, DBRM_SUM, HTE_SUM).  0 = NONE.
# Unknown codes (counted "unknown", never "not given"):
CODE_UNKNOWN <- list(
  reason_no = c(8L, 9L),
  naaccr_rx = c(88L, 99L),
  rx_summ   = c(8L, 9L, 88L, 99L)
)

tr_map_row <- function(source, trtype, date_col = NA_character_,
                       code_col = NA_character_, code_scheme = NA_character_,
                       given_values = integer(0)) {
  dplyr::tibble(source = source, trtype = trtype, date_col = date_col,
                code_col = code_col, code_scheme = code_scheme,
                given_values = list(as.integer(given_values)))
}

SCT_GIVEN <- c(10L, 11L, 12L, 20L)   # 10 BMT NOS; 11 auto; 12 allo; 20 SC harvest+infusion

TR_MAP <- dplyr::bind_rows(
  # UFH (NAACCR summary items)
  tr_map_row("UFH", "chemo",     "CHEMO_START_DATE_SUMMARY",       "CHEMO_CODE_SUMMARY",               "naaccr_rx", 1:3),
  tr_map_row("UFH", "systemic",  "DATE_SYSTEMIC_THERAPY_STARTED"),
  tr_map_row("UFH", "radiation", NA_character_,                    "REASON_NO_RADIATION",              "reason_no", 0L),
  tr_map_row("UFH", "immuno",    "IMMUNO_START_DATE",              "IMMUNOTHERAPY_CODE",               "naaccr_rx", 1L),
  tr_map_row("UFH", "sct",       NA_character_,                    "HEMATOLOGIC_TRANSPLANT_AND_ENDOC", "naaccr_rx", SCT_GIVEN),
  tr_map_row("UFH", "hormone",   "HORMONE_START_DATE",             "HORMONE_CODE",                     "naaccr_rx", 1L),
  # ORL (abstract-style)
  tr_map_row("ORL", "chemo",     "DT_CHEMO",                       "R_N_CHEMO",                        "reason_no", 0L),
  tr_map_row("ORL", "systemic",  "DT_SYS"),
  tr_map_row("ORL", "radiation", "DT_RAD",                         "R_N_RAD",                          "reason_no", 0L),
  tr_map_row("ORL", "immuno",    NA_character_,                    "DBRM_SUM",                         "rx_summ",   1L),
  tr_map_row("ORL", "sct",       NA_character_,                    "HTE_SUM",                          "rx_summ",   SCT_GIVEN),
  tr_map_row("ORL", "hormone",   "DT_HORM",                        "R_N_HORM",                         "reason_no", 0L),
  # TMH (15 TR rows; counts only, no sensitivity). DRAD_SUM: 0 = none; 8/9 unknown;
  # the probe lists no "given" value for it, so given_values is empty.
  tr_map_row("TMH", "chemo",     "DT_CHEMO"),
  tr_map_row("TMH", "systemic",  "DT_SYS"),
  tr_map_row("TMH", "radiation", NA_character_,                    "DRAD_SUM",                         "rx_summ"),
  tr_map_row("TMH", "immuno",    NA_character_,                    "DBRM_SUM",                         "rx_summ",   1L),
  tr_map_row("TMH", "sct",       NA_character_,                    "HTE_SUM",                          "rx_summ",   SCT_GIVEN)
)

# Histology columns used to restrict to HL rows (same two columns and substr(1, 4)
# rule as R/10_cohort_predicates.R:83,92; not listed in the 202 probe).
TR_HIST_COLS <- c("HISTOLOGICAL_TYPE", "MORPH")

# Row-level evidence for one TR_MAP row on HL rows of one SOURCE.
#   row_given   = date present OR code in given_values
#   row_unknown = code in the scheme's unknown codes (88, 99, 8, 9)
tr_row_evidence <- function(rows, map_row) {
  src_rows <- dplyr::filter(rows, SOURCE == map_row$source)
  n <- nrow(src_rows)
  dt <- if (!is.na(map_row$date_col)) as.Date(src_rows[[map_row$date_col]]) else rep(as.Date(NA), n)
  cd <- if (!is.na(map_row$code_col)) {
    suppressWarnings(as.integer(as.character(src_rows[[map_row$code_col]])))
  } else rep(NA_integer_, n)
  unk_codes <- if (is.na(map_row$code_scheme)) integer(0) else CODE_UNKNOWN[[map_row$code_scheme]]
  dplyr::tibble(
    ID = src_rows$ID, SOURCE = map_row$source, trtype = map_row$trtype,
    row_date    = dt,
    row_given   = !is.na(dt) | cd %in% unlist(map_row$given_values),
    row_unknown = cd %in% unk_codes
  )
}

# Patient-level collapse: tr_given = any HL row given; tr_first_date = earliest
# non-missing date across HL rows; unknown (and not given) is "unknown", never
# "not_given".
collapse_evidence <- function(ev, by) {
  ev |>
    dplyr::group_by(dplyr::across(dplyr::all_of(by))) |>
    dplyr::summarise(
      tr_given      = any(row_given),
      tr_unknown    = any(row_unknown),
      tr_first_date = if (any(!is.na(row_date))) min(row_date, na.rm = TRUE) else as.Date(NA),
      .groups = "drop"
    ) |>
    dplyr::mutate(tr_status = dplyr::case_when(tr_given ~ "given", tr_unknown ~ "unknown",
                                               TRUE ~ "not_given"))
}

#' TR first-course treatment flags: one row per patient x treatment type
#'
#' @param ids Optional character vector; restrict to these patient IDs.
#' @param sources TR SOURCE values to include (default UFH + ORL, the two sources
#'   with sensitivity-grade fields; TMH has counts only).
#' @param by_source If TRUE, also stratify by SOURCE (one row per patient x source
#'   x type).
#' @param tr_hl Optional pre-loaded HL-histology rows of TUMOR_REGISTRY_ALL
#'   (columns ID, SOURCE and the TR_MAP columns). NULL = load from DuckDB (own
#'   open/close of the shared connection).
#' @return tibble: ID, [SOURCE], trtype, tr_given (lgl), tr_unknown (lgl),
#'   tr_first_date (Date), tr_status ("given" / "unknown" / "not_given").
build_tr_treatment_flags <- function(ids = NULL, sources = c("UFH", "ORL"),
                                     by_source = FALSE, tr_hl = NULL) {
  if (is.null(tr_hl)) {
    open_pcornet_con()
    tr_tbl_raw  <- get_pcornet_table("TUMOR_REGISTRY_ALL")
    tr_all_cols <- colnames(tr_tbl_raw)
    map_cols <- unique(stats::na.omit(c(TR_MAP$date_col, TR_MAP$code_col)))
    missing_map_cols <- setdiff(map_cols, tr_all_cols)
    hist_present <- intersect(TR_HIST_COLS, tr_all_cols)
    if (length(missing_map_cols) > 0L || !"SOURCE" %in% tr_all_cols ||
        length(hist_present) == 0L) {
      close_pcornet_con()
      stop("[build_tr_treatment_flags] TUMOR_REGISTRY_ALL missing columns: ",
           paste(c(missing_map_cols,
                   if (!"SOURCE" %in% tr_all_cols) "SOURCE",
                   if (length(hist_present) == 0L) "histology"), collapse = ", "))
    }
    tr_data <- tr_tbl_raw |>
      dplyr::select(dplyr::all_of(unique(c("ID", "SOURCE", hist_present, map_cols)))) |>
      dplyr::collect()
    close_pcornet_con()
    tr_hl <- dplyr::filter(
      tr_data,
      dplyr::if_any(dplyr::all_of(hist_present),
                    ~ substr(as.character(.x), 1, 4) %in% ICD_CODES$hl_histology))
  }
  tr_hl <- dplyr::mutate(tr_hl, ID = as.character(ID))
  if (!is.null(ids)) tr_hl <- dplyr::filter(tr_hl, ID %in% as.character(ids))
  map_use <- dplyr::filter(TR_MAP, source %in% sources)
  ev <- dplyr::bind_rows(lapply(seq_len(nrow(map_use)),
                                function(i) tr_row_evidence(tr_hl, map_use[i, ])))
  if (nrow(ev) == 0L) {
    ev <- dplyr::tibble(ID = character(), SOURCE = character(), trtype = character(),
                        row_date = as.Date(character()), row_given = logical(),
                        row_unknown = logical())
  }
  collapse_evidence(ev, if (by_source) c("ID", "SOURCE", "trtype") else c("ID", "trtype"))
}

# ENCOUNTER.ADMIT_DATE values before this date are sentinels (e.g. 1901-01-01),
# not real encounters. Excluded from first/last-encounter computations.
ENC_DATE_SENTINEL_BEFORE <- as.Date("1990-01-01")

# ==============================================================================
# Phase 215: histology code descriptions (ICD-O-3 term list + ICD-O-2 conversion)
# ==============================================================================

#' Build the histology lookup tables from the reference files' contents.
#'
#' Pure function (no file access) so tests can pass small in-test tables.
#' Term list rule: keep rows with Preferred == TRUE; one row per
#' Value + strHistologyBehaviour (stops on duplicates). The 4-digit lookup keeps one
#' row per Value: behavior 3 when present, otherwise the lowest behavior digit.
#'
#' @param terms data frame with Value, strHistologyBehaviour, Preferred, label
#' @param conv  data frame with icdo2_code5, icdo3_code5, site, site_dependent
#' @return list(l5, l4, conv)
build_histology_lookup <- function(terms, conv) {
  need_t <- c("Value", "strHistologyBehaviour", "Preferred", "label")
  need_c <- c("icdo2_code5", "icdo3_code5", "site")
  if (length(setdiff(need_t, names(terms))) > 0L)
    stop("build_histology_lookup: term list missing columns: ",
         paste(setdiff(need_t, names(terms)), collapse = ", "))
  if (length(setdiff(need_c, names(conv))) > 0L)
    stop("build_histology_lookup: conversion table missing columns: ",
         paste(setdiff(need_c, names(conv)), collapse = ", "))

  pref <- terms[toupper(as.character(terms$Preferred)) == "TRUE", , drop = FALSE]
  l5 <- dplyr::tibble(
    hist4       = trimws(as.character(pref$Value)),
    behavior    = trimws(as.character(pref$strHistologyBehaviour)),
    description = trimws(as.character(pref$label))
  )
  l5$key5 <- paste0(l5$hist4, l5$behavior)
  if (anyDuplicated(l5$key5) > 0L)
    stop("build_histology_lookup: duplicate preferred terms for key(s): ",
         paste(utils::head(unique(l5$key5[duplicated(l5$key5)]), 5L), collapse = ", "))

  l4 <- l5[order(l5$hist4, l5$behavior != "3", l5$behavior), , drop = FALSE]
  l4 <- l4[!duplicated(l4$hist4), , drop = FALSE]

  cv <- dplyr::tibble(
    icdo2_code5 = trimws(as.character(conv$icdo2_code5)),
    icdo3_code5 = trimws(as.character(conv$icdo3_code5)),
    site        = toupper(trimws(dplyr::coalesce(as.character(conv$site), "")))
  )
  list(l5 = l5, l4 = l4, conv = cv)
}

# Cached loader for the lookup built from the CONFIG reference paths.
.histology_lookup_cache <- new.env(parent = emptyenv())

#' Load (and cache) the histology lookup from CONFIG$icdo3_histology_terms_path and
#' CONFIG$icdo2_to_icdo3_path. Stops if either file is missing.
load_histology_lookup <- function() {
  if (!is.null(.histology_lookup_cache$lookup)) return(.histology_lookup_cache$lookup)
  tp <- CONFIG$icdo3_histology_terms_path
  cp <- CONFIG$icdo2_to_icdo3_path
  for (p in c(tp, cp)) if (!file.exists(p)) stop("load_histology_lookup: missing reference file: ", p)
  terms <- readxl::read_excel(tp, col_types = "text")
  conv  <- utils::read.csv(cp, colClasses = "character", na.strings = character(0),
                           stringsAsFactors = FALSE)
  .histology_lookup_cache$lookup <- build_histology_lookup(terms, conv)
  .histology_lookup_cache$lookup
}

#' Describe ICD-O histology codes.
#'
#' Returns one row per element of `code`, in input order, with columns
#' raw_code, hist4, behavior, icdo3_code, description, desc_source, match_level.
#' desc_source: icdo3 | icdo3_via_icdo2_conversion | unmatched
#' (extract_fallback is applied by the calling script, D-08).
#' match_level: "5digit", "4digit" (behavior digit absent or not paired with this
#' histology in the term list; description is the 4-digit-level term), or NA.
#'
#' Order for a 5-digit code: exact ICD-O-3 key; ICD-O-2 conversion (site-specific row
#' when `site` matches, else the non-site row; D-05); 4-digit ICD-O-3 term.
#' A 4-digit code uses the 4-digit lookup only. Other shapes are unmatched (D-06).
#'
#' @param code character vector of codes (NA allowed)
#' @param site optional vector (recycled) of registry primary-site codes
#' @param lookup optional list from build_histology_lookup(); default load_histology_lookup()
#' @return tibble with length(code) rows
describe_histology <- function(code, site = NULL, lookup = NULL) {
  if (is.null(lookup)) lookup <- load_histology_lookup()
  n <- length(code)
  raw <- as.character(code)
  site_n <- if (is.null(site)) rep(NA_character_, n) else rep_len(as.character(site), n)
  site_n <- substr(toupper(gsub("[^A-Za-z0-9]", "", site_n)), 1L, 3L)

  norm  <- gsub("/", "", trimws(raw), fixed = TRUE)
  valid <- !is.na(norm) & grepl("^[0-9]{4}([0-9])?$", norm)
  hist4 <- ifelse(valid, substr(norm, 1L, 4L), NA_character_)
  beh   <- ifelse(valid & nchar(norm) == 5L, substr(norm, 5L, 5L), NA_character_)

  icdo3_code <- rep(NA_character_, n); description <- rep(NA_character_, n)
  source <- rep("unmatched", n); level <- rep(NA_character_, n)

  # 1. exact 5-digit ICD-O-3 key
  i5 <- match(norm, lookup$l5$key5)
  hit <- valid & !is.na(beh) & !is.na(i5)
  icdo3_code[hit] <- norm[hit]; description[hit] <- lookup$l5$description[i5[hit]]
  source[hit] <- "icdo3"; level[hit] <- "5digit"

  # 2. ICD-O-2 conversion for remaining 5-digit codes
  todo <- which(valid & !is.na(beh) & source == "unmatched")
  for (k in todo) {
    rows <- which(lookup$conv$icdo2_code5 == norm[k])
    if (length(rows) == 0L) next
    sel <- integer(0)
    if (!is.na(site_n[k]) && nzchar(site_n[k]))
      sel <- rows[lookup$conv$site[rows] == site_n[k]]
    if (length(sel) == 0L) sel <- rows[lookup$conv$site[rows] == ""]
    if (length(sel) == 0L) next
    tgt <- lookup$conv$icdo3_code5[sel[1L]]
    j <- match(tgt, lookup$l5$key5)
    if (is.na(j)) next
    icdo3_code[k] <- tgt; description[k] <- lookup$l5$description[j]
    source[k] <- "icdo3_via_icdo2_conversion"; level[k] <- "5digit"
  }

  # 3. 4-digit ICD-O-3 term (4-digit input, or 5-digit with unpaired behavior)
  todo <- which(valid & source == "unmatched")
  i4 <- match(hist4[todo], lookup$l4$hist4)
  ok <- !is.na(i4)
  icdo3_code[todo[ok]] <- hist4[todo[ok]]
  description[todo[ok]] <- lookup$l4$description[i4[ok]]
  source[todo[ok]] <- "icdo3"; level[todo[ok]] <- "4digit"

  dplyr::tibble(raw_code = raw, hist4 = hist4, behavior = beh, icdo3_code = icdo3_code,
                description = description, desc_source = source, match_level = level)
}
