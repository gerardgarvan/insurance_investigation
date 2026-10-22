# R/187_anthracycline_exposure.R
# Phase 187: Anthracycline Exposure Variables
# Source: .planning/phases/187-anthracycline-exposure-variables/187-CONTEXT.md
# Schema probe: .planning/schemas/187_schema_20261022.md (confirmed 2026-10-22)
#
# Run: source("R/187_anthracycline_exposure.R", local = new.env(parent = globalenv()))
#   from repo root on HiPerGator (module load R/4.5)
#
# Inputs (pinned):
#   R187_EPISODE_RDS      cache/outputs/treatment_episode_detail_180.rds
#   R187_RATES_PARTS_RDS  clean/rds/outputs/survivorship_modality_rates_parts_20261012.rds
#
# Outputs:
#   output/internal/anthracycline_exposure_patient_<YYYYMMDD>.rds  (patient-grain, internal)
#   output/anthracycline_exposure_summary_<YYYYMMDD>.xlsx           (aggregate, public)
#
# Note on R187_RATES_PARTS_RDS default: R/184 does not pin survivorship_modality_rates_parts_*.rds.
#   R/184 reads follow_end from the patient-year RDS (R/179), not from rates_parts$followup.
#   R/187 uses the R/166 parts file as its follow_end source (same source as R/167), following
#   D-11 (do not reimplement compute_followup()). Default date 20261012 from Phase 171 SURV_RUN_DATE
#   (171-01-SUMMARY.md line "Survivorship run date (SURV_RUN_DATE): 20261012").

# ==============================================================================
# SECTION 0 — Header and Pins ----
# ==============================================================================

source("R/00_config.R")

run_date <- format(Sys.Date(), "%Y%m%d")
message("==== R/187: Anthracycline Exposure Variables -- run_date = ", run_date, " ====")

UF_BLUE   <- "#0021A5"
UF_ORANGE <- "#FA4616"

pin <- function(var, default) {
  v <- Sys.getenv(var, unset = "")
  p <- if (nzchar(v)) v else here::here(default)
  list(var = var, path = p, pinned = nzchar(v))
}

pins <- list(
  episode_rds     = pin("R187_EPISODE_RDS",
                        file.path(CONFIG$cache$outputs_dir,
                                  "treatment_episode_detail_180.rds")),
  rates_parts_rds = pin("R187_RATES_PARTS_RDS",
                        file.path(CONFIG$cache$outputs_dir,
                                  "survivorship_modality_rates_parts_20261012.rds"))
  # Default R187_RATES_PARTS_RDS: Phase 171 survivorship run (SURV_RUN_DATE 20261012)
  # per 171-01-SUMMARY.md. Lives in CONFIG$cache$outputs_dir (clean/rds/outputs on HiPerGator).
  # R/184 does not pin this file (R/184 uses patient-year RDS from R/179 for its model;
  # R/187 needs follow_end per D-11, sourced from R/166 parts).
)

message("[187] Pins:")
for (nm in names(pins)) {
  p <- pins[[nm]]
  message("  ", p$var, ": ", p$path, " (pinned=", p$pinned, ")")
}

stopifnot(file.exists(pins$episode_rds$path))
stopifnot(file.exists(pins$rates_parts_rds$path))

# Anthracycline drug set (ANTH-01, D-04)
# Only Doxorubicin present after alias collapse in this extract (24,404 rows; D-03).
# Daunorubicin, Epirubicin, Idarubicin: zero rows — included in constant for future
# compatibility. Mitoxantrone excluded (D-187-02).
ANTHRACYCLINE_DRUGS <- c("Doxorubicin", "Daunorubicin", "Epirubicin", "Idarubicin")

# ==============================================================================
# SECTION 1 — Read, Rename, and Filter Episode File ----
# ==============================================================================

# Load episode detail RDS (180-day treatment episode detail, Phase 124+)
episodes_raw <- readRDS(pins$episode_rds$path)
message("[187] Episode file loaded: ", nrow(episodes_raw), " rows")

# Apply DRUG_NAME_ALIASES from R/00_config.R (lines 2749+) to collapse variants -> canonical.
# Phase 164 D-1/D-3: Doxorubicin liposomal variants collapsed. Probe confirmed this is
# already applied upstream in the episode detail build, but apply defensively here.
if (exists("DRUG_NAME_ALIASES") && !is.null(DRUG_NAME_ALIASES) &&
    "drug_name" %in% names(episodes_raw)) {
  episodes_raw <- episodes_raw |>
    dplyr::mutate(drug_name = dplyr::recode(.data$drug_name, !!!DRUG_NAME_ALIASES))
  message("[187] DRUG_NAME_ALIASES applied.")
}

