# ==============================================================================
# R/192_source_step0_probe.R -- Phase 192.3 Step-0 SOURCE Discovery Probe
# ==============================================================================
#
# Purpose:
#   Discover ENCOUNTER SOURCE values in the HL cohort and LDS_ADDRESS_HISTORY
#   SOURCE values, characterise encounter/address temporal match quality, and
#   count SOURCE distribution in the far/CBC analysis set.
#   Console output only — no RDS or workbook written.
#   Run interactively: source("R/192_source_step0_probe.R", local = new.env(parent = globalenv()))
#
# Inputs (all pinned via env vars with dated defaults):
#   R192_ENC_DISTANCE_RDS  -- Phase 122 enc_distance RDS (same pin as R165/R183)
#
#   cbc_events and anchors are derived from DuckDB at runtime (same approach as
#   R/165_distance_cbc_association.R, which does not save those as RDS files).
#   Optional overrides via R192_CBC_EVENTS_RDS and R192_ANCHORS_RDS: if the env
#   var is set AND the file exists, the RDS is loaded instead. Leave unset on
#   first run (DuckDB derivation is used automatically).
#
# Outputs: console only (paste block to planner)
# Requirements: 192.3-D-01, 192.3-D-02
# ==============================================================================

# ==============================================================================
# SECTION 0: SETUP ----
# ==============================================================================

source("R/00_config.R")
# 00_config.R auto-sources utils_distance_cbc.R, utils_duckdb.R — verify key symbols
stopifnot(
  "CONFIG not found after sourcing R/00_config.R"                            = exists("CONFIG"),
  "open_pcornet_con not found — utils_duckdb.R not sourced"                 = exists("open_pcornet_con"),
  "build_enc_analysis not found — utils_distance_cbc.R not sourced"         = exists("build_enc_analysis"),
  "suppress_display not found — utils_distance_cbc.R not sourced"           = exists("suppress_display")
)
message("[R/192] R/00_config.R sourced OK — CONFIG, open_pcornet_con, build_enc_analysis, suppress_display present.")

# ==============================================================================
# SECTION 1: ENV-VAR PINS ----
# ==============================================================================

ENC_DISTANCE_RDS <- Sys.getenv(
  "R192_ENC_DISTANCE_RDS",
  unset = file.path(CONFIG$output_dir, "encounter_distance_20261015.rds")
)
if (!file.exists(ENC_DISTANCE_RDS)) stop("[R/192] File not found: ", ENC_DISTANCE_RDS)
message("[R/192] ENC_DISTANCE_RDS: ", ENC_DISTANCE_RDS)

# Optional RDS overrides for cbc_events and anchors.
# If the env var is set AND the file exists, load it; otherwise derive from DuckDB.
CBC_EVENTS_RDS_OVERRIDE <- Sys.getenv("R192_CBC_EVENTS_RDS", unset = "")
ANCHORS_RDS_OVERRIDE    <- Sys.getenv("R192_ANCHORS_RDS",    unset = "")

use_cbc_rds     <- nzchar(CBC_EVENTS_RDS_OVERRIDE) && file.exists(CBC_EVENTS_RDS_OVERRIDE)
use_anchors_rds <- nzchar(ANCHORS_RDS_OVERRIDE)    && file.exists(ANCHORS_RDS_OVERRIDE)

if (use_cbc_rds)     message("[R/192] CBC_EVENTS_RDS override: ", CBC_EVENTS_RDS_OVERRIDE)
if (use_anchors_rds) message("[R/192] ANCHORS_RDS override: ",    ANCHORS_RDS_OVERRIDE)

# ==============================================================================
# SECTION 2: LOAD ENC_DISTANCE; OPEN DUCKDB ----
# ==============================================================================

enc_distance_raw <- readRDS(ENC_DISTANCE_RDS)
message("[R/192] enc_distance_raw rows: ", format(nrow(enc_distance_raw), big.mark = ","))

hl_ids <- enc_distance_raw |> dplyr::distinct(ID)

# Open DuckDB once; closed explicitly after all DuckDB queries complete.
open_pcornet_con()

# ==============================================================================
# SECTION (a): ENCOUNTER SOURCE freq for HL cohort (DuckDB) ----
# ==============================================================================

message("[R/192] SECTION (a): ENCOUNTER SOURCE freq ...")

enc_source_raw <- DBI::dbGetQuery(
  pcornet_con,
  "SELECT ID, ENCOUNTERID, ADMIT_DATE, DISCHARGE_DATE, SOURCE FROM ENCOUNTER"
) |>
  dplyr::semi_join(hl_ids, by = "ID") |>
  dplyr::mutate(
    ADMIT_DATE     = as.Date(ADMIT_DATE),
    DISCHARGE_DATE = as.Date(DISCHARGE_DATE)
  )

