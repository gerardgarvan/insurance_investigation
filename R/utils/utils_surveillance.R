# ==============================================================================
# utils_surveillance.R -- Phase 158 surveillance modality frequency helpers
# ==============================================================================
# Pure functions (no DuckDB, no CONFIG) so every rule is unit-testable locally.
# The DuckDB wrapper get_hl_any_dx_ids() lives in utils_treatment.R (D-04).
#
# Contents:
#   Codeset:    load_surveillance_codeset(), normalize_surv_code(),
#               surv_components(), load_lab_analytes(), load_modality_lookup()
#   SQL:        surv_sql_in(), surv_code_where()
#   Denominator: hl_any_dx_from_tibble()
#   Matching:   match_coded_events(), build_component_events()
#   Outputs:    build_code_presence(), compute_followup(),
#               classify_event_window(), compute_modality_stats(),
#               build_patient_modality(), suppress_small(), suppress_table()
#   Phase 159:  map_analyte_hits(), build_analyte_events(),
#               build_analyte_presence(), build_patient_modality_dates()
# ==============================================================================

SURV_REQUIRED_COLS <- c("codeset_row_id", "modality", "submodality",
                        "code_system", "code", "code_norm", "cdm_table",
                        "cdm_column", "type_filter", "match", "tier",
                        "plausibility")
SURV_MATCH_VALUES  <- c("exact", "prefix", "component_all_same_day",
                        "analyte_all_same_day", "analyte_min_same_day")
SURV_ANALYTE_MATCHES <- c("analyte_all_same_day", "analyte_min_same_day")
SURV_TIERS         <- c("primary", "sensitivity")
SURV_TABLE_TYPES   <- list(PROCEDURES    = c("CH", "10", "09"),
                           DIAGNOSIS     = c("10", "09"),
                           LAB_RESULT_CM = "")

# ------------------------------------------------------------------------------
# Codeset
# ------------------------------------------------------------------------------

#' Normalize a code: trim, uppercase, strip dots and a trailing "*" (D-15)
normalize_surv_code <- function(x) {
  x <- toupper(trimws(as.character(x)))
  x <- gsub(".", "", x, fixed = TRUE)
  sub("\\*$", "", x)
}

#' Split a component_all_same_day code_norm ("a;b;c") into normalized parts
surv_components <- function(code_norm) {
  parts <- normalize_surv_code(strsplit(code_norm, ";", fixed = TRUE)[[1]])
  parts[nzchar(parts)]
}

