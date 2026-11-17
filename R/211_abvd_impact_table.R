# ==============================================================================
# Script:  211_abvd_impact_table.R
# Phase:   211 (ABVD-04) -- ABVD/AVD flag impact table, old vs new episode flags
# Purpose: Show how Phase 210 drug-composition flags (abvd_episode / avd_episode)
#          differ from the pre-210 abvd_class-derived flags. Sheets that do not
#          depend on the R/209 workbook; the reconciliation sheet is added in plan 03.
# Inputs:  env R211_OLD180_CSV (default output/internal/gantt_episodes_180_pre210_20261117_120409.csv)
#          env R211_NEW180_CSV (default output/gantt_episodes_180.csv)
#          Column names from R/142 EPISODES_SCHEMA (see utils_abvd_impact.R).
#          BEACOPP components read at run time from REGIMEN_DICT$BEACOPP (R/00_config.R).
# Outputs: output/211_abvd_impact_<RUN_DATE>.xlsx (aggregate counts only; counts 1-10
#          shown as "<11"; no patient IDs, dates or ZIPs).
# Run:     module load R/4.5; R --no-save
#          source("R/211_abvd_impact_table.R", local = new.env(parent = globalenv()))
# ==============================================================================

source(here::here("R", "00_config.R"), local = FALSE)
suppressPackageStartupMessages({
  library(dplyr); library(glue); library(here); library(openxlsx); library(vroom)
})

RUN_DATE <- Sys.getenv("RUN_DATE", format(Sys.Date(), "%Y%m%d"))
message(glue("==== R/211 abvd_impact_table -- RUN DATE {RUN_DATE} ===="))

# Copied verbatim from R/204_gantt_before_after.R:31-36 (prefix changed to R211)
pin_input <- function(env_var, default_rel) {
  v <- Sys.getenv(env_var, "")
  p <- if (nzchar(v)) v else here::here(default_rel)
  if (!file.exists(p)) stop("[R211] input missing: ", p)
  list(path = p, pinned = nzchar(v))
}
pin_old <- pin_input("R211_OLD180_CSV",
                     "output/internal/gantt_episodes_180_pre210_20261117_120409.csv")
pin_new <- pin_input("R211_NEW180_CSV", "output/gantt_episodes_180.csv")

COLS <- ABVD_IMPACT_COLS
FLAG_COLS_EP <- c(COLS$abvd_ep, COLS$avd_ep)

as_flag <- function(x) toupper(trimws(x)) == "TRUE"

read_g <- function(p, need) {
  g <- vroom::vroom(p, col_types = vroom::cols(.default = "c"), show_col_types = FALSE)
  miss <- setdiff(need, names(g))
  if (length(miss) > 0L)
    stop("[R211] missing columns ", paste(miss, collapse = ", "),
         ". Available: ", paste(sort(names(g)), collapse = ", "))
  g
}
need_old <- c(COLS$id, COLS$type, COLS$drugs, COLS$abvd_ep)
need_new <- c(COLS$id, COLS$type, COLS$drugs, COLS$cls, COLS$abvd_ep, COLS$avd_ep)
old <- read_g(pin_old$path, need_old)
new <- read_g(pin_new$path, need_new)
message(glue("  rows old={nrow(old)} new={nrow(new)}"))

# Alignment guard
if (nrow(old) != nrow(new))
  stop("[R211] row counts differ: old=", nrow(old), " new=", nrow(new))
same <- function(a, b) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
mismatch <- sum(!(same(old[[COLS$id]], new[[COLS$id]]) &
                  same(old[[COLS$type]], new[[COLS$type]]) &
                  same(old[[COLS$drugs]], new[[COLS$drugs]])))
message(glue("  alignment mismatches (patient_id/treatment_type/drug_names) = {mismatch}"))
if (mismatch > 0L) stop("[R211] old/new episodes not row-aligned; ", mismatch, " mismatched rows")

# Convert flags to logical
old[[COLS$abvd_ep]] <- as_flag(old[[COLS$abvd_ep]])
for (cc in FLAG_COLS_EP) new[[cc]] <- as_flag(new[[cc]])

# ---- Sheets ------------------------------------------------------------------
sh_class <- suppress_impact_table(episode_crosstab(old, new), "n_episodes")
sh_trans <- suppress_impact_table(episode_transitions(old, new), "n_episodes")
sh_pat   <- suppress_impact_table(patient_flag_compare(old, new), "n_patients")

