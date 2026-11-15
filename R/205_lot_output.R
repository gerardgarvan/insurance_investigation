# ==============================================================================
# 205_lot_output.R -- Per-patient Line-of-Therapy (LOT) Summary
# ==============================================================================
# Phase:        205 (regimen-line-of-therapy-engine)
# Requirements: REGL-07, REGL-08
#
# Purpose:  Loads treatment_episodes_stage2.rds (produced by R/28 with
#           assign_regimen() applied), calls assign_lot() to assign LOT
#           numbers, and writes a per-patient LOT summary to output/internal/.
#           Also runs a Gantt column regression guard. REGL-08.
#
# Inputs:
#   - output/internal/treatment_episodes_stage2.rds  (R28 stage2; env: R205_STAGE2_RDS)
#   - output/gantt_episodes_180.csv                  (R142 export; env: R205_GANTT_CSV)
#
# Outputs:
#   - output/internal/lot_summary_p205.rds           (env: R205_LOT_RDS)
#   - output/internal/lot_summary_p205.csv           (env: R205_LOT_CSV)
#
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(vroom)
  library(glue)
})


# --- SECTION 0: PINS AND CONFIG ----

R205_STAGE2_RDS <- Sys.getenv("R205_STAGE2_RDS", here::here("output", "internal", "treatment_episodes_stage2.rds"))
R205_LOT_RDS    <- Sys.getenv("R205_LOT_RDS",    here::here("output", "internal", "lot_summary_p205.rds"))
R205_LOT_CSV    <- Sys.getenv("R205_LOT_CSV",    here::here("output", "internal", "lot_summary_p205.csv"))
R205_GANTT_CSV  <- Sys.getenv("R205_GANTT_CSV",  here::here("output", "gantt_episodes_180.csv"))

if (!file.exists(R205_STAGE2_RDS)) stop("[R/205] stage2 RDS not found: ", R205_STAGE2_RDS)
if (!file.exists(R205_GANTT_CSV))  stop("[R/205] gantt CSV not found: ",   R205_GANTT_CSV)

key_df <- tibble::tibble(
  item   = c("R205_STAGE2_RDS", "R205_LOT_RDS", "R205_LOT_CSV", "R205_GANTT_CSV"),
  path   = c(R205_STAGE2_RDS, R205_LOT_RDS, R205_LOT_CSV, R205_GANTT_CSV),
  pinned = c(nchar(Sys.getenv("R205_STAGE2_RDS")) > 0,
             nchar(Sys.getenv("R205_LOT_RDS"))    > 0,
             nchar(Sys.getenv("R205_LOT_CSV"))    > 0,
             nchar(Sys.getenv("R205_GANTT_CSV"))  > 0)
)
message("[R/205] KEY:"); print(key_df)


# --- SECTION 1: LOAD INPUTS ----

source(here::here("R", "00_config.R"),              local = new.env(parent = globalenv()))
source(here::here("R", "utils", "utils_regimen.R"), local = new.env(parent = globalenv()))

episodes <- readRDS(R205_STAGE2_RDS)
message("[R/205] stage2 loaded: ", nrow(episodes), " rows, ",
        dplyr::n_distinct(episodes$patient_id), " patients")

# stage2 column names: patient_id, episode_start, episode_stop (from R/28).
# assign_lot() requires: ID, episode_number, start_date, end_date, regimen_label.
stopifnot(
  all(c("patient_id", "episode_number", "episode_start", "episode_stop", "regimen_label")
      %in% names(episodes))
)


# --- SECTION 1B: REGIMEN LABEL QC (regimen_label x treatment_type) ----

stopifnot("treatment_type" %in% names(episodes))
# Local copies: the config/utils above are sourced into throwaway environments.
R205_SYSTEMIC_TYPES <- c("Chemotherapy", "Immunotherapy")
R205_UNREC_LABEL    <- "Unrecognized systemic"
qc_tab <- episodes %>%
  dplyr::mutate(regimen_label = dplyr::coalesce(regimen_label, "(none)")) %>%
  dplyr::count(treatment_type, regimen_label, name = "n") %>%
  dplyr::mutate(n_display = ifelse(n < 11L, "<11", as.character(n))) %>%
  dplyr::select(treatment_type, regimen_label, n_display)
message("[R/205] QC regimen_label x treatment_type (counts 1-10 shown as <11):")
print(as.data.frame(qc_tab), row.names = FALSE)

n_nonsys_labeled <- sum(!is.na(episodes$regimen_label) &
                        !episodes$treatment_type %in% R205_SYSTEMIC_TYPES)
if (n_nonsys_labeled > 0L) {
  stop("[R/205] QC FAIL: ", n_nonsys_labeled,
       " non-systemic episodes carry a regimen_label (stale stage2 RDS? re-run R/28)")
}
n_other <- sum(episodes$regimen_label %in% "Other", na.rm = TRUE)
n_immuno_unrec <- sum(episodes$treatment_type == "Immunotherapy" &
                      episodes$regimen_label %in% R205_UNREC_LABEL)