#' Load and validate data/reference/surveillance_codeset.xlsx (SURV-01)
#'
#' Reads every column as text, turns NA (blank cells) into "", normalizes
#' code_norm, and stops on any structural violation.
load_surveillance_codeset <- function(
    path = file.path("data", "reference", "surveillance_codeset.xlsx")) {

  if (!file.exists(path))
    stop("surveillance codeset not found: ", path)

  cs <- readxl::read_excel(path, sheet = "Analysis_Codeset",
                           col_types = "text")

  missing_cols <- setdiff(SURV_REQUIRED_COLS, names(cs))
  if (length(missing_cols) > 0)
    stop("surveillance codeset missing required columns: ",
         paste(missing_cols, collapse = ", "))

  # Optional column (Phase 159); absent in Phase 158-era files and fixtures
  if (!"min_analyte_count" %in% names(cs)) cs$min_analyte_count <- ""

  cs <- cs |>
    dplyr::mutate(dplyr::across(dplyr::everything(),
                                ~ trimws(dplyr::coalesce(.x, ""))))

  # Drop fully blank rows (e.g. trailing formatting rows)
  cs <- cs[rowSums(cs != "") > 0, , drop = FALSE]

  if (any(cs$codeset_row_id == ""))
    stop("codeset_row_id must be non-blank on every row")
  if (anyDuplicated(cs$codeset_row_id))
    stop("codeset_row_id values must be unique")
  if (any(cs$modality == "" | cs$code_norm == ""))
    stop("modality and code_norm must be non-blank on every row")

  bad_tier <- setdiff(unique(cs$tier), SURV_TIERS)
  if (length(bad_tier) > 0)
    stop("Invalid tier values: ", paste(bad_tier, collapse = ", "))

  bad_match <- setdiff(unique(cs$match), SURV_MATCH_VALUES)
  if (length(bad_match) > 0)
    stop("Invalid match values: ", paste(bad_match, collapse = ", "))

  is_rule <- cs$match %in% SURV_ANALYTE_MATCHES

  # Analyte rule rows draw on Lab_Analytes across tables: cdm_table and
  # type_filter must be blank. All other rows need a known table.
  bad_rule_tbl <- is_rule & (cs$cdm_table != "" | cs$type_filter != "")
  if (any(bad_rule_tbl))
    stop("Analyte rule rows must have blank cdm_table and type_filter: ",
         paste(cs$codeset_row_id[bad_rule_tbl], collapse = ", "))
  bad_table <- setdiff(unique(cs$cdm_table[!is_rule]), names(SURV_TABLE_TYPES))
  if (length(bad_table) > 0)
    stop("Invalid cdm_table values: ", paste(bad_table, collapse = ", "))

  # type_filter must be the bare value for its table (e.g. "CH", not
  # "PX_TYPE='CH'"); LAB_RESULT_CM rows must be blank
  bad_type <- !is_rule & purrr::pmap_lgl(
    list(cs$cdm_table, cs$type_filter),
    function(t, f) !is.null(SURV_TABLE_TYPES[[t]]) && !(f %in% SURV_TABLE_TYPES[[t]]))
  if (any(bad_type))
    stop("Invalid type_filter for its cdm_table on rows: ",
         paste(cs$codeset_row_id[bad_type], collapse = ", "))

  # Normalize code_norm (component and analyte rule rows part by part)
  cs$code_norm <- ifelse(
    cs$match %in% c("component_all_same_day", SURV_ANALYTE_MATCHES),
    vapply(cs$code_norm, function(z) paste(surv_components(z), collapse = ";"),
           character(1)),
    normalize_surv_code(cs$code_norm)
  )

  comp <- cs$match == "component_all_same_day"
  if (any(comp)) {
    n_parts <- vapply(cs$code_norm[comp],
                      function(z) length(surv_components(z)), integer(1))
    if (any(n_parts < 2) || any(cs$cdm_table[comp] != "LAB_RESULT_CM"))
      stop("component_all_same_day rows need >= 2 ';'-separated component ",
           "codes and cdm_table = LAB_RESULT_CM")
  }

  # min_analyte_count: integer 1..(n listed - 1) on analyte_min_same_day rows,
  # blank everywhere else (Phase 159 D-10)
  is_min <- cs$match == "analyte_min_same_day"
  if (any(!is_min & cs$min_analyte_count != ""))
    stop("min_analyte_count must be blank except on analyte_min_same_day rows: ",
         paste(cs$codeset_row_id[!is_min & cs$min_analyte_count != ""], collapse = ", "))
  if (any(is_min)) {
    k <- suppressWarnings(as.integer(cs$min_analyte_count[is_min]))
    n <- vapply(cs$code_norm[is_min], function(z) length(surv_components(z)), integer(1))
    bad <- is.na(k) | k < 1 | k >= n |
      !grepl("^[0-9]+$", cs$min_analyte_count[is_min])
    if (any(bad))
      stop("min_analyte_count must be a whole number >= 1 and < the number of ",
           "listed analytes on rows: ",
           paste(cs$codeset_row_id[is_min][bad], collapse = ", "))
  }
  if (any(is_rule & !nzchar(cs$code_norm)))
    stop("Analyte rule rows must list at least one analyte")

  dup <- duplicated(cs[, c("modality", "code_norm", "match")])
  if (any(dup))
    stop("Duplicate modality x code_norm: ",
         paste(cs$modality[dup], cs$code_norm[dup], sep = "/", collapse = "; "))

  tibble::as_tibble(cs)
}

