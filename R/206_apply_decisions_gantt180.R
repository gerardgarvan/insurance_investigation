# ==============================================================================
# R/206_apply_decisions_gantt180.R
# Apply the 2026-11-14 team decisions to the delivered Phase 204 Gantt file.
#
#   (A) D-201-01 = NO : GnRH-agonist supportive agents do NOT make an episode
#       ABVD_PLUS. Chemotherapy rows that are ABVD_PLUS in the base (Phase 204)
#       file and carry one of {ABVD, AVD, BV+AVD, Nivo+AVD} in the Phase 205
#       candidate take the Phase 205 abvd_class.
#   (B) 205-2 = NO    : ABVD/AVD partial does NOT count toward ever_abvd. No new
#       Phase 205 label is introduced; every other row/column is left as in base.
#   (C) Phase 210 rule: abvd_episode / avd_episode are recomputed from drug_names
#       (plus J-code evidence in triggering_codes; JCODE_ABVD fallback) with
#       compute_abvd_avd_flags() (ABVD-01/02). ever_abvd / ever_avd = any() over the
#       patient's rows. ever_abvd_plus is deprecated (old definition kept). Output
#       has 34 columns. AVD_INCLUDES_BV_NIVO is honoured.
#
# Inputs (pinned, env-overridable; stop if missing):
#   R206_BASE_GANTT  default output/internal/pre205_run_backup/gantt_episodes_180.csv
#   R206_P205_GANTT  default output/internal/p205_candidate_v4/gantt_episodes_180.csv
# Outputs:
#   output/gantt_episodes_180.csv                          (34 cols: 32 base + avd_episode, ever_avd)
#   output/gantt_episodes_180_flag_dictionary.csv          (no patient data)
#   output/internal/gantt_episodes_180_pre_decisions_20261114.csv (copy, no overwrite)
#   output/internal/decisions_20261114_changes.csv         (internal only)
# Interactive HiPerGator only: source("R/206_apply_decisions_gantt180.R",
#   local = new.env(parent = globalenv()))
# ==============================================================================

suppressPackageStartupMessages(library(here))
source(here::here("R", "00_config.R"), local = FALSE)
stopifnot(exists("compute_abvd_avd_flags"))

BASE_GANTT <- Sys.getenv("R206_BASE_GANTT",
  here::here("output", "internal", "pre205_run_backup", "gantt_episodes_180.csv"))
P205_GANTT <- Sys.getenv("R206_P205_GANTT",
  here::here("output", "internal", "p205_candidate_v4", "gantt_episodes_180.csv"))
LIVE_GANTT <- here::here("output", "gantt_episodes_180.csv")
PRE_COPY   <- here::here("output", "internal", "gantt_episodes_180_pre_decisions_20261114.csv")
CHANGES_CSV <- here::here("output", "internal", "decisions_20261114_changes.csv")

EXPECTED_ROWS <- 22548L
TAKE_P205_CLASSES <- c("ABVD", "AVD", "BV+AVD", "Nivo+AVD")
# Same 32 columns / order as R/142 EPISODES_SCHEMA (Phase 201b).
SCHEMA_32 <- c(
  "patient_id", "treatment_type", "episode_number",
  "episode_start", "episode_stop", "episode_length_days",
  "distinct_dates_in_episode",
  "triggering_codes", "drug_names", "triggering_code_descriptions",
  "cancer_category", "is_hodgkin",
  "drug_group",
  "code_type", "source_table", "sct_cross_use_flag",
  "episode_dx_codes", "episode_dx_categories",
  "episode_dx_7day_confirmed", "age_at_episode",
  "has_autoimmune_dx", "first_autoimmune_dx_date",
  "autoimmune_dx_code_system",
  "immune_flag", "ever_brentuximab", "immune_flag_dx",
  "ever_abvd", "abvd_episode", "tr_hl_dx", "tr_nhl_dx",
  "abvd_class", "ever_abvd_plus"
)
# Phase 210: same order as R/142 EPISODES_SCHEMA
SCHEMA_34 <- c(SCHEMA_32, "avd_episode", "ever_avd")