# Rename columns to match last_anthracycline_dose() signature (D-08a pattern from
# R/167_anthracycline_echo.R lines 77-113):
#   patient_id -> ID, treatment_date -> admin_date, episode_number -> episode_id
if ("patient_id"     %in% names(episodes_raw)) episodes_raw <- dplyr::rename(episodes_raw, ID = patient_id)
if ("treatment_date" %in% names(episodes_raw)) episodes_raw <- dplyr::rename(episodes_raw, admin_date = treatment_date)
if ("episode_number" %in% names(episodes_raw)) episodes_raw <- dplyr::rename(episodes_raw, episode_id = episode_number)

# D-08a: first_line column absent in 180-day episode detail; treat all rows as first-line
# for helper compatibility (last_dose_firstline_dt == last_dose_ever_dt when all first_line=TRUE).
if (!"first_line" %in% names(episodes_raw)) {
  message("[187] D-08a: 'first_line' absent — adding first_line = TRUE for all rows.")
  episodes_raw <- dplyr::mutate(episodes_raw, first_line = TRUE)
}

# Ensure admin_date is Date
if ("admin_date" %in% names(episodes_raw)) {
  episodes_raw <- dplyr::mutate(episodes_raw, admin_date = as.Date(.data$admin_date))
}

# Validate required columns after rename
req_cols <- c("ID", "drug_name", "admin_date", "first_line", "treatment_type")
missing  <- setdiff(req_cols, names(episodes_raw))
if (length(missing) > 0L) {
  stop("[187] Missing columns after rename: ", paste(missing, collapse = ", "))
}

# Load follow-up (D-11 — do NOT reimplement compute_followup())
# Source: rates_parts$followup from survivorship_modality_rates_parts_<date>.rds
# (produced by R/166_survivorship_modality_rates.R SECTION 8, confirmed in 166-02-SUMMARY.md)
rates_parts <- readRDS(pins$rates_parts_rds$path)
followup <- if (!is.null(rates_parts$followup)) {
  rates_parts$followup |> dplyr::select("ID", "follow_end")
} else {
  stop("[187] rates_parts$followup is NULL — check survivorship_modality_rates_parts file.")
}
message("[187] Cohort size from follow-up table: ", nrow(followup))

# ID types must match before any join (episode patient_id is chr per probe; D-03)
followup     <- dplyr::mutate(followup, ID = as.character(.data$ID))
episodes_raw <- dplyr::mutate(episodes_raw, ID = as.character(.data$ID))

stopifnot(!anyDuplicated(followup$ID))

n_followup_na <- sum(is.na(followup$follow_end))
message("[187] follow_end NA in follow-up table: ", n_followup_na,
        " (these patients get years_since_last_anthracycline = NA)")

# Cohort patient set = all IDs in the follow-up table (D-04a).
# Episodes with IDs not in followup are dropped and counted on KEY.
n_episode_ids   <- dplyr::n_distinct(episodes_raw$ID)
episodes_cohort <- dplyr::semi_join(episodes_raw, followup, by = "ID")
n_dropped_ids   <- n_episode_ids - dplyr::n_distinct(episodes_cohort$ID)
message("[187] Episode IDs dropped (not in followup): ", n_dropped_ids)

# ==============================================================================
# SECTION 2 — Compute Flags and Time Variables ----
# ==============================================================================