#' Load and validate the Lab_Analytes sheet (Phase 159 LAB-01).
#' If codeset is given, every analyte named in an analyte rule row must exist.
load_lab_analytes <- function(
    path = file.path("data", "reference", "surveillance_codeset.xlsx"),
    codeset = NULL) {

  req <- c("analyte_row_id", "analyte", "code_system", "code", "code_norm",
           "cdm_table", "type_filter")
  la <- readxl::read_excel(path, sheet = "Lab_Analytes", col_types = "text")
  miss <- setdiff(req, names(la))
  if (length(miss) > 0)
    stop("Lab_Analytes missing required columns: ", paste(miss, collapse = ", "))

  la <- la |>
    dplyr::mutate(dplyr::across(dplyr::everything(),
                                ~ trimws(dplyr::coalesce(.x, ""))))
  la <- la[rowSums(la != "") > 0, , drop = FALSE]

  if (any(la$analyte_row_id == "") || anyDuplicated(la$analyte_row_id))
    stop("Lab_Analytes analyte_row_id must be non-blank and unique")
  if (any(la$analyte == "" | la$code_norm == ""))
    stop("Lab_Analytes analyte and code_norm must be non-blank")

  la$analyte   <- toupper(la$analyte)
  la$code_norm <- normalize_surv_code(la$code_norm)

  bad_tbl <- !la$cdm_table %in% c("LAB_RESULT_CM", "PROCEDURES")
  if (any(bad_tbl))
    stop("Lab_Analytes cdm_table must be LAB_RESULT_CM or PROCEDURES: ",
         paste(la$analyte_row_id[bad_tbl], collapse = ", "))
  bad_type <- purrr::pmap_lgl(list(la$cdm_table, la$type_filter),
                              function(t, f) !(f %in% SURV_TABLE_TYPES[[t]]))
  if (any(bad_type))
    stop("Lab_Analytes invalid type_filter on rows: ",
         paste(la$analyte_row_id[bad_type], collapse = ", "))

  dup <- duplicated(la[, c("analyte", "cdm_table", "code_norm")])
  if (any(dup))
    stop("Lab_Analytes duplicate analyte x code: ",
         paste(la$analyte[dup], la$code_norm[dup], sep = "/", collapse = "; "))

  if (!is.null(codeset)) {
    rules <- codeset[codeset$match %in% SURV_ANALYTE_MATCHES, , drop = FALSE]
    for (i in seq_len(nrow(rules))) {
      unknown <- setdiff(surv_components(rules$code_norm[i]), la$analyte)
      if (length(unknown) > 0)
        stop("Rule row ", rules$codeset_row_id[i], " references analyte ",
             paste(unknown, collapse = ", "), " not found in Lab_Analytes")
    }
  }
  tibble::as_tibble(la)
}

#' Load the Modalities sheet: modality -> column prefix for the per-patient
#' table, in display order. Every codeset modality must be listed (LAB-06).
load_modality_lookup <- function(
    path = file.path("data", "reference", "surveillance_codeset.xlsx"),
    codeset = NULL) {

  md <- readxl::read_excel(path, sheet = "Modalities", col_types = "text")
  miss <- setdiff(c("modality", "column_prefix", "display_order"), names(md))
  if (length(miss) > 0)
    stop("Modalities missing required columns: ", paste(miss, collapse = ", "))
  md <- md |>
    dplyr::mutate(dplyr::across(dplyr::everything(),
                                ~ trimws(dplyr::coalesce(.x, "")))) |>
    dplyr::filter(modality != "")
  if (anyDuplicated(md$modality) || anyDuplicated(md$column_prefix))
    stop("Modalities: modality and column_prefix must be unique")
  if (!all(grepl("^[a-z][a-z0-9_]*$", md$column_prefix)))
    stop("Modalities: column_prefix must be lowercase letters, digits, underscores")
  ord <- suppressWarnings(as.numeric(md$display_order))
  if (anyNA(ord)) stop("Modalities: display_order must be numeric")

  if (!is.null(codeset)) {
    unlisted <- setdiff(unique(codeset$modality), md$modality)
    if (length(unlisted) > 0)
      stop("Modalities sheet is missing codeset modalities: ",
           paste(unlisted, collapse = ", "))
  }
  md <- md[order(ord), ]
  stats::setNames(md$column_prefix, md$modality)
}

# ------------------------------------------------------------------------------
# SQL builders (string-only; used with dplyr::filter(dplyr::sql(...)))
# ------------------------------------------------------------------------------

surv_sql_in <- function(x) {
  x <- unique(x)
  paste0("(", paste0("'", gsub("'", "''", x, fixed = TRUE), "'",
                     collapse = ", "), ")")
}

#' WHERE clause matching a CDM code column against exact codes and prefixes,
#' with the column normalized in SQL the same way as normalize_surv_code()
surv_code_where <- function(col, exact = character(), prefix = character()) {
  norm  <- sprintf("REPLACE(UPPER(TRIM(%s)), '.', '')", col)
  parts <- character()
  if (length(exact))  parts <- c(parts, sprintf("%s IN %s", norm, surv_sql_in(exact)))
  if (length(prefix)) parts <- c(parts, sprintf("%s LIKE '%s%%'", norm,
                                                gsub("'", "''", unique(prefix))))
  if (!length(parts)) return("FALSE")
  paste0("(", paste(parts, collapse = " OR "), ")")
}

