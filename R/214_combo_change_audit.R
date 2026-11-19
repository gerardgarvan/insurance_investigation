# ==============================================================================
# 214_combo_change_audit.R -- Phase 214: chemo combination change audit (old vs new Gantt)
# ==============================================================================
# Read-only audit. Accounts for every change in the set of distinct chemo drug_names
# combinations between the old list (chemo_combo_check.csv) and the new Gantt
# (unique_chemo_drugs.csv / gantt_episodes_180.csv), and attributes a cause per
# affected episode by matching old and new Gantt episodes (COMBO-01..06).
# Does not change cohort membership, 7-day logic or D-201-04.
#
# Decisions (headless): Q-214-01 unit = episode-level drug_names string compared after
# normalisation; Q-214-02 blank row kept as "(blank)" and counted by treatment_type
# (it is excluded from the 314/161/29/21 classification); Q-214-04 cause (b) wording
# stays "consistent with".
#
# Input names: Gantt columns from R/206 SCHEMA_32. No .planning/schemas/214 probe has
# been read yet, so the constants below are # UNVERIFIED until the output of
# R/tools/214_probe_combo_inputs.R is checked on HiPerGator. CSV headers were read
# locally (chemo_combo_check.csv: drug_names; unique_chemo_drugs.csv: drug_names;
# change list: status, combination_normalized, old_file_string, new_file_string,
# related_combination, hypothesized_cause_UNCONFIRMED).
#
# Pinned inputs (env var, dated default; KEY records pinned TRUE/FALSE):
#   R214_OLD_GANTT      CONFIG$gantt_180_snapshot_path (gantt_episodes_180_20260814_PINNED.csv)
#   R214_OLD_GANTT_ALT  optional comma-separated explicit extra old candidates
#   R214_NEW_GANTT      output/gantt_episodes_180.csv
#   R214_OLD_COMBOS     docs/combo_audit/chemo_combo_check.csv
#   R214_NEW_COMBOS     docs/combo_audit/unique_chemo_drugs.csv
#   R214_CHANGE_LIST    docs/combo_audit/combo_change_list_2026-11-19.csv
#
# Outputs: output/internal/214_combo_change_audit_YYYYMMDD.xlsx (real counts, no IDs/dates)
#          output/214_combo_change_audit_team_YYYYMMDD.xlsx (counts 1-10 -> "<11")
#
# Run interactively on HiPerGator:
#   module load R/4.5; R --no-save
#   source("R/214_combo_change_audit.R", local = new.env(parent = globalenv()))
# ==============================================================================

suppressPackageStartupMessages({ library(dplyr); library(glue); library(openxlsx) })
source("R/00_config.R")
message("=== R/214: Chemo combination change audit ===\n")

# --- column-name constants (R/206 SCHEMA_32) -- UNVERIFIED until probe is read -----
COL_PID <- "patient_id"; COL_TYPE <- "treatment_type"
COL_START <- "episode_start"; COL_STOP <- "episode_stop"
COL_DRUGS <- "drug_names"; COL_CODES <- "triggering_codes"
COL_SRC <- "source_table"; COL_CTYPE <- "code_type"
COL_TR_NHL <- "tr_nhl_dx"
CHEMO_TYPE <- "Chemotherapy"
REF_COUNTS <- c(unchanged = 314L, label_only = 161L, new = 29L, dropped = 21L)
UF_BLUE <- "0021A5"; UF_ORANGE <- "FA4616"
DRUGS_ABSENT_OLD <- c("Brentuximab Vedotin", "Nivolumab", "Pembrolizumab")
# Rituximab/Methotrexate codes from config (not typed here); Phase 200 added J8610 and the
# rituximab CUI/J-codes. Config does not flag which entries were new, so all are listed.
ADDED_CODES <- unique(c(RITUXIMAB_CODES$hcpcs, RITUXIMAB_CODES$rxnorm, MTX_CODES$hcpcs, MTX_CODES$rxnorm))
MED_TABLES <- c("MED_ADMIN", "DISPENSING")   # Phase 200 R/26 capture-fix tables

