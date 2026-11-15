# ==============================================================================
# utils/utils_treatment.R -- Shared treatment analysis helpers
# ==============================================================================
#
# Purpose:
#   Shared treatment analysis helpers. Provides safe_table(), get_hl_patient_ids(),
#   and empty_result() for treatment pipeline scripts. safe_table() wraps
#   get_pcornet_table() with null-guard for missing tables (returns NULL instead
#   of error). get_hl_patient_ids() queries DIAGNOSIS for HL cohort. empty_result()
#   returns zero-row tibble matching code inventory schema for graceful handling
#   of missing data sources.
#
# Inputs:
#   - None (utility function library, not a standalone script)
#
# Outputs:
#   - None (defines functions loaded into calling scripts' environment)
#
# Dependencies:
#   - dplyr: Data manipulation for HL patient ID query
#   - tibble: empty_result() tibble creation
#   - glue: String formatting for messages
#
# Requirements: N/A (utility module)
#
# ==============================================================================

#' Safely access a PCORnet table with null-guard
#'
#' Wraps get_pcornet_table() in tryCatch to handle missing tables gracefully.
#' Returns NULL (not an error) when a table doesn't exist.
#'
#' @param name Character. PCORnet table name (e.g., "PROCEDURES", "DISPENSING")
#' @return A dplyr-compatible object (tibble or tbl_dbi), or NULL if not found
safe_table <- function(name) {
  tryCatch(
    get_pcornet_table(name),
    error = function(e) {
      message(glue::glue("  Table {name} not found; skipping"))
      NULL
    }
  )
}

#' Create empty result tibble for missing tables
#'
#' Returns a zero-row tibble matching the standard code inventory schema.
#' @return Tibble with columns: code, code_type, source_table, n, drug_name
empty_result <- function() {
  tibble::tibble(
    code = character(), code_type = character(), source_table = character(),
    n = integer(), drug_name = character()
  )
}

#' Get patient IDs with a Hodgkin Lymphoma diagnosis
#'
#' Queries DIAGNOSIS table for any patient with an HL ICD-10 or ICD-9 code.
#' Used to pull ALL drugs for HL patients (not just curated TREATMENT_CODES).
#'
#' @return Character vector of unique patient IDs
get_hl_patient_ids <- function() {
  dx_tbl <- safe_table("DIAGNOSIS")
  if (is.null(dx_tbl)) {
    message("  Warning: DIAGNOSIS table not found, cannot identify HL patients")
    return(character(0))
  }

  tryCatch(
    {
      hl_ids <- dx_tbl %>%
        dplyr::filter(
          (DX_TYPE == "10" & DX %in% ICD_CODES$hl_icd10) |
            (DX_TYPE == "09" & DX %in% ICD_CODES$hl_icd9)
        ) %>%
        dplyr::select(ID) %>%
        dplyr::distinct() %>%
        dplyr::collect() %>%
        dplyr::pull(ID)
      message(glue::glue("  Found {format(length(hl_ids), big.mark = ',')} patients with HL diagnosis"))
      hl_ids
    },
    error = function(e) {
      message(glue::glue("  Warning: HL patient lookup failed: {e$message}"))
      character(0)
    }
  )
}

#' Helper: return nrow or 0 for NULL tibbles (for logging)
#' @param df A data frame or NULL
#' @return Integer row count (0 if NULL)
nrow_or_0 <- function(df) if (is.null(df)) 0L else nrow(df)

#' Verify output file exists and log size
#'
#' Checks if a file exists and prints formatted size message.
#' Used for post-run verification of RDS/XLSX outputs.
#'
#' @param path Character. File path to check
#' @param label Character. Human-readable label for the file
check_file <- function(path, label) {
  if (file.exists(path)) {
    sz <- file.size(path)
    message(glue("  OK: {label} ({round(sz/1024, 1)} KB)"))
  } else {
    message(glue("  MISSING: {label}"))
  }
}

# ==============================================================================
# D-12 revised Phase 122: MED_ADMIN / DISPENSING chemo detection helpers
# ==============================================================================

#' Normalize an NDC code to 11-digit no-hyphen format
#'
#' Strips hyphens and left-pads with zeros to produce the standard 11-digit
#' NDC string required for RxNav API lookups and crosswalk key matching.
#' Vectorized — safe to apply to a column.
#'
#' @param ndc Character vector of NDC codes (hyphenated or plain)
#' @return Character vector of 11-digit no-hyphen NDC strings
normalize_ndc <- function(ndc) {
  stringr::str_remove_all(ndc, "-") |>
    stringr::str_pad(width = 11, side = "left", pad = "0")
}

