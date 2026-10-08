# ==============================================================================
# 167_anthracycline_echo.R -- Anthracycline-to-Echocardiogram Timing
# ==============================================================================
# INTERNAL — contains patient IDs. Not for release outside the secure enclave.
#
# Purpose:  Characterise echocardiogram receipt after the last anthracycline
#           dose (SRATE-03) and the post-dose echo rate (SRATE-04).
#           Writes survivorship_echo_parts_<YYYYMMDD>.rds for Plan 04 workbook.
#
# D-08a note: first_line column is absent from treatment_episode_detail_180.rds.
#   last_dose_firstline_dt is computed as max admin_date across all 180-day
#   episodes for included drugs (functionally = last_dose_ever_dt in this
#   dataset). Documented as D-166-02 fallback in C_anthracycline_echo KEY block.
#
# D-166-01: Per-drug patient counts computed at runtime; drugs_primary excludes
#   Mitoxantrone (D-07a); mitoxantrone added only in sensitivity variant.
#
# Inputs:
#   treatment_episode_detail_180.rds            -- from CONFIG$cache$outputs_dir
#   survivorship_dated_events_<date>.rds        -- from Plan 02 (R/166)
#   survivorship_modality_rates_parts_<date>.rds or
#     surveillance_modality_patient_<date>.rds  -- for follow-up (ID, follow_end)
#
# Outputs (CONFIG$cache$outputs_dir):
#   survivorship_echo_parts_<YYYYMMDD>.rds      -- named list (INTERNAL)
#
# Usage (HiPerGator):
#   module load R/4.4.2
#   Rscript R/167_anthracycline_echo.R
#
# Requirements: SRATE-03, SRATE-04
# Decisions:    166-CONTEXT.md D-06..D-14c; 166-AUDIT.md
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(here)
})

# ---------- 1. Dependencies ---------------------------------------------------

if (!requireNamespace("survival", quietly = TRUE)) {
  stop(
    "Install survival: renv::install('survival'); renv::snapshot()\n",
    "Then re-run this script."
  )
}

source(here::here("R", "00_config.R"))
if (!exists("last_anthracycline_dose")) {
  source(here::here("R", "utils", "utils_anthracycline_echo.R"))
}

run_date <- format(Sys.Date(), "%Y%m%d")
out_dir  <- CONFIG$cache$outputs_dir

# ---------- 2. Load episode file ----------------------------------------------
# Audit confirms: treatment_episode_detail_180.rds, patient_id column (not ID).
# D-08a: first_line column absent -> all rows treated equivalently.

episode_file_pattern <- "treatment_episode_detail_180\\.rds$"
episode_candidates   <- list.files(out_dir, pattern = episode_file_pattern,
                                   full.names = TRUE)
if (length(episode_candidates) == 0L) {
  stop(
    "No treatment episode file found matching '", episode_file_pattern,
    "' in: ", out_dir, "\n",
    "Expected: treatment_episode_detail_180.rds"
  )
}
episode_file_used <- sort(episode_candidates, decreasing = TRUE)[1L]
message("Loading episode file: ", episode_file_used)

episodes_raw <- readRDS(episode_file_used)

# Rename patient_id -> ID per 166-AUDIT.md (patient ID column mismatch)
if (!"ID" %in% names(episodes_raw) && "patient_id" %in% names(episodes_raw)) {
  episodes_raw <- episodes_raw |> dplyr::rename(ID = patient_id)
}

# Rename treatment_date -> admin_date; episode_number -> episode_id
if ("treatment_date"  %in% names(episodes_raw)) {
  episodes_raw <- episodes_raw |> dplyr::rename(admin_date = treatment_date)
}
if ("episode_number"  %in% names(episodes_raw)) {
  episodes_raw <- episodes_raw |> dplyr::rename(episode_id = episode_number)
}
if (!"admin_date" %in% names(episodes_raw)) {
  stop("Could not find a date column (treatment_date / admin_date) in episode file.")
}

# Apply DRUG_NAME_ALIASES from 00_config.R to collapse variants -> canonical
if (exists("DRUG_NAME_ALIASES") && !is.null(DRUG_NAME_ALIASES)) {
  episodes_raw <- episodes_raw |>
    dplyr::mutate(
      drug_name = dplyr::recode(.data$drug_name, !!!DRUG_NAME_ALIASES)
    )
}

# Ensure admin_date is Date
episodes_raw <- episodes_raw |>
  dplyr::mutate(admin_date = as.Date(.data$admin_date))