# --- pinned inputs -------------------------------------------------------------------
pin <- function(var, default) {
  v <- Sys.getenv(var, unset = ""); pinned <- nzchar(v)
  p <- if (pinned) v else default
  if (is.null(p) || !file.exists(p)) stop("[R214] pinned input missing: ", var, " -> ", p)
  list(var = var, path = p, pinned = pinned)
}
P <- list(
  old_gantt = pin("R214_OLD_GANTT", CONFIG$gantt_180_snapshot_path),
  new_gantt = pin("R214_NEW_GANTT", file.path(CONFIG$output_dir, "gantt_episodes_180.csv")),
  old_combos = pin("R214_OLD_COMBOS", "docs/combo_audit/chemo_combo_check.csv"),
  new_combos = pin("R214_NEW_COMBOS", "docs/combo_audit/unique_chemo_drugs.csv"),
  change_list = pin("R214_CHANGE_LIST", "docs/combo_audit/combo_change_list_2026-11-19.csv")
)
alt <- strsplit(Sys.getenv("R214_OLD_GANTT_ALT", unset = ""), ",", fixed = TRUE)[[1]]
alt <- alt[nzchar(alt)]
if (length(alt) > 0L && !all(file.exists(alt))) stop("[R214] R214_OLD_GANTT_ALT file(s) missing")

read_list <- function(f) {                      # one drug_names string per line; BOM/quotes stripped
  x <- readLines(f, warn = FALSE, encoding = "UTF-8")
  gsub('^"|"$', "", sub("^﻿", "", x))[-1]
}
read_gantt <- function(f) {
  g <- read.csv(f, stringsAsFactors = FALSE, colClasses = "character", na.strings = c("NA", ""))
  need <- c(COL_PID, COL_TYPE, COL_START, COL_STOP, COL_DRUGS)
  if (length(setdiff(need, names(g))) > 0L)
    stop("[R214] ", basename(f), ": missing columns ", paste(setdiff(need, names(g)), collapse = ", "))
  g[[COL_START]] <- as.Date(g[[COL_START]]); g[[COL_STOP]] <- as.Date(g[[COL_STOP]])
  g
}
fmt <- function(n) format(n, big.mark = ",", trim = TRUE)

# --- COMBO-01: classify -------------------------------------------------------------
old_raw <- read_list(P$old_combos$path); new_raw <- read_list(P$new_combos$path)
old_raw_nb <- old_raw[nzchar(trimws(old_raw))]; new_raw_nb <- new_raw[nzchar(trimws(new_raw))]
cl <- classify_combos(old_raw_nb, new_raw_nb)
cnt <- table(factor(cl$status, levels = names(REF_COUNTS)))
message(glue("[COMBO-01] old={length(old_raw_nb)} new={length(new_raw_nb)} (+{length(new_raw) - length(new_raw_nb)} blank) | ",
             "unchanged={cnt[['unchanged']]} label_only={cnt[['label_only']]} new={cnt[['new']]} dropped={cnt[['dropped']]}"))

# --- COMBO-02: old snapshot reproduces chemo_combo_check.csv --------------------------
chemo_keys <- function(g) {
  d <- g[[COL_DRUGS]][g[[COL_TYPE]] == CHEMO_TYPE & !is.na(g[[COL_DRUGS]])]
  sort(setdiff(unique(normalise_combo(d)), COMBO_BLANK_KEY))
}
target_keys <- sort(unique(normalise_combo(old_raw_nb)))
cands <- unique(c(P$old_gantt$path, alt))
old_g <- NULL; old_path <- NA_character_; cand_rows <- list()
for (cf in cands) {
  g <- read_gantt(cf); k <- chemo_keys(g)
  extra <- length(setdiff(k, target_keys)); miss <- length(setdiff(target_keys, k))
  cand_rows[[cf]] <- data.frame(candidate = basename(cf), extra = extra, missing = miss, stringsAsFactors = FALSE)
  message(glue("[COMBO-02] candidate {basename(cf)}: extra={extra} missing={miss}"))
  if (extra == 0L && miss == 0L && is.null(old_g)) { old_g <- g; old_path <- cf }
}
if (is.null(old_g)) stop("[R214] COMBO-02: no old Gantt candidate reproduces chemo_combo_check.csv (see per-candidate counts above). ",
                         "Set R214_OLD_GANTT / R214_OLD_GANTT_ALT to explicit files and rerun.")