#' Load NDC->RxNorm crosswalk from data/reference/ndc_rxnorm_crosswalk.rds
#'
#' Returns named character vector (NDC -> RxCUI) or empty vector with message.
#' Named vector allows O(1) lookup: rxcui <- crosswalk[ndc_value].
#' If the file is absent (crosswalk not yet built on HiPerGator), degrades
#' gracefully — never crashes. Callers must handle character(0) return.
#'
#' @return Named character vector (NDC -> RxCUI) or character(0)
load_ndc_crosswalk <- function() {
  path <- here::here("data", "reference", "ndc_rxnorm_crosswalk.rds")
  if (!file.exists(path)) {
    message("  NDC->RxNorm crosswalk not found at ", path,
            " — NDC-coded rows will NOT contribute to chemo detection.")
    message("  Run R/108_build_ndc_rxnorm_crosswalk.R on HiPerGator to build it.")
    return(character(0))
  }
  cw <- readRDS(path)
  message(glue::glue("  NDC crosswalk loaded: {length(cw)} NDC->RxCUI mappings"))
  cw
}

#' Extract chemo-matching rows from a single PCORnet medication table
#'
#' Returns a tibble of (ID, treatment_date, triggering_code) for chemo hits,
#' or NULL with a message if the table or required columns are absent.
#'
#' ENCOUNTERID intentionally omitted; callers add it if the source has it.
#' (DISPENSING may lack ENCOUNTERID in this extract; omitting keeps the
#' helper contract consistent across all three tables.)
#'
#' @param table_name  "PRESCRIBING", "DISPENSING", or "MED_ADMIN"
#' @param chemo_rxnorm  Character vector of RxNorm CUIs (TREATMENT_CODES$chemo_rxnorm)
#' @param ndc_crosswalk Named character vector: NDC -> RxCUI, or NULL to skip NDC path
#'   (load via load_ndc_crosswalk(); NULL/character(0) both degrade gracefully)
#' @param return_raw_name Logical (default FALSE). When TRUE, adds a `raw_med_name`
#'   column to the returned tibble. For MED_ADMIN rows this carries
#'   RAW_MEDADMIN_MED_NAME when the column exists (guarded via any_of() so a
#'   missing column degrades to NA rather than erroring). For PRESCRIBING and
#'   DISPENSING rows, raw_med_name is always NA_character_ (no raw free-text
#'   field available in this extract). When FALSE (default), the return contract
#'   is unchanged — tibble(ID, treatment_date, triggering_code) — so all
#'   existing callers in R/10, R/11, R/25, R/76, R/20 are unaffected.
#' @param return_source Logical (default FALSE). When TRUE, adds a `source`
#'   column tagging which sub-path produced each row: "PRESCRIBING" for
#'   PRESCRIBING-table rows, "DISPENSING (NDC)" for DISPENSING-table rows,
#'   "MED_ADMIN (RX)" for MED_ADMIN rows matched via MEDADMIN_TYPE == "RX",
#'   and "MED_ADMIN (NDC)" for MED_ADMIN rows matched via MEDADMIN_TYPE == "ND"
#'   (NDC-crosswalk-resolved). When FALSE (default), the return contract is
#'   unchanged — the `source` column is never added — so all existing callers
#'   in R/10, R/11, R/25, R/26, R/76, R/109 are unaffected.
#' @param return_name_capture Logical (default FALSE). When TRUE, adds a
#'   name-based capture tier for MED_ADMIN rows where MEDADMIN_TYPE is not
#'   "RX" or "ND", using `canonicalize_drug_name()` on RAW_MEDADMIN_MED_NAME.
#'   Triggers MCAP-05 safety gate: halts if a resolved canonical label is not
#'   in the known drug set (unique values of DRUG_NAME_ALIASES). Source tag for
#'   name-matched rows = "MED_ADMIN_NAME". triggering_code = "NAME:<canonical>".
#'   Only rows not already captured by RX/ND paths are added (anti-join on
#'   ID + treatment_date). Existing callers pass neither argument so they are
#'   unaffected (default FALSE skips the name tier entirely).
#' @return Tibble(ID, treatment_date, triggering_code) with distinct rows, or NULL.
#'   When return_raw_name = TRUE: tibble(ID, treatment_date, triggering_code, raw_med_name).
#'   When return_source = TRUE: adds a `source` column (see @param above).
get_chemo_hits <- function(table_name, chemo_rxnorm, ndc_crosswalk = NULL,
                           return_raw_name = FALSE, return_source = FALSE,
                           return_name_capture = FALSE) {
  tbl <- safe_table(table_name)
  if (is.null(tbl)) {
    message(glue::glue("  [{table_name}] table not found — skipping chemo detection"))
    return(NULL)
  }

  if (table_name == "PRESCRIBING") {
    if (!"RXNORM_CUI" %in% colnames(tbl)) {
      message(glue::glue("  [PRESCRIBING] RXNORM_CUI absent — unexpected; skipping"))
      return(NULL)
    }
    result <- tbl %>%
      dplyr::filter(RXNORM_CUI %in% chemo_rxnorm) %>%
      dplyr::mutate(treatment_date = dplyr::coalesce(RX_ORDER_DATE, RX_START_DATE)) %>%
      dplyr::filter(!is.na(treatment_date)) %>%
      dplyr::select(ID, treatment_date, triggering_code = RXNORM_CUI) %>%
      dplyr::collect() %>%
      dplyr::distinct(ID, treatment_date, triggering_code)
    if (return_raw_name) result <- dplyr::mutate(result, raw_med_name = NA_character_)
    if (return_source) result <- dplyr::mutate(result, source = "PRESCRIBING")
    result

  } else if (table_name == "DISPENSING") {
    if (!"NDC" %in% colnames(tbl)) {
      message(glue::glue("  [DISPENSING] NDC column absent — skipping"))
      return(NULL)
    }
    if (is.null(ndc_crosswalk) || length(ndc_crosswalk) == 0) {
      message("  [DISPENSING] no NDC crosswalk loaded — skipping chemo match")
      return(NULL)
    }
    rows <- tbl %>%
      dplyr::filter(!is.na(NDC), !is.na(DISPENSE_DATE)) %>%
      dplyr::select(ID, treatment_date = DISPENSE_DATE, NDC) %>%
      dplyr::collect()
    result <- rows %>%
      dplyr::mutate(rxcui = ndc_crosswalk[normalize_ndc(NDC)]) %>%
      dplyr::filter(!is.na(rxcui), rxcui %in% chemo_rxnorm) %>%
      dplyr::select(ID, treatment_date, triggering_code = rxcui) %>%
      dplyr::distinct(ID, treatment_date, triggering_code)
    if (return_raw_name) result <- dplyr::mutate(result, raw_med_name = NA_character_)
    if (return_source) result <- dplyr::mutate(result, source = "DISPENSING (NDC)")
    result

  } else if (table_name == "MED_ADMIN") {
    required <- c("MEDADMIN_TYPE", "MEDADMIN_CODE", "MEDADMIN_START_DATE")
    missing_cols <- required[!required %in% colnames(tbl)]
    if (length(missing_cols) > 0) {
      message(glue::glue(
        "  [MED_ADMIN] missing columns: {paste(missing_cols, collapse = ', ')} — skipping"
      ))
      return(NULL)
    }
    # RX-typed rows: MEDADMIN_CODE holds RxNorm CUI directly.
    # When return_raw_name = TRUE, carry RAW_MEDADMIN_MED_NAME guarded by any_of()
    # so a missing column degrades to absent (not an error) on lazy dbplyr tbls.
    rx_hits <- tbl %>%
      dplyr::filter(
        MEDADMIN_TYPE == "RX",
        MEDADMIN_CODE %in% chemo_rxnorm,
        !is.na(MEDADMIN_START_DATE)
      ) %>%
      dplyr::select(ID, treatment_date = MEDADMIN_START_DATE,
                    triggering_code = MEDADMIN_CODE,
                    dplyr::any_of(c(raw_med_name = "RAW_MEDADMIN_MED_NAME"))) %>%
      dplyr::collect()
    # Ensure raw_med_name column exists regardless of source schema
    if (!"raw_med_name" %in% colnames(rx_hits)) {
      rx_hits <- dplyr::mutate(rx_hits, raw_med_name = NA_character_)
    }
    # Dedup on key cols; take first raw_med_name per (ID, treatment_date, triggering_code)
    rx_hits <- rx_hits %>%
      dplyr::group_by(ID, treatment_date, triggering_code) %>%
      dplyr::summarise(raw_med_name = dplyr::first(raw_med_name), .groups = "drop")
    if (return_source) rx_hits <- dplyr::mutate(rx_hits, source = "MED_ADMIN (RX)")

    # ND-typed rows: MEDADMIN_CODE holds NDC — needs crosswalk
    nd_hits <- NULL
    if (!is.null(ndc_crosswalk) && length(ndc_crosswalk) > 0) {
      nd_rows <- tbl %>%
        dplyr::filter(
          MEDADMIN_TYPE == "ND",
          !is.na(MEDADMIN_CODE),
          !is.na(MEDADMIN_START_DATE)
        ) %>%
        dplyr::select(ID, treatment_date = MEDADMIN_START_DATE,
                      NDC = MEDADMIN_CODE,
                      dplyr::any_of(c(raw_med_name = "RAW_MEDADMIN_MED_NAME"))) %>%
        dplyr::collect()
      if (!"raw_med_name" %in% colnames(nd_rows)) {
        nd_rows <- dplyr::mutate(nd_rows, raw_med_name = NA_character_)
      }
      nd_hits <- nd_rows %>%
        dplyr::mutate(rxcui = ndc_crosswalk[normalize_ndc(NDC)]) %>%
        dplyr::filter(!is.na(rxcui), rxcui %in% chemo_rxnorm) %>%
        dplyr::select(ID, treatment_date, triggering_code = rxcui, raw_med_name) %>%
        dplyr::group_by(ID, treatment_date, triggering_code) %>%
        dplyr::summarise(raw_med_name = dplyr::first(raw_med_name), .groups = "drop")
      if (return_source) nd_hits <- dplyr::mutate(nd_hits, source = "MED_ADMIN (NDC)")
    }
    result <- dplyr::bind_rows(rx_hits, nd_hits)

    # --- Phase 204 (MCAP-01): NAME-typed rows ---
    # MCAP-05 safety gate: halt if any resolved canonical is not in known drug set.
    if (return_name_capture) {
      name_rows <- tbl %>%
        dplyr::filter(
          !MEDADMIN_TYPE %in% c("RX", "ND"),
          !is.na(RAW_MEDADMIN_MED_NAME),
          nchar(trimws(RAW_MEDADMIN_MED_NAME)) > 0,
          !is.na(MEDADMIN_START_DATE)
        ) %>%
        dplyr::select(ID, treatment_date = MEDADMIN_START_DATE,
                      raw_name = RAW_MEDADMIN_MED_NAME) %>%
        dplyr::collect()

      name_rows <- name_rows %>%
        dplyr::mutate(
          canonical = canonicalize_drug_name(toupper(trimws(raw_name)))
        )

      # Supportive care (G-CSF, antiemetics, ESAs, steroids) is not treatment: drop
      # before the safety gate and capture. Falls back to empty if config lacks it.
      sc_names <- if (exists("SUPPORTIVE_CARE_NAMES")) SUPPORTIVE_CARE_NAMES else character(0)
      name_rows <- dplyr::filter(name_rows, !tolower(trimws(canonical)) %in% sc_names)

      known_canonicals <- setdiff(unique(unname(DRUG_NAME_ALIASES)), sc_names)

      # MCAP-05: halt on any alias-resolved canonical not in the known drug set
      unexpected <- dplyr::filter(name_rows,
        canonical != toupper(trimws(raw_name)),
        !canonical %in% known_canonicals)
      if (nrow(unexpected) > 0) {
        stop(glue::glue(
          "[get_chemo_hits] MCAP-05: unexpected drug family in RAW_MEDADMIN_MED_NAME. ",
          "Review these strings before proceeding: ",
          paste(unique(unexpected$raw_name), collapse = "; ")
        ))
      }

      name_hits <- name_rows %>%
        dplyr::filter(canonical %in% known_canonicals) %>%
        dplyr::mutate(
          triggering_code = paste0("NAME:", canonical),
          raw_med_name    = raw_name
        ) %>%
        dplyr::select(ID, treatment_date, triggering_code, raw_med_name) %>%
        dplyr::distinct(ID, treatment_date, triggering_code, raw_med_name)
      if (return_source) name_hits <- dplyr::mutate(name_hits, source = "MED_ADMIN_NAME")

      # Anti-join: only add rows not already captured by RX/ND paths
      name_hits_new <- dplyr::anti_join(
        name_hits,
        dplyr::select(result, ID, treatment_date),
        by = c("ID", "treatment_date")
      )
      result <- dplyr::bind_rows(result, name_hits_new)
    }

    # Keep only the columns the caller asked for, preserving the original
    # 3-column contract when both return_raw_name and return_source are FALSE
    # (the default) so all existing callers are byte-identical to before.
    keep_cols <- c("ID", "treatment_date", "triggering_code")
    if (return_raw_name || return_name_capture) keep_cols <- c(keep_cols, "raw_med_name")
    if (return_source) keep_cols <- c(keep_cols, "source")
    result <- dplyr::select(result, dplyr::any_of(keep_cols))
    result

  } else {
    message(glue::glue("  [{table_name}] unrecognised table for get_chemo_hits() — skipping"))
    NULL
  }
}

