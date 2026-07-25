# ==============================================================================
# 112_doi_attribution_report.R -- DoI Drug Co-occurrence Attribution Report
# ==============================================================================
# Purpose:     ATTRIBUTION AND OUTPUT investigation script. Reads doi_encounters.rds
#              and doi_patients.rds (R/111, read-only), plus treatment_episode_detail.rds
#              (R/26, read-only). Performs a two-tier drug-admin to DoI encounter
#              linkage (ENCOUNTERID equi-join → ±DOI_ATTRIBUTION_WINDOW_DAYS PATID
#              temporal window), derives the three-state likely_non_lymphoma_directed
#              flag, and (Plan 02) writes doi_attribution_report.xlsx (4 sheets).
#
#              Co-occurrence only — never causal. Every column and comment uses
#              "with [dx]" phrasing. No column uses causal attribution naming.
#
# Inputs:      doi_encounters.rds  (R/111, read-only)
#                Columns: ID, ENCOUNTERID, DX_DATE, doi_code, doi_category,
#                         paraneoplastic_flag, in_hl_cohort
#              doi_patients.rds    (R/111, read-only)
#                Columns: ID, has_any_doi, doi_categories, doi_first_date,
#                         doi_last_date, n_doi_encounters, in_hl_cohort
#              treatment_episode_detail.rds  (R/26, READ-ONLY — must NOT mutate)
#                Columns: patient_id, treatment_type, treatment_date, triggering_code,
#                         ENCOUNTERID, drug_name, episode_number, episode_start,
#                         episode_stop, historical_flag
#              DuckDB DIAGNOSIS table — dated HL-diagnosis pull only (D-03):
#                native DX_TYPE + hl_icd10/hl_icd9 filter, retain DX_DATE, collect()
#
# Outputs:     (Plan 01) doi_drug_links — in-memory data frame with:
#                ID, drug_class, triggering_code, treatment_date, ENCOUNTERID,
#                drug_name, doi_code, doi_category, DX_DATE, paraneoplastic_flag,
#                in_hl_cohort, attribution_method (encounter_id/temporal_window/none),
#                likely_non_lymphoma_directed (TRUE/FALSE/NA — logical, not character)
#              (Plan 02) doi_attribution_report.xlsx (4 sheets)
#
# READ-ONLY w.r.t. R/111 artifacts, treatment_episode_detail.rds, utils_cancer.R,
#              R/28. This script does NOT modify any upstream artifact.
#
# Registration: R/39, SCRIPT_INDEX, R/88 registration is Phase 130 — not done here.
#
# Requirements (this plan): DOI-ATTR-01 (two-tier ENCOUNTERID-then-±window linkage)
#                           DOI-ATTR-02 (three-state likely_non_lymphoma_directed)
#                           DOI-ATTR-03 (attribution_method column; co-occurrence lang)
#              (Plan 02):   DOI-OUT-01, DOI-OUT-02, DOI-OUT-03
#
# Usage:       Rscript R/112_doi_attribution_report.R
#              source("R/112_doi_attribution_report.R")
#
# Note:        Structural-only verification on Windows (no Rscript against real
#              DuckDB). Full run with real DIAGNOSIS counts is HiPerGator ONLY.
#              INTERNAL-ONLY: raw counts, no automated small-cell suppression —
#              suppress manually before external sharing (DOI-OUT-02).
# ==============================================================================


# ==============================================================================
# SECTION 1: SETUP AND LIBRARIES ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(lubridate)
  library(janitor)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_dates.R")

# Defensive sourcing: utils_treatment may already be loaded via R/00_config.R
# auto-source glob; only re-source if the function is absent from search path.
if (!exists("get_hl_patient_ids")) source("R/utils/utils_treatment.R")

message(glue(
  "=== R/112 DoI Drug Co-occurrence Attribution Report ===\n",
  "    Attribution window: ±{DOI_ATTRIBUTION_WINDOW_DAYS} days (DOI_ATTRIBUTION_WINDOW_DAYS)\n",
  "    Plans: 129-01 (linkage + flag) | 129-02 (xlsx write)\n",
  "    READ-ONLY w.r.t. R/111 artifacts, R/26, utils_cancer.R, R/28"
))


