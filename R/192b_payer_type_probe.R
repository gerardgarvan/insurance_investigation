# ==============================================================================
# R/192b_payer_type_probe.R -- Phase 192.3 Payer-Type Supplementary Probe
# ==============================================================================
#
# Purpose:
#   Frequency of ENCOUNTER.PAYER_TYPE_PRIMARY and PAYER_TYPE_SECONDARY for the
#   HL cohort. Flags codes starting with "1" (PCORnet = Medicare) vs others.
#   Console output only — no files written.
#
# Run: source("R/192b_payer_type_probe.R", local = new.env(parent = globalenv()))
# ==============================================================================

source("R/00_config.R")
stopifnot(
  "CONFIG not found"        = exists("CONFIG"),
  "open_pcornet_con not found" = exists("open_pcornet_con"),
  "suppress_display not found" = exists("suppress_display")
)

ENC_DISTANCE_RDS <- Sys.getenv(
  "R192_ENC_DISTANCE_RDS",
  unset = file.path(CONFIG$output_dir, "encounter_distance_20261015.rds")
)
if (!file.exists(ENC_DISTANCE_RDS)) stop("[R/192b] File not found: ", ENC_DISTANCE_RDS)

hl_ids <- readRDS(ENC_DISTANCE_RDS) |> dplyr::distinct(ID)
message("[R/192b] HL cohort IDs: ", format(nrow(hl_ids), big.mark = ","))

open_pcornet_con()

payer_raw <- DBI::dbGetQuery(
  pcornet_con,
  "SELECT ID, ENCOUNTERID, SOURCE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY FROM ENCOUNTER"
) |>
  dplyr::semi_join(hl_ids, by = "ID")

close_pcornet_con()
message("[R/192b] DuckDB closed. Encounters in cohort: ", format(nrow(payer_raw), big.mark = ","))

# Flag Medicare (PCORnet: codes starting with "1")
payer_raw <- payer_raw |>
  dplyr::mutate(
    primary_starts1   = startsWith(as.character(PAYER_TYPE_PRIMARY),   "1"),
    secondary_starts1 = startsWith(as.character(PAYER_TYPE_SECONDARY),  "1")
  )

# --- PRIMARY payer type freq ---
pt_primary <- payer_raw |>
  dplyr::count(PAYER_TYPE_PRIMARY, name = "n", sort = TRUE) |>
  dplyr::mutate(
    medicare_flag = startsWith(as.character(PAYER_TYPE_PRIMARY), "1"),
    n_display     = suppress_display(n)
  )

# --- SECONDARY payer type freq ---
pt_secondary <- payer_raw |>
  dplyr::count(PAYER_TYPE_SECONDARY, name = "n", sort = TRUE) |>
  dplyr::mutate(
    medicare_flag = startsWith(as.character(PAYER_TYPE_SECONDARY), "1"),
    n_display     = suppress_display(n)
  )

# --- PRIMARY by SOURCE (focus on FLM) ---
pt_by_source <- payer_raw |>
  dplyr::count(SOURCE, PAYER_TYPE_PRIMARY, name = "n", sort = FALSE) |>
  dplyr::mutate(
    medicare_flag = startsWith(as.character(PAYER_TYPE_PRIMARY), "1"),
    n_display     = suppress_display(n)
  ) |>
  dplyr::arrange(SOURCE, dplyr::desc(n))

# --- Medicare encounters by SOURCE ---
medicare_by_source <- payer_raw |>
  dplyr::filter(primary_starts1 | secondary_starts1) |>
  dplyr::count(SOURCE, name = "n_medicare_enc") |>
  dplyr::mutate(n_display = suppress_display(n_medicare_enc)) |>
  dplyr::arrange(dplyr::desc(n_medicare_enc))

cat("\n===BEGIN PAYER PROBE OUTPUT===\n\n")

cat("--- PAYER_TYPE_PRIMARY frequency (HL cohort encounters) ---\n")
cat("(Codes starting with '1' = Medicare per PCORnet spec)\n")
print(pt_primary |> dplyr::select(PAYER_TYPE_PRIMARY, medicare_flag, n_display), n = 40)

cat("\n--- PAYER_TYPE_SECONDARY frequency ---\n")
print(pt_secondary |> dplyr::select(PAYER_TYPE_SECONDARY, medicare_flag, n_display), n = 40)

cat("\n--- Encounters with any Medicare payer (primary OR secondary) by SOURCE ---\n")
print(medicare_by_source, n = 20)

cat("\n--- PAYER_TYPE_PRIMARY by SOURCE (top codes per site) ---\n")
print(pt_by_source |> dplyr::select(SOURCE, PAYER_TYPE_PRIMARY, medicare_flag, n_display), n = 80)

cat("\n===END PAYER PROBE OUTPUT===\n")
message("[R/192b] Payer probe complete. Paste the block above.")