# build_patient_out() is used for BOTH synthetic fixtures and real data.
# No separate copy of logic anywhere. (D-16)
#
# Arguments:
#   episodes:  tibble with ID (chr), treatment_type, drug_name, admin_date (Date),
#              first_line (lgl), episode_id — already renamed/cleaned by SECTION 1
#   followup:  tibble with ID (chr), follow_end (Date) — one row per cohort patient
#   drugs:     character vector of drug names (ANTHRACYCLINE_DRUGS)
build_patient_out <- function(episodes, followup, drugs) {
  # any_chemo: TRUE if patient has any row with treatment_type == "Chemotherapy" (D-04b)
  chemo_episodes <- dplyr::filter(episodes, .data$treatment_type == "Chemotherapy")

  chemo_ids <- dplyr::distinct(chemo_episodes, .data$ID)

  # last_anthracycline_dose() from R/utils/utils_anthracycline_echo.R lines 58-88:
  #   inputs: episodes tibble (ID, drug_name, admin_date, first_line, episode_id)
  #           drugs character vector
  #   returns: tibble -- ID, last_dose_firstline_dt, last_dose_ever_dt
  # Phase 187 uses last_dose_ever_dt (all episodes, not first-line only). (D-14)
  dose_tbl <- last_anthracycline_dose(chemo_episodes, drugs)

  # drugs_received: alphabetically sorted anthracycline drug names per patient (D-05)
  drugs_received_tbl <- chemo_episodes |>
    dplyr::filter(.data$drug_name %in% drugs) |>
    dplyr::group_by(.data$ID) |>
    dplyr::summarise(
      drugs_received = paste(sort(unique(.data$drug_name)), collapse = "; "),
      .groups = "drop"
    )

  out <- followup |>
    dplyr::mutate(any_chemo = .data$ID %in% chemo_ids$ID) |>
    dplyr::left_join(
      dplyr::select(dose_tbl, "ID", last_anthracycline_date = "last_dose_ever_dt"),
      by = "ID"
    ) |>
    dplyr::left_join(drugs_received_tbl, by = "ID") |>
    dplyr::mutate(
      # any_anthracycline: derived from presence of an anthracycline row (not from the date),
      # so an NA admin_date can never silently turn an exposed patient into FALSE. (D-06)
      any_anthracycline = !is.na(.data$drugs_received),   # never NA
      dose_after_end    = .data$any_anthracycline &
                          !is.na(.data$follow_end) &
                          .data$last_anthracycline_date > .data$follow_end,   # D-07 flag
      years_since_last_anthracycline = dplyr::if_else(
        .data$any_anthracycline & !is.na(.data$follow_end) & !.data$dose_after_end,
        as.numeric(.data$follow_end - .data$last_anthracycline_date) / 365.25,
        NA_real_
      )
    )

  # Guard: an exposed patient must have a date. A mismatch means an anthracycline
  # row had NA admin_date — stop to prevent silent data loss.
  bad <- out$any_anthracycline & is.na(out$last_anthracycline_date)
  if (any(bad)) {
    stop("[187] ", sum(bad), " patient(s) have an anthracycline row but NA last date — ",
         "check admin_date NAs in the episode file.")
  }

  out
}

# ---- Synthetic fixtures (must pass before real data) ----
# Covers (D-16): no chemo; chemo without anthracycline; single administration;
# multiple administrations (latest date kept); last dose after follow_end.

fx_followup <- dplyr::tibble(
  ID         = c("A", "B", "C", "D", "E"),
  follow_end = as.Date(c("2024-12-31", "2024-12-31", "2024-12-31",
                          "2024-12-31", "2020-01-01"))
)
fx_episodes <- dplyr::tibble(
  ID             = c("B",           "C",           "D",           "D",           "E"),
  treatment_type = "Chemotherapy",
  drug_name      = c("Bleomycin",   "Doxorubicin", "Doxorubicin", "Doxorubicin", "Doxorubicin"),
  admin_date     = as.Date(c("2015-03-01", "2016-01-01", "2015-01-01", "2018-06-01", "2021-05-01")),
  first_line     = TRUE,
  episode_id     = c("1", "1", "1", "2", "1")
)

fx <- build_patient_out(fx_episodes, fx_followup, ANTHRACYCLINE_DRUGS)
fx <- fx[match(c("A", "B", "C", "D", "E"), fx$ID), ]

# A: no chemo -> any_chemo FALSE, any_anthracycline FALSE, dates NA
stopifnot(!fx$any_chemo[1], !fx$any_anthracycline[1], is.na(fx$last_anthracycline_date[1]),
          is.na(fx$years_since_last_anthracycline[1]))

# B: chemo without anthracycline -> any_chemo TRUE, any_anthracycline FALSE, years NA
stopifnot(fx$any_chemo[2], !fx$any_anthracycline[2], is.na(fx$years_since_last_anthracycline[2]))

# C: single administration -> last date = "2016-01-01", years computed correctly
stopifnot(fx$any_anthracycline[3],
          fx$last_anthracycline_date[3] == as.Date("2016-01-01"),
          abs(fx$years_since_last_anthracycline[3] -
                as.numeric(as.Date("2024-12-31") - as.Date("2016-01-01")) / 365.25) < 1e-9)

# D: multiple administrations -> latest date kept (2018-06-01, not 2015-01-01)
stopifnot(fx$last_anthracycline_date[4] == as.Date("2018-06-01"))

# E: last dose after follow_end (2021-05-01 > 2020-01-01) -> years NA, flagged
stopifnot(fx$dose_after_end[5], is.na(fx$years_since_last_anthracycline[5]))

# Flag values never NA
stopifnot(!anyNA(fx$any_chemo), !anyNA(fx$any_anthracycline))

message("[187] All fixtures passed (no chemo, chemo w/o anthracycline, single, multiple, after follow_end).")