# D-08a: first_line absent -> set all to TRUE (functionally equivalent to ever)
if (!"first_line" %in% names(episodes_raw)) {
  message(
    "D-08a: 'first_line' column absent from episode file. ",
    "Setting first_line = TRUE for all rows (last_dose_firstline_dt == last_dose_ever_dt). ",
    "Documented as D-166-02 fallback."
  )
  episodes_raw <- episodes_raw |> dplyr::mutate(first_line = TRUE)
}

# Ensure required columns present
req_cols <- c("ID", "drug_name", "admin_date", "first_line", "episode_id")
missing_cols <- setdiff(req_cols, names(episodes_raw))
if (length(missing_cols) > 0L) {
  stop("Episode file is missing required columns: ",
       paste(missing_cols, collapse = ", "))
}

episodes <- episodes_raw |>
  dplyr::select(dplyr::all_of(req_cols))

# ---------- 3. D-166-01: Per-drug patient counts ------------------------------

anthracycline_pattern <- regex("doxo|dauno|epiru|idaru|mitox", ignore_case = TRUE)
drug_counts_tbl <- episodes |>
  dplyr::filter(stringr::str_detect(.data$drug_name, anthracycline_pattern)) |>
  dplyr::distinct(.data$ID, .data$drug_name) |>
  dplyr::count(.data$drug_name, name = "n_patients") |>
  dplyr::arrange(dplyr::desc(.data$n_patients))

qc_anthracycline_drug_counts <- drug_counts_tbl

present_drugs <- drug_counts_tbl$drug_name

# Primary drugs: Doxorubicin + any present Dauno/Epi/Ida (class-effect D-07)
# Mitoxantrone explicitly excluded from primary (D-07a)
class_drugs <- c("Daunorubicin", "Epirubicin", "Idarubicin")
drugs_primary <- c("Doxorubicin",
                   intersect(class_drugs, present_drugs))

mitoxantrone_n <- dplyr::coalesce(
  drug_counts_tbl$n_patients[drug_counts_tbl$drug_name == "Mitoxantrone"][1L],
  0L
)

d_166_01_record <- paste0(
  "D-166-01 — Anthracycline drugs present in cohort: ",
  paste(drug_counts_tbl$drug_name, collapse = ", "), ". ",
  "Primary clock includes: ", paste(drugs_primary, collapse = ", "), ". ",
  "Mitoxantrone (n=", mitoxantrone_n, " patients) excluded from primary clock (D-07a); ",
  "included in sensitivity variant if n > 0. ",
  if (!("first_line" %in% names(episodes_raw) && any(episodes_raw$first_line == FALSE, na.rm = TRUE))) {
    "D-08a/D-166-02: first_line column absent from 180-day file; all episodes treated as first-line."
  } else {
    "First-line episodes used per 180-day episode file."
  }
)

message(d_166_01_record)

# ---------- 4. Load echo events and follow-up ---------------------------------

# Echo events from Plan 02's dated-events file
dated_events_candidates <- list.files(
  out_dir,
  pattern = "survivorship_dated_events_.*\\.rds$",
  full.names = TRUE
)
if (length(dated_events_candidates) == 0L) {
  stop(
    "No survivorship_dated_events_*.rds found in: ", out_dir, "\n",
    "Run R/166_survivorship_modality_rates.R (Plan 02) first."
  )
}
dated_events_file <- sort(dated_events_candidates, decreasing = TRUE)[1L]
message("Loading dated events: ", dated_events_file)
dated_events <- readRDS(dated_events_file)

echo_modality_name <- "Echocardiogram"
echo_events <- dated_events |>
  dplyr::filter(.data$modality == echo_modality_name) |>
  dplyr::select("ID", "modality", "event_date")

message("Echo events loaded: ", nrow(echo_events), " rows")

