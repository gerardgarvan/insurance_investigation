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