# ==============================================================================
# SECTION 2: LOAD INPUTS (READ-ONLY) ----
# ==============================================================================
# Load the three upstream read-only artifacts produced by R/111 and R/26.
# No mutation of these data frames is permitted.

message("\n--- Section 2: Loading inputs ---")

doi_enc <- readRDS(file.path(CONFIG$cache$outputs_dir, "doi_encounters.rds"))
doi_pat <- readRDS(file.path(CONFIG$cache$outputs_dir, "doi_patients.rds"))
tx_detail <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds"))

message(glue("  doi_encounters: {nrow(doi_enc)} rows, {n_distinct(doi_enc$ID)} patients"))
message(glue("  doi_patients:   {nrow(doi_pat)} rows"))
message(glue("  tx_detail:      {nrow(tx_detail)} rows loaded"))

# Build flat rituximab+MTX code vector for triggering_code filter.
# Combines HCPCS and RxNorm CUIs from both code lists (config Section 4d).
rituximab_mtx_codes <- unique(c(
  RITUXIMAB_CODES$hcpcs,
  RITUXIMAB_CODES$rxnorm,
  MTX_CODES$hcpcs,
  MTX_CODES$rxnorm
))

message(glue("  rituximab_mtx_codes: {length(rituximab_mtx_codes)} codes loaded from config"))

# Filter tx_detail to rituximab/MTX administrations only.
# Rename patient_id -> ID for a consistent PATID join key with doi_enc (ID column).
# Retain triggering_code for drug-class labeling and downstream audit.
drug_admins <- tx_detail %>%
  filter(triggering_code %in% rituximab_mtx_codes) %>%
  mutate(
    drug_class = if_else(
      triggering_code %in% c(RITUXIMAB_CODES$hcpcs, RITUXIMAB_CODES$rxnorm),
      "rituximab",
      "methotrexate"
    )
  ) %>%
  rename(ID = patient_id) %>%
  select(ID, treatment_date, triggering_code, ENCOUNTERID, drug_name, drug_class, historical_flag)

message(glue(
  "  drug_admins (rituximab/MTX filtered): {nrow(drug_admins)} rows, ",
  "{n_distinct(drug_admins$ID)} patients"
))


# ==============================================================================
# SECTION 3: DATED HL-DIAGNOSIS PULL (NEW DUCKDB QUERY — D-03) ----
# ==============================================================================
# This is the ONLY new DuckDB query permitted in R/112. Mirrors the HL-code
# filter in get_hl_patient_ids() (utils_treatment.R §62-88) but RETAINS DX_DATE
# for the temporal NA test in Section 5. IDs-only is INSUFFICIENT for the NA
# test (D-03: NA fires when HL dx falls within ±DOI_ATTRIBUTION_WINDOW_DAYS of
# drug admin).
#
# Native-filter ordering: filter() runs in SQL before R collects — DuckDB pushes
# the ICD code predicates down so only HL-matching rows are materialized.
# DuckDB connection teardown is deferred — Plan 02 owns teardown after the xlsx write.

message("\n--- Section 3: Dated HL-diagnosis pull (DuckDB native filter) ---")

USE_DUCKDB <- TRUE
open_pcornet_con()

hl_dx_dated <- get_pcornet_table("DIAGNOSIS") %>%
  filter(
    (DX_TYPE == "10" & DX %in% ICD_CODES$hl_icd10) |
      (DX_TYPE == "09" & DX %in% ICD_CODES$hl_icd9)
  ) %>%
  select(ID, DX_DATE) %>%
  collect()

# Parse dates; drop sentinel 1900 and unparseable NA rows (pipeline convention).
hl_dx_dated <- hl_dx_dated %>%
  mutate(DX_DATE = parse_pcornet_date(DX_DATE)) %>%
  filter(!is.na(DX_DATE) & year(DX_DATE) != 1900L) %>%
  distinct(ID, DX_DATE)

message(glue(
  "  hl_dx_dated: {nrow(hl_dx_dated)} rows, ",
  "{n_distinct(hl_dx_dated$ID)} patients with dated HL diagnosis"
))
# NOTE: DuckDB teardown is deferred to Plan 02 (Plan 01 does not write files).