if (n_other > 0L || n_immuno_unrec > 0L) {
  stop("[R/205] QC FAIL: legacy 'Other' label present (", n_other, ") or Immunotherapy ",
       "episodes labeled '", R205_UNREC_LABEL, "' (", n_immuno_unrec, ")")
}
message("[R/205] QC PASS: labels only on Chemotherapy/Immunotherapy episodes")


# --- SECTION 2: ASSIGN LOT ----

# SCT dates: TODO — load once schema probe for SCT table is available (REGL-06-B).
lot_episodes <- assign_lot(
  episode_df = episodes %>%
    dplyr::rename(ID = patient_id, start_date = episode_start, end_date = episode_stop),
  lot_gap_days        = LOT_GAP_DAYS,
  maintenance_classes = MAINTENANCE_DRUG_CLASSES,
  sct_dates_df        = NULL
)
# Restore original column names.
lot_episodes <- lot_episodes %>%
  dplyr::rename(patient_id = ID, episode_start = start_date, episode_stop = end_date)

message("[R/205] LOT assigned: ", nrow(lot_episodes), " episodes, ",
        dplyr::n_distinct(lot_episodes$patient_id), " patients")
print(dplyr::count(lot_episodes, line_of_therapy))


# --- SECTION 3: PER-PATIENT LOT SUMMARY (REGL-07) ----

lot_summary <- lot_episodes %>%
  dplyr::group_by(patient_id) %>%
  dplyr::summarise(
    line_1_regimen  = {
      ep1 <- regimen_label[line_of_therapy == 1L]
      if (length(ep1) == 0L) NA_character_ else ep1[1L]
    },
    line_1_start   = {
      dt1 <- episode_start[line_of_therapy == 1L]
      if (length(dt1) == 0L) as.Date(NA) else min(dt1, na.rm = TRUE)
    },
    n_lines        = dplyr::n_distinct(line_of_therapy),
    regimen_per_line = {
      pairs <- dplyr::tibble(
        lot = line_of_therapy,
        reg = dplyr::coalesce(regimen_label, "Unknown")
      ) %>%
        dplyr::distinct() %>%
        dplyr::arrange(lot) %>%
        dplyr::mutate(tok = paste0(lot, ":", reg))
      paste(pairs$tok, collapse = ";")
    },
    .groups = "drop"
  ) %>%
  dplyr::rename(ID = patient_id)

n_patients_lot <- nrow(lot_summary)
message("[R/205] REGL-07: lot_summary: ", n_patients_lot, " patients; ",
        "n_lines distribution:")
print(dplyr::count(lot_summary, n_lines))

# Apply suppress_small() to displayed patient count (output/internal/ only — no PHI boundary).
# Count itself is safe (PHI is IDs, not counts); suppress here for any tabular display.
n_patients_display <- if (n_patients_lot < 11L) "<11" else as.character(n_patients_lot)
message("[R/205] Patients in lot_summary: ", n_patients_display)

saveRDS(lot_summary, R205_LOT_RDS)
readr::write_csv(lot_summary, R205_LOT_CSV)
message("[R/205] REGL-07: lot_summary written: ", n_patients_display, " patients — ", R205_LOT_RDS)


# --- SECTION 4: GANTT REGRESSION GUARD (REGL-08) ----

# Pre-Phase-205 column regression guard. REGL-08.
gantt <- vroom::vroom(R205_GANTT_CSV, col_types = vroom::cols(.default = "c"), show_col_types = FALSE)

expected_cols_205 <- c(
  "patient_id", "treatment_type", "episode_number",
  "episode_start", "episode_stop", "episode_length_days",
  "distinct_dates_in_episode",
  "triggering_codes", "drug_names", "triggering_code_descriptions",
  "cancer_category", "is_hodgkin",
  "drug_group",
  "code_type", "source_table", "sct_cross_use_flag",
  "episode_dx_codes", "episode_dx_categories",
  "episode_dx_7day_confirmed", "age_at_episode",
  # Phase 192.1
  "has_autoimmune_dx", "first_autoimmune_dx_date",
  # Phase 192.2
  "autoimmune_dx_code_system",
  # Phase 199
  "immune_flag", "ever_brentuximab", "immune_flag_dx",
  # Phase 201
  "ever_abvd", "abvd_episode", "tr_hl_dx", "tr_nhl_dx",
  # Phase 201b
  "abvd_class", "ever_abvd_plus"
)

missing_cols <- setdiff(expected_cols_205, names(gantt))
if (length(missing_cols) > 0) {
  stop("[R/205] Gantt regression FAIL — columns missing: ", paste(missing_cols, collapse = ", "))
}
message("[R/205] Gantt regression guard: PASS (", length(expected_cols_205), " columns confirmed)")
message("[R/205] Gantt rows: ", nrow(gantt), "; patients: ", dplyr::n_distinct(gantt$patient_id))
