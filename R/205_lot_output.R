# ==============================================================================
# 205_lot_output.R -- Per-patient Line-of-Therapy (LOT) Summary
# ==============================================================================
# Phase:        205 (regimen-line-of-therapy-engine); revised quick 261114-sir
# Requirements: REGL-07, REGL-08
#
# Purpose:  Loads treatment_episodes_stage2.rds (produced by R/28 with
#           assign_regimen() applied), calls assign_lot() to assign LOT
#           numbers over recognized systemic regimens only, writes a per-patient
#           LOT summary to output/internal/, and reconciles the 205 Gantt
#           against a pinned Phase 204 baseline (value-level, REGL-08).
#
# Inputs:
#   - treatment_episodes_stage2.rds in CONFIG$cache$outputs_dir
#                                                    (env: R205_STAGE2_RDS)
#   - output/gantt_episodes_180.csv                  (R142 export; env: R205_GANTT_CSV)
#   - output/internal/pre205_run_backup/gantt_episodes_180.csv
#                                                    (Phase 204 baseline; env: R205_BASELINE_GANTT)
#
# Outputs:
#   - output/internal/lot_summary_p205.rds           (env: R205_LOT_RDS)
#   - output/internal/lot_summary_p205.csv           (env: R205_LOT_CSV)
#   - output/internal/regimen_reconciliation_p205.csv (env: R205_RECON_CSV)
#
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(vroom)
  library(glue)
})

# Config (and R/utils/*, auto-sourced) into the global env: CONFIG and the
# Phase 205 constants must be visible below.
source(here::here("R", "00_config.R"))


# --- SECTION 0: PINS AND CONFIG ----

R205_STAGE2_RDS <- Sys.getenv("R205_STAGE2_RDS",
  file.path(CONFIG$cache$outputs_dir, "treatment_episodes_stage2.rds"))
R205_LOT_RDS    <- Sys.getenv("R205_LOT_RDS",    here::here("output", "internal", "lot_summary_p205.rds"))
R205_LOT_CSV    <- Sys.getenv("R205_LOT_CSV",    here::here("output", "internal", "lot_summary_p205.csv"))
R205_GANTT_CSV  <- Sys.getenv("R205_GANTT_CSV",  here::here("output", "gantt_episodes_180.csv"))
R205_BASELINE_GANTT <- Sys.getenv("R205_BASELINE_GANTT",
  here::here("output", "internal", "pre205_run_backup", "gantt_episodes_180.csv"))
R205_RECON_CSV  <- Sys.getenv("R205_RECON_CSV",
  here::here("output", "internal", "regimen_reconciliation_p205.csv"))

for (f in c(R205_STAGE2_RDS, R205_GANTT_CSV, R205_BASELINE_GANTT)) {
  if (!file.exists(f)) stop("[R/205] input not found: ", f)
}

pin_names <- c("R205_STAGE2_RDS", "R205_LOT_RDS", "R205_LOT_CSV", "R205_GANTT_CSV",
               "R205_BASELINE_GANTT", "R205_RECON_CSV")
key_df <- tibble::tibble(
  item   = pin_names,
  path   = c(R205_STAGE2_RDS, R205_LOT_RDS, R205_LOT_CSV, R205_GANTT_CSV,
             R205_BASELINE_GANTT, R205_RECON_CSV),
  pinned = vapply(pin_names, function(n) nchar(Sys.getenv(n)) > 0, logical(1L))
)
message("[R/205] KEY:"); print(key_df)

# Counts 1-10 shown as "<11".
fmt_n <- function(n) ifelse(is.na(n), "NA", ifelse(n >= 1L & n < 11L, "<11", as.character(n)))


# --- SECTION 1: LOAD INPUTS ----

episodes <- readRDS(R205_STAGE2_RDS)
message("[R/205] stage2 loaded: ", nrow(episodes), " rows, ",
        dplyr::n_distinct(episodes$patient_id), " patients")

# stage2 column names: patient_id, episode_start, episode_stop (from R/28).
# assign_lot() requires: ID, episode_number, start_date, end_date, regimen_label.
stopifnot(
  all(c("patient_id", "episode_number", "episode_start", "episode_stop",
        "regimen_label", "treatment_type", "drug_names") %in% names(episodes))
)


# --- SECTION 1B: REGIMEN LABEL QC (regimen_label x treatment_type) ----

qc_tab <- episodes %>%
  dplyr::mutate(regimen_label = dplyr::coalesce(regimen_label, "(none)")) %>%
  dplyr::count(treatment_type, regimen_label, name = "n") %>%
  dplyr::mutate(n_display = fmt_n(n)) %>%
  dplyr::select(treatment_type, regimen_label, n_display)