new_g <- read_gantt(P$new_gantt$path)
old_c <- old_g[old_g[[COL_TYPE]] == CHEMO_TYPE, , drop = FALSE]
new_c <- new_g[new_g[[COL_TYPE]] == CHEMO_TYPE, , drop = FALSE]
old_c$drug_key <- normalise_combo(old_c[[COL_DRUGS]]); new_c$drug_key <- normalise_combo(new_c[[COL_DRUGS]])
message(glue("[COMBO-02] old snapshot {basename(old_path)}: chemo episodes={fmt(nrow(old_c))}; new Gantt chemo episodes={fmt(nrow(new_c))}"))

# --- COMBO-03: episodes and patients per new / dropped combination ----------------------
count_by_key <- function(df, keys) {
  df %>% filter(drug_key %in% keys) %>% group_by(combination_normalized = drug_key) %>%
    summarise(n_episodes = n(), n_patients = n_distinct(.data[[COL_PID]]), .groups = "drop")
}
new_keys <- cl$combination_normalized[cl$status == "new"]
drop_keys <- cl$combination_normalized[cl$status == "dropped"]
fill0 <- function(x) { x$n_episodes[is.na(x$n_episodes)] <- 0L; x$n_patients[is.na(x$n_patients)] <- 0L; x }
new_tbl <- cl %>% filter(status == "new") %>% left_join(count_by_key(new_c, new_keys), by = "combination_normalized") %>% fill0()
drop_tbl <- cl %>% filter(status == "dropped") %>% left_join(count_by_key(old_c, drop_keys), by = "combination_normalized") %>% fill0()
message(glue("[COMBO-03] new combos: {nrow(new_tbl)} ({fmt(sum(new_tbl$n_episodes))} episodes); ",
             "dropped: {nrow(drop_tbl)} ({fmt(sum(drop_tbl$n_episodes))} episodes)"))

# --- COMBO-04: episode matching and cause -------------------------------------------------
in_old <- unique(old_g[[COL_PID]]); in_new <- unique(new_g[[COL_PID]])
mt <- match_episodes(old_c, new_c)
aff_new <- which(new_c$drug_key %in% new_keys)      # new-side episodes carrying a "new" combination
aff_old <- which(old_c$drug_key %in% drop_keys)     # old-side episodes carrying a "dropped" combination
cause_rows <- list()
for (i in aff_new) {
  p <- mt[mt$new_row == i, , drop = FALSE]
  ok <- if (nrow(p)) old_c$drug_key[p$old_row[1]] else NA_character_
  pt <- if (nrow(p)) p$pair_type[1] else NA_character_
  cz <- attribute_cause(ok, new_c$drug_key[i], new_c[[COL_PID]][i] %in% in_old, TRUE, pt)
  codes_i <- if (COL_CODES %in% names(new_c)) new_c[[COL_CODES]][i] else NA_character_
  cause_rows[[length(cause_rows) + 1L]] <- data.frame(
    side = "new", combination_normalized = new_c$drug_key[i], cause = cz,
    added = if (cz == "b") combo_added_drugs(ok, new_c$drug_key[i]) else NA_character_,
    source_table = if (COL_SRC %in% names(new_c)) new_c[[COL_SRC]][i] else NA_character_,
    code_type = if (COL_CTYPE %in% names(new_c)) new_c[[COL_CTYPE]][i] else NA_character_,
    code_hit = if (is.na(codes_i)) NA else any(vapply(ADDED_CODES, grepl, logical(1), x = codes_i, fixed = TRUE)),
    stringsAsFactors = FALSE)
}
for (i in aff_old) {
  p <- mt[mt$old_row == i, , drop = FALSE]
  nk <- if (nrow(p)) new_c$drug_key[p$new_row[1]] else NA_character_
  pt <- if (nrow(p)) p$pair_type[1] else NA_character_
  cz <- attribute_cause(old_c$drug_key[i], nk, TRUE, old_c[[COL_PID]][i] %in% in_new, pt)
  cause_rows[[length(cause_rows) + 1L]] <- data.frame(
    side = "dropped", combination_normalized = old_c$drug_key[i], cause = cz,
    added = NA_character_, source_table = NA_character_, code_type = NA_character_, code_hit = NA,
    stringsAsFactors = FALSE)
}
causes <- bind_rows(cause_rows)
# Cause (b) wording is "consistent with", never "confirmed" (Q-214-04)
rm_added <- grepl("Rituximab|Methotrexate", causes$added)
causes$b_note <- ifelse(causes$cause != "b", NA_character_,
  ifelse(causes$source_table %in% MED_TABLES, "consistent with Phase 200 R/26 MED_ADMIN/DISPENSING capture fix",
  ifelse(rm_added & causes$code_hit %in% TRUE, "consistent with added Rituximab/Methotrexate codes", "other source")))