# ---- Real data ----
patient_out <- build_patient_out(episodes_cohort, followup, ANTHRACYCLINE_DRUGS)

n_dose_after_end <- sum(patient_out$dose_after_end)
message("[187] D-07 flagged (last dose after follow_end): ", n_dose_after_end)
message("[187] any_chemo TRUE: ", sum(patient_out$any_chemo),
        " | FALSE: ", sum(!patient_out$any_chemo))

# Select final output columns (D-05)
patient_out <- patient_out |>
  dplyr::select("ID", "any_chemo", "any_anthracycline", "last_anthracycline_date",
                "years_since_last_anthracycline", "follow_end", "drugs_received")

# Post-computation guards (must_have truths from plan)
stopifnot(!anyNA(patient_out$any_chemo))
stopifnot(!anyNA(patient_out$any_anthracycline))
stopifnot(nrow(patient_out) == nrow(followup))
stopifnot(all(patient_out$years_since_last_anthracycline >= 0, na.rm = TRUE))

# D-03b: treatment_date range in probe (2012-01-01 to 2025-03-27) spans the study period
# with no anchor-relative window filter applied in R/142 build. No extra date filter needed.

# ==============================================================================
# SECTION 3 — Write Outputs ----
# ==============================================================================

# ---- Patient-grain RDS (internal — no sharing, contains ID and dates) ----
out_rds_path <- here::here("output", "internal",
                           glue::glue("anthracycline_exposure_patient_{run_date}.rds"))
saveRDS(patient_out, out_rds_path)
message("[187] Patient RDS written: ", out_rds_path)
message("[187] Rows: ", nrow(patient_out),
        " | any_anthracycline TRUE: ", sum(patient_out$any_anthracycline),
        " | FALSE: ", sum(!patient_out$any_anthracycline))

# ---- Aggregate summary workbook (public — no patient IDs or dates) ----
# Suppression helpers (CLAUDE.md: counts 1-10 shown as "<11", zero as "0")
sup <- function(n) {
  dplyr::case_when(
    n == 0L            ~ "0",
    n >= 1L & n <= 10L ~ "<11",
    TRUE               ~ as.character(n)
  )
}

# Complementary suppression (D-15): if either cell of a TRUE/FALSE pair is "<11",
# both are suppressed. Applies only to flag pairs where cohort total is visible.
sup_pair <- function(n_true, n_false) {
  s <- c(sup(n_true), sup(n_false))
  if (any(s == "<11")) s <- c("<11", "<11")
  s
}

n_total <- nrow(patient_out)

# Sheet: COUNTS_BY_FLAG
chemo_s <- sup_pair(sum(patient_out$any_chemo),         sum(!patient_out$any_chemo))
anth_s  <- sup_pair(sum(patient_out$any_anthracycline), sum(!patient_out$any_anthracycline))
counts_flag <- dplyr::tibble(
  flag       = c("any_chemo TRUE", "any_chemo FALSE",
                 "any_anthracycline TRUE", "any_anthracycline FALSE"),
  n_patients = c(chemo_s, anth_s)
)

# Sheet: COUNTS_BY_DRUG
# Count distinct patients per drug from episode rows (not from substring-matching drugs_received).
# All four drugs listed; zero present shown as "0". Not additive; no complementary rule.
drug_counts <- episodes_cohort |>
  dplyr::filter(.data$treatment_type == "Chemotherapy", .data$drug_name %in% ANTHRACYCLINE_DRUGS) |>
  dplyr::distinct(.data$ID, .data$drug_name) |>
  dplyr::count(.data$drug_name, name = "n")

counts_drug <- dplyr::tibble(drug = ANTHRACYCLINE_DRUGS) |>
  dplyr::left_join(drug_counts, by = c("drug" = "drug_name")) |>
  dplyr::mutate(
    n            = dplyr::coalesce(.data$n, 0L),
    n_patients   = sup(.data$n),
    present_in_data = .data$n > 0
  ) |>
  dplyr::select("drug", "n_patients", "present_in_data")

# Sheet: FLAGS (quality / diagnostic counts)
flags_sheet <- dplyr::tibble(
  item       = c("D-07 last dose after follow_end",
                 "D-04a episode IDs not in follow-up table",
                 "follow_end missing in follow-up table"),
  n_patients = sup(c(n_dose_after_end, n_dropped_ids, n_followup_na))
)

# Build workbook with KEY sheet leftmost (R/184 pattern: R/184 lines 1218-1269)
wb <- openxlsx::createWorkbook()

# Styles
hdr_blue   <- openxlsx::createStyle(fgFill = UF_BLUE,   fontColour = "white",
                                    textDecoration = "bold", halign = "left")
