# ==============================================================================
# 78_venn_lymphoma_3way.R -- 3-way Venn data: NLPHL vs Classical HL vs NHL
# ==============================================================================
#
# Purpose:
#   Produces data for an external Venn diagram tool with 3 circles:
#   - NLPHL (C81.0x / 201.4x)
#   - Classical HL (C81.1-C81.9 / 201.0-201.3, 201.5-201.9)
#   - NHL (C82-C86 / 200, 202)
#
#   Universe: All patients with any lymphoma diagnosis code in the data.
#
#   For each of the 7 Venn regions + universe, outputs:
#   - n_patients: total patients in that region
#   - n_7day_<type>: 7-day confirmed count for each applicable type
#   - n_7day_all_types: confirmed 7-day in ALL types present in that region
#
# Outputs:
#   - output/venn_lymphoma_3way_summary.csv   (region-level counts for Venn software)
#   - output/venn_lymphoma_3way_patients.csv  (patient-level flags for flexible analysis)
#   - Console summary
#
# Dependencies:
#   - R/00_config.R (CONFIG, ICD_CODES, ICD9_NLPHL_CODES)
#   - R/01_load_pcornet.R (DuckDB connection, get_pcornet_table)
#
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(glue)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

message("\n", strrep("=", 70))
message("3-Way Venn Data: NLPHL vs Classical HL vs NHL")
message(strrep("=", 70))

# ==============================================================================
# SECTION 2: DEFINE NHL CODE PATTERNS ----
# ==============================================================================
# NHL ICD-10-CM codes: C82-C86 (major NHL categories)
#   C82: Follicular lymphoma
#   C83: Non-follicular lymphoma (includes DLBCL, Burkitt, etc.)
#   C84: Mature T/NK-cell lymphomas
#   C85: Other specified and unspecified types of NHL
#   C86: Other specified types of T/NK-cell lymphoma
#
# NHL ICD-9-CM codes: 200.xx, 202.xx
#   200: Lymphosarcoma and reticulosarcoma
#   202: Other malignant neoplasms of lymphoid and histiocytic tissue

NHL_ICD10_PATTERN <- "^C8[2-6]"
NHL_ICD9_PATTERN  <- "^(200|202)"

# ==============================================================================
# SECTION 3: QUERY ALL LYMPHOMA DIAGNOSES ----
# ==============================================================================

message("\nQuerying DIAGNOSIS for all lymphoma codes (HL + NHL)...")

# --- ICD-10 lymphoma rows ---
dx_icd10 <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  select(ID, DX, DX_DATE) %>%
  collect() %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^C8[1-6]"))

# --- ICD-9 lymphoma rows ---
dx_icd9 <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "09") %>%
  select(ID, DX, DX_DATE) %>%
  collect() %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^(200|201|202)"))

message(glue("  ICD-10 lymphoma rows: {format(nrow(dx_icd10), big.mark=',')}"))
message(glue("  ICD-9 lymphoma rows:  {format(nrow(dx_icd9), big.mark=',')}"))

# ==============================================================================
# SECTION 4: CLASSIFY INTO 3 TYPES ----
# ==============================================================================
# Each diagnosis row is classified as NLPHL, Classical HL, or NHL.
# A patient can appear in multiple types if they have codes from each.

# --- NLPHL rows ---
nlphl_rows <- bind_rows(
  dx_icd10 %>% filter(str_detect(DX_norm, "^C810")),
  dx_icd9  %>% filter(DX %in% ICD9_NLPHL_CODES | DX_norm %in% str_remove_all(ICD9_NLPHL_CODES, "\\."))
)

# --- Classical HL rows ---
classical_rows <- bind_rows(
  dx_icd10 %>% filter(str_detect(DX_norm, "^C81") & !str_detect(DX_norm, "^C810")),
  dx_icd9  %>% filter(
    str_detect(DX_norm, "^201") &
      !(DX %in% ICD9_NLPHL_CODES | DX_norm %in% str_remove_all(ICD9_NLPHL_CODES, "\\."))
  )
)

# --- NHL rows ---
nhl_rows <- bind_rows(
  dx_icd10 %>% filter(str_detect(DX_norm, NHL_ICD10_PATTERN)),
  dx_icd9  %>% filter(str_detect(DX_norm, NHL_ICD9_PATTERN))
)

# Unique patient IDs per type
nlphl_ids     <- unique(nlphl_rows$ID)
classical_ids <- unique(classical_rows$ID)
nhl_ids       <- unique(nhl_rows$ID)

# Universe: any patient with at least one lymphoma code
all_lymphoma_ids <- unique(c(nlphl_ids, classical_ids, nhl_ids))

message(glue("\n  NLPHL patients:      {format(length(nlphl_ids), big.mark=',')}"))
message(glue("  Classical HL:        {format(length(classical_ids), big.mark=',')}"))
message(glue("  NHL:                 {format(length(nhl_ids), big.mark=',')}"))
message(glue("  Universe (any):      {format(length(all_lymphoma_ids), big.mark=',')}"))