# Build cbc_events and anchors from DuckDB (same approach as R/165) unless RDS
# overrides are present.
cohort_ids <- unique(enc_distance_raw$ID)

if (use_cbc_rds) {
  cbc_events <- readRDS(CBC_EVENTS_RDS_OVERRIDE)
  message("[R/192] cbc_events loaded from RDS: ", nrow(cbc_events), " rows")
} else {
  message("[R/192] Building cbc_events from DuckDB via build_cbc_events() ...")
  cbc_events <- build_cbc_events(pcornet_con, cohort_ids)
  message("[R/192] cbc_events rows: ", format(nrow(cbc_events), big.mark = ","))
}

if (use_anchors_rds) {
  anchors <- readRDS(ANCHORS_RDS_OVERRIDE)
  message("[R/192] anchors loaded from RDS: ", nrow(anchors), " rows")
} else {
  message("[R/192] Fetching anchor dates via get_hl_any_dx_ids() ...")
  anchors <- get_hl_any_dx_ids()
  message("[R/192] anchors rows: ", nrow(anchors), "; missing anchor: ",
          sum(is.na(anchors$hl_anchor_date)))
}

# Explicit close — on.exit is the safety net
close_pcornet_con()
message("[R/192] DuckDB connection closed.")

# Duplicate ENCOUNTERID count
n_dup_encounterid <- sum(duplicated(enc_source_raw$ENCOUNTERID))

# SOURCE freq with suppression
enc_source_freq <- enc_source_raw |>
  dplyr::count(SOURCE, name = "n_encounters", sort = TRUE) |>
  dplyr::mutate(n_display = suppress_display(n_encounters))

# ==============================================================================
# SECTION (b): LDS_ADDRESS_HISTORY SOURCE freq + missingness ----
# ==============================================================================

message("[R/192] SECTION (b): LDS_ADDRESS_HISTORY SOURCE freq ...")

ADDR_PATH <- file.path(CONFIG$data_dir, "LDS_ADDRESS_HISTORY_Mailhot_V1.csv")
if (!file.exists(ADDR_PATH)) stop("[R/192] Address file not found: ", ADDR_PATH)

addr_raw <- vroom::vroom(ADDR_PATH, col_types = vroom::cols(.default = "c"), progress = FALSE)
message("[R/192] addr_raw rows: ", format(nrow(addr_raw), big.mark = ","))

addr_source_freq <- addr_raw |>
  dplyr::count(SOURCE, name = "n_rows", sort = TRUE) |>
  dplyr::mutate(n_display = suppress_display(n_rows))

n_addr_missing_source <- sum(is.na(addr_raw$SOURCE) | trimws(addr_raw$SOURCE) == "")

# Restrict to cohort and compute overlapping address periods
addr_cohort <- addr_raw |>
  dplyr::semi_join(hl_ids, by = "ID") |>
  dplyr::mutate(
    period_start = as.Date(ADDRESS_PERIOD_START),
    period_end   = dplyr::if_else(
      is.na(ADDRESS_PERIOD_END) | trimws(ADDRESS_PERIOD_END) == "",
      as.Date("9999-12-31"), as.Date(ADDRESS_PERIOD_END)
    )
  )

# Overlapping periods: for each patient, any two rows where one's period_start
# falls strictly within another's [period_start, period_end).
addr_overlap <- addr_cohort |>
  dplyr::arrange(ID, period_start) |>
  dplyr::group_by(ID) |>
  dplyr::mutate(prev_end = dplyr::lag(period_end)) |>
  dplyr::filter(!is.na(prev_end), period_start < prev_end) |>
  dplyr::ungroup()

n_patients_with_overlap <- dplyr::n_distinct(addr_overlap$ID)
n_overlap_rows          <- nrow(addr_overlap)

# ==============================================================================
# SECTION (c): Crosstab ENCOUNTER.SOURCE x in-effect address SOURCE ----
# ==============================================================================

message("[R/192] SECTION (c): encounter/address SOURCE crosstab ...")

addr_for_match <- addr_cohort |>
  dplyr::mutate(addr_source = trimws(SOURCE))

# Pass 1: exact interval match [period_start <= ADMIT_DATE AND ADMIT_DATE < period_end]
enc_addr_interval <- enc_source_raw |>
  dplyr::select(ID, ENCOUNTERID, ADMIT_DATE, SOURCE) |>
  dplyr::left_join(
    addr_for_match |> dplyr::select(ID, period_start, period_end, addr_source),
    by = "ID", relationship = "many-to-many"
  ) |>
  dplyr::filter(!is.na(period_start),
                period_start <= ADMIT_DATE,
                ADMIT_DATE < period_end) |>
  dplyr::arrange(ID, ENCOUNTERID, dplyr::desc(period_start), dplyr::desc(period_end)) |>
  dplyr::group_by(ENCOUNTERID) |>
  dplyr::slice_head(n = 1L) |>
  dplyr::ungroup() |>
  dplyr::select(ENCOUNTERID, addr_source_interval = addr_source)

