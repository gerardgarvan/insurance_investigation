# ==============================================================================
# Script:  204_gantt_before_after.R
# Phase:   204 — med-admin-name-based-capture (MCAP-03, replaces the R/26 block)
# Purpose: Compare gantt_episodes_180.csv built WITH Phase 204 against the
#          pre-204 copy. Run AFTER R/28 -> R/52 -> R/142 (the old check inside
#          R/26 ran before those rebuilt the CSVs, so it always passed).
#          Reports rows, episodes and patients by treatment_type, and the
#          patient/episode counts that must not change (abvd_class, ever_abvd,
#          immune_flag, ever_brentuximab). Expected change is Chemotherapy only.
# Inputs:  env R204_PRE180_CSV  (default output/internal/gantt_episodes_180_pre_p204.csv)
#          env R204_POST180_CSV (default output/gantt_episodes_180.csv)
#          Column names from R/142 EPISODES_SCHEMA (patient_id, treatment_type,
#          abvd_class, ever_abvd, immune_flag, ever_brentuximab).
# Outputs: output/204_gantt_before_after_<date>.xlsx (KEY, by_type, flags);
#          no patient-level data.
# Run:     module load R/4.5; R --no-save
#          source("R/204_gantt_before_after.R", local = new.env(parent = globalenv()))
# ==============================================================================

source(here::here("R", "00_config.R"), local = FALSE)
suppressPackageStartupMessages({
  library(dplyr); library(glue); library(here); library(openxlsx); library(vroom)
})

RUN_DATE <- Sys.getenv("RUN_DATE", format(Sys.Date(), "%Y%m%d"))
message(glue("==== R/204 gantt_before_after -- RUN DATE {RUN_DATE} ===="))

COL_ID <- "patient_id"; COL_TYPE <- "treatment_type"; COL_ABVD_CLASS <- "abvd_class"
FLAG_COLS <- c("ever_abvd", "immune_flag", "ever_brentuximab")

pin_input <- function(env_var, default_rel) {
  v <- Sys.getenv(env_var, "")
  p <- if (nzchar(v)) v else here::here(default_rel)
  if (!file.exists(p)) stop("[R204] input missing: ", p)
  list(path = p, pinned = nzchar(v))
}
pin_pre  <- pin_input("R204_PRE180_CSV",  "output/internal/gantt_episodes_180_pre_p204.csv")
pin_post <- pin_input("R204_POST180_CSV", "output/gantt_episodes_180.csv")

read_g <- function(p) {
  g <- vroom::vroom(p, col_types = vroom::cols(.default = "c"), show_col_types = FALSE)
  miss <- setdiff(c(COL_ID, COL_TYPE, COL_ABVD_CLASS, FLAG_COLS), names(g))
  if (length(miss) > 0L)
    stop("[R204] missing columns ", paste(miss, collapse = ", "),
         ". Available: ", paste(sort(names(g)), collapse = ", "))
  g
}
pre  <- read_g(pin_pre$path)
post <- read_g(pin_post$path)
message(glue("  rows pre={nrow(pre)} post={nrow(post)}"))

fmt_sup <- function(n) ifelse(!is.na(n) & n >= 1L & n <= 10L, "<11", format(n, big.mark = ","))

by_type <- function(g) {
  g %>% group_by(.data[[COL_TYPE]]) %>%
    summarise(episodes = n(), patients = n_distinct(.data[[COL_ID]]), .groups = "drop") %>%
    rename(treatment_type = 1)
}
bt <- full_join(by_type(pre), by_type(post), by = "treatment_type", suffix = c("_pre", "_post")) %>%
  mutate(across(-treatment_type, ~ coalesce(.x, 0L)),
         episodes_delta = episodes_post - episodes_pre,
         patients_delta = patients_post - patients_pre)

n_flag <- function(g, col) {
  g %>% filter(toupper(trimws(.data[[col]])) == "TRUE") %>% summarise(n = n_distinct(.data[[COL_ID]])) %>% pull(n)
}
fl <- tibble(
  metric = c(paste0("patients: ", FLAG_COLS)),
  pre  = vapply(FLAG_COLS, function(c) n_flag(pre,  c), integer(1)),
  post = vapply(FLAG_COLS, function(c) n_flag(post, c), integer(1))
)
ac <- function(g) g %>% count(.data[[COL_ABVD_CLASS]], name = "n") %>% rename(level = 1) %>%
  mutate(level = coalesce(level, "(blank)"))
ac_cmp <- full_join(ac(pre), ac(post), by = "level", suffix = c("_pre", "_post")) %>%
  mutate(across(-level, ~ coalesce(.x, 0L))) %>%
  transmute(metric = paste0("episodes: abvd_class = ", level), pre = n_pre, post = n_post)
fl <- bind_rows(fl, ac_cmp) %>% mutate(delta = post - pre)

# Pass/fail: rows may only grow; non-Chemotherapy types and flag/abvd_class counts unchanged.
other_changed <- bt %>% filter(treatment_type != "Chemotherapy",
                               episodes_delta != 0L | patients_delta != 0L)
flags_changed <- fl %>% filter(delta != 0L)
ok_rows  <- nrow(post) >= nrow(pre)
ok_other <- nrow(other_changed) == 0L
ok_flags <- nrow(flags_changed) == 0L
message(glue("  rows grew or equal: {ok_rows}; non-Chemotherapy types unchanged: {ok_other}; ",
             "flag and abvd_class counts unchanged: {ok_flags}"))
chemo <- bt %>% filter(treatment_type == "Chemotherapy")
if (nrow(chemo) == 1L)
  message(glue("  Chemotherapy episodes {fmt_sup(chemo$episodes_pre)} -> {fmt_sup(chemo$episodes_post)}; ",
               "patients {fmt_sup(chemo$patients_pre)} -> {fmt_sup(chemo$patients_post)}"))

fmt_df <- function(d) d %>% mutate(across(where(is.numeric), fmt_sup))
KEY <- tibble(
  item = c("run_date", "script", "input: pre", "pinned: pre", "input: post", "pinned: post",
           "rows pre", "rows post", "check: rows not lower", "check: non-Chemotherapy unchanged",
           "check: flags and abvd_class unchanged", "suppression_note"),
  value = c(RUN_DATE, "R/204_gantt_before_after.R", pin_pre$path, as.character(pin_pre$pinned),
            pin_post$path, as.character(pin_post$pinned), as.character(nrow(pre)),
            as.character(nrow(post)), as.character(ok_rows), as.character(ok_other),
            as.character(ok_flags), "counts 1-10 shown as <11")
)
wb <- createWorkbook()
hdr <- createStyle(fgFill = "#0021A5", fontColour = "#FFFFFF", textDecoration = "bold")
for (nm in c("KEY", "by_type", "flags")) {
  d <- switch(nm, KEY = KEY, by_type = fmt_df(bt), flags = fmt_df(fl))
  addWorksheet(wb, nm); writeData(wb, nm, d, headerStyle = hdr)
  setColWidths(wb, nm, cols = seq_len(ncol(d)), widths = "auto")
}
out_xlsx <- here::here("output", glue("204_gantt_before_after_{RUN_DATE}.xlsx"))
saveWorkbook(wb, out_xlsx, overwrite = TRUE)
message(glue("  wrote {out_xlsx}"))
if (!(ok_rows && ok_other)) stop("[R204] unexpected change outside Chemotherapy; see by_type sheet")