message("[R/205] QC regimen_label x treatment_type (counts 1-10 shown as <11):")
print(as.data.frame(qc_tab), row.names = FALSE)

n_nonsys_labeled <- sum(!is.na(episodes$regimen_label) &
                        !episodes$treatment_type %in% REGIMEN_SYSTEMIC_TYPES)
if (n_nonsys_labeled > 0L) {
  stop("[R/205] QC FAIL: ", n_nonsys_labeled,
       " non-systemic episodes carry a regimen_label (stale stage2 RDS? re-run R/28)")
}
n_other <- sum(episodes$regimen_label %in% "Other", na.rm = TRUE)
if (n_other > 0L) {
  stop("[R/205] QC FAIL: legacy 'Other' label present (", n_other, "); re-run R/28")
}
# Every systemic episode with a drug name must carry a label (never NA).
n_na_named <- sum(is.na(episodes$regimen_label) &
                  episodes$treatment_type %in% REGIMEN_SYSTEMIC_TYPES &
                  !is.na(episodes$drug_names) & nzchar(trimws(episodes$drug_names)))
if (n_na_named > 0L) {
  stop("[R/205] QC FAIL: ", n_na_named,
       " systemic episodes with drug_names have NA regimen_label (re-run R/28)")
}
# Round 5 hard QC: a Chemotherapy episode labelled with an immunotherapy-only label
# must itself contain brentuximab / nivolumab / pembrolizumab in drug_names.
n_immuno_mislabel <- sum(
  episodes$treatment_type %in% "Chemotherapy" &
  episodes$regimen_label %in% REGIMEN_IMMUNO_ONLY_LABELS &
  !grepl("brentuximab|nivolumab|pembrolizumab", tolower(dplyr::coalesce(episodes$drug_names, ""))))
message("[R/205] QC Chemotherapy episodes labelled BV mono / PD-1 mono (or BV+Nivo / BV+PD-1) ",
        "without those agents in drug_names: ", n_immuno_mislabel, " (must be 0)")
if (n_immuno_mislabel > 0L) {
  stop("[R/205] QC FAIL: ", n_immuno_mislabel,
       " Chemotherapy episodes carry an immunotherapy-only label without BV / nivolumab / ",
       "pembrolizumab in their own drug_names (re-run R/28 with the round-5 utils_regimen.R)")
}
message("[R/205] QC PASS: labels only on Chemotherapy/Immunotherapy; none NA where drug_names present")
if ("regimen_basis" %in% names(episodes)) {
  message("[R/205] regimen_basis (counts 1-10 shown as <11):")
  print(as.data.frame(dplyr::mutate(dplyr::count(episodes, regimen_basis), n = fmt_n(n))),
        row.names = FALSE)
}


# --- SECTION 2: ASSIGN LOT (recognized systemic regimens only) ----

lot_episodes <- assign_lot(
  episode_df = episodes %>%
    dplyr::rename(ID = patient_id, start_date = episode_start, end_date = episode_stop),
  lot_gap_days        = LOT_GAP_DAYS,
  maintenance_classes = MAINTENANCE_DRUG_CLASSES,
  same_family_restart_days = LOT_SAME_FAMILY_RESTART_DAYS
)
message("[R/205] LOT rule: new line on regimen-family change, or same-family restart after >= ",
        LOT_SAME_FAMILY_RESTART_DAYS, " days")
lot_episodes <- lot_episodes %>%
  dplyr::rename(patient_id = ID, episode_start = start_date, episode_stop = end_date)

message("[R/205] LOT assigned: ", nrow(lot_episodes), " episodes (",
        fmt_n(sum(!is.na(lot_episodes$line_of_therapy))), " with a line), ",
        dplyr::n_distinct(lot_episodes$patient_id), " patients")
print(as.data.frame(dplyr::mutate(dplyr::count(lot_episodes, line_of_therapy), n = fmt_n(n))),
      row.names = FALSE)

nonsys_lot <- sum(!is.na(lot_episodes$line_of_therapy) &
                  !lot_episodes$treatment_type %in% REGIMEN_SYSTEMIC_TYPES)
bad_lot <- sum(!is.na(lot_episodes$line_of_therapy) &
               lot_episodes$regimen_label %in% REGIMEN_NOT_RECOGNIZED_LABELS)
if (nonsys_lot > 0L || bad_lot > 0L) {
  stop("[R/205] QC FAIL: line_of_therapy set on non-systemic (", nonsys_lot,
       ") or Unrecognized/Non-lymphoma (", bad_lot, ") episodes")
}