# ------------------------------------------------------------------------------
# Denominator (SURV-02)
# ------------------------------------------------------------------------------

#' HL any-dx logic on an in-memory DIAGNOSIS extract.
#' dx_tbl: ID, DX, DX_TYPE, DX_DATE (Date), ADMIT_DATE (Date).
#' Returns ID, hl_anchor_date (min of DX_DATE, falling back to ADMIT_DATE);
#' patients with no usable date keep hl_anchor_date = NA.
hl_any_dx_from_tibble <- function(dx_tbl) {
  dx_tbl |>
    dplyr::mutate(dx_norm = normalize_surv_code(DX),
                  dx_type = trimws(as.character(DX_TYPE))) |>
    dplyr::filter((dx_type == "10" & startsWith(dx_norm, "C81")) |
                  (dx_type == "09" & startsWith(dx_norm, "201"))) |>
    dplyr::mutate(use_date = dplyr::coalesce(DX_DATE, ADMIT_DATE)) |>
    dplyr::group_by(ID) |>
    dplyr::summarise(
      hl_anchor_date = if (all(is.na(use_date))) as.Date(NA)
                       else min(use_date, na.rm = TRUE),
      .groups = "drop")
}

# ------------------------------------------------------------------------------
# Matching
# ------------------------------------------------------------------------------

#' Match collected CDM rows to exact/prefix codeset rows.
#' raw: ID, code_raw, type_val ("" for labs), event_date (Date), source_table.
#' Returns one row per raw row x matching codeset row, with type_ok flag
#' (type_val equals the row's type_filter; always TRUE when type_filter = "").
match_coded_events <- function(raw, codeset) {
  empty <- tibble::tibble(
    codeset_row_id = character(), ID = character(), code_data = character(),
    type_val = character(), event_date = as.Date(character()),
    source_table = character(), modality = character(),
    submodality = character(), tier = character(), type_ok = logical())
  if (nrow(raw) == 0) return(empty)

  raw <- raw |>
    dplyr::mutate(code_data = normalize_surv_code(code_raw),
                  type_val  = trimws(dplyr::coalesce(as.character(type_val), "")))
  cs_cols <- c("codeset_row_id", "code_norm", "type_filter", "modality",
               "submodality", "tier")

  ex <- codeset |> dplyr::filter(match == "exact") |> dplyr::select(dplyr::all_of(cs_cols))
  m_exact <- raw |>
    dplyr::inner_join(ex, by = c(code_data = "code_norm"),
                      relationship = "many-to-many")

  px <- codeset |> dplyr::filter(match == "prefix") |> dplyr::select(dplyr::all_of(cs_cols))
  m_prefix <- purrr::map_dfr(seq_len(nrow(px)), function(i) {
    r <- px[i, ]
    raw |>
      dplyr::filter(startsWith(code_data, r$code_norm)) |>
      dplyr::mutate(codeset_row_id = r$codeset_row_id,
                    type_filter = r$type_filter, modality = r$modality,
                    submodality = r$submodality, tier = r$tier)
  })

  out <- dplyr::bind_rows(m_exact, m_prefix)
  if (nrow(out) == 0) return(empty)
  out |>
    dplyr::mutate(type_ok = type_filter == "" | type_val == type_filter) |>
    dplyr::select(dplyr::all_of(names(empty)))
}

