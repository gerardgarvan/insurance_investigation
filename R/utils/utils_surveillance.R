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
    stop("Duplicate (non-unique) modality x code_norm: ",
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
#' Returns a named character vector (names = modality, values = prefix).
#' Phase 160: the optional eligible_sex column ("" / "F" / "M") is validated and
#' attached as attribute "eligible_sex"; read it with modality_eligible_sex().
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
  # Phase 160 IMP-04: optional eligible_sex column; absent = no extra views
  if (!"eligible_sex" %in% names(md)) md$eligible_sex <- ""
  md$eligible_sex <- toupper(md$eligible_sex)
  bad_sex <- !md$eligible_sex %in% c("", "F", "M")
  if (any(bad_sex))
    stop("Modalities: eligible_sex must be blank, F, or M: ",
         paste(md$modality[bad_sex], collapse = ", "))

  md <- md[order(ord), ]
  lookup <- stats::setNames(md$column_prefix, md$modality)
  attr(lookup, "eligible_sex") <- stats::setNames(md$eligible_sex, md$modality)
  lookup
}

#' Per-modality eligible_sex ("" / "F" / "M") for a load_modality_lookup()
#' result; all "" when the attribute is absent.
modality_eligible_sex <- function(lookup) {
  es <- attr(lookup, "eligible_sex")
  if (is.null(es)) stats::setNames(rep("", length(lookup)), names(lookup)) else es
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

# ------------------------------------------------------------------------------
# Phase 159: analyte rules and per-patient date counts
# ------------------------------------------------------------------------------

#' Map collected CDM rows to Lab_Analytes rows.
#' raw: ID, code_raw, type_val ("" for labs), event_date (Date), cdm_table.
#' Returns ID, analyte_row_id, analyte, event_date, type_ok, type_val.
#' A code listed under several analytes maps to each of them.
map_analyte_hits <- function(raw, analytes) {
  empty <- tibble::tibble(ID = character(), analyte_row_id = character(),
                          analyte = character(), event_date = as.Date(character()),
                          type_ok = logical(), type_val = character())
  if (nrow(raw) == 0) return(empty)
  raw |>
    dplyr::mutate(code_norm = normalize_surv_code(code_raw),
                  type_val  = trimws(dplyr::coalesce(as.character(type_val), ""))) |>
    dplyr::inner_join(analytes |> dplyr::select(analyte_row_id, analyte, cdm_table,
                                                code_norm, type_filter),
                      by = c("cdm_table", "code_norm"),
                      relationship = "many-to-many") |>
    dplyr::mutate(type_ok = type_filter == "" | type_val == type_filter) |>
    dplyr::select(dplyr::all_of(names(empty)))
}

#' Build events for analyte_all_same_day / analyte_min_same_day rule rows
#' (Phase 159 D-08..D-10). hits: output of map_analyte_hits().
#' An ID x date qualifies when the number of DISTINCT listed analytes resulted
#' that day (type_ok rows only, from either table) reaches the threshold:
#' all listed analytes, or min_analyte_count.
#' Returns list(events = same schema as build_component_events()$events,
#'              near_miss = one row per rule row x analytes-present count).
build_analyte_events <- function(hits, codeset) {
  empty_ev <- tibble::tibble(
    codeset_row_id = character(), ID = character(), code_data = character(),
    type_val = character(), event_date = as.Date(character()),
    source_table = character(), modality = character(),
    submodality = character(), tier = character(), type_ok = logical())
  empty_nm <- tibble::tibble(
    codeset_row_id = character(), modality = character(), match = character(),
    n_listed = integer(), threshold = integer(), n_analytes_present = integer(),
    n_id_dates = integer(), qualifies = logical())
  rules <- codeset |> dplyr::filter(match %in% SURV_ANALYTE_MATCHES)
  if (nrow(rules) == 0)
    return(list(events = empty_ev, near_miss = empty_nm))

  day_analytes <- hits |>
    dplyr::filter(type_ok, !is.na(event_date)) |>
    dplyr::distinct(ID, event_date, analyte)

  res <- lapply(seq_len(nrow(rules)), function(i) {
    r <- rules[i, ]
    listed <- surv_components(r$code_norm)
    thr <- if (r$match == "analyte_all_same_day") length(listed)
           else as.integer(r$min_analyte_count)
    by_day <- day_analytes |>
      dplyr::filter(analyte %in% listed) |>
      dplyr::count(ID, event_date, name = "n_present")
    ev <- by_day |>
      dplyr::filter(n_present >= thr) |>
      dplyr::transmute(codeset_row_id = r$codeset_row_id, ID,
                       code_data = r$code_norm, type_val = "", event_date,
                       source_table = "ANALYTE_RULE", modality = r$modality,
                       submodality = r$submodality, tier = r$tier, type_ok = TRUE)
    nm <- by_day |>
      dplyr::count(n_present, name = "n_id_dates") |>
      dplyr::transmute(codeset_row_id = r$codeset_row_id, modality = r$modality,
                       match = r$match, n_listed = length(listed),
                       threshold = as.integer(thr),
                       n_analytes_present = as.integer(n_present),
                       n_id_dates = as.integer(n_id_dates),
                       qualifies = n_present >= thr)
    list(ev = ev, nm = nm)
  })
  list(events    = dplyr::bind_rows(empty_ev, lapply(res, `[[`, "ev")),
       near_miss = dplyr::bind_rows(empty_nm, lapply(res, `[[`, "nm")))
}

#' A2_analyte_presence (LAB-04): one row per Lab_Analytes row, from its own
#' hits (all dates, before any de-duplication across codes).
build_analyte_presence <- function(analytes, hits) {
  ok <- hits |>
    dplyr::filter(type_ok) |>
    dplyr::group_by(analyte_row_id) |>
    dplyr::summarise(
      n_results       = dplyr::n(),
      n_patients      = dplyr::n_distinct(ID),
      n_patient_dates = dplyr::n_distinct(ID, event_date),
      first_date      = min(event_date, na.rm = TRUE),
      last_date       = max(event_date, na.rm = TRUE),
      .groups = "drop")
  mism <- hits |>
    dplyr::filter(!type_ok) |>
    dplyr::count(analyte_row_id, name = "n_results_other_type")
  out <- analytes |>
    dplyr::left_join(ok,   by = "analyte_row_id") |>
    dplyr::left_join(mism, by = "analyte_row_id") |>
    dplyr::mutate(
      dplyr::across(c(n_results, n_patients, n_patient_dates, n_results_other_type),
                    ~ dplyr::coalesce(as.integer(.x), 0L)),
      present = n_results > 0)
  stopifnot("A2 must have one row per Lab_Analytes row" =
              nrow(out) == nrow(analytes))
  out
}

#' LAB-06 per-patient table: one row per follow-up (denominator) ID; for each
#' modality in lookup order, distinct post-anchor dates within follow-up for
#' the primary tier (n_dates_<prefix>) and for primary or sensitivity
#' (n_dates_<prefix>_any). Missing combinations are 0L, never NA.
build_patient_modality_dates <- function(events_win, followup, lookup) {
  unknown <- setdiff(unique(events_win$modality), names(lookup))
  if (length(unknown) > 0)
    stop("Modalities without a column prefix: ", paste(unknown, collapse = ", "))

  post <- events_win |>
    dplyr::filter(type_ok, window == "post") |>
    dplyr::select(ID, modality, tier, event_date)
  cnt <- dplyr::bind_rows(
    post |> dplyr::filter(tier == "primary") |>
      dplyr::distinct(ID, modality, event_date) |>
      dplyr::count(ID, modality, name = "n") |>
      dplyr::mutate(col = paste0("n_dates_", lookup[modality])),
    post |>
      dplyr::distinct(ID, modality, event_date) |>
      dplyr::count(ID, modality, name = "n") |>
      dplyr::mutate(col = paste0("n_dates_", lookup[modality], "_any")))

  cols <- as.vector(rbind(paste0("n_dates_", lookup),
                          paste0("n_dates_", lookup, "_any")))
  wide <- followup |>
    dplyr::select(ID, hl_anchor_date, follow_end, person_years, in_confirmed_cohort)
  for (cl in cols) {
    v <- cnt[cnt$col == cl, c("ID", "n")]
    wide[[cl]] <- dplyr::coalesce(as.integer(v$n[match(wide$ID, v$ID)]), 0L)
  }
  stopifnot("One row per denominator ID" = !anyDuplicated(wide$ID),
            "No NA counts" = !anyNA(wide[cols]))
  wide
}

# ------------------------------------------------------------------------------
# Phase 160: missing-analyte diagnostic, eligible denominators, codeset summary
# ------------------------------------------------------------------------------

#' A3 block 1 (IMP-02, 160 D-02): for every analyte_all_same_day rule row with
#' >= 2 listed analytes, the ID x dates with exactly n_listed - 1 listed
#' analytes present, attributed to the one missing analyte. Also returns the
#' complete days (all listed analytes present), which 160 D-08 uses as the
#' comparison group for block 2. Same inputs and filters as
#' build_analyte_events(), so totals reconcile with its near-miss table.
#' @return list(days, overall, by_year)
#'   days:    codeset_row_id, modality, ID, event_date, day_type
#'            ("near_miss" / "complete"), missing_analyte (NA on complete days)
#'   overall: codeset_row_id, modality, n_listed, missing_analyte, n_id_dates
#'   by_year: as overall plus calendar_year
summarise_missing_analyte <- function(hits, codeset) {
  empty_days <- tibble::tibble(codeset_row_id = character(), modality = character(),
                               ID = character(), event_date = as.Date(character()),
                               day_type = character(), missing_analyte = character())
  rules <- codeset |> dplyr::filter(match == "analyte_all_same_day")
  rules <- rules[vapply(rules$code_norm, function(z) length(surv_components(z)),
                        integer(1)) >= 2, , drop = FALSE]

  day_an <- hits |>
    dplyr::filter(type_ok, !is.na(event_date)) |>
    dplyr::distinct(ID, event_date, analyte)

  days <- dplyr::bind_rows(empty_days, lapply(seq_len(nrow(rules)), function(i) {
    r <- rules[i, ]
    listed <- surv_components(r$code_norm)
    n_l <- length(listed)
    present <- dplyr::filter(day_an, analyte %in% listed)
    by_day <- dplyr::count(present, ID, event_date, name = "n_present")
    near <- dplyr::filter(by_day, n_present == n_l - 1L)
    missing <- near |>
      dplyr::select(ID, event_date) |>
      tidyr::crossing(analyte = listed) |>
      dplyr::anti_join(present, by = c("ID", "event_date", "analyte")) |>
      dplyr::transmute(ID, event_date, missing_analyte = analyte)
    dplyr::bind_rows(
      missing |> dplyr::mutate(day_type = "near_miss"),
      by_day |> dplyr::filter(n_present == n_l) |>
        dplyr::transmute(ID, event_date, day_type = "complete",
                         missing_analyte = NA_character_)) |>
      dplyr::mutate(codeset_row_id = r$codeset_row_id, modality = r$modality,
                    n_listed = n_l)
  }))
  if (!"n_listed" %in% names(days)) days$n_listed <- integer()

  near <- dplyr::filter(days, day_type == "near_miss")
  overall <- near |>
    dplyr::count(codeset_row_id, modality, n_listed, missing_analyte, name = "n_id_dates") |>
    dplyr::arrange(codeset_row_id, dplyr::desc(n_id_dates))
  by_year <- near |>
    dplyr::mutate(calendar_year = as.integer(format(event_date, "%Y"))) |>
    dplyr::count(codeset_row_id, modality, n_listed, missing_analyte, calendar_year,
                 name = "n_id_dates") |>
    dplyr::arrange(codeset_row_id, missing_analyte, calendar_year)
  list(days = dplyr::select(days, -n_listed), overall = overall, by_year = by_year)
}

#' Deterministic sample of A3 days for the candidate-code query (160 D-03, D-08,
#' D-09). Near-miss days are sampled within each rule x missing analyte, and
#' complete (comparison) days within each rule; one day per patient per group;
#' at most n_max days per group. Rows are sorted before sampling so the result
#' does not depend on the order DuckDB returned them in.
select_a3_sample <- function(days, n_max = 5000L, seed = 2026L) {
  if (nrow(days) == 0) return(dplyr::mutate(days, sample_group = character()))
  d <- days |>
    dplyr::mutate(sample_group = paste(codeset_row_id, day_type,
                                       dplyr::coalesce(missing_analyte, ""), sep = "|")) |>
    dplyr::arrange(sample_group, ID, event_date)
  set.seed(seed)
  d$.u <- stats::runif(nrow(d))
  d |>
    dplyr::group_by(sample_group, ID) |>
    dplyr::slice_min(.u, n = 1, with_ties = FALSE) |>
    dplyr::group_by(sample_group) |>
    dplyr::slice_min(.u, n = n_max, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select(-.u) |>
    dplyr::arrange(sample_group, ID, event_date)
}

#' SQL expression giving the first non-missing of several raw date columns as
#' a DATE, for joining sampled ID x dates inside the database (160 D-09).
#' DuckDB: tries ISO text, then MM/DD/YYYY text; SQLite (local fixtures): DATE().
#' Rows it cannot convert simply do not join; R re-parses and filters exactly.
surv_sql_date_expr <- function(cols, dialect = c("duckdb", "sqlite")) {
  dialect <- match.arg(dialect)
  one <- function(col) switch(dialect,
    duckdb = sprintf(paste0("COALESCE(TRY_CAST(LEFT(CAST(%1$s AS VARCHAR), 10) AS DATE), ",
                            "CAST(TRY_STRPTIME(CAST(%1$s AS VARCHAR), '%%m/%%d/%%Y') AS DATE))"), col),
    sqlite = sprintf("DATE(%s)", col))
  if (length(cols) == 1) return(one(cols))
  paste0("COALESCE(", paste(vapply(cols, one, character(1)), collapse = ", "), ")")
}

#' A3 block 2 (IMP-02, 160 D-08): rank lab codes that are not in Lab_Analytes by
#' how much more often they appear on near-miss days than on complete days of
#' the same rule. A replacement code for the missing analyte scores near 1
#' (present on near-miss days, absent on complete days); routine labs such as
#' hemoglobin appear on both and score near 0.
#' @param candidates LAB_RESULT_CM rows on sampled days: ID, event_date and any
#'   of LAB_LOINC, LAB_PX, LAB_PX_TYPE, RAW_LAB_CODE, RAW_LAB_NAME, RESULT_UNIT
#' @param sample select_a3_sample() output
#' @param analytes Lab_Analytes; excluded: Lab_Analytes_Excluded (code, reason)
#' @param master_codes normalized crosswalk MASTER codes (character)
#' @param top_n rows kept per rule x missing analyte
rank_candidate_codes <- function(candidates, sample, analytes, excluded,
                                 master_codes = character(), top_n = 25L) {
  out_cols <- c("codeset_row_id", "modality", "missing_analyte", "rank", "code_source",
                "code_norm", "top_raw_code", "top_raw_name", "top_unit",
                "n_near_days", "n_near_sampled", "coverage_near",
                "n_control_days", "n_control_sampled", "coverage_control", "lift",
                "in_excluded", "excluded_reason", "in_master")
  empty <- tibble::as_tibble(stats::setNames(
    lapply(out_cols, function(x) if (x %in% c("rank", "n_near_days", "n_near_sampled",
                                              "n_control_days", "n_control_sampled")) integer()
                                 else if (x %in% c("coverage_near", "coverage_control", "lift")) numeric()
                                 else if (x %in% c("in_excluded", "in_master")) logical()
                                 else character()), out_cols))
  if (nrow(candidates) == 0 || nrow(sample) == 0) return(empty)

  col <- function(nm) if (nm %in% names(candidates)) trimws(dplyr::coalesce(as.character(candidates[[nm]]), "")) else rep("", nrow(candidates))
  loinc <- col("LAB_LOINC"); lpx <- col("LAB_PX"); lpxt <- toupper(col("LAB_PX_TYPE"))
  raw_code <- col("RAW_LAB_CODE")
  cand <- tibble::tibble(
    ID = candidates$ID, event_date = candidates$event_date,
    code_source = dplyr::case_when(nzchar(loinc) ~ "LOINC",
                                   lpxt == "LC" & nzchar(lpx) ~ "LAB_PX",
                                   nzchar(raw_code) ~ "RAW", TRUE ~ NA_character_),
    code_norm = normalize_surv_code(dplyr::case_when(nzchar(loinc) ~ loinc,
                                                     lpxt == "LC" & nzchar(lpx) ~ lpx,
                                                     TRUE ~ raw_code)),
    raw_code = raw_code, raw_name = col("RAW_LAB_NAME"), unit = col("RESULT_UNIT")) |>
    dplyr::filter(!is.na(code_source)) |>
    dplyr::filter(!(code_source != "RAW" & code_norm %in% analytes$code_norm))

  # Most common raw code / name / unit per code (display only)
  top_of <- function(x) { x <- x[nzchar(x)]; if (!length(x)) "" else names(sort(table(x), decreasing = TRUE))[1] }
  labels <- cand |>
    dplyr::group_by(code_source, code_norm) |>
    dplyr::summarise(top_raw_code = top_of(raw_code), top_raw_name = top_of(raw_name),
                     top_unit = top_of(unit), .groups = "drop")
  cand_days <- dplyr::distinct(cand, ID, event_date, code_source, code_norm)

  ctrl <- sample |> dplyr::filter(day_type == "complete") |>
    dplyr::distinct(codeset_row_id, ID, event_date)
  near <- sample |> dplyr::filter(day_type == "near_miss") |>
    dplyr::distinct(codeset_row_id, modality, missing_analyte, ID, event_date)
  if (nrow(near) == 0) return(empty)

  near_n <- dplyr::count(near, codeset_row_id, modality, missing_analyte, name = "n_near_sampled")
  ctrl_n <- dplyr::count(ctrl, codeset_row_id, name = "n_control_sampled")
  near_hits <- near |>
    dplyr::inner_join(cand_days, by = c("ID", "event_date"), relationship = "many-to-many") |>
    dplyr::count(codeset_row_id, modality, missing_analyte, code_source, code_norm,
                 name = "n_near_days")
  ctrl_hits <- ctrl |>
    dplyr::inner_join(cand_days, by = c("ID", "event_date"), relationship = "many-to-many") |>
    dplyr::count(codeset_row_id, code_source, code_norm, name = "n_control_days")

  excl <- tibble::tibble(code_norm = normalize_surv_code(excluded$code),
                         excluded_reason = as.character(excluded$reason)) |>
    dplyr::distinct(code_norm, .keep_all = TRUE)

  res <- near_hits |>
    dplyr::left_join(near_n, by = c("codeset_row_id", "modality", "missing_analyte")) |>
    dplyr::left_join(ctrl_hits, by = c("codeset_row_id", "code_source", "code_norm")) |>
    dplyr::left_join(ctrl_n, by = "codeset_row_id") |>
    dplyr::mutate(n_control_days = dplyr::coalesce(n_control_days, 0L),
                  n_control_sampled = dplyr::coalesce(n_control_sampled, 0L),
                  coverage_near = n_near_days / n_near_sampled,
                  coverage_control = dplyr::if_else(n_control_sampled > 0,
                                                    n_control_days / n_control_sampled, NA_real_),
                  lift = coverage_near - dplyr::coalesce(coverage_control, 0)) |>
    dplyr::left_join(labels, by = c("code_source", "code_norm")) |>
    dplyr::left_join(excl, by = "code_norm") |>
    dplyr::mutate(in_excluded = !is.na(excluded_reason),
                  excluded_reason = dplyr::coalesce(excluded_reason, ""),
                  in_master = code_norm %in% master_codes) |>
    dplyr::group_by(codeset_row_id, missing_analyte) |>
    dplyr::arrange(dplyr::desc(lift), dplyr::desc(n_near_days), code_norm, .by_group = TRUE) |>
    dplyr::mutate(rank = dplyr::row_number()) |>
    dplyr::filter(rank <= top_n) |>
    dplyr::ungroup()
  dplyr::bind_rows(empty, res)[, out_cols]
}

#' B/C statistics with an optional sex-specific view (IMP-04, 160 D-04/D-10).
#' All-patient columns come from compute_modality_stats() unchanged (L-5).
#' When eligible_sex is "F" or "M", adds the eligible-sex columns and the
#' other/unknown-sex counts. Patients missing from sex_lookup, or with a blank
#' or non-F/M sex, count as "UN" (other/unknown).
compute_eligible_modality_stats <- function(events, followup, keys, tiers,
                                            sex_lookup, eligible_sex = "",
                                            by = "modality") {
  base <- compute_modality_stats(events, followup, keys, tiers, by)
  if (is.null(eligible_sex) || eligible_sex == "") return(base)

  sx <- followup |>
    dplyr::select(ID) |>
    dplyr::left_join(dplyr::distinct(sex_lookup, ID, .keep_all = TRUE), by = "ID") |>
    dplyr::mutate(sex = toupper(trimws(dplyr::coalesce(as.character(sex), ""))),
                  sex = dplyr::if_else(sex %in% c("F", "M"), sex, "UN"))
  e_ids <- sx$ID[sx$sex == eligible_sex]
  fu_e <- dplyr::filter(followup, ID %in% e_ids)
  fu_o <- dplyr::filter(followup, !ID %in% e_ids)
  st <- function(fu) {
    if (nrow(fu) == 0)   # no patients of that sex: zero counts, undefined rates
      return(dplyr::mutate(base, n_patients = 0L, total_event_dates = 0L,
                           pct_of_denominator = NA_real_, person_years_denominator = 0,
                           events_per_person_year = NA_real_))
    compute_modality_stats(dplyr::filter(events, ID %in% fu$ID), fu, keys, tiers, by)
  }
  e <- st(fu_e); o <- st(fu_o)
  base |>
    dplyr::left_join(e |> dplyr::transmute(dplyr::across(dplyr::all_of(by)),
                       denominator_eligible = nrow(fu_e),
                       n_patients_eligible = n_patients,
                       pct_of_eligible = pct_of_denominator,
                       total_event_dates_eligible = total_event_dates,
                       person_years_eligible = person_years_denominator,
                       events_per_person_year_eligible = events_per_person_year),
                     by = by) |>
    dplyr::left_join(o |> dplyr::transmute(dplyr::across(dplyr::all_of(by)),
                       n_patients_other_sex = n_patients,
                       total_event_dates_other_sex = total_event_dates),
                     by = by) |>
    dplyr::mutate(eligible_sex = eligible_sex)
}

#' Release suppression for the eligible-sex columns, including complementary
#' suppression (160 D-11): because the all-patient count is published,
#' eligible = all - other, so if either side of a pair is 1..threshold both
#' sides and their derived columns are withheld. Counts 1..threshold show
#' "<11"; other withheld cells are blank. prefix handles C-sheet column names.
suppress_eligible_columns <- function(df, prefix = "", threshold = 10L) {
  p <- function(x) paste0(prefix, x)
  pairs <- list(
    list(a = p("n_patients_eligible"), b = p("n_patients_other_sex"),
         deps = p("pct_of_eligible")),
    list(a = p("total_event_dates_eligible"), b = p("total_event_dates_other_sex"),
         deps = p("events_per_person_year_eligible")))
  for (pr in pairs) {
    if (!all(c(pr$a, pr$b) %in% names(df))) next
    a <- df[[pr$a]]; b <- df[[pr$b]]
    small <- function(x) !is.na(x) & x > 0 & x <= threshold
    hide <- small(a) | small(b)
    for (cl in c(pr$a, pr$b, intersect(pr$deps, names(df)))) {
      v <- as.character(df[[cl]])
      v[hide] <- ""
      df[[cl]] <- v
    }
    df[[pr$a]][small(a)] <- "<11"
    df[[pr$b]][small(b)] <- "<11"
  }
  df
}

#' Codeset_summary sheet (IMP-05): generated from the loaded codeset each run.
#' @return list(by_modality, by_analyte)
build_codeset_summary <- function(codeset, analytes, analyte_presence = NULL) {
  by_modality <- codeset |>
    dplyr::group_by(modality, tier, match) |>
    dplyr::summarise(
      n_codes = dplyr::n_distinct(code_norm),
      codes = paste(sort(unique(code)), collapse = "; "),
      threshold = dplyr::case_when(
        dplyr::first(match) == "analyte_min_same_day" ~
          paste0(">= ", paste(unique(min_analyte_count), collapse = "/"), " listed analytes"),
        dplyr::first(match) %in% c("analyte_all_same_day", "component_all_same_day") ~ "all listed",
        TRUE ~ ""),
      .groups = "drop") |>
    dplyr::arrange(modality, dplyr::desc(tier == "primary"), match)
  by_analyte <- analytes |>
    dplyr::group_by(analyte) |>
    dplyr::summarise(n_codes = dplyr::n_distinct(code_norm),
                     codes = paste(sort(unique(code)), collapse = "; "),
                     .groups = "drop")
  if (!is.null(analyte_presence)) {
    pres <- analyte_presence |>
      dplyr::group_by(analyte) |>
      dplyr::summarise(n_codes_present = sum(present), .groups = "drop")
    by_analyte <- dplyr::left_join(by_analyte, pres, by = "analyte") |>
      dplyr::relocate(n_codes_present, .after = n_codes)
  }
  list(by_modality = by_modality, by_analyte = by_analyte)
}