# ==============================================================================
# SECTION 4: TWO-TIER DRUG↔DoI LINKAGE (DOI-ATTR-01) ----
# ==============================================================================
# Mirrors the ENCOUNTERID-first → temporal-window pattern from R/28 D-01/D-02.
#
# TIER 1: ENCOUNTERID equi-join (higher confidence — same encounter).
#   Guard: filter !is.na(ENCOUNTERID) & ENCOUNTERID != "" on BOTH sides before
#   the join so blank/NA ENCOUNTERIDs do not spuriously match.
#
# TIER 2: ±DOI_ATTRIBUTION_WINDOW_DAYS PATID temporal window (for drug admins
#   NOT matched in tier 1 by ENCOUNTERID). Uses the named constant — never a
#   literal 90.
#
# attribution_method values (DOI-ATTR-03):
#   "encounter_id"    — matched by ENCOUNTERID equi-join (tier 1)
#   "temporal_window" — matched by ±DOI_ATTRIBUTION_WINDOW_DAYS PATID window (tier 2)
#   "none"            — drug admin has no DoI co-occurrence in either tier

message("\n--- Section 4: Two-tier drug↔DoI linkage ---")

# ---- TIER 1: ENCOUNTERID equi-join ----
tier1 <- drug_admins %>%
  filter(!is.na(ENCOUNTERID) & ENCOUNTERID != "") %>%
  inner_join(
    doi_enc %>% filter(!is.na(ENCOUNTERID) & ENCOUNTERID != ""),
    by = "ENCOUNTERID",
    suffix = c("_drug", "_dx")
  ) %>%
  # After the join ID may appear as ID_drug / ID_dx — coalesce to a single ID.
  mutate(
    ID = coalesce(ID_drug, ID_dx),
    attribution_method = "encounter_id"
  ) %>%
  # Standardize to the canonical column set before bind_rows.
  # Retain drug-side ENCOUNTERID (ENCOUNTERID is the join key; no suffix here).
  select(
    ID,
    drug_class, triggering_code, treatment_date, ENCOUNTERID, drug_name, historical_flag,
    doi_code, doi_category, DX_DATE = DX_DATE, paraneoplastic_flag, in_hl_cohort,
    attribution_method
  )

message(glue("  Tier 1 (ENCOUNTERID equi-join): {nrow(tier1)} drug-DoI pairs"))

# ---- TIER 2: ±DOI_ATTRIBUTION_WINDOW_DAYS PATID temporal window ----
# Take drug admins whose (ID, treatment_date, ENCOUNTERID) tuple is not already
# in tier1, PATID-join to doi_enc on ID, then keep pairs within the window.

# Identify drug admins matched in tier 1 (by ID + treatment_date + ENCOUNTERID).
tier1_keys <- tier1 %>%
  select(ID, treatment_date, ENCOUNTERID) %>%
  distinct()

drug_unmatched <- drug_admins %>%
  anti_join(tier1_keys, by = c("ID", "treatment_date", "ENCOUNTERID"))

message(glue("  Unmatched drug admins passed to tier 2: {nrow(drug_unmatched)}"))

tier2 <- drug_unmatched %>%
  inner_join(doi_enc, by = "ID", suffix = c("_drug", "_dx")) %>%
  # Keep pairs where the DoI encounter DX_DATE is within ±DOI_ATTRIBUTION_WINDOW_DAYS
  # of the drug administration date. Named constant, NOT a literal 90.
  filter(
    abs(as.integer(DX_DATE - treatment_date)) <= DOI_ATTRIBUTION_WINDOW_DAYS
  ) %>%
  mutate(attribution_method = "temporal_window") %>%
  # Standardize to the canonical column set; retain drug-side ENCOUNTERID.
  rename(ENCOUNTERID = ENCOUNTERID_drug) %>%
  select(
    ID,
    drug_class, triggering_code, treatment_date, ENCOUNTERID, drug_name, historical_flag,
    doi_code, doi_category, DX_DATE, paraneoplastic_flag, in_hl_cohort,
    attribution_method
  )

message(glue("  Tier 2 (±{DOI_ATTRIBUTION_WINDOW_DAYS}-day PATID window): {nrow(tier2)} drug-DoI pairs"))

# ---- Combine matched tiers ----
doi_drug_links_matched <- bind_rows(tier1, tier2)

