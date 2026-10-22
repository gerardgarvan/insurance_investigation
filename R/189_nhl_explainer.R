# ==============================================================================
# R/189_nhl_explainer.R
# ==============================================================================
# Purpose: Generate NHL subset explainer document for clinical team (COMM-01)
# Inputs:  R189_NHL_ONLY, R189_HL_NHL — the two subset files written by R/170
#          (output/internal/nhl_only_episodes_20261008.csv and
#           output/internal/hl_nhl_episodes_20261008.csv; pinned, dated defaults)
# Outputs: output/189-NHL-EXPLAINER-<YYYYMMDD>.md
#          .planning/phases/189-team-deliverables-and-milestone-closeout/189-NHL-EXPLAINER-<YYYYMMDD>.md
# Dependencies: R/00_config.R (here, readr, dplyr); no new packages
# Requirements: COMM-01
# ==============================================================================

source(here::here("R/00_config.R"))
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

run_date  <- format(Sys.Date(), "%Y%m%d")
out_path  <- here::here("output", paste0("189-NHL-EXPLAINER-", run_date, ".md"))
phase_path <- here::here(
  ".planning", "phases",
  "189-team-deliverables-and-milestone-closeout",
  paste0("189-NHL-EXPLAINER-", run_date, ".md")
)

# ------------------------------------------------------------------------------
# Pin the two R/170 subset CSVs (168-01-SUMMARY.md; R/170_nhl_gantt_subsets.R)
# Patient ID column: patient_id (R/170_nhl_gantt_subsets.R lines 212, 260, 267)
# ------------------------------------------------------------------------------
R189_NHL_ONLY <- Sys.getenv(
  "R189_NHL_ONLY",
  unset = here::here("output", "internal", "nhl_only_episodes_20261008.csv")
)
R189_HL_NHL <- Sys.getenv(
  "R189_HL_NHL",
  unset = here::here("output", "internal", "hl_nhl_episodes_20261008.csv")
)

stopifnot(
  file.exists(R189_NHL_ONLY),
  file.exists(R189_HL_NHL)
)

ids_nhl   <- as.character(readr::read_csv(R189_NHL_ONLY,
                                          col_types = cols(.default = "c"),
                                          show_col_types = FALSE)$patient_id)
ids_hlnhl <- as.character(readr::read_csv(R189_HL_NHL,
                                          col_types = cols(.default = "c"),
                                          show_col_types = FALSE)$patient_id)

if (anyNA(ids_nhl) || any(trimws(ids_nhl) == "") ||
    anyNA(ids_hlnhl) || any(trimws(ids_hlnhl) == "")) {
  stop("[R/189] Missing or blank patient IDs in an R/170 subset file.")
}

ids_nhl   <- unique(ids_nhl)
ids_hlnhl <- unique(ids_hlnhl)

N_NHL_ONLY <- length(ids_nhl)
N_HL_NHL   <- length(ids_hlnhl)
N_OVERLAP  <- length(intersect(ids_nhl, ids_hlnhl))

if (N_OVERLAP > 0) {
  stop("[R/189] Subsets overlap (", N_OVERLAP, "); the explainer states they are mutually exclusive.")
}

message("[R/189] NHL-only: ", N_NHL_ONLY, " | HL+NHL: ", N_HL_NHL, " | overlap: ", N_OVERLAP)

# Source citation constants (168-01-SUMMARY.md; plan 189-01 context D-02, D-06)
EPISODE_FILE <- "gantt_episodes_180.csv"
COMBOS_FILE  <- "Chemo_combos_6mo_amc090826-smc"
TAB_NAME     <- "Chemo and Cancer Dx"
COL_E_TO_J   <- c("Definitely HL", "Definitely NHL", "Initial", "Relapse", "Notes", "HL and NHL")

# ------------------------------------------------------------------------------
# Privacy suppression helper (CLAUDE.md; 189-CONTEXT.md D-03)
# ------------------------------------------------------------------------------
suppress_n <- function(n) {
  if (n == 0L)     return("0")
  if (n < 11L)     return("<11")
  as.character(n)
}

# Both subset counts must be independently suppressed;
# if either falls below 11 neither is reported individually.
N_NHL_ONLY_str <- suppress_n(N_NHL_ONLY)
N_HL_NHL_str   <- suppress_n(N_HL_NHL)
N_OVERLAP_str  <- suppress_n(N_OVERLAP)