hdr_orange <- openxlsx::createStyle(fgFill = UF_ORANGE, fontColour = "white",
                                    textDecoration = "bold", halign = "left")

# ---- Sheet 1: KEY (leftmost) ----
key_data <- dplyr::tibble(
  item  = c(
    "Phase",
    "Script",
    "Run date",
    "Host",
    "Schema probe file",
    "R187_EPISODE_RDS path",
    "R187_EPISODE_RDS pinned",
    "R187_RATES_PARTS_RDS path",
    "R187_RATES_PARTS_RDS pinned",
    "R187_RATES_PARTS_RDS default source",
    "Drug set (ANTHRACYCLINE_DRUGS)",
    "Drugs present in extract",
    "Drugs absent in extract",
    "D-03b date window note",
    "any_chemo filter",
    "Total cohort patients (followup rows)",
    "any_anthracycline TRUE",
    "any_anthracycline FALSE",
    "any_chemo TRUE",
    "any_chemo FALSE",
    "D-07 flagged (last dose after follow_end)",
    "D-04a dropped (episode IDs not in cohort)",
    "follow_end missing",
    "Years unit",
    "Output RDS path"
  ),
  value = c(
    "187 (anthracycline-exposure-variables)",
    "R/187_anthracycline_exposure.R",
    run_date,
    Sys.info()[["nodename"]],
    ".planning/schemas/187_schema_20261022.md (confirmed 2026-10-22)",
    pins$episode_rds$path,
    as.character(pins$episode_rds$pinned),
    pins$rates_parts_rds$path,
    as.character(pins$rates_parts_rds$pinned),
    paste0("Phase 171 SURV_RUN_DATE 20261012 (171-01-SUMMARY.md); ",
           "R/184 does not pin this file -- R/184 uses R/179 patient-year RDS for follow_end"),
    paste(ANTHRACYCLINE_DRUGS, collapse = "; "),
    "Doxorubicin",
    "Daunorubicin; Epirubicin; Idarubicin",
    paste0("treatment_date range 2012-01-01 to 2025-03-27 (probe confirmed); ",
           "no anchor-relative window filter applied (D-03b)"),
    "treatment_type == 'Chemotherapy' (D-04b)",
    sup(n_total),
    anth_s[1],
    anth_s[2],
    chemo_s[1],
    chemo_s[2],
    sup(n_dose_after_end),
    sup(n_dropped_ids),
    sup(n_followup_na),
    "days / 365.25",
    out_rds_path
  )
)

openxlsx::addWorksheet(wb, "KEY")
openxlsx::writeData(wb, "KEY", key_data, startRow = 1)
openxlsx::addStyle(wb, "KEY",
                   style = hdr_blue,
                   rows = 1, cols = 1:2, gridExpand = TRUE)

# ---- Sheet 2: COUNTS_BY_FLAG ----
openxlsx::addWorksheet(wb, "COUNTS_BY_FLAG")
openxlsx::writeData(wb, "COUNTS_BY_FLAG", counts_flag, startRow = 1)
openxlsx::addStyle(wb, "COUNTS_BY_FLAG",
                   style = hdr_blue, rows = 1, cols = 1:2, gridExpand = TRUE)

# ---- Sheet 3: COUNTS_BY_DRUG ----
openxlsx::addWorksheet(wb, "COUNTS_BY_DRUG")
openxlsx::writeData(wb, "COUNTS_BY_DRUG", counts_drug, startRow = 1)
openxlsx::addStyle(wb, "COUNTS_BY_DRUG",
                   style = hdr_blue, rows = 1, cols = 1:3, gridExpand = TRUE)

# ---- Sheet 4: FLAGS ----
openxlsx::addWorksheet(wb, "FLAGS")
openxlsx::writeData(wb, "FLAGS", flags_sheet, startRow = 1)
openxlsx::addStyle(wb, "FLAGS",
                   style = hdr_orange, rows = 1, cols = 1:2, gridExpand = TRUE)

out_xlsx_path <- here::here("output",
                             glue::glue("anthracycline_exposure_summary_{run_date}.xlsx"))
openxlsx::saveWorkbook(wb, out_xlsx_path, overwrite = TRUE)
message("[187] Summary workbook written: ", out_xlsx_path)

# ---- Final output path record (for 187-01-SUMMARY.md) ----
message("========================================")
message("[187] OUTPUT RDS (record in SUMMARY):  ", out_rds_path)
message("[187] OUTPUT XLSX:                     ", out_xlsx_path)
message("[187] Run date:                        ", run_date)
message("========================================")