message(glue("  Total matched pairs (tier1 + tier2): {nrow(doi_drug_links_matched)}"))

# ---- Drug admins with NO DoI co-occurrence ----
# Represent as rows with doi_category = NA and attribution_method = "none".
# These carry the FALSE flag in Section 5.
matched_drug_keys <- doi_drug_links_matched %>%
  select(ID, treatment_date, ENCOUNTERID) %>%
  distinct()

drug_admins_none <- drug_admins %>%
  anti_join(matched_drug_keys, by = c("ID", "treatment_date", "ENCOUNTERID")) %>%
  mutate(
    doi_code           = NA_character_,
    doi_category       = NA_character_,
    DX_DATE            = as.Date(NA),
    paraneoplastic_flag = NA,
    in_hl_cohort       = NA,
    attribution_method  = "none"
  ) %>%
  select(
    ID,
    drug_class, triggering_code, treatment_date, ENCOUNTERID, drug_name, historical_flag,
    doi_code, doi_category, DX_DATE, paraneoplastic_flag, in_hl_cohort,
    attribution_method
  )

message(glue("  Drug admins with no DoI co-occurrence (attribution_method='none'): {nrow(drug_admins_none)}"))

# ---- Full linked frame (matched + unmatched) ----
# attribution_method takes exactly: "encounter_id" / "temporal_window" / "none"
doi_drug_links <- bind_rows(doi_drug_links_matched, drug_admins_none)

message(glue(
  "  doi_drug_links: {nrow(doi_drug_links)} total rows, ",
  "{n_distinct(doi_drug_links$ID)} patients"
))

# Attribution method distribution (console review)
message("\n  Attribution method tabyl:")
print(janitor::tabyl(doi_drug_links, attribution_method))


# ==============================================================================
# SECTION 5: THREE-STATE likely_non_lymphoma_directed FLAG (DOI-ATTR-02) ----
# ==============================================================================
# For each matched drug↔DoI pair, test whether a dated HL diagnosis is also
# active in the same ±DOI_ATTRIBUTION_WINDOW_DAYS window (D-03). Uses the dated
# hl_dx_dated pull from Section 3 (NOT mere HL-cohort membership — dates required).
#
# Three-state semantics (locked by roadmap, D-03):
#   TRUE  — drug co-occurs with a DoI AND no HL active in the same window
#            (stronger signal: drug more likely for the non-malignant DoI condition)
#   NA    — HL also active in the same ±DOI_ATTRIBUTION_WINDOW_DAYS window
#            (ambiguous — MUST NOT be collapsed to FALSE; this is the clinically
#            interesting state where attribution is genuinely uncertain)
#   FALSE — no drug↔DoI co-occurrence (attribution_method == "none")
#
# Column type: logical (TRUE/FALSE/NA), never character or integer coercion.

message("\n--- Section 5: Three-state likely_non_lymphoma_directed flag ---")

# Compute whether any HL dx date falls within ±DOI_ATTRIBUTION_WINDOW_DAYS of
# each distinct (ID, treatment_date) drug administration in the matched set.
hl_active <- doi_drug_links %>%
  filter(attribution_method != "none") %>%
  select(ID, treatment_date) %>%
  distinct() %>%
  left_join(hl_dx_dated, by = "ID") %>%
  group_by(ID, treatment_date) %>%
  summarise(
    hl_active_in_window = any(
      !is.na(DX_DATE) &
        abs(as.integer(DX_DATE - treatment_date)) <= DOI_ATTRIBUTION_WINDOW_DAYS
    ),
    .groups = "drop"
  )

# Join hl_active back to the full doi_drug_links frame on (ID, treatment_date).
# Unmatched rows (attribution_method == "none") will receive NA from the left join
# but are handled by the first case_when branch below.
doi_drug_links <- doi_drug_links %>%
  left_join(hl_active, by = c("ID", "treatment_date")) %>%
  mutate(
    # Three-state logical flag. Order matters: "none" branch fires first.
    # NA is preserved intentionally (D-03: ambiguous HL+DoI co-occurrence state
    # is clinically distinct from FALSE; collapsing NA→FALSE would undercount
    # the uncertain cases where chart review is required).
    likely_non_lymphoma_directed = case_when(
      attribution_method == "none"  ~ FALSE,  # no drug↔DoI co-occurrence
      hl_active_in_window == TRUE   ~ NA,     # HL also active in same window — ambiguous
      TRUE                          ~ TRUE    # DoI co-occurs AND no HL in window
    )
  ) %>%
  # Drop the intermediate helper column; the flag is what matters downstream.
  select(-hl_active_in_window)