fmt_sup <- function(n) if (n >= 1L && n <= 10L) "<11" else format(n, big.mark = ",")
qc_fail <- function(...) stop("R/206 QC FAIL: ", ..., call. = FALSE)
qc_ok   <- function(msg) message("  OK: ", msg)

read_chr <- function(path) {
  utils::read.csv(path, colClasses = "character", na.strings = "",
                  check.names = FALSE, stringsAsFactors = FALSE)
}
ep_key <- function(d) paste(d$patient_id, d$treatment_type, d$episode_start, sep = "\r")

message("R/206: apply 2026-11-14 decisions to gantt_episodes_180.csv")
for (p in c(BASE_GANTT, P205_GANTT, LIVE_GANTT)) {
  if (!file.exists(p)) stop("Input missing (stop): ", p, call. = FALSE)
}
message("  base: ", BASE_GANTT, " (pinned = ", nzchar(Sys.getenv("R206_BASE_GANTT")), ")")
message("  p205: ", P205_GANTT, " (pinned = ", nzchar(Sys.getenv("R206_P205_GANTT")), ")")

base <- read_chr(BASE_GANTT)
p205 <- read_chr(P205_GANTT)
message("  rows: base ", nrow(base), ", p205 ", nrow(p205))

# ---- QC: inputs ---------------------------------------------------------------
if (!identical(names(base), SCHEMA_32)) qc_fail("base columns differ from the 32-column schema")
if (!all(SCHEMA_32 %in% names(p205)))   qc_fail("p205 file lacks required columns")
if (nrow(base) != EXPECTED_ROWS) qc_fail(sprintf("base rows %d != %d", nrow(base), EXPECTED_ROWS))
if (nrow(p205) != EXPECTED_ROWS) qc_fail(sprintf("p205 rows %d != %d", nrow(p205), EXPECTED_ROWS))
kb <- ep_key(base); kp <- ep_key(p205)
if (anyDuplicated(kb)) qc_fail("duplicate patient_id + treatment_type + episode_start in base")
if (anyDuplicated(kp)) qc_fail("duplicate patient_id + treatment_type + episode_start in p205")
if (!setequal(kb, kp)) qc_fail("base and p205 episode keys are not 1:1")
qc_ok("join key unique and 1:1; row counts both match expected")

# ---- Apply decisions ------------------------------------------------------------
p205_class <- p205$abvd_class[match(kb, kp)]
is_chemo   <- !is.na(base$treatment_type) & base$treatment_type == "Chemotherapy"
changed    <- is_chemo & !is.na(base$abvd_class) & base$abvd_class == "ABVD_PLUS" &
              !is.na(p205_class) & p205_class %in% TAKE_P205_CLASSES

out <- base
out$abvd_class[changed] <- p205_class[changed]

message("  AVD_INCLUDES_BV_NIVO = ", AVD_INCLUDES_BV_NIVO)
# Phase 210: flags from drug_names (+ J-code evidence in triggering_codes); abvd_class
# (final, after the decision logic above) only feeds the JCODE_ABVD fallback.
fl <- compute_abvd_avd_flags(out$drug_names, out$treatment_type,
                             abvd_class = out$abvd_class, code_text = out$triggering_codes)
stopifnot("abvd_episode and avd_episode mutually exclusive" = !any(fl$abvd_episode & fl$avd_episode))
tf <- function(x) ifelse(x, "TRUE", "FALSE")
out$abvd_episode <- tf(fl$abvd_episode)
out$avd_episode  <- tf(fl$avd_episode)
out$ever_abvd    <- tf(patient_ever_flag(out$patient_id, fl$abvd_episode))
out$ever_avd     <- tf(patient_ever_flag(out$patient_id, fl$avd_episode))
# ever_abvd_plus: DEPRECATED (Phase 210); old definition kept.
ever_plus_pt <- tapply(!is.na(out$abvd_class) & out$abvd_class == "ABVD_PLUS",
                       out$patient_id, any)