# --- SECTION 3: PER-PATIENT LOT SUMMARY (REGL-07) ----

lot_summary <- lot_episodes %>%
  dplyr::filter(!is.na(line_of_therapy)) %>%
  dplyr::group_by(patient_id) %>%
  dplyr::summarise(
    line_1_regimen = {
      ep1 <- regimen_label[line_of_therapy == 1L]
      if (length(ep1) == 0L) NA_character_ else ep1[1L]
    },
    line_1_start = {
      dt1 <- episode_start[line_of_therapy == 1L]
      if (length(dt1) == 0L) as.Date(NA) else min(dt1, na.rm = TRUE)
    },
    n_lines = dplyr::n_distinct(line_of_therapy),
    regimen_per_line = {
      pairs <- dplyr::tibble(lot = line_of_therapy, reg = regimen_label) %>%
        dplyr::distinct() %>%
        dplyr::arrange(lot) %>%
        dplyr::mutate(tok = paste0(lot, ":", reg))
      paste(pairs$tok, collapse = ";")
    },
    .groups = "drop"
  ) %>%
  dplyr::rename(ID = patient_id)

message("[R/205] REGL-07: lot_summary: ", fmt_n(nrow(lot_summary)),
        " patients with >= 1 recognized line; n_lines distribution:")
print(as.data.frame(dplyr::mutate(dplyr::count(lot_summary, n_lines), n = fmt_n(n))),
      row.names = FALSE)

# QC: patients with > 4 lines and the top regimen sequences (labels only, no IDs).
n_gt4 <- sum(lot_summary$n_lines > 4L)
message("[R/205] QC patients with > 4 lines: ", fmt_n(n_gt4))
if (n_gt4 > 0L) {
  top_seq <- lot_summary %>%
    dplyr::filter(n_lines > 4L) %>%
    dplyr::count(regimen_per_line, sort = TRUE, name = "n") %>%
    dplyr::slice_head(n = 10L) %>%
    dplyr::mutate(n = fmt_n(n))
  print(as.data.frame(top_seq), row.names = FALSE)
}

saveRDS(lot_summary, R205_LOT_RDS)
readr::write_csv(lot_summary, R205_LOT_CSV)
message("[R/205] REGL-07: lot_summary written: ", fmt_n(nrow(lot_summary)), " patients - ", R205_LOT_RDS)


# --- SECTION 4: GANTT RECONCILIATION VS PINNED 204 BASELINE (REGL-08) ----

read_gantt <- function(path) {
  g <- vroom::vroom(path, col_types = vroom::cols(.default = "c"), show_col_types = FALSE)
  need <- c("patient_id", "treatment_type", "episode_number", "episode_start",
            "abvd_class", "ever_abvd")
  miss <- setdiff(need, names(g))
  if (length(miss) > 0L) stop("[R/205] ", basename(dirname(path)), "/", basename(path),
                              " missing columns: ", paste(miss, collapse = ", "))
  g
}
g205 <- read_gantt(R205_GANTT_CSV)
g204 <- read_gantt(R205_BASELINE_GANTT)
message("[R/205] Gantt 205: ", nrow(g205), " rows; baseline 204: ", nrow(g204), " rows")

blank_to <- function(x) ifelse(is.na(x) | x == "", "(blank)", x)
keys <- c("patient_id", "treatment_type", "episode_number", "episode_start")
if (anyDuplicated(g204[keys]) > 0L || anyDuplicated(g205[keys]) > 0L) {
  stop("[R/205] Gantt episode key (", paste(keys, collapse = ", "), ") is not unique")
}
ep_cmp <- dplyr::full_join(
  g204 %>% dplyr::select(dplyr::all_of(keys), class_204 = abvd_class, ever_204 = ever_abvd),
  g205 %>% dplyr::select(dplyr::all_of(keys), class_205 = abvd_class, ever_205 = ever_abvd),
  by = keys)
n_only_204 <- sum(is.na(ep_cmp$ever_205) & !is.na(ep_cmp$ever_204))
n_only_205 <- sum(is.na(ep_cmp$ever_204) & !is.na(ep_cmp$ever_205))
message("[R/205] episodes only in 204: ", fmt_n(n_only_204), "; only in 205: ", fmt_n(n_only_205))

chemo <- dplyr::filter(ep_cmp, treatment_type == "Chemotherapy")

# (a) abvd_class 204 x 205 cross-tab (chemotherapy episodes), suppressed.
xtab <- chemo %>%
  dplyr::mutate(class_204 = blank_to(class_204), class_205 = blank_to(class_205)) %>%
  dplyr::count(class_204, class_205, name = "n")