# ==============================================================================
# SECTION 5: 7-DAY CONFIRMATION PER TYPE ----
# ==============================================================================
# Reuse the same logic from R/77: 2+ unique dates with ≥7 day span.

compute_7day_ids <- function(dx_rows) {
  dx_rows %>%
    filter(!is.na(DX_DATE)) %>%
    distinct(ID, DX_DATE) %>%
    group_by(ID) %>%
    filter(n() >= 2, as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7) %>%
    ungroup() %>%
    pull(ID) %>%
    unique()
}

nlphl_7day_ids     <- compute_7day_ids(nlphl_rows)
classical_7day_ids <- compute_7day_ids(classical_rows)
nhl_7day_ids       <- compute_7day_ids(nhl_rows)

message(glue("\n  7-day confirmed:"))
message(glue("  NLPHL:       {format(length(nlphl_7day_ids), big.mark=',')} / {format(length(nlphl_ids), big.mark=',')}"))
message(glue("  Classical:   {format(length(classical_7day_ids), big.mark=',')} / {format(length(classical_ids), big.mark=',')}"))
message(glue("  NHL:         {format(length(nhl_7day_ids), big.mark=',')} / {format(length(nhl_ids), big.mark=',')}"))

# ==============================================================================
# SECTION 6: COMPUTE 7 VENN REGIONS ----
# ==============================================================================
# 3-circle Venn has 7 exclusive regions:
#   1. NLPHL only
#   2. Classical HL only
#   3. NHL only
#   4. NLPHL ∩ Classical (not NHL)
#   5. NLPHL ∩ NHL (not Classical)
#   6. Classical ∩ NHL (not NLPHL)
#   7. All 3

# Helper: exclusive region membership
in_nlphl     <- all_lymphoma_ids %in% nlphl_ids
in_classical <- all_lymphoma_ids %in% classical_ids
in_nhl       <- all_lymphoma_ids %in% nhl_ids

region_ids <- list(
  nlphl_only        = all_lymphoma_ids[ in_nlphl & !in_classical & !in_nhl],
  classical_only    = all_lymphoma_ids[!in_nlphl &  in_classical & !in_nhl],
  nhl_only          = all_lymphoma_ids[!in_nlphl & !in_classical &  in_nhl],
  nlphl_classical   = all_lymphoma_ids[ in_nlphl &  in_classical & !in_nhl],
  nlphl_nhl         = all_lymphoma_ids[ in_nlphl & !in_classical &  in_nhl],
  classical_nhl     = all_lymphoma_ids[!in_nlphl &  in_classical &  in_nhl],
  all_three         = all_lymphoma_ids[ in_nlphl &  in_classical &  in_nhl]
)

# Sanity check: regions should be mutually exclusive and sum to universe
region_total <- sum(sapply(region_ids, length))
stopifnot(region_total == length(all_lymphoma_ids))

message(glue("\n  Venn regions (exclusive):"))
for (nm in names(region_ids)) {
  message(glue("  {format(nm, width=20)}: {format(length(region_ids[[nm]]), big.mark=',')}"))
}

# ==============================================================================
# SECTION 7: 7-DAY CONFIRMED COUNTS PER REGION ----
# ==============================================================================
# For each region, compute how many patients are 7-day confirmed in each
# applicable type, AND how many are confirmed in ALL applicable types.

compute_region_stats <- function(ids, region_name, applicable_types) {
  n <- length(ids)
  if (n == 0) {
    row <- data.frame(
      region = region_name,
      n_patients = 0,
      stringsAsFactors = FALSE
    )
    for (type in c("nlphl", "classical", "nhl")) {
      row[[paste0("n_7day_", type)]] <- NA_integer_
    }
    row$n_7day_all_applicable <- 0L
    return(row)
  }

  # 7-day confirmed in each individual type
  n_7day_nlphl     <- if ("nlphl" %in% applicable_types)     length(intersect(ids, nlphl_7day_ids))     else NA_integer_
  n_7day_classical <- if ("classical" %in% applicable_types) length(intersect(ids, classical_7day_ids)) else NA_integer_
  n_7day_nhl       <- if ("nhl" %in% applicable_types)       length(intersect(ids, nhl_7day_ids))       else NA_integer_

  # Confirmed 7-day in ALL applicable types simultaneously
  confirmed_in_all <- ids
  if ("nlphl" %in% applicable_types)     confirmed_in_all <- intersect(confirmed_in_all, nlphl_7day_ids)
  if ("classical" %in% applicable_types) confirmed_in_all <- intersect(confirmed_in_all, classical_7day_ids)
  if ("nhl" %in% applicable_types)       confirmed_in_all <- intersect(confirmed_in_all, nhl_7day_ids)

  data.frame(
    region               = region_name,
    n_patients           = n,
    n_7day_nlphl         = n_7day_nlphl,
    n_7day_classical     = n_7day_classical,
    n_7day_nhl           = n_7day_nhl,
    n_7day_all_applicable = length(confirmed_in_all),
    stringsAsFactors     = FALSE
  )
}