out$ever_abvd_plus <- as.character(ifelse(ever_plus_pt[out$patient_id], "TRUE", "FALSE"))
out <- out[, SCHEMA_34]
n_jfb <- sum(fl$abvd_jcode_fallback)

# ---- QC: results ----------------------------------------------------------------
message("\nQC")
if (!identical(names(out), SCHEMA_34)) qc_fail("output schema differs from the 34-column schema")
if (nrow(out) != EXPECTED_ROWS)        qc_fail("output row count changed")
qc_ok(sprintf("schema identical (34 columns, same order); rows = %s", fmt_sup(nrow(out))))

new_vals <- setdiff(unique(out$abvd_class[!is.na(out$abvd_class)]),
                    unique(base$abvd_class[!is.na(base$abvd_class)]))
if (length(new_vals)) qc_fail("new abvd_class values introduced: ", paste(new_vals, collapse = ", "))
qc_ok("no new abvd_class values")

untouched <- setdiff(SCHEMA_32, c("abvd_class", "abvd_episode", "ever_abvd", "ever_abvd_plus"))
for (cn in untouched) {
  if (!identical(out[[cn]], base[[cn]])) qc_fail("unexpected change in column ", cn)
}
qc_ok("all other 28 columns identical to base")
if (any(out$abvd_class[!changed] != base$abvd_class[!changed], na.rm = TRUE) ||
    !identical(is.na(out$abvd_class), is.na(base$abvd_class))) {
  qc_fail("abvd_class changed on rows outside the decision set")
}
for (cn in c("ever_abvd", "ever_avd", "ever_abvd_plus")) {
  if (any(tapply(out[[cn]], out$patient_id, function(x) length(unique(x))) != 1L)) {
    qc_fail(cn, " not constant within patient")
  }
}
for (pr in list(c("ever_abvd", "abvd_episode"), c("ever_avd", "avd_episode"))) {
  pt_any <- tapply(out[[pr[2]]] == "TRUE", out$patient_id, any)
  if (!identical(unname(as.logical(pt_any[out$patient_id])), out[[pr[1]]] == "TRUE"))
    qc_fail(pr[1], " does not equal any(", pr[2], ") over the patient")
}
qc_ok("ever_abvd / ever_avd / ever_abvd_plus constant within patient; ever_* = any(episode flag)")
if (any(out$abvd_episode == "TRUE" & !is_chemo)) qc_fail("abvd_episode TRUE on a non-Chemotherapy row")
if (any(out$avd_episode == "TRUE" & !is_chemo))  qc_fail("avd_episode TRUE on a non-Chemotherapy row")
if (any(out$abvd_episode == "TRUE" & out$avd_episode == "TRUE")) qc_fail("a row has both abvd_episode and avd_episode TRUE")
qc_ok("flags only on Chemotherapy rows; abvd_episode and avd_episode never both TRUE")
# Informational (intended change from base; not a failure).
xt <- table(base = base$abvd_episode, new = out$abvd_episode)
message("  info: abvd_episode base vs new (episodes)")
for (b in c("FALSE", "TRUE")) for (nw in c("FALSE", "TRUE")) {
  v <- if (b %in% rownames(xt) && nw %in% colnames(xt)) as.integer(xt[b, nw]) else 0L
  message(sprintf("    base %s -> new %s: %s", b, nw, fmt_sup(v)))
}
message("  info: avd_episode TRUE episodes by abvd_class:\n",
        tab_str_pre <- {
          x <- out$abvd_class[out$avd_episode == "TRUE"]
          if (!length(x)) "    (none)" else {
            t <- table(ifelse(is.na(x), "(NA)", x))
            paste0("    ", names(t), ": ", vapply(as.integer(t), fmt_sup, ""), collapse = "\n")
          }
        })