recon_xtab <- xtab %>%
  dplyr::transmute(section = "abvd_class_204_x_205", class_204, class_205,
                   n_display = fmt_n(n))
message("[R/205] abvd_class 204 x 205 (chemotherapy episodes; counts 1-10 shown as <11):")
print(as.data.frame(recon_xtab[, -1]), row.names = FALSE)

# (a2) Drug-set breakdown of every 204 -> 205 class change with n >= 11
# (episode drug sets only, no IDs; sets sorted so order/separator do not matter;
# counts 1-10 shown as <11). Also the BV+AVD / Nivo+AVD residual vs 204 (target 0,
# or a documented reason: Phase 201 anchored on Immunotherapy BV/nivolumab dates
# within +/-ABVD_CONCURRENT_WINDOW_DAYS of the chemo date span; 205 uses any systemic row).
drugset_key <- function(x) {
  vapply(x, function(s) {
    tk <- sort(unique(trimws(unlist(strsplit(ifelse(is.na(s), "", s), "[,;]")))))
    tk <- tk[nzchar(tk)]
    if (length(tk) == 0L) "(none)" else paste(tk, collapse = " + ")
  }, character(1L), USE.NAMES = FALSE)
}
recon_ds <- NULL
if ("drug_names" %in% names(g205)) {
  chg <- chemo %>%
    dplyr::left_join(g205 %>% dplyr::select(dplyr::all_of(keys), drug_names), by = keys) %>%
    dplyr::mutate(class_204 = blank_to(class_204), class_205 = blank_to(class_205)) %>%
    dplyr::filter(class_204 != class_205) %>%
    dplyr::mutate(drug_set = drugset_key(drug_names))
  pairs_n <- chg %>% dplyr::count(class_204, class_205, name = "n_pair") %>%
    dplyr::filter(n_pair >= 11L)
  message("[R/205] 204 -> 205 class changes with n >= 11: ", nrow(pairs_n),
          " pair(s); drug-set breakdown (top 12 sets per pair; counts 1-10 shown as <11):")
  recon_ds <- chg %>%
    dplyr::inner_join(pairs_n, by = c("class_204", "class_205")) %>%
    dplyr::count(class_204, class_205, n_pair, drug_set, name = "n") %>%
    dplyr::arrange(class_204, class_205, dplyr::desc(n)) %>%
    dplyr::group_by(class_204, class_205) %>%
    dplyr::slice_head(n = 12L) %>%
    dplyr::ungroup()
  for (i in seq_len(nrow(pairs_n))) {
    message("  ", pairs_n$class_204[i], " -> ", pairs_n$class_205[i],
            " (n = ", fmt_n(pairs_n$n_pair[i]), ")")
    sub_i <- recon_ds %>%
      dplyr::filter(class_204 == pairs_n$class_204[i], class_205 == pairs_n$class_205[i])
    print(as.data.frame(dplyr::transmute(sub_i, drug_set, n = fmt_n(n))), row.names = FALSE)
  }
  recon_ds <- recon_ds %>%
    dplyr::transmute(section = "drugset_204_to_205", class_204,
                     class_205 = paste0(class_205, " | ", drug_set), n_display = fmt_n(n))
} else {
  message("[R/205] drug_names not in Gantt 205; drug-set breakdown skipped")
}
for (cls in c("BV+AVD", "Nivo+AVD")) {
  n204 <- sum(chemo$class_204 %in% cls)
  n205 <- sum(chemo$class_205 %in% cls)
  n_diff <- sum((chemo$class_204 %in% cls) != (chemo$class_205 %in% cls))
  message("[R/205] ", cls, " residual vs 204: 204 = ", fmt_n(n204), "; 205 = ", fmt_n(n205),
          "; episodes that differ = ", fmt_n(n_diff), " (target 0)")
}

# (a3) Drug sets of the BV+AVD residual episodes (204 vs 205 disagree), by direction.
recon_bv <- NULL
if ("drug_names" %in% names(g205)) {
  bv_res <- chemo %>%
    dplyr::filter((class_204 %in% "BV+AVD") != (class_205 %in% "BV+AVD")) %>%
    dplyr::left_join(g205 %>% dplyr::select(dplyr::all_of(keys), drug_names), by = keys) %>%
    dplyr::mutate(direction = ifelse(class_204 %in% "BV+AVD",
                                     paste0("204 BV+AVD -> 205 ", blank_to(class_205)),
                                     paste0("204 ", blank_to(class_204), " -> 205 BV+AVD")),
                  drug_set = drugset_key(drug_names)) %>%
    dplyr::count(direction, drug_set, name = "n") %>%
    dplyr::arrange(direction, dplyr::desc(n))
  message("[R/205] BV+AVD residual episodes by direction and drug set (counts 1-10 shown as <11):")
  print(as.data.frame(dplyr::transmute(bv_res, direction, drug_set, n = fmt_n(n))), row.names = FALSE)
  recon_bv <- bv_res %>%
    dplyr::transmute(section = "bv_avd_residual_drugsets", class_204 = direction,
                     class_205 = drug_set, n_display = fmt_n(n))
}