# Pass 2: most-recent-before fallback (period_start <= ADMIT_DATE, no period_end constraint)
enc_addr_recency <- enc_source_raw |>
  dplyr::select(ID, ENCOUNTERID, ADMIT_DATE, SOURCE) |>
  dplyr::left_join(
    addr_for_match |> dplyr::select(ID, period_start, addr_source),
    by = "ID", relationship = "many-to-many"
  ) |>
  dplyr::filter(!is.na(period_start), period_start <= ADMIT_DATE) |>
  dplyr::arrange(ID, ENCOUNTERID, dplyr::desc(period_start)) |>
  dplyr::group_by(ENCOUNTERID) |>
  dplyr::slice_head(n = 1L) |>
  dplyr::ungroup() |>
  dplyr::select(ENCOUNTERID, addr_source_recency = addr_source)

# Assign match category per encounter
enc_match <- enc_source_raw |>
  dplyr::select(ENCOUNTERID, enc_source = SOURCE) |>
  dplyr::left_join(enc_addr_interval, by = "ENCOUNTERID") |>
  dplyr::left_join(enc_addr_recency,  by = "ENCOUNTERID") |>
  dplyr::mutate(
    match_category = dplyr::case_when(
      !is.na(addr_source_interval) ~ "interval_match",
      !is.na(addr_source_recency)  ~ "recency_fallback",
      TRUE                         ~ "no_match"
    ),
    addr_source_effective = dplyr::coalesce(addr_source_interval, addr_source_recency)
  )

# Crosstab: ENCOUNTER SOURCE x effective address SOURCE x match category
crosstab_src <- enc_match |>
  dplyr::count(enc_source, addr_source_effective, match_category, name = "n") |>
  dplyr::mutate(n_display = suppress_display(n)) |>
  dplyr::arrange(match_category, enc_source, addr_source_effective)

match_summary <- enc_match |>
  dplyr::count(match_category, name = "n_encounters") |>
  dplyr::mutate(n_display = suppress_display(n_encounters))

# ==============================================================================
# SECTION (d): Analysis-set encounter counts by SOURCE_raw ----
# ==============================================================================

message("[R/192] SECTION (d): analysis-set SOURCE counts ...")

enc_dates_for_build <- enc_source_raw |>
  dplyr::select(ENCOUNTERID, ADMIT_DATE, DISCHARGE_DATE, SOURCE)

enc_analysis <- build_enc_analysis(
  enc_distance = enc_distance_raw,
  cbc_events   = cbc_events,
  anchors      = anchors,
  enc_dates    = enc_dates_for_build,
  cutoff       = CONFIG$far_from_care_cutoff_mi
)

analysis_source_freq <- enc_analysis |>
  dplyr::count(SOURCE, name = "n_analysis_enc", sort = TRUE) |>
  dplyr::mutate(n_display = suppress_display(n_analysis_enc))

# ==============================================================================
# SECTION (e): Print paste-ready block ----
# ==============================================================================

cat("\n===BEGIN STEP0 OUTPUT===\n\n")

cat("--- SECTION (a): ENCOUNTER SOURCE frequency (HL cohort) ---\n")
print(enc_source_freq |> dplyr::select(SOURCE, n_display), n = 30)
cat(glue::glue("Duplicate ENCOUNTERIDs in cohort ENCOUNTER pull: {suppress_display(n_dup_encounterid)}\n"))

cat("\n--- SECTION (b): LDS_ADDRESS_HISTORY SOURCE frequency ---\n")
print(addr_source_freq |> dplyr::select(SOURCE, n_display), n = 30)
cat(glue::glue("Missing/blank SOURCE rows in LDS_ADDRESS_HISTORY: {suppress_display(n_addr_missing_source)}\n"))
cat(glue::glue("Patients with overlapping address periods: {suppress_display(n_patients_with_overlap)}\n"))
cat(glue::glue("Overlapping address period rows: {suppress_display(n_overlap_rows)}\n"))

cat("\n--- SECTION (c): ENCOUNTER.SOURCE x in-effect address SOURCE crosstab ---\n")
cat("Match category counts (all HL cohort encounters):\n")
print(match_summary, n = 10)
cat("\nCrosstab enc_source x addr_source_effective x match_category:\n")
print(crosstab_src, n = 50)

cat("\n--- SECTION (d): Analysis-set encounter counts by SOURCE_raw ---\n")
cat("(build_enc_analysis() output — SOURCE column before any reassignment)\n")
print(analysis_source_freq, n = 30)

cat("\n===END STEP0 OUTPUT===\n")
message("[R/192] Step-0 probe complete. Paste the block above to the planner.")