message(glue("  doi_drug_links with three-state flag: {nrow(doi_drug_links)} rows"))

# likely_non_lymphoma_directed distribution (console review).
# Shows TRUE / FALSE / NA counts — NA count is the clinically interesting signal.
message("\n  likely_non_lymphoma_directed tabyl (TRUE/FALSE/NA):")
print(janitor::tabyl(doi_drug_links, likely_non_lymphoma_directed, show_na = TRUE))

message(glue(
  "\n=== Section 5 complete. doi_drug_links ready for Plan 02 sheet assembly. ===\n",
  "    Columns: ID, drug_class, triggering_code, treatment_date, ENCOUNTERID,\n",
  "             drug_name, historical_flag, doi_code, doi_category, DX_DATE,\n",
  "             paraneoplastic_flag, in_hl_cohort, attribution_method,\n",
  "             likely_non_lymphoma_directed\n",
  "    attribution_method values: encounter_id / temporal_window / none\n",
  "    likely_non_lymphoma_directed: TRUE / FALSE / NA (logical, not character)\n",
  "    NOTE: DuckDB teardown happens in Plan 02 after xlsx write.\n",
  "    NOTE: No file written in Plan 01 — Plan 02 owns doi_attribution_report.xlsx."
))


# ==============================================================================
# SECTION 6: SHEET DATA FRAMES (4-SHEET WORKBOOK ASSEMBLY — PLAN 02) ----
# ==============================================================================
# Produces four data frames for doi_attribution_report.xlsx.
# ALL counts are RAW (no suppress_small) — internal-only workbook per D-01 /
# DOI-OUT-02.  in_hl_cohort dimension carried on every sheet per D-02.
#
# Shared note + footnote strings (exact text required by DOI-OUT-02/03 acceptance
# criteria). Defined ONCE here and referenced in Section 7 add_styled_sheet calls.
# ---------------------------------------------------------------------------

message("\n--- Section 6: Building 4-sheet data frames ---")

internal_only_note <- "INTERNAL-ONLY: raw counts, no automated small-cell suppression — suppress manually before external sharing"
caveats_footnote   <- "Co-occurrence does not imply treatment attribution. Clinical chart review required for confirmation."

# ---------------------------------------------------------------------------
# SHEET 1: Patient Prevalence  (patient grain, matched links only)
# Group: in_hl_cohort x doi_category x drug_class
# RAW n_patients / n_encounters; three-state flag breakdowns.
# ---------------------------------------------------------------------------

df_patient_prevalence <- doi_drug_links %>%
  filter(attribution_method != "none") %>%
  group_by(in_hl_cohort, doi_category, drug_class) %>%
  summarise(
    n_patients                      = n_distinct(ID),          # RAW
    n_encounters                    = n_distinct(ENCOUNTERID), # RAW
    # Patient-grain to match n_patients: count DISTINCT patients with >=1 pair in
    # each flag state, not raw pair rows (a patient with 3 TRUE pairs counts once).
    n_patients_likely_non_lymphoma  = n_distinct(ID[likely_non_lymphoma_directed %in% TRUE]),
    n_patients_ambiguous_hl_active  = n_distinct(ID[is.na(likely_non_lymphoma_directed)]),
    .groups = "drop"
  ) %>%
  arrange(desc(in_hl_cohort), doi_category, drug_class)

message(glue("  df_patient_prevalence: {nrow(df_patient_prevalence)} rows"))

# ---------------------------------------------------------------------------
# SHEET 2: Encounter Co-occurrence  (encounter grain — detail sheet)
# Includes attribution_method (DOI-ATTR-03). Column names use "with" language
# (co-occurrence); NO column contains "_for_".
# ---------------------------------------------------------------------------

