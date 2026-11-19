# ==============================================================================
# R/tools/214_probe_combo_inputs.R -- schema probe for Phase 214 inputs
# ==============================================================================
# Writes .planning/schemas/214_schema_<date>.md (names, types, counts; no values).
# The three reference CSVs probe locally; the Gantt files exist on HiPerGator only.
# Run from the repo root (interactive R):
#   source("R/tools/214_probe_combo_inputs.R", local = new.env(parent = globalenv()))
# ==============================================================================
source("R/00_config.R")
files <- c(
  "docs/combo_audit/chemo_combo_check.csv",
  "docs/combo_audit/unique_chemo_drugs.csv",
  "docs/combo_audit/combo_change_list_2026-11-19.csv"
)
if (!IS_LOCAL) {
  files <- c(files,
    Sys.getenv("R214_OLD_GANTT", unset = CONFIG$gantt_180_snapshot_path),
    Sys.getenv("R214_NEW_GANTT", unset = file.path(CONFIG$output_dir, "gantt_episodes_180.csv")),
    # explicit pre-v3.15 backup candidates: list them here by name after `ls output/internal/pre_v315_backup/`
    strsplit(Sys.getenv("R214_PROBE_EXTRA", unset = ""), ",", fixed = TRUE)[[1]])
  files <- files[nzchar(files)]
}
probe_inputs("214", files = files)
message("[214 probe] wrote .planning/schemas/214_schema_*.md for ", length(files), " files")