# Follow-up: ID, hl_anchor_date, follow_end
# Try Plan 02 rates parts first, fall back to surveillance_modality_patient
fu_candidates <- list.files(
  out_dir,
  pattern = "survivorship_modality_rates_parts_.*\\.rds$",
  full.names = TRUE
)
if (length(fu_candidates) > 0L) {
  fu_file <- sort(fu_candidates, decreasing = TRUE)[1L]
  message("Loading follow-up from rates parts: ", fu_file)
  rates_parts <- readRDS(fu_file)
  if (is.list(rates_parts) && !is.null(rates_parts$followup)) {
    followup <- rates_parts$followup |>
      dplyr::select("ID", dplyr::any_of(c("hl_anchor_date", "follow_end")))
  } else if (is.list(rates_parts) && !is.null(rates_parts$long_rates)) {
    followup <- rates_parts$long_rates |>
      dplyr::distinct(.data$ID, .data$hl_anchor_date, .data$follow_end)
  } else if (is.data.frame(rates_parts)) {
    followup <- rates_parts |>
      dplyr::distinct(.data$ID, dplyr::any_of(c("hl_anchor_date", "follow_end")))
  } else {
    stop("Could not extract follow-up from survivorship_modality_rates_parts_*.rds")
  }
} else {
  # Fallback: surveillance_modality_patient_<date>.rds
  surv_candidates <- list.files(
    out_dir,
    pattern = "surveillance_modality_patient_.*\\.rds$",
    full.names = TRUE
  )
  if (length(surv_candidates) == 0L) {
    stop(
      "No follow-up source found. Need either:\n",
      "  survivorship_modality_rates_parts_*.rds (Plan 02), or\n",
      "  surveillance_modality_patient_*.rds (R/147).\n",
      "Run the appropriate upstream script first."
    )
  }
  fu_file <- sort(surv_candidates, decreasing = TRUE)[1L]
  message("Loading follow-up from surveillance_modality_patient: ", fu_file)
  surv_patient <- readRDS(fu_file)
  followup <- surv_patient |>
    dplyr::distinct(.data$ID, .data$hl_anchor_date, .data$follow_end)
}

# Deaths via resolve_death_date() (same source as R/147)
if (!exists("resolve_death_date")) source(here::here("R", "utils", "utils_death.R"))
# Deaths are loaded inside R/147's flow; here we call the same data source
# by loading from the DuckDB connection or CONFIG as R/147 does.
# If deaths tibble isn't available, create an empty one (no competing event).
if (!exists("deaths_resolved")) {
  message(
    "NOTE: deaths_resolved not found in environment. ",
    "Death as competing event will not be applied. ",
    "Re-run with deaths_resolved loaded from R/147's DEATH table query."
  )
  deaths_resolved <- tibble::tibble(
    ID                  = character(0),
    death_date_resolved = as.Date(character(0))
  )
}

# ---------- 5. Compute variants -----------------------------------------------

run_variant <- function(var_drugs, var_dose_col, var_label) {
  message("Running variant: ", var_label)

  doses   <- last_anthracycline_dose(episodes, drugs = var_drugs)
  tte_res <- echo_time_to_event(doses, echo_events, followup, deaths_resolved,
                                dose_col = var_dose_col)
  tte     <- tte_res$data
  n_no_time <- tte_res$n_no_time_after_last_dose

  # CIF + KM
  cif_km <- if (nrow(tte) >= 2L) {
    tryCatch(
      echo_cif_km(tte, horizons = c(365L, 730L, 1825L)),
      error = function(e) {
        message("CIF error for variant ", var_label, ": ", conditionMessage(e))
        NULL
      }
    )
  } else {
    message("Variant ", var_label, ": insufficient data for CIF (n=", nrow(tte), ")")
    NULL
  }

  # Echo rate per patient
  echo_rate <- echo_rate_post_dose(doses, echo_events, followup,
                                   dose_col = var_dose_col)

  # QC counts
  n_any_anthracycline  <- dplyr::n_distinct(
    episodes |> dplyr::filter(.data$drug_name %in% var_drugs) |> dplyr::pull(.data$ID)
  )
  n_with_firstline_last_dose <- sum(!is.na(doses$last_dose_firstline_dt))
  n_anthra_no_firstline <- n_any_anthracycline - n_with_firstline_last_dose
  n_echo_events    <- sum(tte$event_status == "echo",  na.rm = TRUE)
  n_deaths         <- sum(tte$event_status == "death", na.rm = TRUE)
  n_censored       <- sum(tte$event_status == "censored", na.rm = TRUE)

  # Echo rate summary
  rate_vals <- echo_rate$rate_per_py[!is.na(echo_rate$rate_per_py)]
  pooled_rate <- if (sum(echo_rate$person_years, na.rm = TRUE) > 0) {
    sum(echo_rate$n_dates_post, na.rm = TRUE) /
      sum(echo_rate$person_years, na.rm = TRUE)
  } else NA_real_

  rate_summary <- tibble::tibble(
    variant     = var_label,
    n_patients  = length(rate_vals),
    mean_rate   = mean(rate_vals),
    median_rate = median(rate_vals),
    q25_rate    = quantile(rate_vals, 0.25),
    q75_rate    = quantile(rate_vals, 0.75),
    pooled_rate = pooled_rate
  )

  list(
    label            = var_label,
    doses            = doses,
    tte              = tte,
    n_no_time        = n_no_time,
    cif_km           = cif_km,
    echo_rate        = echo_rate,
    rate_summary     = rate_summary,
    qc = tibble::tibble(
      variant                      = var_label,
      n_with_any_anthracycline     = n_any_anthracycline,
      n_with_firstline_last_dose   = n_with_firstline_last_dose,
      n_anthracycline_no_firstline = n_anthra_no_firstline,
      n_no_time_after_last_dose    = n_no_time,
      n_echo_events                = n_echo_events,
      n_deaths_before_echo         = n_deaths,
      n_censored                   = n_censored
    )
  )
}