df_encounter_cooccurrence <- doi_drug_links %>%
  filter(attribution_method != "none") %>%
  select(
    ID,
    treatment_date,
    drug_class,
    drug_name,
    ENCOUNTERID,
    doi_category,
    DX_DATE,
    attribution_method,
    in_hl_cohort,
    likely_non_lymphoma_directed
  )

message(glue("  df_encounter_cooccurrence: {nrow(df_encounter_cooccurrence)} rows (encounter grain)"))

# ---------------------------------------------------------------------------
# SHEET 3: Drug x DoI Summary  (drug x DoI matrix, RAW counts)
# Rare categories (NMO, pemphigus, GPA) will show single-digit cells BY DESIGN.
# No suppress_small per D-01.
# ---------------------------------------------------------------------------

df_drug_doi_summary <- doi_drug_links %>%
  filter(attribution_method != "none") %>%
  group_by(drug_class, doi_category, in_hl_cohort) %>%
  summarise(
    n_patients                 = n_distinct(ID),          # RAW
    n_encounters               = n_distinct(ENCOUNTERID), # RAW
    n_encounter_id_method      = sum(attribution_method == "encounter_id"),
    n_temporal_window_method   = sum(attribution_method == "temporal_window"),
    .groups = "drop"
  ) %>%
  arrange(drug_class, doi_category, desc(in_hl_cohort))

message(glue("  df_drug_doi_summary: {nrow(df_drug_doi_summary)} rows"))

# ---------------------------------------------------------------------------
# SHEET 4: Metadata  (window documentation + sensitivity counts — DOI-OUT-03)
# ±30 / ±90 / ±180 day sensitivity comparison using the inline helper.
# The 90-day count uses the named constant DOI_ATTRIBUTION_WINDOW_DAYS.
# ---------------------------------------------------------------------------

# Attribution method distribution (from doi_drug_links).
attribution_tabyl <- janitor::tabyl(doi_drug_links, attribution_method)

# tabyl omits levels with zero rows, so subsetting $n on an absent level yields
# integer(0). Feeding integer(0) into the tribble below errors ("size 0"). This
# helper coerces any zero-length pick to 0L — applied to BOTH the attribution-
# method counts and the three-state flag counts so a run missing any single
# level (e.g. all matches via encounter_id, so no "temporal_window" row) is safe.
tabyl_count <- function(tab, mask) {
  v <- tab$n[mask]
  if (length(v) == 0L) 0L else as.integer(v)
}

n_matched_encounter_id    <- tabyl_count(attribution_tabyl, attribution_tabyl$attribution_method == "encounter_id")
n_matched_temporal_window <- tabyl_count(attribution_tabyl, attribution_tabyl$attribution_method == "temporal_window")
n_no_cooccurrence         <- tabyl_count(attribution_tabyl, attribution_tabyl$attribution_method == "none")

# Three-state flag counts.
flag_tabyl <- janitor::tabyl(doi_drug_links, likely_non_lymphoma_directed, show_na = TRUE)
n_true  <- tabyl_count(flag_tabyl, !is.na(flag_tabyl$likely_non_lymphoma_directed) & flag_tabyl$likely_non_lymphoma_directed == TRUE)
n_false <- tabyl_count(flag_tabyl, !is.na(flag_tabyl$likely_non_lymphoma_directed) & flag_tabyl$likely_non_lymphoma_directed == FALSE)
n_na    <- tabyl_count(flag_tabyl, is.na(flag_tabyl$likely_non_lymphoma_directed))

# Sensitivity recompute: count temporal-window-style pairs at ±win days.
# Uses drug_admins x doi_enc (raw input tables, not the linked frame) so
# the window is measured cleanly without encounter-tier confounds.
count_window_matches <- function(win) {
  drug_admins %>%
    inner_join(doi_enc, by = "ID") %>%
    filter(abs(as.integer(DX_DATE - treatment_date)) <= win) %>%
    summarise(n_pairs = n(), n_patients = n_distinct(ID))
}

sens_30  <- count_window_matches(30L)
sens_90  <- count_window_matches(DOI_ATTRIBUTION_WINDOW_DAYS)  # named constant — must not be literal 90
sens_180 <- count_window_matches(180L)