# (b) patient-level ever_abvd and first-chemo-ABVD, before / after.
abvd_cls <- c("ABVD", "AVD", "JCODE_ABVD")
pt <- ep_cmp %>%
  dplyr::mutate(start = as.Date(episode_start)) %>%
  dplyr::group_by(patient_id) %>%
  dplyr::summarise(
    ever_204 = any(ever_204 %in% "TRUE"),
    ever_205 = any(ever_205 %in% "TRUE"),
    first_204 = {
      i <- which(treatment_type == "Chemotherapy")
      if (length(i) == 0L) NA else class_204[i[which.min(start[i])]] %in% abvd_cls
    },
    first_205 = {
      i <- which(treatment_type == "Chemotherapy")
      if (length(i) == 0L) NA else class_205[i[which.min(start[i])]] %in% abvd_cls
    },
    .groups = "drop")
recon_pt <- tibble::tibble(
  section   = "patient_level",
  class_204 = c("ever_abvd", "ever_abvd", "ever_abvd", "ever_abvd",
                "first_chemo_abvd", "first_chemo_abvd", "first_chemo_abvd", "first_chemo_abvd"),
  class_205 = c("204 TRUE", "205 TRUE", "both TRUE", "changed",
                "204 TRUE", "205 TRUE", "both TRUE", "changed"),
  n = c(sum(pt$ever_204), sum(pt$ever_205), sum(pt$ever_204 & pt$ever_205),
        sum(pt$ever_204 != pt$ever_205),
        sum(pt$first_204 %in% TRUE), sum(pt$first_205 %in% TRUE),
        sum(pt$first_204 %in% TRUE & pt$first_205 %in% TRUE),
        sum(!is.na(pt$first_204) & !is.na(pt$first_205) & pt$first_204 != pt$first_205))
) %>% dplyr::mutate(n_display = fmt_n(n))
message("[R/205] patient-level before/after (counts 1-10 shown as <11):")
print(as.data.frame(recon_pt[, c("class_204", "class_205", "n_display")]), row.names = FALSE)

# (c) Warn (do not stop) when an ABVD-family class changes by > 5%.
fam_classes <- c("ABVD", "AVD", "BV+AVD", "Nivo+AVD", "ABVD_PLUS")
chk <- tibble::tibble(cls = fam_classes) %>%
  dplyr::rowwise() %>%
  dplyr::mutate(n204 = sum(chemo$class_204 %in% cls),
                n205 = sum(chemo$class_205 %in% cls),
                pct_change = if (n204 >= 11L && n205 >= 11L) 100 * (n205 - n204) / n204 else NA_real_) %>%
  dplyr::ungroup()
for (i in seq_len(nrow(chk))) {
  big <- if (is.na(chk$pct_change[i])) {
    # Either side is 1-10 or 0: flag if the count moved at all and one side is >= 11.
    (chk$n204[i] != chk$n205[i]) && max(chk$n204[i], chk$n205[i]) >= 11L
  } else abs(chk$pct_change[i]) > 5
  if (isTRUE(big)) {
    warning("[R/205] abvd_class '", chk$cls[i], "' changed by > 5% (204 ",
            fmt_n(chk$n204[i]), " -> 205 ", fmt_n(chk$n205[i]),
            if (!is.na(chk$pct_change[i])) sprintf(", %+.1f%%", chk$pct_change[i]) else "",
            ")", call. = FALSE)
  }
}
recon_cls <- chk %>%
  dplyr::transmute(section = "class_totals", class_204 = cls,
                   class_205 = sprintf("204 %s -> 205 %s", fmt_n(n204), fmt_n(n205)),
                   n_display = ifelse(is.na(pct_change), "NA", sprintf("%+.1f%%", pct_change)))

recon <- dplyr::bind_rows(
  recon_xtab,
  recon_pt %>% dplyr::select(section, class_204, class_205, n_display),
  recon_ds,
  recon_bv,
  recon_cls)
readr::write_csv(recon, R205_RECON_CSV)
message("[R/205] reconciliation written: ", nrow(recon), " rows - ", R205_RECON_CSV)