# ---- Console summary ------------------------------------------------------------
tab_str <- function(x) {
  t <- table(ifelse(is.na(x), "(NA, non-chemo)", x))
  paste0("    ", names(t), ": ", vapply(as.integer(t), fmt_sup, ""), collapse = "\n")
}
n_pt <- function(flag, d) fmt_sup(length(unique(d$patient_id[d[[flag]] == "TRUE"])))
message("\nabvd_class BEFORE:\n", tab_str(base$abvd_class))
message("abvd_class AFTER:\n",  tab_str(out$abvd_class))
message(sprintf("ever_abvd patients:      before %s, after %s", n_pt("ever_abvd", base), n_pt("ever_abvd", out)))
message(sprintf("ever_avd patients:       after %s", n_pt("ever_avd", out)))
message(sprintf("abvd_episode episodes:   after %s; avd_episode episodes: after %s",
                fmt_sup(sum(out$abvd_episode == "TRUE")), fmt_sup(sum(out$avd_episode == "TRUE"))))
message("JCODE_ABVD fallback episodes (no drug/code evidence, abvd_episode kept TRUE): ", fmt_sup(n_jfb))
message(sprintf("ever_abvd_plus patients: before %s, after %s", n_pt("ever_abvd_plus", base), n_pt("ever_abvd_plus", out)))
message(sprintf("changed episodes: %s; changed patients: %s",
                fmt_sup(sum(changed)), fmt_sup(length(unique(base$patient_id[changed])))))

# ---- Write ----------------------------------------------------------------------
dir.create(dirname(PRE_COPY), recursive = TRUE, showWarnings = FALSE)
if (file.exists(PRE_COPY)) {
  message("  pre-decisions copy already exists, not overwritten: ", PRE_COPY)
} else {
  if (!file.copy(LIVE_GANTT, PRE_COPY, overwrite = FALSE)) qc_fail("could not copy live file to pre-decisions backup")
  message("  wrote pre-decisions copy: ", PRE_COPY)
}

chg <- data.frame(
  patient_id = base$patient_id[changed], episode_start = base$episode_start[changed],
  old_class = base$abvd_class[changed], new_class = out$abvd_class[changed],
  drug_names = base$drug_names[changed], stringsAsFactors = FALSE)
utils::write.csv(chg, CHANGES_CSV, row.names = FALSE, na = "")
message("  wrote ", CHANGES_CSV, " (internal; ", nrow(chg), " rows)")

# Quote only text-typed columns (logical/numeric stay bare), as write.csv does
# for the typed frame in R/142; NA written as blank.
is_text <- vapply(out, function(x) is.character(utils::type.convert(x, as.is = TRUE, na.strings = "")),
                  logical(1))
utils::write.csv(out, LIVE_GANTT, row.names = FALSE, na = "", quote = which(is_text))
chk <- read_chr(LIVE_GANTT)
if (!identical(names(chk), SCHEMA_34) || nrow(chk) != EXPECTED_ROWS) qc_fail("written file failed read-back check")
if (!identical(chk, out)) { bad <- names(out)[!vapply(names(out), function(cn) identical(chk[[cn]], out[[cn]]), NA)]; qc_fail("written file does not round-trip to the in-memory result; columns: ", paste(bad, collapse = ","), "; attrs equal: ", isTRUE(all.equal(attributes(chk), attributes(out)))) }
message("  wrote ", LIVE_GANTT, " (", ncol(chk), " columns, ", fmt_sup(nrow(chk)), " rows); read-back OK")

# Flag dictionary (no patient data) plus QC row for Phase 211.
dict <- abvd_flag_dictionary()
dict <- rbind(dict, data.frame(
  column = "qc: jcode_abvd_fallback_episodes", level = "qc",
  definition = fmt_sup(n_jfb), status = "qc", stringsAsFactors = FALSE))
DICT_CSV <- here::here("output", "gantt_episodes_180_flag_dictionary.csv")
utils::write.csv(dict, DICT_CSV, row.names = FALSE, na = "")
message("  wrote ", DICT_CSV, " (", nrow(dict), " rows)")
message("R/206 done")