df_metadata <- tibble::tribble(
  ~parameter,                          ~value,
  "attribution_window_days",           as.character(DOI_ATTRIBUTION_WINDOW_DAYS),
  "window_rationale",                  "One clinical quarter; RA/psoriasis/IBD indication-to-drug timelines span months",
  "n_drug_admins_total",               as.character(nrow(drug_admins)),
  "n_drug_admins_rituximab",           as.character(sum(drug_admins$drug_class == "rituximab")),
  "n_drug_admins_methotrexate",        as.character(sum(drug_admins$drug_class == "methotrexate")),
  "n_matched_encounter_id",            as.character(n_matched_encounter_id),
  "n_matched_temporal_window",         as.character(n_matched_temporal_window),
  "n_no_cooccurrence",                 as.character(n_no_cooccurrence),
  "n_true_likely_non_lymphoma",        as.character(n_true),
  "n_false_likely_non_lymphoma",       as.character(n_false),
  "n_na_ambiguous_hl_active",          as.character(n_na),
  "sensitivity_30d_pairs",             as.character(sens_30$n_pairs),
  "sensitivity_30d_patients",          as.character(sens_30$n_patients),
  "sensitivity_90d_pairs",             as.character(sens_90$n_pairs),
  "sensitivity_90d_patients",          as.character(sens_90$n_patients),
  "sensitivity_180d_pairs",            as.character(sens_180$n_pairs),
  "sensitivity_180d_patients",         as.character(sens_180$n_patients)
)

message(glue("  df_metadata: {nrow(df_metadata)} rows"))
message("\n=== Section 6 complete. All 4 sheet data frames ready. ===")


# ==============================================================================
# SECTION 7: OPENXLSX2 WORKBOOK ASSEMBLY AND SAVE ----
# ==============================================================================
# Builds doi_attribution_report.xlsx with exactly 4 sheets:
#   1. Patient Prevalence
#   2. Encounter Co-occurrence
#   3. Drug x DoI Summary
#   4. Metadata
#
# Every sheet carries:
#   - Row 1: Title (Calibri 16 bold)
#   - Row 2: Subtitle with internal_only_note + generation date (DOI-OUT-02)
#   - Row 4: Data table (header styled dark gray / white bold, freeze at row 5)
#   - Footer row: caveats_footnote (DOI-OUT-03), 2 rows below last data row
#
# NO suppress_small() — RAW counts per D-01 / DOI-OUT-02.
# ---------------------------------------------------------------------------

message("\n--- Section 7: openxlsx2 workbook assembly ---")