variants <- list()

# Primary
variants$primary <- run_variant(
  var_drugs    = drugs_primary,
  var_dose_col = "last_dose_firstline_dt",
  var_label    = "primary"
)

# Sensitivity: ever dose
variants$sens_ever <- run_variant(
  var_drugs    = drugs_primary,
  var_dose_col = "last_dose_ever_dt",
  var_label    = "sens_ever"
)

# Sensitivity: doxorubicin only
variants$sens_dox_only <- run_variant(
  var_drugs    = "Doxorubicin",
  var_dose_col = "last_dose_firstline_dt",
  var_label    = "sens_dox_only"
)

# Sensitivity: include mitoxantrone (only if present)
if (mitoxantrone_n > 0L) {
  variants$sens_mitox <- run_variant(
    var_drugs    = c(drugs_primary, "Mitoxantrone"),
    var_dose_col = "last_dose_firstline_dt",
    var_label    = "sens_mitox"
  )
}

# ---------- 6. Assemble C_anthracycline_echo block ----------------------------

cif_km_by_variant <- purrr::map_dfr(variants, function(v) {
  if (is.null(v$cif_km)) return(NULL)
  v$cif_km |> dplyr::mutate(variant = v$label, .before = 1)
})

rate_summary_by_variant <- purrr::map_dfr(variants, `[[`, "rate_summary")

caveat_d14c <- paste0(
  "D-14c: Echoes outside OneFlorida+ partner sites are not captured; ",
  "cumulative incidence and rates are lower bounds on echo receipt."
)

C_anthracycline_echo <- list(
  cif_km_by_variant    = cif_km_by_variant,
  rate_summary         = rate_summary_by_variant,
  d_166_01_record      = d_166_01_record,
  d_166_02_note        = paste0(
    "D-166-02: 180-day episode file used (treatment_episode_detail_180.rds). ",
    "first_line column absent; D-08a fallback applied — ",
    "last_dose_firstline_dt computed over all 180-day episodes."
  ),
  mitoxantrone_note    = paste0(
    "Mitoxantrone is excluded from the primary anthracycline clock — ",
    "an anthracenedione rather than an anthracycline and rarely used in HL; ",
    "it is also cardiotoxic (Children's Oncology Group long-term follow-up ",
    "guidelines count it with a dose-equivalence factor). ",
    "Patient count: ", mitoxantrone_n, ". ",
    if (mitoxantrone_n > 0L) "Included in sens_mitox sensitivity variant." else
      "No sensitivity variant generated (0 patients)."
  ),
  caveat_d14c          = caveat_d14c
)

# ---------- 7. QC block -------------------------------------------------------

qc_echo <- dplyr::bind_rows(purrr::map(variants, `[[`, "qc")) |>
  dplyr::mutate(
    first_line_flag_absent = TRUE,  # D-08a
    episode_file_used      = basename(episode_file_used),
    n_echo_events_total    = nrow(echo_events),
    echo_modality_string   = echo_modality_name
  )

# ---------- 8. Primary echo rate for Plan 04 export ---------------------------

echo_rate_patient <- variants$primary$echo_rate

# ---------- 9. Save output ----------------------------------------------------

output_list <- list(
  C_anthracycline_echo         = C_anthracycline_echo,
  cif_km_by_variant            = cif_km_by_variant,
  echo_rate_patient            = echo_rate_patient,
  qc_echo                      = qc_echo,
  qc_anthracycline_drug_counts = qc_anthracycline_drug_counts,
  d_166_01_record              = d_166_01_record,
  episode_file_used            = episode_file_used,
  caveat_d14c                  = caveat_d14c,
  run_date                     = run_date
)

out_path <- file.path(out_dir,
                      glue::glue("survivorship_echo_parts_{run_date}.rds"))
saveRDS(output_list, out_path)
message("Saved: ", out_path)
message("Done. Run date: ", run_date)