#' Build component_all_same_day events (D-22).
#' lab: ID, code_raw, event_date. Returns list(events, near_miss) where
#' near_miss has one row per codeset row with the count of ID x dates having
#' some but not all components.
build_component_events <- function(lab, codeset) {
  comp_rows <- codeset |> dplyr::filter(match == "component_all_same_day")
  empty_ev <- tibble::tibble(
    codeset_row_id = character(), ID = character(), code_data = character(),
    type_val = character(), event_date = as.Date(character()),
    source_table = character(), modality = character(),
    submodality = character(), tier = character(), type_ok = logical())
  if (nrow(comp_rows) == 0)
    return(list(events = empty_ev,
                near_miss = tibble::tibble(codeset_row_id = character(),
                                           n_partial_id_dates = integer())))
  lab <- lab |>
    dplyr::mutate(code_data = normalize_surv_code(code_raw)) |>
    dplyr::filter(!is.na(event_date))

  res <- lapply(seq_len(nrow(comp_rows)), function(i) {
    r <- comp_rows[i, ]
    comps <- surv_components(r$code_norm)
    by_day <- lab |>
      dplyr::filter(code_data %in% comps) |>
      dplyr::distinct(ID, event_date, code_data) |>
      dplyr::count(ID, event_date, name = "n_comp")
    ev <- by_day |>
      dplyr::filter(n_comp == length(comps)) |>
      dplyr::transmute(codeset_row_id = r$codeset_row_id, ID,
                       code_data = r$code_norm, type_val = "",
                       event_date, source_table = "LAB_RESULT_CM",
                       modality = r$modality, submodality = r$submodality,
                       tier = r$tier, type_ok = TRUE)
    nm <- tibble::tibble(codeset_row_id = r$codeset_row_id,
                         n_partial_id_dates = sum(by_day$n_comp < length(comps)))
    list(ev = ev, nm = nm)
  })
  list(events    = dplyr::bind_rows(empty_ev, lapply(res, `[[`, "ev")),
       near_miss = dplyr::bind_rows(lapply(res, `[[`, "nm")))
}

# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------

#' A_code_presence (SURV-03): one row per codeset row, built from matched
#' events BEFORE any de-duplication. Only type_ok rows count toward presence;
#' code matches with a different PX_TYPE/DX_TYPE are reported separately.
build_code_presence <- function(codeset, matched) {
  ok <- matched |>
    dplyr::filter(type_ok) |>
    dplyr::group_by(codeset_row_id) |>
    dplyr::summarise(
      n_records       = dplyr::n(),
      n_patients      = dplyr::n_distinct(ID),
      n_patient_dates = dplyr::n_distinct(ID, event_date),
      first_date      = min(event_date, na.rm = TRUE),
      last_date       = max(event_date, na.rm = TRUE),
      .groups = "drop")
  mism <- matched |>
    dplyr::filter(!type_ok) |>
    dplyr::group_by(codeset_row_id) |>
    dplyr::summarise(
      n_records_other_type = dplyr::n(),
      other_types = paste(sort(unique(type_val)), collapse = ";"),
      .groups = "drop")
  out <- codeset |>
    dplyr::left_join(ok,   by = "codeset_row_id") |>
    dplyr::left_join(mism, by = "codeset_row_id") |>
    dplyr::mutate(
      dplyr::across(c(n_records, n_patients, n_patient_dates,
                      n_records_other_type), ~ dplyr::coalesce(as.integer(.x), 0L)),
      other_types = dplyr::coalesce(other_types, ""),
      present = n_records > 0)
  stopifnot("A_code_presence must have one row per codeset row" =
              nrow(out) == nrow(codeset))
  out
}

#' Follow-up per patient (D-09, D-10, D-26).
#' denominator: ID, hl_anchor_date. last_enc: ID, last_enc_date.
#' death: ID, death_date (may have several rows per ID; earliest is used).
compute_followup <- function(denominator, last_enc, death, cutoff) {
  death1 <- death |>
    dplyr::filter(!is.na(death_date)) |>
    dplyr::group_by(ID) |>
    dplyr::summarise(death_date = min(death_date), .groups = "drop")
  denominator |>
    dplyr::left_join(last_enc, by = "ID") |>
    dplyr::left_join(death1,   by = "ID") |>
    dplyr::mutate(
      follow_end = dplyr::if_else(
        is.na(death_date) & is.na(last_enc_date), as.Date(NA),
        pmin(death_date, last_enc_date, cutoff, na.rm = TRUE)),
      fu_days = as.numeric(follow_end - hl_anchor_date),
      fu_status = dplyr::case_when(
        is.na(follow_end) ~ "no_followup_date",
        fu_days <= 0      ~ "zero_or_negative",
        TRUE              ~ "ok"),
      person_years = dplyr::if_else(fu_status == "ok", fu_days / 365.25, 0))
}