# ---------------------------------------------------------------------------
# DRY helper: add a styled sheet.
# Adapted from R/110 §586-615 (title row 1 / subtitle row 2 / data row 4 /
# freeze row 5).  EXTENDED to write caveats_footnote as a trailing footer row
# on EVERY sheet (DOI-OUT-03).
# ---------------------------------------------------------------------------
add_styled_sheet <- function(wb, sheet_name, title, subtitle_text, data) {
  ncols    <- max(ncol(data), 1L)
  last_col <- if (ncols <= 26L) LETTERS[ncols] else paste0("A", LETTERS[ncols - 26L])

  # Row 1: Title
  wb$add_data(sheet = sheet_name, x = title, start_row = 1, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A1",
              name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
  wb$merge_cells(sheet = sheet_name, dims = glue("A1:{last_col}1"))

  # Row 2: Subtitle (internal-only note + run date)
  wb$add_data(sheet = sheet_name, x = subtitle_text, start_row = 2, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A2",
              name = "Calibri", size = 10, color = wb_color("FF6B7280"))
  wb$merge_cells(sheet = sheet_name, dims = glue("A2:{last_col}2"))

  # Row 4: Data table
  wb$add_data(sheet = sheet_name, x = data, start_row = 4, start_col = 1)

  # Row 4 header styling: dark gray fill + white bold font
  wb$add_fill(sheet = sheet_name, dims = glue("A4:{last_col}4"),
              color = wb_color("FF374151"))
  wb$add_font(sheet = sheet_name, dims = glue("A4:{last_col}4"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

  # Freeze pane below header row
  wb$freeze_pane(sheet = sheet_name, firstActiveRow = 5)

  # Footer row: CAVEATS footnote two rows below last data row (DOI-OUT-03).
  # Guarantees the footnote appears on ALL FOUR sheets.
  footer_row <- 4L + nrow(data) + 2L
  wb$add_data(sheet = sheet_name, x = caveats_footnote,
              start_row = footer_row, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = glue("A{footer_row}"),
              name = "Calibri", size = 9, italic = TRUE, color = wb_color("FF6B7280"))
  wb$merge_cells(sheet = sheet_name, dims = glue("A{footer_row}:{last_col}{footer_row}"))

  wb
}

OUT_XLSX <- file.path(CONFIG$cache$outputs_dir, "doi_attribution_report.xlsx")
run_date <- format(Sys.Date(), "%Y-%m-%d")

# Shared subtitle pattern: internal-only note + generation date.
make_subtitle <- function(sheet_desc) {
  glue("{internal_only_note} | {sheet_desc} | Generated: {run_date}")
}

# ---------------------------------------------------------------------------
# Build workbook: exactly 4 worksheets, exactly these 4 sheet names.
# ---------------------------------------------------------------------------
wb <- wb_workbook()

# Sheet 1: Patient Prevalence
wb$add_worksheet("Patient Prevalence")
wb <- add_styled_sheet(
  wb,
  sheet_name    = "Patient Prevalence",
  title         = "DoI Drug Co-occurrence: Patient Prevalence by in_hl_cohort x DoI Category x Drug Class",
  subtitle_text = make_subtitle("patient grain; matched links only (attribution_method != 'none')"),
  data          = df_patient_prevalence
)

# Sheet 2: Encounter Co-occurrence
wb$add_worksheet("Encounter Co-occurrence")
wb <- add_styled_sheet(
  wb,
  sheet_name    = "Encounter Co-occurrence",
  title         = "DoI Drug Co-occurrence: Encounter-Grain Detail with Attribution Method",
  subtitle_text = make_subtitle("encounter grain; one row per drug-DoI matched pair"),
  data          = df_encounter_cooccurrence
)

# Sheet 3: Drug x DoI Summary
wb$add_worksheet("Drug x DoI Summary")
wb <- add_styled_sheet(
  wb,
  sheet_name    = "Drug x DoI Summary",
  title         = "DoI Drug Co-occurrence: Drug x DoI Matrix — RAW Counts by Attribution Tier",
  subtitle_text = make_subtitle("drug x DoI matrix; rare categories show single-digit cells by design"),
  data          = df_drug_doi_summary
)

# Sheet 4: Metadata
wb$add_worksheet("Metadata")
wb <- add_styled_sheet(
  wb,
  sheet_name    = "Metadata",
  title         = "DoI Attribution Report: Window Parameters and Sensitivity Analysis",
  subtitle_text = make_subtitle(glue("attribution_window_days = {DOI_ATTRIBUTION_WINDOW_DAYS}; sensitivity at ±30/±180 days")),
  data          = df_metadata
)

# ---------------------------------------------------------------------------
# Save workbook — tryCatch so a Windows run with no materialized inputs does
# not hard-fail. Runtime write is verified on HiPerGator in Phase 130.
# ---------------------------------------------------------------------------
tryCatch({
  wb$save(OUT_XLSX)
  message(glue("  Wrote deliverable xlsx: {OUT_XLSX}"))
}, error = function(e) {
  message(glue("  [WARN] Could not write xlsx (expected on Windows with no data): {conditionMessage(e)}"))
})

message("\n=== Section 7 complete. doi_attribution_report.xlsx assembled (4 sheets). ===")


# ==============================================================================
# SECTION 8: TEARDOWN ----
# ==============================================================================
# Close the DuckDB connection opened in Section 3. This script owns teardown.
# Plan 01 deferred this step — Plan 02 (this script continuation) owns it.
# ---------------------------------------------------------------------------

message("\n--- Section 8: Teardown ---")
close_pcornet_con()

message(glue(
  "\n=== R/112 complete. ===\n",
  "    doi_attribution_report.xlsx: 4 sheets (Patient Prevalence, Encounter Co-occurrence,\n",
  "                                           Drug x DoI Summary, Metadata)\n",
  "    RAW counts; internal-only note + CAVEATS footnote on every sheet (D-01/DOI-OUT-02/03).\n",
  "    DuckDB connection closed.\n",
  "    Registration (R/39, SCRIPT_INDEX, R/88 smoke-test) is Phase 130."
))