roll <- rollup_cause(causes)
cause_summary <- causes %>% count(side, cause, name = "n_episodes") %>% arrange(side, cause)
b_summary <- causes %>% filter(cause == "b") %>% count(added, source_table, code_type, b_note, name = "n_episodes") %>%
  arrange(desc(n_episodes))
cc <- table(causes$cause)
message(glue("[COMBO-04] affected episodes: new side={length(aff_new)}, dropped side={length(aff_old)}; combos with primary cause={nrow(roll)}"))
message("[COMBO-04] episodes by cause: ", paste(names(cc), as.integer(cc), sep = "=", collapse = " "))
new_tbl <- new_tbl %>% left_join(roll[, c("combination_normalized", "primary_cause")], by = "combination_normalized")
drop_tbl <- drop_tbl %>% left_join(roll[, c("combination_normalized", "primary_cause")], by = "combination_normalized")

# Change-list hypothesis is compared with the computed cause, never copied into results (A-214-09)
chg <- read.csv(P$change_list$path, stringsAsFactors = FALSE)
hyp <- chg %>% filter(status %in% c("new", "dropped")) %>%
  select(combination_normalized, hypothesis_UNCONFIRMED = hypothesized_cause_UNCONFIRMED) %>%
  left_join(roll[, c("combination_normalized", "primary_cause")], by = "combination_normalized")
# Cause (e): patients absent from the new Gantt, and how many carry the tr_nhl_dx flag on the old Gantt
e_pat <- old_c[aff_old, , drop = FALSE]; e_pat <- e_pat[!(e_pat[[COL_PID]] %in% in_new), , drop = FALSE]
n_e_pat <- n_distinct(e_pat[[COL_PID]])
n_e_trnhl <- if (COL_TR_NHL %in% names(e_pat))
  n_distinct(e_pat[[COL_PID]][tolower(e_pat[[COL_TR_NHL]]) %in% c("true", "1", "yes")]) else NA_integer_

# --- COMBO-05: specific checks --------------------------------------------------------------
rit_rel <- chg %>% filter(status == "new", grepl("Old combination plus Rituximab", hypothesized_cause_UNCONFIRMED, fixed = TRUE))
drug_has <- function(keys, d) vapply(keys, function(k) d %in% combo_drugs(k), logical(1))
new_all_keys <- sort(unique(normalise_combo(new_raw_nb)))
chk_all <- bind_rows(
  data.frame(check = "old combination + Rituximab (change-list rows)", n_combos = nrow(rit_rel),
             n_in_new_list = sum(rit_rel$combination_normalized %in% new_all_keys), n_in_old_list = NA_integer_),
  bind_rows(lapply(DRUGS_ABSENT_OLD, function(d) data.frame(
    check = paste0("combinations containing ", d), n_combos = sum(drug_has(new_all_keys, d)),
    n_in_new_list = sum(drug_has(new_all_keys, d)), n_in_old_list = sum(drug_has(target_keys, d))))),
  data.frame(check = "Ofatumumab", n_combos = NA_integer_,
             n_in_new_list = sum(drug_has(new_all_keys, "Ofatumumab")), n_in_old_list = sum(drug_has(target_keys, "Ofatumumab"))))
blank_new <- new_g[is.na(new_g[[COL_DRUGS]]) | !nzchar(trimws(new_g[[COL_DRUGS]])), , drop = FALSE]
chk_blank <- blank_new %>% count(treatment_type = .data[[COL_TYPE]], name = "n_episodes")
message(glue("[COMBO-05] Rituximab-plus change-list rows={nrow(rit_rel)}; blank drug_names episodes in new Gantt={nrow(blank_new)} (",
             "{paste(chk_blank$treatment_type, chk_blank$n_episodes, sep = '=', collapse = ', ')})"))