# Applicable types for each region
region_types <- list(
  nlphl_only      = "nlphl",
  classical_only  = "classical",
  nhl_only        = "nhl",
  nlphl_classical = c("nlphl", "classical"),
  nlphl_nhl       = c("nlphl", "nhl"),
  classical_nhl   = c("classical", "nhl"),
  all_three       = c("nlphl", "classical", "nhl")
)

summary_rows <- lapply(names(region_ids), function(nm) {
  compute_region_stats(region_ids[[nm]], nm, region_types[[nm]])
})

# Add universe totals row
universe_row <- data.frame(
  region               = "UNIVERSE",
  n_patients           = length(all_lymphoma_ids),
  n_7day_nlphl         = length(nlphl_7day_ids),
  n_7day_classical     = length(classical_7day_ids),
  n_7day_nhl           = length(nhl_7day_ids),
  n_7day_all_applicable = length(
    Reduce(intersect, list(nlphl_7day_ids, classical_7day_ids, nhl_7day_ids))
  ),
  stringsAsFactors = FALSE
)

summary_df <- bind_rows(summary_rows, universe_row)

# ==============================================================================
# SECTION 8: PATIENT-LEVEL FLAGS ----
# ==============================================================================
# One row per patient, with binary flags for each type + 7-day status.
# External Venn tools (InteractiVenn, DeepVenn, etc.) can consume this directly.

patient_flags <- data.frame(
  ID              = all_lymphoma_ids,
  has_nlphl       = as.integer(all_lymphoma_ids %in% nlphl_ids),
  has_classical   = as.integer(all_lymphoma_ids %in% classical_ids),
  has_nhl         = as.integer(all_lymphoma_ids %in% nhl_ids),
  confirmed_7day_nlphl     = as.integer(all_lymphoma_ids %in% nlphl_7day_ids),
  confirmed_7day_classical = as.integer(all_lymphoma_ids %in% classical_7day_ids),
  confirmed_7day_nhl       = as.integer(all_lymphoma_ids %in% nhl_7day_ids),
  stringsAsFactors = FALSE
)

# Derive region label for convenience
patient_flags <- patient_flags %>%
  mutate(
    venn_region = case_when(
      has_nlphl == 1 & has_classical == 1 & has_nhl == 1 ~ "all_three",
      has_nlphl == 1 & has_classical == 1 & has_nhl == 0 ~ "nlphl_classical",
      has_nlphl == 1 & has_classical == 0 & has_nhl == 1 ~ "nlphl_nhl",
      has_nlphl == 0 & has_classical == 1 & has_nhl == 1 ~ "classical_nhl",
      has_nlphl == 1 & has_classical == 0 & has_nhl == 0 ~ "nlphl_only",
      has_nlphl == 0 & has_classical == 1 & has_nhl == 0 ~ "classical_only",
      has_nlphl == 0 & has_classical == 0 & has_nhl == 1 ~ "nhl_only",
      TRUE ~ "unknown"
    )
  )

# ==============================================================================
# SECTION 9: OUTPUT ----
# ==============================================================================

summary_path <- build_output_path("venn", "venn_lymphoma_3way_summary.csv")
patient_path <- build_output_path("venn", "venn_lymphoma_3way_patients.csv")

write.csv(summary_df, summary_path, row.names = FALSE)
write.csv(patient_flags, patient_path, row.names = FALSE)

message(glue("\n  Summary CSV: {summary_path}"))
message(glue("  Patient CSV: {patient_path}"))

# --- Console summary ---
message("\n", strrep("-", 70))
message("REGION SUMMARY (for Venn diagram input)")
message(strrep("-", 70))
message(glue("{'Region',-22} {'N',>8} {'7d NLPHL',>10} {'7d CHL',>8} {'7d NHL',>8} {'7d All',>8}"))
message(strrep("-", 70))

for (i in seq_len(nrow(summary_df))) {
  row <- summary_df[i, ]
  fmt <- function(x) if (is.na(x)) "   --" else format(x, big.mark = ",", width = 8)
  message(glue("{row$region,-22} {format(row$n_patients, big.mark=',', width=8)} {fmt(row$n_7day_nlphl),>10} {fmt(row$n_7day_classical),>8} {fmt(row$n_7day_nhl),>8} {fmt(row$n_7day_all_applicable),>8}"))
}

message(strrep("-", 70))

# --- Print set lists for tools like InteractiVenn ---
message("\nSet membership lists (for copy-paste into Venn tools):")
message(glue("  NLPHL set:      {length(nlphl_ids)} patients"))
message(glue("  Classical set:  {length(classical_ids)} patients"))
message(glue("  NHL set:        {length(nhl_ids)} patients"))

message("\n", strrep("=", 70))
message("3-way Venn data export complete")
message(strrep("=", 70))