#' Assign each event to pre / post / after_followup (D-25).
#' Anchor-day events are "pre" unless anchor_day_is_post = TRUE.
classify_event_window <- function(events, followup, anchor_day_is_post = FALSE) {
  events |>
    dplyr::inner_join(followup |> dplyr::select(ID, hl_anchor_date, follow_end),
                      by = "ID") |>
    dplyr::mutate(window = dplyr::case_when(
      event_date <  hl_anchor_date ~ "pre",
      event_date == hl_anchor_date & !anchor_day_is_post ~ "pre",
      is.na(follow_end) | event_date > follow_end ~ "after_followup",
      TRUE ~ "post"))
}

#' Modality frequency (SURV-04/05) for the given tiers, post-anchor window,
#' at ID x <by> x date grain. keys: tibble of all key combinations to report
#' (zero rows kept). Events per person-year is pooled over the WHOLE
#' denominator's person-years (D-26).
compute_modality_stats <- function(events, followup, keys, tiers,
                                   by = "modality") {
  denom_n  <- nrow(followup)
  total_py <- sum(followup$person_years)
  ev <- events |>
    dplyr::filter(type_ok, tier %in% tiers, window == "post") |>
    dplyr::distinct(dplyr::across(dplyr::all_of(c("ID", by, "event_date"))))
  per_pt <- ev |> dplyr::count(dplyr::across(dplyr::all_of(c(by, "ID"))),
                               name = "n_dates")
  stats <- per_pt |>
    dplyr::group_by(dplyr::across(dplyr::all_of(by))) |>
    dplyr::summarise(
      n_patients        = dplyr::n(),
      dates_per_pt_median = stats::median(n_dates),
      dates_per_pt_q1   = unname(stats::quantile(n_dates, 0.25)),
      dates_per_pt_q3   = unname(stats::quantile(n_dates, 0.75)),
      dates_per_pt_max  = max(n_dates),
      total_event_dates = sum(n_dates),
      .groups = "drop")
  keys |>
    dplyr::left_join(stats, by = by) |>
    dplyr::mutate(
      n_patients        = dplyr::coalesce(n_patients, 0L),
      total_event_dates = dplyr::coalesce(total_event_dates, 0L),
      pct_of_denominator = 100 * n_patients / denom_n,
      person_years_denominator = total_py,
      events_per_person_year = if (total_py > 0) total_event_dates / total_py
                               else NA_real_)
}

#' SURV-06: one row per ID x modality.
build_patient_modality <- function(events, followup) {
  ev <- events |> dplyr::filter(type_ok)
  summ <- function(d, suffix) {
    d |>
      dplyr::distinct(ID, modality, window, event_date) |>
      dplyr::group_by(ID, modality) |>
      dplyr::summarise(
        n_dates_pre   = sum(window == "pre"),
        n_dates_post  = sum(window == "post"),
        n_dates_after_followup = sum(window == "after_followup"),
        first_post_date = if (any(window == "post")) min(event_date[window == "post"]) else as.Date(NA),
        last_post_date  = if (any(window == "post")) max(event_date[window == "post"]) else as.Date(NA),
        .groups = "drop") |>
      dplyr::rename_with(~ paste0(.x, suffix), -c(ID, modality))
  }
  summ(ev, "_any") |>
    dplyr::left_join(summ(dplyr::filter(ev, tier == "primary"), "_primary"),
                     by = c("ID", "modality")) |>
    dplyr::mutate(dplyr::across(dplyr::starts_with("n_dates") & dplyr::ends_with("_primary"),
                                ~ dplyr::coalesce(.x, 0L))) |>
    dplyr::left_join(followup |> dplyr::select(ID, hl_anchor_date, follow_end,
                                               person_years, in_confirmed_cohort),
                     by = "ID")
}

# ------------------------------------------------------------------------------
# Small-cell suppression (D-19, D-27)
# ------------------------------------------------------------------------------

#' 1..threshold -> "<11"; 0 and larger counts unchanged (as character)
suppress_small <- function(x, threshold = 10L) {
  ifelse(!is.na(x) & x > 0 & x <= threshold, "<11", as.character(x))
}

#' Suppress count columns and blank the columns derived from them.
#' rules: named list, count column -> character vector of dependent columns.
suppress_table <- function(df, rules, threshold = 10L) {
  for (cnt in names(rules)) {
    x <- df[[cnt]]
    hit <- !is.na(x) & x > 0 & x <= threshold
    for (dep in rules[[cnt]]) {
      df[[dep]] <- as.character(df[[dep]])
      df[[dep]][hit] <- ""
    }
    df[[cnt]] <- suppress_small(x, threshold)
  }
  df
}