# --- QC -------------------------------------------------------------------------------------------
qc <- bind_rows(
  data.frame(check = paste0("count ", names(REF_COUNTS), " vs reference"),
             value = paste0(as.integer(cnt), " vs ", REF_COUNTS),
             note = ifelse(as.integer(cnt) == REF_COUNTS, "matches", "DIFFERS (reported, not a failure)")),
  data.frame(check = "old snapshot reproduces old list", value = basename(old_path), note = "yes"),
  data.frame(check = "combinations with a computed primary cause / change-list rows new+dropped",
             value = paste0(sum(!is.na(hyp$primary_cause)), " / ", nrow(hyp)),
             note = "hypothesis text is free text; see Hypothesis_check sheet"),
  data.frame(check = "cause (e) patients / of which tr_nhl_dx TRUE", value = paste0(n_e_pat, " / ", n_e_trnhl), note = ""),
  data.frame(check = paste0("candidate ", names(cand_rows)),
             value = vapply(cand_rows, function(r) paste0("extra=", r$extra, " missing=", r$missing), ""), note = ""))

# --- COMBO-06: workbooks ----------------------------------------------------------------------------------
key <- data.frame(
  item = c("run date", "old Gantt used", "new Gantt", "old combos", "new combos", "change list",
           paste0("pinned: ", c("old Gantt", "new Gantt", "old combos", "new combos", "change list")), "scope"),
  value = c(format(Sys.Date()), basename(old_path), basename(P$new_gantt$path), basename(P$old_combos$path),
            basename(P$new_combos$path), basename(P$change_list$path), vapply(P, function(x) as.character(x$pinned), ""),
            "Read-only audit; counts of combinations/episodes/patients; no IDs or dates"),
  stringsAsFactors = FALSE)
label_only <- cl %>% filter(status == "label_only") %>% select(combination_normalized, old_file_string, new_file_string)
write_wb <- function(path, sheets) {
  wb <- createWorkbook(); modifyBaseFont(wb, fontName = "Arial", fontSize = 10)
  hs <- createStyle(fontName = "Arial", fontColour = "#FFFFFF", fgFill = paste0("#", UF_BLUE), textDecoration = "bold")
  for (nm in names(sheets)) {
    addWorksheet(wb, nm, tabColour = if (nm == "KEY") paste0("#", UF_ORANGE) else paste0("#", UF_BLUE))
    writeData(wb, nm, sheets[[nm]], headerStyle = hs)
    setColWidths(wb, nm, cols = seq_len(ncol(sheets[[nm]])), widths = "auto")
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  saveWorkbook(wb, path, overwrite = TRUE)
}
sheets <- list(KEY = key, New_combinations = new_tbl, Dropped_combinations = drop_tbl, Label_only = label_only,
               Cause_summary = cause_summary, Cause_b_detail = b_summary, Hypothesis_check = hyp,
               Specific_checks = chk_all, Blank_by_treatment_type = chk_blank, QC = qc)
stamp <- format(Sys.Date(), "%Y%m%d")
f_int <- file.path("output", "internal", paste0("214_combo_change_audit_", stamp, ".xlsx"))
f_team <- file.path("output", paste0("214_combo_change_audit_team_", stamp, ".xlsx"))
write_wb(f_int, sheets)
team <- sheets
team$New_combinations <- suppress_combo_counts(team$New_combinations, c("n_episodes", "n_patients"))
team$Dropped_combinations <- suppress_combo_counts(team$Dropped_combinations, c("n_episodes", "n_patients"))
team$Cause_summary <- suppress_combo_counts(team$Cause_summary, "n_episodes")
team$Cause_b_detail <- suppress_combo_counts(team$Cause_b_detail, "n_episodes")
team$Specific_checks <- suppress_combo_counts(team$Specific_checks, c("n_combos", "n_in_new_list", "n_in_old_list"))
team$Blank_by_treatment_type <- suppress_combo_counts(team$Blank_by_treatment_type, "n_episodes")
team$QC <- qc[!grepl("^cause \\(e\\)", qc$check), ]
write_wb(f_team, team)
message(glue("[COMBO-06] wrote {f_int} and {f_team} (KEY first; team copy suppressed 1-10 -> <11)"))
message("=== R/214 complete ===")