#' Phase 204 QC table of name-captured MED_ADMIN strings (MCAP-05)
#'
#' @param ma_dates Tibble from get_chemo_hits("MED_ADMIN", return_source = TRUE,
#'   return_raw_name = TRUE, return_name_capture = TRUE).
#' @return Tibble(canonical, raw_med_name, n_records, n_patients, *_disp) with
#'   counts 1-10 displayed as "<11".
build_p204_name_qc <- function(ma_dates) {
  ma_dates %>%
    dplyr::filter(source == "MED_ADMIN_NAME", !is.na(raw_med_name)) %>%
    dplyr::mutate(canonical = sub("^NAME:", "", triggering_code)) %>%
    dplyr::group_by(canonical, raw_med_name) %>%
    dplyr::summarise(
      n_records  = dplyr::n(),
      n_patients = dplyr::n_distinct(ID),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      n_records_disp  = dplyr::if_else(n_records  < 11L, "<11", as.character(n_records)),
      n_patients_disp = dplyr::if_else(n_patients < 11L, "<11", as.character(n_patients))
    ) %>%
    dplyr::arrange(canonical, dplyr::desc(n_records))
}

#' Get all patients with at least one HL diagnosis code (SURV-02, D-01..D-04, D-24)
#'
#' ICD-10 C81* (DX_TYPE "10") or ICD-9 201* (DX_TYPE "09"), matched in DuckDB
#' before collect(). Anchor = earliest DX_DATE, falling back to ADMIT_DATE
#' (hl_any_dx_from_tibble() in utils_surveillance.R). Patients with no usable
#' date are returned with hl_anchor_date = NA; the caller drops and counts them.
#'
#' Unlike get_hl_patient_ids(), this function STOPS on failure instead of
#' returning an empty result, so a broken query cannot yield N = 0 silently.
#'
#' @return tibble: ID (chr), hl_anchor_date (Date), in_confirmed_cohort (lgl)
get_hl_any_dx_ids <- function() {
  dx <- safe_table("DIAGNOSIS")
  if (is.null(dx))
    stop("get_hl_any_dx_ids(): DIAGNOSIS table unavailable")
  if (!inherits(dx, "tbl_lazy"))
    stop("get_hl_any_dx_ids(): safe_table('DIAGNOSIS') returned an in-memory ",
         "table; a lazy DuckDB tbl is required (L-5)")

  date_cols <- intersect(c("DX_DATE", "ADMIT_DATE"), colnames(dx))
  raw <- dx |>
    dplyr::filter(dplyr::sql(paste0(
      "(TRIM(DX_TYPE) = '10' AND REPLACE(UPPER(TRIM(DX)), '.', '') LIKE 'C81%') OR ",
      "(TRIM(DX_TYPE) = '09' AND REPLACE(UPPER(TRIM(DX)), '.', '') LIKE '201%')"))) |>
    dplyr::select(dplyr::all_of(c("ID", "DX", "DX_TYPE", date_cols))) |>
    dplyr::collect()

  for (dc in c("DX_DATE", "ADMIT_DATE")) {
    raw[[dc]] <- if (dc %in% names(raw)) parse_pcornet_date(raw[[dc]])
                 else rep(as.Date(NA), nrow(raw))
  }

  anchors <- hl_any_dx_from_tibble(raw)

  confirmed <- get_hl_patient_ids()
  if (length(confirmed) == 0)
    stop("get_hl_any_dx_ids(): get_hl_patient_ids() returned no IDs; ",
         "refusing to build in_confirmed_cohort (D-24)")

  anchors |> dplyr::mutate(in_confirmed_cohort = ID %in% confirmed)
}
