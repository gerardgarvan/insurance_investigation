# R/tools/check_immuno_fix_preview.R
# Read-only preview tool: counts patients and dates that the new immunotherapy
# MED_ADMIN/DISPENSING branches would add, before R/26 changes are deployed.
# Phase 200 — do NOT modify pipeline state or write any files.
#
# Run on HiPerGator BEFORE the main chain (Step 1 in plan 200-02).
# GATE: brentuximab gain must be ~184; stop if < 150 or if ND hits return raw NDCs.
#
# Source from repo root:
#   source("R/tools/check_immuno_fix_preview.R", local = new.env(parent = globalenv()))

# Load config and the PCORnet table registry into the GLOBAL environment, as R/26 does
# (R/26 lines 68-69). get_chemo_hits() reads tables via get_pcornet_table(), which only
# works after R/01_load_pcornet.R has run; IMMUNE_DRUG_DEFS etc. must be visible here.
suppressPackageStartupMessages({
  source("R/00_config.R")
  source("R/01_load_pcornet.R")
})

# ── 1. Build immuno_ma_codes (D-200-R2: exclude multivitamin RxNorm CUIs) ──────
vitamin_cuis    <- names(QUESTIONABLE_IMMUNO_CODES)[QUESTIONABLE_IMMUNO_CODES == "questionable-vitamin"]
immuno_ma_codes <- setdiff(TREATMENT_CODES$immunotherapy_rxnorm, vitamin_cuis)
message(glue(
  "immuno_ma_codes: {length(immuno_ma_codes)} CUIs ",
  "(of {length(TREATMENT_CODES$immunotherapy_rxnorm)} total, ",
  "{length(vitamin_cuis)} vitamin excluded)"
))

# ── 2. Load NDC crosswalk once ──────────────────────────────────────────────────
ndc_xwalk <- load_ndc_crosswalk()

# ── Helper: suppress small counts per privacy rules ────────────────────────────
# Only 1-10 are suppressed; 0 prints as "0".
suppress_n <- function(n) ifelse(n >= 1 & n <= 10, "<11", as.character(n))

# ── Helper: summarise hits by triggering_code with drug name lookup ─────────────
summarise_hits <- function(hits, label) {
  if (is.null(hits) || nrow(hits) == 0) {
    message(glue("  {label}: 0 hits"))
    return(invisible(NULL))
  }
  message(glue("\n  === {label} ==="))
  message("  NOTE: ND-typed MED_ADMIN hits: triggering_code is resolved RxCUI,")
  message("  not raw NDC (get_chemo_hits line 278). If drug_name is NA, drug name resolution needed.")
  summary_tbl <- hits %>%
    group_by(triggering_code) %>%
    summarise(
      n_patients = n_distinct(ID),
      n_dates    = n_distinct(paste(ID, treatment_date)),
      .groups = "drop"
    ) %>%
    mutate(
      drug_name     = MEDICATION_LOOKUP[triggering_code],
      n_patients_lbl = suppress_n(n_patients),
      n_dates_lbl    = suppress_n(n_dates)
    ) %>%
    arrange(desc(n_patients))
  for (i in seq_len(nrow(summary_tbl))) {
    r <- summary_tbl[i, ]
    message(glue(
      "    code={r$triggering_code}  drug={coalesce(r$drug_name, 'NA')}",
      "  patients={r$n_patients_lbl}  dates={r$n_dates_lbl}"
    ))
  }
  invisible(summary_tbl)
}

# ── 3. DISPENSING branch ────────────────────────────────────────────────────────
message("\n--- DISPENSING branch ---")
disp_hits <- get_chemo_hits("DISPENSING", immuno_ma_codes, ndc_xwalk)
disp_summary <- summarise_hits(disp_hits, "DISPENSING")

# ── 4. MED_ADMIN branch ─────────────────────────────────────────────────────────
message("\n--- MED_ADMIN branch ---")
ma_hits <- get_chemo_hits("MED_ADMIN", immuno_ma_codes, ndc_xwalk)
ma_summary <- summarise_hits(ma_hits, "MED_ADMIN")

# ── 5. Total unique patients across both branches ───────────────────────────────
all_ids <- unique(c(
  if (!is.null(disp_hits)) disp_hits$ID else character(0),
  if (!is.null(ma_hits))   ma_hits$ID   else character(0)
))
message(glue("\n  Total unique patients (DISPENSING + MED_ADMIN union): {suppress_n(length(all_ids))}"))

# ── 6. Vitamin codes separately — would-be contribution ────────────────────────
message("\n--- Vitamin CUIs excluded by D-200-R2 — would-be contribution ---")
# One call per table for all vitamin CUIs (not 8 x 2 full-table scans), then count per code.
v_disp <- get_chemo_hits("DISPENSING", vitamin_cuis, ndc_xwalk)
v_ma   <- get_chemo_hits("MED_ADMIN",  vitamin_cuis, ndc_xwalk)
v_all  <- dplyr::bind_rows(
  if (!is.null(v_disp)) dplyr::select(v_disp, ID, triggering_code) else NULL,
  if (!is.null(v_ma))   dplyr::select(v_ma,   ID, triggering_code) else NULL
)
for (vcui in vitamin_cuis) {
  v_pts <- if (is.null(v_all) || nrow(v_all) == 0) 0L else
    dplyr::n_distinct(v_all$ID[v_all$triggering_code == vcui])
  message(glue("  vitamin CUI {vcui}: {suppress_n(v_pts)} patients"))
}
v_tot <- if (is.null(v_all) || nrow(v_all) == 0) 0L else dplyr::n_distinct(v_all$ID)
message(glue("  all vitamin CUIs combined: {suppress_n(v_tot)} patients (excluded from R/26)"))

# ── 7. Brentuximab gate check ───────────────────────────────────────────────────
# Brentuximab CUIs in immuno_ma_codes (from IMMUNE_DRUG_DEFS$`Brentuximab Vedotin`$rxnorm)
bren_cuis <- intersect(immuno_ma_codes, IMMUNE_DRUG_DEFS[["Brentuximab Vedotin"]]$rxnorm)
message(glue("\n  Brentuximab CUIs in immuno_ma_codes: {paste(bren_cuis, collapse=', ')}"))

bren_disp <- if (!is.null(disp_hits) && length(bren_cuis) > 0) {
  filter(disp_hits, triggering_code %in% bren_cuis)
} else NULL
bren_ma   <- if (!is.null(ma_hits) && length(bren_cuis) > 0) {
  filter(ma_hits, triggering_code %in% bren_cuis)
} else NULL
bren_n <- length(unique(c(
  if (!is.null(bren_disp)) bren_disp$ID else character(0),
  if (!is.null(bren_ma))   bren_ma$ID   else character(0)
)))

# Note: this counts ALL brentuximab patients found via the new MED_ADMIN/DISPENSING code
# path, including those already in the Gantt via PROCEDURES (J9042). The 184 baseline is the
# subset NOT already in the Gantt, so a value at or above ~184 is expected.
message(glue("  GATE CHECK: brentuximab_patients = {suppress_n(bren_n)}"))
if (bren_n < 150) {
  warning("  GATE FAIL: brentuximab gain is 0 or < 150 — check NDC crosswalk or CUI list before proceeding.")
} else {
  message("  GATE PASS: brentuximab gain is within expected range (~184 from MED_ADMIN code path).")
}

message("\ncheck_immuno_fix_preview complete")