if (N_NHL_ONLY_str == "<11" || N_HL_NHL_str == "<11") {
  N_NHL_ONLY_str <- "<11"
  N_HL_NHL_str   <- "<11"
}

# ------------------------------------------------------------------------------
# Classification wording (R/170_nhl_gantt_subsets.R, classify_patient_groups()
# lines 79-90; classify_x() lines 51-53; join_ej_chemo_only() lines 96-111)
#
# Group 1 strict (NHL-only): all chemo episodes marked Definitely NHL and none
#   marked Definitely HL or HL and NHL — R/170 classify_patient_groups(), uses
#   group1_strict column built from !any(hl) & all(nhl).
# Group 2 (HL+NHL): any episode marked HL and NHL — R/170
#   classify_patient_groups(), uses group2 column built from any(hlnhl).
# Columns E-J record: cancer-type designation per episode (Definitely HL,
#   Definitely NHL, HL and NHL), treatment line (Initial, Relapse), and
#   free-text notes; joined at (patient_id, episode_number) grain on chemo
#   rows only — non-chemo rows receive NA in columns E-J.
# ------------------------------------------------------------------------------

# Build the analyst footnote column-name string inline (no glue dependency)
col_str <- paste(
  paste0("`", COL_E_TO_J, "`"),
  collapse = ", "
)

lines <- c(
  "# NHL Subset Identification: Summary for Team Review",
  "",
  "## Background",
  "",
  paste0(
    "Patients in the Hodgkin Lymphoma (HL) cohort may have co-occurring non-Hodgkin ",
    "Lymphoma (NHL) diagnoses recorded in their treatment history. To support downstream ",
    "analyses, patients were classified into two subsets based on the cancer-type ",
    "designation assigned to each chemotherapy treatment episode."
  ),
  "",
  "## Classification Approach",
  "",
  paste0(
    "Each chemotherapy row in the treatment episode file was evaluated against the ",
    "cancer-type columns contributed by a left-join at the treatment-period level ",
    "(one row per patient and episode number). Episodes were classified as ",
    '"Definitely NHL", "Definitely HL", or "HL and NHL" based on the content of ',
    "those columns. A patient was assigned to the NHL-only subset if all their ",
    "episodes were classified as Definitely NHL and none were classified as HL or ",
    "HL+NHL. A patient was assigned to the HL+NHL subset if any episode was ",
    "classified as HL and NHL."
  ),
  "",
  paste0(
    "Non-chemotherapy rows in the episode file do not receive cancer-type designations ",
    "and were not used in this classification."
  ),
  "",
  "## Patient Counts",
  "",
  "| Subset       | Patients |",
  "|:-------------|:---------|",
  paste0("| NHL-only     | ", N_NHL_ONLY_str, " |"),
  paste0("| HL and NHL   | ", N_HL_NHL_str,   " |"),
  paste0("| Overlap      | ", N_OVERLAP_str,  " |"),
  "",
  paste0(
    "Counts are derived from the treatment episode file and reflect the episode-level ",
    "classification described above. Patients in the NHL-only and HL+NHL subsets are ",
    "mutually exclusive (zero overlap confirmed)."
  ),
  "",
  "---",
  "",
  paste0(
    "*Analyst note: Episodes from* `", EPISODE_FILE, "` *were joined to the ",
    COMBOS_FILE, " workbook (*`", COMBOS_FILE, "`*), tab \"", TAB_NAME, "\", ",
    "columns E–J (", col_str, "), ",
    "at treatment-period grain; non-chemotherapy rows received empty ",
    "values in columns E–J. Subsets built by R/170; counts read from its dated outputs. ",
    "Generated by R/189_nhl_explainer.R on ", run_date, ".*"
  )
)

# ------------------------------------------------------------------------------
# Write output
# ------------------------------------------------------------------------------
writeLines(lines, out_path)
message("[R/189] Explainer written: ", out_path)

# Copy to phase folder (unchanged — verified byte-for-byte)
if (!isTRUE(file.copy(out_path, phase_path, overwrite = TRUE))) {
  stop("[R/189] Copy to phase folder failed.")
}
if (!identical(readLines(out_path, warn = FALSE), readLines(phase_path, warn = FALSE))) {
  stop("[R/189] Phase copy differs from output copy.")
}
message("[R/189] Phase copy written: ", phase_path)
message("[R/189] Done. Output paths:")
message("  output/  : ", out_path)
message("  phase/   : ", phase_path)