# ABVD_PLUS with avd_episode TRUE (no bleomycin)
no_bleo <- new[new[[COLS$cls]] %in% "ABVD_PLUS" & new[[COLS$avd_ep]], , drop = FALSE]
n_no_bleo <- nrow(no_bleo)
sh_nobleo <- bind_rows(
  tibble::tibble(pattern = "(all ABVD_PLUS episodes with avd_episode TRUE)", n_episodes = n_no_bleo),
  drug_set_patterns(no_bleo[[COLS$drugs]])
)
sh_nobleo <- suppress_impact_table(sh_nobleo, "n_episodes")

# ABVD-episode TRUE with BEACOPP components beyond the four ABVD drugs
bea <- REGIMEN_DICT$BEACOPP
bea_components <- unique(c(bea$drugs, bea$optional))
if (length(bea_components) == 0L) stop("[R211] REGIMEN_DICT$BEACOPP has no drugs")
is_extra <- beacopp_extra_components(new[[COLS$drugs]], bea_components)
bea_rows <- new[new[[COLS$abvd_ep]] & is_extra, , drop = FALSE]
n_bea <- nrow(bea_rows)
sh_bea <- bind_rows(
  tibble::tibble(pattern = "(all abvd_episode TRUE with extra BEACOPP component)", n_episodes = n_bea),
  drug_set_patterns(bea_rows[[COLS$drugs]])
)
sh_bea <- suppress_impact_table(sh_bea, "n_episodes")

# Patient ever_abvd x ever_avd (new flags, any() per patient)
pt <- new |>
  group_by(.data[[COLS$id]]) |>
  summarise(ev_abvd = any(.data[[COLS$abvd_ep]]), ev_avd = any(.data[[COLS$avd_ep]]),
            .groups = "drop")
sh_ever <- suppress_impact_table(ever_cross(pt$ev_abvd, pt$ev_avd), "n_patients")

# ---- KEY ---------------------------------------------------------------------
key <- tibble::tibble(
  item = c("run_date", "script", "old_csv", "old_csv_pinned", "new_csv", "new_csv_pinned",
           "rows_old", "rows_new", "alignment_mismatches", "suppression",
           "sheets", "reconciliation"),
  value = c(RUN_DATE, "R/211_abvd_impact_table.R",
            pin_old$path, as.character(pin_old$pinned),
            pin_new$path, as.character(pin_new$pinned),
            as.character(nrow(old)), as.character(nrow(new)), as.character(mismatch),
            "Counts 1-10 shown as <11; no patient-level data in this workbook.",
            "episode_by_class, episode_transitions, patient_flags, abvd_plus_no_bleo, abvd_plus_beacopp_comp, ever_abvd_x_avd",
            "Pending (plan 03): R/209 reconciliation sheet not yet included.")
)

# ---- Workbook ----------------------------------------------------------------
sheets <- list(KEY = key, episode_by_class = sh_class, episode_transitions = sh_trans,
               patient_flags = sh_pat, abvd_plus_no_bleo = sh_nobleo,
               abvd_plus_beacopp_comp = sh_bea, ever_abvd_x_avd = sh_ever)

wb <- createWorkbook()
modifyBaseFont(wb, fontSize = 10, fontName = "Arial")
hdr <- createStyle(fontName = "Arial", fontSize = 10, fontColour = "#FFFFFF",
                   fgFill = "#0021A5", textDecoration = "bold")
accent <- createStyle(fontName = "Arial", fontSize = 10, fontColour = "#FFFFFF",
                      fgFill = "#FA4616", textDecoration = "bold")
for (nm in names(sheets)) {
  addWorksheet(wb, nm)
  writeData(wb, nm, as.data.frame(sheets[[nm]]), headerStyle = hdr)
  setColWidths(wb, nm, cols = seq_len(ncol(sheets[[nm]])), widths = "auto")
}
addStyle(wb, "KEY", accent, rows = 1, cols = 1)  # accent on KEY title cell

out_path <- here::here("output", glue("211_abvd_impact_{RUN_DATE}.xlsx"))
saveWorkbook(wb, out_path, overwrite = TRUE)

message(glue("  sheets written: {paste(names(sheets), collapse = ', ')}"))
message(glue("  abvd_plus_no_bleo episodes = {fmt_sup(n_no_bleo)}; beacopp-comp episodes = {fmt_sup(n_bea)}"))
message(glue("  output: {out_path}"))
